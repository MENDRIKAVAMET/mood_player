import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../services/groq_service.dart';
import '../../services/mood_query_parser.dart';
import '../../theme/mood_colors.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/app_header.dart';
import '../../widgets/track_list_tools.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/track_options_sheet.dart';

/// Recherche en plein écran, en remplacement de l'ancienne boîte de
/// dialogue : une vraie page laisse la place à un historique de
/// recherches et à des résultats qui défilent comme le reste de la
/// bibliothèque, au lieu d'être tassés dans une petite fenêtre.
///
/// Elle filtre localement au lieu de passer par `searchTracks` du
/// TrackNotifier : l'ancienne version modifiait la liste globale, si bien
/// qu'après une recherche la bibliothèque restait filtrée sans que rien
/// ne l'indique à l'écran.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scroll = ScrollController();
  late final TrackListLocator _locator =
      TrackListLocator(controller: _scroll);
  TrackSortOption? _sort;
  List<String> _recentSearches = [];
  String _query = '';

  // Recherche par ambiance : interprétation Groq de la requête courante.
  MoodQuery? _aiQuery;
  String? _aiForQuery;
  bool _aiLoading = false;
  String? _aiError;

  /// Ambiances détectées que l'utilisateur a décochées.
  final Set<MoodType> _hiddenMoods = {};

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadRecentSearches() async {
    final searches = await ref.read(storageServiceProvider).getRecentSearches();
    if (mounted) setState(() => _recentSearches = searches);
  }

  /// Enregistre la recherche dans l'historique. Appelé à la validation
  /// (et non à chaque frappe) pour ne pas polluer l'historique avec
  /// « a », « ab », « abc »…
  Future<void> _commitSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    await ref.read(storageServiceProvider).addRecentSearch(trimmed);
    await _loadRecentSearches();
  }

  Future<void> _removeRecentSearch(String query) async {
    await ref.read(storageServiceProvider).removeRecentSearch(query);
    await _loadRecentSearches();
  }

  /// Demande à Groq ce que veut dire la phrase, quand les mots-clés locaux
  /// n'ont rien compris. Jamais à la frappe : à la validation, ou via le bouton.
  Future<void> _askAi() async {
    final query = _query.trim();
    if (query.isEmpty || _aiLoading) return;
    final key = MoodQueryParser.normalize(query);
    setState(() {
      _aiLoading = true;
      _aiError = null;
    });
    try {
      final result = await ref.read(moodQueryServiceProvider).interpretWithAi(query);
      if (!mounted) return;
      setState(() {
        _aiLoading = false;
        _aiQuery = result;
        _aiForQuery = key;
        _hiddenMoods.clear();
        if (!result.hasMoods && !result.hasExclusions) {
          _aiError = 'Je n\'ai pas reconnu d\'ambiance dans cette phrase.';
        }
      });
    } on GroqRateLimitException {
      _failAi('Trop de requêtes pour le moment, réessaie dans un instant.');
    } on GroqNetworkException {
      _failAi('Connexion impossible : vérifie ta connexion internet.');
    } catch (_) {
      _failAi('L\'interprétation par IA n\'est pas disponible pour le moment.');
    }
  }

  void _failAi(String message) {
    if (!mounted) return;
    setState(() {
      _aiLoading = false;
      _aiError = message;
    });
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _hiddenMoods.clear();
      _aiError = null;
    });
  }

  /// À la validation : si ni les titres ni les mots-clés ne répondent, on
  /// laisse l'IA tenter de comprendre.
  void _onSubmit(String value) {
    _commitSearch(value);
    final q = value.trim();
    if (q.split(RegExp(r'\s+')).length < 2) return;
    final local = ref.read(moodQueryServiceProvider).parseLocal(q);
    if (local.hasMoods || local.hasExclusions) return;
    final lower = q.toLowerCase();
    final hasTextMatch = ref.read(trackProvider).tracks.any((t) =>
        t.title.toLowerCase().contains(lower) ||
        t.artist.toLowerCase().contains(lower) ||
        (t.album?.toLowerCase().contains(lower) ?? false));
    if (!hasTextMatch) _askAi();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTracks = ref.watch(trackProvider).tracks;
    final currentId = ref.watch(currentTrackIdProvider);
    final lowerQuery = _query.trim().toLowerCase();
    final matches = lowerQuery.isEmpty
        ? const <Track>[]
        : allTracks
            .where((t) =>
                t.title.toLowerCase().contains(lowerQuery) ||
                t.artist.toLowerCase().contains(lowerQuery) ||
                (t.album?.toLowerCase().contains(lowerQuery) ?? false))
            .toList();

    // Ambiances comprises : mots-clés locaux d'abord, sinon l'IA (si elle a
    // déjà répondu à CETTE phrase). Les puces décochées sont retirées.
    final service = ref.read(moodQueryServiceProvider);
    final detected = lowerQuery.isEmpty
        ? MoodQuery.empty
        : () {
            final local = service.parseLocal(_query);
            if (local.hasMoods) return local;
            final ai = _aiForQuery == MoodQueryParser.normalize(_query)
                ? _aiQuery
                : null;
            if (ai != null && (ai.hasMoods || ai.hasExclusions)) return ai;
            return local; // peut n'avoir que des exclusions (« pas triste »)
          }();
    final activeMoods = detected.only(
      detected.weights.keys.toSet().difference(_hiddenMoods),
    );
    final matchIds = {for (final t in matches) t.id};
    // Si toutes les puces sont décochées, on n'affiche rien par ambiance
    // (et surtout pas « tout sauf les exclusions »). Seule une phrase
    // purement négative filtre par exclusion.
    final moodSearchOn =
        detected.hasMoods ? activeMoods.hasMoods : detected.hasExclusions;
    final byMood = moodSearchOn
        ? activeMoods.rank(allTracks.where((t) => !matchIds.contains(t.id)))
        : const <Track>[];
    final combined = [...matches, ...byMood];
    final results = _sort == null ? combined : sortTracks(combined, _sort!);
    // Séparateur entre « correspond au texte » et « correspond à l'ambiance ».
    final headerAt =
        (_sort == null && matches.isNotEmpty && byMood.isNotEmpty)
            ? matches.length
            : null;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildSearchField(),
            if (lowerQuery.isNotEmpty && (detected.hasMoods || detected.hasExclusions || _aiLoading))
              _DetectedMoodsRow(
                query: detected,
                hidden: _hiddenMoods,
                loading: _aiLoading,
                onToggle: (m) => setState(() {
                  if (!_hiddenMoods.remove(m)) _hiddenMoods.add(m);
                }),
              ),
            Expanded(
              child: lowerQuery.isEmpty
                  ? Column(
                      children: [
                        _ExampleQueries(onTap: (q) {
                          _controller.text = q;
                          _controller.selection = TextSelection.fromPosition(
                            TextPosition(offset: q.length),
                          );
                          _onQueryChanged(q);
                          _commitSearch(q);
                        }),
                        Expanded(child: _RecentSearchesList(
                      searches: _recentSearches,
                      onTapSearch: (s) {
                        _controller.text = s;
                        _controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: s.length),
                        );
                        _onQueryChanged(s);
                        _commitSearch(s);
                      },
                      onRemove: _removeRecentSearch,
                      onClearAll: () async {
                        await ref.read(storageServiceProvider).clearRecentSearches();
                        await _loadRecentSearches();
                      },
                    )),
                      ],
                    )
                  : results.isEmpty
                      ? _NoResults(
                          query: _query,
                          loading: _aiLoading,
                          error: _aiError,
                          onAskAi: (!detected.hasMoods &&
                                  !detected.hasExclusions &&
                                  !_aiLoading)
                              ? _askAi
                              : null,
                          hasUnclassified: (detected.hasMoods || detected.hasExclusions) &&
                              allTracks.any((t) => !t.isClassified),
                        )
                      : Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                left: AppTheme.spacingXL,
                                right: AppTheme.spacingS,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${results.length} résultat${results.length > 1 ? 's' : ''}',
                                    style: AppTheme.bodyMedium.copyWith(
                                        color: AppTheme.textTertiary),
                                  ),
                                  const Spacer(),
                                  TrackListActionBar(
                                    tracks: results,
                                    sort: _sort,
                                    onSort: (c) =>
                                        setState(() => _sort = c.option),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Stack(
                                children: [
                                  TrackListScrollbar(
                                    controller: _scroll,
                                    child: ListView.builder(
                                      controller: _scroll,
                                      padding: const EdgeInsets.only(
                                        top: AppTheme.spacingS,
                                        bottom: 40,
                                      ),
                                      itemCount: results.length +
                                          (headerAt != null ? 1 : 0),
                                      itemBuilder: (context, rawIndex) {
                                        if (headerAt != null &&
                                            rawIndex == headerAt) {
                                          return const _SectionLabel(
                                              'Correspond à l\'ambiance');
                                        }
                                        final index =
                                            (headerAt != null && rawIndex > headerAt)
                                                ? rawIndex - 1
                                                : rawIndex;
                                        final track = results[index];
                                        void open() {
                                          _commitSearch(_query);
                                          openPlayer(context,
                                              track: track, tracks: results);
                                        }

                                        return KeyedSubtree(
                                          key: _locator.keyFor(track.id),
                                          child: TrackTile(
                                            track: track,
                                            index: index,
                                            isPlaying:
                                                currentId == track.id.toString(),
                                            onTap: open,
                                            onPlay: () => togglePlayTrack(ref, track, results),
                                            onMore: () => showTrackOptionsSheet(
                                                context, ref, track),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  LocateTrackButton(
                                      locator: _locator, tracks: results),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return AppHeader(
      showBack: true,
      titleWidget: Container(
        height: 40,
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Row(
          children: [
            const SizedBox(width: AppTheme.spacingM),
            Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 20),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                onChanged: _onQueryChanged,
                onSubmitted: _onSubmit,
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Titre, artiste ou ambiance…',
                  hintStyle:
                      AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_query.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _controller.clear();
                  _onQueryChanged('');
                },
                child: Icon(
                  Icons.close_rounded,
                  color: AppTheme.textTertiary,
                  size: 18,
                ),
              ),
            const SizedBox(width: AppTheme.spacingM),
          ],
        ),
      ),
    );
  }
}

class _RecentSearchesList extends StatelessWidget {
  final List<String> searches;
  final ValueChanged<String> onTapSearch;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearAll;

  const _RecentSearchesList({
    required this.searches,
    required this.onTapSearch,
    required this.onRemove,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    if (searches.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingXL),
          child: Text(
            'Vos recherches récentes apparaîtront ici.',
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingL,
            AppTheme.spacingS,
            AppTheme.spacingL,
            AppTheme.spacingS,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recherches récentes', style: AppTheme.labelMedium),
              GestureDetector(
                onTap: onClearAll,
                child: Text(
                  'Tout effacer',
                  style: AppTheme.labelMedium.copyWith(color: AppTheme.accentPrimary),
                ),
              ),
            ],
          ),
        ),
        for (final search in searches)
          ListTile(
            leading: Icon(Icons.history_rounded, color: AppTheme.textTertiary),
            title: Text(search, style: AppTheme.bodyMedium),
            trailing: IconButton(
              icon: Icon(Icons.close_rounded, color: AppTheme.textTertiary, size: 18),
              onPressed: () => onRemove(search),
            ),
            onTap: () => onTapSearch(search),
          ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  final bool loading;
  final String? error;
  final VoidCallback? onAskAi;
  final bool hasUnclassified;

  const _NoResults({
    required this.query,
    this.loading = false,
    this.error,
    this.onAskAi,
    this.hasUnclassified = false,
  });

  @override
  Widget build(BuildContext context) {
    final hint = loading
        ? 'Je cherche ce que tu veux écouter…'
        : hasUnclassified
            ? 'Aucun morceau classé dans cette ambiance pour l\'instant. '
                'Classe ta bibliothèque pour de meilleurs résultats.'
            : 'Aucun résultat pour « $query »';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(Icons.search_off_rounded, size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
            ),
            if (error != null) ...[
              const SizedBox(height: AppTheme.spacingS),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
              ),
            ],
            if (onAskAi != null) ...[
              const SizedBox(height: AppTheme.spacingM),
              OutlinedButton.icon(
                onPressed: onAskAi,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Chercher par ambiance (IA)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Puces des ambiances comprises dans la phrase ; toucher une puce
/// l'exclut (ou la remet) des résultats.
class _DetectedMoodsRow extends StatelessWidget {
  final MoodQuery query;
  final Set<MoodType> hidden;
  final bool loading;
  final ValueChanged<MoodType> onToggle;

  const _DetectedMoodsRow({
    required this.query,
    required this.hidden,
    required this.loading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL, AppTheme.spacingXS, AppTheme.spacingL, AppTheme.spacingS,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: AppTheme.spacingS,
          runSpacing: AppTheme.spacingS,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (query.hasMoods || !query.hasExclusions)
              Text(
                query.fromAi ? 'Compris par l\'IA :' : 'Ambiances :',
                style: AppTheme.labelMedium,
              ),
            if (loading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            for (final mood in query.ranked.take(4))
              GestureDetector(
                onTap: () => onToggle(mood),
                child: _chip(mood, !hidden.contains(mood)),
              ),
            if (query.hasExclusions) ...[
              Text(
                query.fromAi && !query.hasMoods
                    ? 'Compris par l\'IA · sans :'
                    : 'Sans :',
                style: AppTheme.labelMedium,
              ),
              for (final mood in query.excluded) _excludedChip(mood),
            ],
          ],
        ),
      ),
    );
  }

  /// Ambiance écartée : puce barrée, non cliquable.
  Widget _excludedChip(MoodType mood) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM, vertical: AppTheme.spacingXS,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: AppTheme.spacingXXS),
          Text(
            mood.displayName,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(MoodType mood, bool on) {
    final color = MoodColors.forMood(mood).primary;
    return AnimatedContainer(
      duration: AppTheme.animFast,
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM, vertical: AppTheme.spacingXS,
      ),
      decoration: BoxDecoration(
        color: on ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: on ? color : Colors.transparent, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(mood.iconData, size: 14, color: on ? color : AppTheme.textSecondary),
          const SizedBox(width: AppTheme.spacingXXS),
          Text(
            mood.displayName,
            style: AppTheme.bodySmall.copyWith(
              color: on ? color : AppTheme.textSecondary,
              fontWeight: on ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

/// Exemples de phrases, affichés tant que le champ est vide : c'est ce qui
/// fait découvrir la recherche par ambiance.
class _ExampleQueries extends StatelessWidget {
  final ValueChanged<String> onTap;
  const _ExampleQueries({required this.onTap});

  static const _examples = [
    'un truc calme pour réviser',
    'pour le trajet',
    'pour faire du sport',
    'pour m\'endormir',
    'une soirée entre amis',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL, AppTheme.spacingM, AppTheme.spacingL, AppTheme.spacingS,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Essaie par ambiance', style: AppTheme.labelMedium),
            const SizedBox(height: AppTheme.spacingS),
            Wrap(
              spacing: AppTheme.spacingS,
              runSpacing: AppTheme.spacingS,
              children: [
                for (final e in _examples)
                  ActionChip(
                    label: Text(e, style: AppTheme.bodySmall),
                    onPressed: () => onTap(e),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingXL, AppTheme.spacingM, AppTheme.spacingL, AppTheme.spacingXS,
        ),
        child: Text(text, style: AppTheme.labelMedium),
      );
}
