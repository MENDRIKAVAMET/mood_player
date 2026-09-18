import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/lyrics_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';

/// Recherche manuelle de paroles, sur le modèle de Muso Player : les champs
/// artiste/titre sont pré-remplis avec les tags du morceau mais restent
/// modifiables (les tags sont parfois faux ou incomplets), l'utilisateur
/// lance la recherche, parcourt les résultats et importe celui qui
/// correspond. Une fois importé, ce choix a priorité sur tout ce que la
/// recherche automatique pourrait trouver.
class LyricsSearchScreen extends ConsumerStatefulWidget {
  final Track track;

  const LyricsSearchScreen({super.key, required this.track});

  @override
  ConsumerState<LyricsSearchScreen> createState() =>
      _LyricsSearchScreenState();
}

class _LyricsSearchScreenState extends ConsumerState<LyricsSearchScreen> {
  late final TextEditingController _artistController =
      TextEditingController(text: widget.track.artist);
  late final TextEditingController _titleController =
      TextEditingController(text: widget.track.title);

  bool _loading = false;
  bool _searched = false;
  List<LyricsSearchResult> _results = const [];
  String? _importingKey;

  @override
  void initState() {
    super.initState();
    // Comme dans Muso Player, on lance une première recherche
    // automatiquement avec ce que l'app connaît déjà du morceau.
    WidgetsBinding.instance.addPostFrameCallback((_) => _runSearch());
  }

  @override
  void dispose() {
    _artistController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final artist = _artistController.text.trim();
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    setState(() {
      _loading = true;
      _searched = true;
    });

    final service = ref.read(lyricsServiceProvider);
    final results = await service.search(title: title, artist: artist);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _results = results;
    });
  }

  String _resultKey(LyricsSearchResult r) => '${r.artistName}-${r.trackName}';

  Future<void> _import(LyricsSearchResult result) async {
    setState(() => _importingKey = _resultKey(result));

    final service = ref.read(lyricsServiceProvider);
    final trackKey = '${widget.track.artist} - ${widget.track.title}';
    await service.importResult(trackKey: trackKey, result: result);

    // Le prochain écran paroles doit relire (l'import a priorité sur tout
    // le reste), donc on invalide le cache pour ce morceau.
    ref.invalidate(lyricsProvider(lyricsKeyFor(widget.track)));

    if (!mounted) return;
    setState(() => _importingKey = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Paroles importées')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(widget.track.mood);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Rechercher les paroles', style: AppTheme.titleMedium),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingL,
              AppTheme.spacingS,
              AppTheme.spacingL,
              AppTheme.spacingM,
            ),
            child: Column(
              children: [
                _SearchField(
                  controller: _artistController,
                  label: 'Artiste',
                  onSubmitted: (_) => _runSearch(),
                ),
                const SizedBox(height: AppTheme.spacingM),
                _SearchField(
                  controller: _titleController,
                  label: 'Titre',
                  onSubmitted: (_) => _runSearch(),
                ),
                const SizedBox(height: AppTheme.spacingL),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _loading ? null : _runSearch,
                    style: FilledButton.styleFrom(
                      backgroundColor: moodColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: AppTheme.spacingM),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusM),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Rechercher'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildResults(moodColors)),
        ],
      ),
    );
  }

  Widget _buildResults(MoodColors moodColors) {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_searched && !_loading && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingXL),
          child: Text(
            "Aucun résultat. Vérifie l'orthographe de l'artiste et du "
            'titre, ou essaie une version plus simple (sans "(Live)", '
            'featuring, etc.).',
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final result = _results[index];
        final key = _resultKey(result);
        return _ResultTile(
          result: result,
          color: moodColors.primary,
          importing: _importingKey == key,
          onImport: () => _import(result),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;

  const _SearchField({
    required this.controller,
    required this.label,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: AppTheme.bodyLarge,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
        filled: true,
        fillColor: AppTheme.backgroundCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingL,
          vertical: AppTheme.spacingM,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final LyricsSearchResult result;
  final Color color;
  final bool importing;
  final VoidCallback onImport;

  const _ResultTile({
    required this.result,
    required this.color,
    required this.importing,
    required this.onImport,
  });

  String get _durationLabel {
    final seconds = result.durationSeconds;
    if (seconds == null) return '';
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tag = result.instrumental
        ? 'Instrumental'
        : result.hasSynced
            ? 'Synchronisé'
            : 'Texte';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingS,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.trackName,
                  style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    result.artistName,
                    if (result.albumName != null && result.albumName!.isNotEmpty)
                      result.albumName!,
                    if (_durationLabel.isNotEmpty) _durationLabel,
                  ].join(' · '),
                  style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        tag,
                        style: AppTheme.labelSmall.copyWith(color: color),
                      ),
                    ),
                  ],
                ),
                if (result.preview.isNotEmpty) ...[
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    result.preview,
                    style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          SizedBox(
            width: 88,
            child: importing
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : OutlinedButton(
                    onPressed: onImport,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: color,
                      side: BorderSide(color: color.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      ),
                    ),
                    child: const Text('Importer'),
                  ),
          ),
        ],
      ),
    );
  }
}
