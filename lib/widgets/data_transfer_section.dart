import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/providers.dart';
import '../services/backup_service.dart';
import '../theme/app_theme.dart';

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(storageServiceProvider));
});

/// Section « Transfert de données » de l'écran de profil : exporte les
/// classifications (et le reste) dans un fichier à envoyer par n'importe
/// quelle appli, et importe un fichier venant d'un autre téléphone ou
/// d'une autre personne - sans connexion ni appel à l'IA.
class DataTransferSection extends ConsumerStatefulWidget {
  const DataTransferSection({super.key});

  @override
  ConsumerState<DataTransferSection> createState() =>
      _DataTransferSectionState();
}

class _ImportChoice {
  final Set<BackupCategory> categories;
  final bool overwrite;
  const _ImportChoice({
    required this.categories,
    required this.overwrite,
  });
}

/// Ce que l'import a fait côté profil (hors morceaux), pour le bilan.
class _ProfileImportStats {
  final int artistsAdded;
  final int artistsSkipped;
  const _ProfileImportStats({this.artistsAdded = 0, this.artistsSkipped = 0});
}

class _DataTransferSectionState extends ConsumerState<DataTransferSection> {
  bool _busy = false;

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
        ),
        backgroundColor:
            error ? AppTheme.accentError : AppTheme.backgroundCardElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _export() async {
    if (_busy) return;

    final categories = await showDialog<Set<BackupCategory>>(
      context: context,
      builder: (_) => const _ExportDialog(),
    );
    if (categories == null || categories.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final file = await ref.read(backupServiceProvider).exportToFile(
            profile: ref.read(profileProvider),
            categories: categories,
          );
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        text: 'Mes données Mood Player',
      );
    } catch (e) {
      _snack('Export impossible : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;

    final picked = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final data = await service.readFile(path);
      if (!mounted) return;

      final choice = await showDialog<_ImportChoice>(
        context: context,
        builder: (_) => _ImportDialog(data: data),
      );
      if (choice == null || !mounted) return;

      final cats = choice.categories;
      final result = await service.apply(
        data,
        overwriteClassifications: choice.overwrite,
        categories: cats,
      );

      // Artistes préférés : seuls ceux qui existent sur cet appareil sont
      // retenus, et ils s'ajoutent à ceux déjà choisis (rien n'est écrasé).
      List<String>? favorites;
      var stats = const _ProfileImportStats();
      if (cats.contains(BackupCategory.favoriteArtists)) {
        final match = await service.matchFavoriteArtists(data.favoriteArtists);
        final existing = ref.read(profileProvider).favoriteArtists;
        final merged = [
          ...existing,
          ...match.onDevice.where((a) => !existing.contains(a)),
        ];
        favorites = merged;
        stats = _ProfileImportStats(
          artistsAdded: merged.length - existing.length,
          artistsSkipped: match.skipped,
        );
      }

      final touchesProfile = favorites != null ||
          cats.contains(BackupCategory.periodMoods) ||
          cats.contains(BackupCategory.smartQueue);
      if (touchesProfile) {
        await ref.read(profileProvider.notifier).applyImported(
              favoriteArtists: favorites,
              periodMoods: cats.contains(BackupCategory.periodMoods)
                  ? data.periodMoods
                  : null,
              smartQueueEnabled: cats.contains(BackupCategory.smartQueue)
                  ? data.smartQueueEnabled
                  : null,
            );
      }
      if (cats.contains(BackupCategory.customMoods)) {
        await ref.read(customMoodProvider.notifier).loadMoods();
      }
      if (cats.contains(BackupCategory.playCounts)) {
        await ref.read(playbackStatsProvider.notifier).reload();
      }
      await ref.read(trackProvider.notifier).loadTracks();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ResultDialog(
          result: result,
          choice: choice,
          stats: stats,
        ),
      );
    } on BackupFormatException catch (e) {
      _snack(e.message, error: true);
    } catch (e) {
      _snack('Import impossible : $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transfert de données', style: AppTheme.titleLarge),
        const SizedBox(height: AppTheme.spacingS),
        Text(
          'Changement de téléphone, ou classifications d\'une autre '
          'personne : exportez vos données dans un fichier, importez-les sur '
          'l\'autre appareil. Aucune connexion nécessaire.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
        ),
        const SizedBox(height: AppTheme.spacingM),
        _TransferTile(
          icon: Icons.ios_share_rounded,
          title: 'Exporter mes données',
          subtitle: 'Vous choisissez les données à inclure',
          onTap: _busy ? null : _export,
        ),
        const SizedBox(height: AppTheme.spacingS),
        _TransferTile(
          icon: Icons.file_download_rounded,
          title: 'Importer des données',
          subtitle: 'Vous choisissez les données à importer',
          onTap: _busy ? null : _import,
        ),
        if (_busy) ...[
          const SizedBox(height: AppTheme.spacingM),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }
}

