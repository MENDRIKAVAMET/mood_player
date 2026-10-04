import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
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
    final lowerQuery = _query.trim().toLowerCase();
    final matches = lowerQuery.isEmpty
        ? const <Track>[]
        : allTracks
            .where((t) =>
                t.title.toLowerCase().contains(lowerQuery) ||
                t.artist.toLowerCase().contains(lowerQuery) ||
                (t.album?.toLowerCase().contains(lowerQuery) ?? false))
            .toList();
    final results = _sort == null ? matches : sortTracks(matches, _sort!);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildSearchField(),
            Expanded(
              child: lowerQuery.isEmpty
                  ? _RecentSearchesList(
                      searches: _recentSearches,
                      onTapSearch: (s) {
                        _controller.text = s;
                        _controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: s.length),
                        );
                        setState(() => _query = s);
                        _commitSearch(s);
                      },
                      onRemove: _removeRecentSearch,
                      onClearAll: () async {
                        await ref.read(storageServiceProvider).clearRecentSearches();
                        await _loadRecentSearches();
                      },
                    )
                  : results.isEmpty
                      ? _NoResults(query: _query)
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
                                      itemCount: results.length,
                                      itemBuilder: (context, index) {
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
                                            onTap: open,
                                            onPlay: open,
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
                onChanged: (value) => setState(() => _query = value),
                onSubmitted: _commitSearch,
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Rechercher morceaux, artistes...',
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
                  setState(() => _query = '');
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

  const _NoResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              'Aucun résultat pour « $query »',
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
