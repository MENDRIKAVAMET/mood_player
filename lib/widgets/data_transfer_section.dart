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
  final bool includePersonalData;
  final bool overwrite;
  const _ImportChoice({
    required this.includePersonalData,
    required this.overwrite,
  });
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
    setState(() => _busy = true);
    try {
      final file = await ref
          .read(backupServiceProvider)
          .exportToFile(profile: ref.read(profileProvider));
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

      final result = await service.apply(
        data,
        overwriteClassifications: choice.overwrite,
        includePersonalData: choice.includePersonalData,
      );

      if (choice.includePersonalData) {
        await ref.read(profileProvider.notifier).applyImported(
              favoriteArtists: data.favoriteArtists,
              periodMoods: data.periodMoods,
              smartQueueEnabled: data.smartQueueEnabled,
            );
        await ref.read(customMoodProvider.notifier).loadMoods();
        await ref.read(playbackStatsProvider.notifier).reload();
      }
      await ref.read(trackProvider.notifier).loadTracks();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _ResultDialog(result: result, choice: choice),
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
          subtitle: 'Classifications, favoris, ambiances perso, réglages',
          onTap: _busy ? null : _export,
        ),
        const SizedBox(height: AppTheme.spacingS),
        _TransferTile(
          icon: Icons.file_download_rounded,
          title: 'Importer des données',
          subtitle: 'Depuis un fichier Mood Player',
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

class _ImportDialog extends StatefulWidget {
  final BackupData data;
  const _ImportDialog({required this.data});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _restoreAll = true;
  bool _overwrite = false;

  Widget _option({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? AppTheme.accentPrimary : AppTheme.textTertiary,
      ),
      title: Text(title, style: AppTheme.titleMedium),
      subtitle: Text(
        subtitle,
        style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return AlertDialog(
      backgroundColor: AppTheme.backgroundSecondary,
      title: const Text('Importer ce fichier ?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${d.classifiedCount} morceau(x) classé(s) dans ce fichier. '
              'Seuls ceux qui sont aussi sur cet appareil (même titre et '
              'même artiste) seront retrouvés.',
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spacingM),
            _option(
              selected: _restoreAll,
              title: 'Tout restaurer',
              subtitle: 'Mon ancien téléphone : classifications, favoris, '
                  'ambiances perso, écoutes et réglages',
              onTap: () => setState(() => _restoreAll = true),
            ),
            _option(
              selected: !_restoreAll,
              title: 'Classifications seulement',
              subtitle: 'Les données d\'une autre personne : je garde mes '
                  'favoris et mes réglages',
              onTap: () => setState(() => _restoreAll = false),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _overwrite,
              activeThumbColor: AppTheme.accentPrimary,
              onChanged: (v) => setState(() => _overwrite = v),
              title: Text('Remplacer mes classifications',
                  style: AppTheme.titleMedium),
              subtitle: Text(
                'Sinon, les morceaux que j\'ai déjà classés restent tels quels',
                style: AppTheme.bodySmall
                    .copyWith(color: AppTheme.textTertiary),
              ),
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
          onPressed: () => Navigator.pop(
            context,
            _ImportChoice(
              includePersonalData: _restoreAll,
              overwrite: _overwrite,
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
  const _ResultDialog({required this.result, required this.choice});

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      '${result.matched} morceau(x) retrouvé(s) sur ${result.totalInFile}.',
      '${result.classificationsApplied} classification(s) importée(s).',
      if (result.classificationsKept > 0)
        '${result.classificationsKept} déjà classé(s) ici, conservé(s).',
      if (choice.includePersonalData && result.likedAdded > 0)
        '${result.likedAdded} favori(s) ajouté(s).',
      if (choice.includePersonalData && result.customMoodTracksAdded > 0)
        '${result.customMoodTracksAdded} morceau(x) ajouté(s) à vos ambiances perso.',
    ];
    final nothingFound = result.matched == 0;
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
          ] else if (result.unmatched > 0) ...[
            const SizedBox(height: AppTheme.spacingS),
            Text(
              '${result.unmatched} morceau(x) du fichier ne sont pas sur cet '
              'appareil et ont été ignorés.',
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
