import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/duplicate_finder.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/track_artwork.dart';

/// Écran « Doublons » : liste les morceaux présents en plusieurs
/// exemplaires, propose celui à garder (favori, déjà classé, hors dossiers
/// WhatsApp/Téléchargements…) et retire les autres de la bibliothèque en
/// leur faisant hériter du favori et de l'ambiance. Les fichiers eux-mêmes
/// ne sont jamais supprimés de l'appareil.
class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  List<DuplicateGroup> _groups = const [];

  /// Index du groupe -> id de l'exemplaire à garder.
  final Map<int, int> _keeperByGroup = {};

  /// Groupes que l'utilisateur laisse tels quels.
  final Set<int> _ignored = {};

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    final tracks = ref.read(trackProvider).tracks;
    final groups = DuplicateFinder.find(tracks);
    _groups = groups;
    _keeperByGroup
      ..clear()
      ..addEntries([
        for (var i = 0; i < groups.length; i++)
          MapEntry(i, groups[i].suggestedKeeper.id),
      ]);
    _ignored.clear();
  }

  int get _toRemoveCount {
    var n = 0;
    for (var i = 0; i < _groups.length; i++) {
      if (_ignored.contains(i)) continue;
      n += _groups[i].tracks.length - 1;
    }
    return n;
  }

  List<DuplicateResolution> _buildResolutions() {
    final result = <DuplicateResolution>[];
    for (var i = 0; i < _groups.length; i++) {
      if (_ignored.contains(i)) continue;
      final group = _groups[i];
      final keeperId = _keeperByGroup[i] ?? group.suggestedKeeper.id;
      final keeper = group.tracks.firstWhere(
        (t) => t.id == keeperId,
        orElse: () => group.suggestedKeeper,
      );
      result.add(DuplicateResolution(
        keeper: keeper,
        removed: [for (final t in group.tracks) if (t.id != keeper.id) t],
      ));
    }
    return result;
  }

  Future<void> _confirmAndMerge() async {
    final count = _toRemoveCount;
    if (count == 0 || _busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: Text('Retirer $count doublon${count > 1 ? 's' : ''} ?',
            style: AppTheme.titleMedium),
        content: Text(
          'Les exemplaires non gardés sont retirés de la bibliothèque. '
          'Leurs fichiers restent sur ton téléphone, et le favori et '
          'l\'ambiance sont transférés à l\'exemplaire conservé.',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Retirer',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final removed = await ref
        .read(trackProvider.notifier)
        .mergeDuplicates(_buildResolutions());
    if (!mounted) return;

    setState(() {
      _busy = false;
      _scan();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed > 0
              ? '$removed doublon${removed > 1 ? 's' : ''} retiré'
                  '${removed > 1 ? 's' : ''}'
              : 'Aucun doublon retiré',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.backgroundCardElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// « Musique/Rap » à partir de « /storage/emulated/0/Musique/Rap/x.mp3 ».
  String _folderOf(Track t) {
    final path = t.filePath;
    if (path == null || path.isEmpty) return 'Dossier inconnu';
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return 'Dossier inconnu';
    final dirs = parts.sublist(0, parts.length - 1);
    return dirs.length >= 2
        ? '${dirs[dirs.length - 2]}/${dirs.last}'
        : dirs.last;
  }

  @override
  Widget build(BuildContext context) {
    final removeCount = _toRemoveCount;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: 'Doublons',
                showBack: true,
                actions: [
                  AppHeaderButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Relancer la détection',
                    onTap: _busy ? null : () => setState(_scan),
                  ),
                ],
              ),
              Expanded(
                child: _groups.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
              ),
              if (_groups.isNotEmpty) _buildBottomBar(removeCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                size: 56, color: AppTheme.accentSuccess),
            const SizedBox(height: AppTheme.spacingM),
            Text('Aucun doublon', style: AppTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Ta bibliothèque est propre : aucun morceau n\'apparaît en '
              'double (même titre, même artiste, durée proche).',
              style: AppTheme.bodyMedium
                  .copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final extra = _groups.fold<int>(0, (a, g) => a + g.extraCount);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingS,
        AppTheme.spacingL,
        AppTheme.spacingL,
      ),
      itemCount: _groups.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppTheme.spacingM),
            child: Text(
              '${_groups.length} morceau${_groups.length > 1 ? 'x' : ''} '
              'en double · $extra exemplaire${extra > 1 ? 's' : ''} en trop.\n'
              'Touche un exemplaire pour choisir celui à garder.',
              style: AppTheme.bodyMedium
                  .copyWith(color: AppTheme.textSecondary),
            ),
          );
        }
        return _buildGroupCard(index - 1);
      },
    );
  }

  Widget _buildGroupCard(int groupIndex) {
    final group = _groups[groupIndex];
    final ignored = _ignored.contains(groupIndex);
    final keeperId = _keeperByGroup[groupIndex] ?? group.suggestedKeeper.id;

    return Opacity(
      opacity: ignored ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: AppTheme.glassDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${group.suggestedKeeper.title} · '
                    '${group.tracks.length} exemplaires',
                    style: AppTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            if (!_ignored.add(groupIndex)) {
                              _ignored.remove(groupIndex);
                            }
                          }),
                  child: Text(ignored ? 'Inclure' : 'Ignorer'),
                ),
              ],
            ),
            for (final t in group.tracks)
              _buildTrackRow(
                groupIndex: groupIndex,
                track: t,
                isKeeper: t.id == keeperId,
                ignored: ignored,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackRow({
    required int groupIndex,
    required Track track,
    required bool isKeeper,
    required bool ignored,
  }) {
    final accent = AppTheme.accentPrimary;
    final details = <String>[
      track.durationFormatted,
      _folderOf(track),
      if (track.isClassified && track.mood != MoodType.unknown)
        track.moodDisplayName,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingS),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        onTap: (ignored || _busy)
            ? null
            : () => setState(() => _keeperByGroup[groupIndex] = track.id),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingS),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            color: isKeeper && !ignored
                ? accent.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border.all(
              color: isKeeper && !ignored
                  ? accent.withValues(alpha: 0.5)
                  : AppTheme.border,
            ),
          ),
          child: Row(
            children: [
              TrackArtwork(track: track, size: 44, radius: AppTheme.radiusS),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.title,
                            style: AppTheme.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (track.isLiked) ...[
                          const SizedBox(width: AppTheme.spacingXS),
                          const Icon(Icons.favorite_rounded,
                              size: 14, color: Colors.redAccent),
                        ],
                      ],
                    ),
                    Text(
                      track.artist,
                      style: AppTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      details,
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                ignored
                    ? 'Ignoré'
                    : (isKeeper ? 'À garder' : 'Sera retiré'),
                style: AppTheme.labelSmall.copyWith(
                  color: ignored
                      ? AppTheme.textTertiary
                      : (isKeeper ? accent : AppTheme.accentError),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(int removeCount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingM,
        AppTheme.spacingL,
        AppTheme.spacingL,
      ),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accentPrimary,
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
          ),
          onPressed: (_busy || removeCount == 0) ? null : _confirmAndMerge,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cleaning_services_rounded),
          label: Text(
            removeCount == 0
                ? 'Rien à retirer'
                : 'Retirer $removeCount doublon${removeCount > 1 ? 's' : ''}',
          ),
        ),
      ),
    );
  }
}