class _TransferTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _TransferTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingL),
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Icon(icon, color: AppTheme.accentPrimary),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textTertiary),
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
}

/// Une ligne à cocher d'une boîte de choix de données.
Widget _categoryTile({
  required BackupCategory category,
  required bool selected,
  required String subtitle,
  required ValueChanged<bool> onChanged,
}) {
  return CheckboxListTile(
    contentPadding: EdgeInsets.zero,
    value: selected,
    activeColor: AppTheme.accentPrimary,
    checkColor: AppTheme.textInverse,
    controlAffinity: ListTileControlAffinity.leading,
    onChanged: (v) => onChanged(v ?? false),
    title: Text(category.label, style: AppTheme.titleMedium),
    subtitle: Text(
      subtitle,
      style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
    ),
  );
}

/// Choix des données à mettre dans le fichier exporté.
class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  final Set<BackupCategory> _selected = {...BackupCategory.values};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.backgroundSecondary,
      title: const Text('Exporter quoi ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cochez les données à mettre dans le fichier.',
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spacingS),
            for (final category in BackupCategory.values)
              _categoryTile(
                category: category,
                selected: _selected.contains(category),
                subtitle: category.description,
                onChanged: (v) => setState(() {
                  if (v) {
                    _selected.add(category);
                  } else {
                    _selected.remove(category);
                  }
                }),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, Set<BackupCategory>.of(_selected)),
          child: const Text('Exporter'),
        ),
      ],
    );
  }
}

/// Choix des données à importer parmi celles que le fichier contient.
class _ImportDialog extends StatefulWidget {
  final BackupData data;
  const _ImportDialog({required this.data});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final List<BackupCategory> _available = [
    for (final c in BackupCategory.values)
      if (widget.data.availableCategories.contains(c)) c,
  ];
  late final Set<BackupCategory> _selected = {..._available};
  bool _overwrite = false;

  String _detail(BackupCategory c) {
    final d = widget.data;
    final n = d.countFor(c);
    switch (c) {
      case BackupCategory.classifications:
        return '$n morceau(x) classé(s)';
      case BackupCategory.liked:
        return '$n favori(s)';
      case BackupCategory.playCounts:
        return '$n morceau(x) avec un compteur d\'écoute';
      case BackupCategory.customMoods:
        return '$n ambiance(s) perso';
      case BackupCategory.favoriteArtists:
        return '$n artiste(s) - seuls ceux présents sur cet appareil '
            'seront ajoutés';
      case BackupCategory.periodMoods:
        return '$n moment(s) de la journée';
      case BackupCategory.smartQueue:
        return d.smartQueueEnabled == true ? 'Activée' : 'Désactivée';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTrackData = _available.any((c) => c.isTrackBased);
    return AlertDialog(
      backgroundColor: AppTheme.backgroundSecondary,
      title: const Text('Importer quoi ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_available.isEmpty)
              Text(
                'Ce fichier ne contient aucune donnée à importer.',
                style: AppTheme.bodyMedium,
              )
            else ...[
              Text(
                hasTrackData
                    ? 'Cochez les données à importer. Les morceaux ne sont '
                        'retrouvés que s\'ils sont aussi sur cet appareil '
                        '(même titre et même artiste).'
                    : 'Cochez les données à importer.',
                style: AppTheme.bodyMedium,
              ),
              const SizedBox(height: AppTheme.spacingS),
              for (final category in _available)
                _categoryTile(
                  category: category,
                  selected: _selected.contains(category),
                  subtitle: _detail(category),
                  onChanged: (v) => setState(() {
                    if (v) {
                      _selected.add(category);
                    } else {
                      _selected.remove(category);
                    }
                  }),
                ),
              if (_selected.contains(BackupCategory.classifications))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _overwrite,
                  activeThumbColor: AppTheme.accentPrimary,
                  onChanged: (v) => setState(() => _overwrite = v),
                  title: Text('Remplacer mes classifications',
                      style: AppTheme.titleMedium),
                  subtitle: Text(
                    'Sinon, les morceaux que j\'ai déjà classés restent '
                    'tels quels',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textTertiary),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _ImportChoice(
                      categories: Set<BackupCategory>.of(_selected),
                      overwrite: _overwrite &&
                          _selected.contains(BackupCategory.classifications),
                    ),
                  ),
          child: const Text('Importer'),
        ),
      ],
    );
  }
}

class _ResultDialog extends StatelessWidget {
  final BackupImportResult result;
  final _ImportChoice choice;
  final _ProfileImportStats stats;
  const _ResultDialog({
    required this.result,
    required this.choice,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    final cats = choice.categories;
    final usedTracks = cats.any((c) => c.isTrackBased) && result.totalInFile > 0;
    final lines = <String>[
      if (usedTracks)
        '${result.matched} morceau(x) retrouvé(s) sur ${result.totalInFile}.',
      if (cats.contains(BackupCategory.classifications))
        '${result.classificationsApplied} classification(s) importée(s).',
      if (cats.contains(BackupCategory.classifications) &&
          result.classificationsKept > 0)
        '${result.classificationsKept} déjà classé(s) ici, conservé(s).',
      if (cats.contains(BackupCategory.liked) && result.likedAdded > 0)
        '${result.likedAdded} favori(s) ajouté(s).',
      if (cats.contains(BackupCategory.customMoods) &&
          result.customMoodTracksAdded > 0)
        '${result.customMoodTracksAdded} morceau(x) ajouté(s) à vos ambiances perso.',
      if (cats.contains(BackupCategory.favoriteArtists))
        '${stats.artistsAdded} artiste(s) préféré(s) ajouté(s).',
      if (cats.contains(BackupCategory.periodMoods))
        'Ambiances par moment de la journée importées.',
      if (cats.contains(BackupCategory.smartQueue))
        'Réglage de lecture intelligente importé.',
    ];
    final nothingFound = usedTracks && result.matched == 0;
    return AlertDialog(
      backgroundColor: AppTheme.backgroundSecondary,
      title: Text(nothingFound ? 'Aucun morceau retrouvé' : 'Import terminé'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingXS),
              child: Text(l, style: AppTheme.bodyMedium),
            ),
          if (nothingFound) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Vérifiez que la bibliothèque de cet appareil a bien été '
              'scannée (onglet Bibliothèque) puis réessayez.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
            ),
          ] else if (usedTracks && result.unmatched > 0) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              '${result.unmatched} morceau(x) du fichier ne sont pas sur cet '
              'appareil et ont été ignorés.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
            ),
          ],
          if (stats.artistsSkipped > 0) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              '${stats.artistsSkipped} artiste(s) préféré(s) du fichier '
              'n\'existent pas sur cet appareil et ont été ignorés.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Fermer', style: TextStyle(color: AppTheme.accentPrimary)),
        ),
      ],
    );
  }
}
