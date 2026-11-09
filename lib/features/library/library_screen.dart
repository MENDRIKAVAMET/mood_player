import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/classify_progress_banner.dart';
import '../../widgets/app_header.dart';
import '../../widgets/header_actions.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/track_list_tools.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/track_options_sheet.dart';
import '../../utils/app_error.dart';

/// Onglet « Bibliothèque » : uniquement la liste complète des morceaux.
///
/// Les sections d'ambiances vivent désormais dans leur propre onglet.
/// Empilées ici au-dessus de la liste, elles occupaient à elles seules
/// plus d'un écran de hauteur (en-tête + recherche + actions + deux
/// carrousels de 180 px), si bien que la liste démarrait sous la ligne de
/// flottaison : elle était bien là et scrollable, mais invisible sans
/// faire défiler — exactement le symptôme observé.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _bannerKey = GlobalKey();
  late final TrackListLocator _locator = TrackListLocator(
    controller: _scrollController,
    leadingKeys: [_headerKey, _bannerKey],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Scan de toute la bibliothèque audio de l'appareil à chaque
      // ouverture : récupère les nouveaux fichiers et rafraîchit les
      // métadonnées des morceaux déjà connus, sans toucher à leur
      // classification.
      ref.read(trackProvider.notifier).scanAndLoadTracks().then((_) {
        // « Volume uniforme » : mesure les nouveaux morceaux (ne fait rien
        // si la fonction est désactivée).
        if (mounted) ref.read(loudnessProvider.notifier).analyzeLibrary();
      });
      ref.read(customMoodProvider.notifier).loadMoods();

      // Démarre le suivi des écoutes réelles dès l'ouverture de l'app,
      // sans attendre que l'utilisateur visite « Découvertes ».
      ref.read(playbackStatsProvider);

      _requestNotificationPermission();
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.status;
      if (status.isGranted) return;

      if (status.isPermanentlyDenied) {
        // Après un refus définitif, Android ne réaffichera plus jamais la
        // boîte système : request() renverrait « denied » en silence. Le
        // seul chemin restant est la page de réglages de l'app.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                "La notification de lecture est désactivée. Active-la dans "
                "les paramètres de l'app pour la voir apparaître.",
              ),
              action: SnackBarAction(
                label: 'Paramètres',
                onPressed: openAppSettings,
              ),
            ),
          );
        }
        return;
      }

      await Permission.notification.request();
    } catch (_) {
      // Non critique : la lecture fonctionne quoi qu'il arrive.
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(trackProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        showAppError(context, next.error!);
      }
    });

    final trackState = ref.watch(trackProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              AppHeader.tab(
                title: 'Aura',
                actions: [
                  const HeaderActions(),
                  AppHeaderButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'Plus d\'options',
                    onTap: () => _showMenuSheet(context),
                  ),
                ],
              ),
              Expanded(
                child: Stack(
                  children: [
                    TrackListScrollbar(
                      controller: _scrollController,
                      child: CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _headerKey,
                  child: _buildAllTracksHeader(trackState),
                ),
              ),

              if (trackState.isClassifying)
                SliverToBoxAdapter(
                  child: KeyedSubtree(
                    key: _bannerKey,
                    child: ClassifyProgressBanner(
                      progress: trackState.classifyProgress!,
                      total: trackState.classifyTotal!,
                    ),
                  ),
                ),

              if (trackState.isLoading)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, _) => SkeletonLoader.trackTile(),
                    childCount: 5,
                  ),
                )
              else if (trackState.filteredTracks.isEmpty)
                SliverToBoxAdapter(child: _buildEmptyState(trackState))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final track = trackState.filteredTracks[index];
                      final isPlaying =
                          currentTrack.valueOrNull?.id == track.id.toString();
                      return KeyedSubtree(
                        key: _locator.keyFor(track.id),
                        child: TrackTile(
                          track: track,
                          index: index,
                          isPlaying: isPlaying,
                          onTap: () => openPlayer(
                            context,
                            track: track,
                            tracks: trackState.filteredTracks,
                          ),
                          onPlay: () => togglePlayTrack(
                              ref, track, trackState.filteredTracks),
                          onMore: () =>
                              showTrackOptionsSheet(context, ref, track),
                        ),
                      );
                    },
                    childCount: trackState.filteredTracks.length,
                  ),
                ),

              // Marge basse pour le mini-lecteur et la barre d'onglets.
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
                      ),
                    ),
                    LocateTrackButton(
                      locator: _locator,
                      tracks: trackState.filteredTracks,
                      bottom: 100,
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

  String _formatTotal(int ms) {
    final totalMinutes = Duration(milliseconds: ms).inMinutes;
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '$m min';
    return '$h h ${m.toString().padLeft(2, '0')} min';
  }

  IconData _sortIcon(TrackSortOption option) {
    switch (option) {
      case TrackSortOption.nameAsc:
      case TrackSortOption.nameDesc:
        return Icons.sort_by_alpha_rounded;
      case TrackSortOption.dateNewest:
      case TrackSortOption.dateOldest:
        return Icons.schedule_rounded;
    }
  }

  /// Carte de résumé de la bibliothèque : titre, nombre de morceaux et durée
  /// totale, les deux actions de lecture en grand, puis le tri et le filtre
  /// de durée en pastilles lisibles (plutôt que des icônes sans libellé).
  Widget _buildAllTracksHeader(TrackState trackState) {
    final tracks = trackState.filteredTracks;
    final hasTracks = tracks.isNotEmpty;
    final minSeconds = trackState.minDurationSeconds;

    var totalMs = 0;
    for (final t in tracks) {
      totalMs += t.duration ?? 0;
    }
    final summary = hasTracks
        ? '${tracks.length} morceau${tracks.length > 1 ? 'x' : ''}'
            '${totalMs > 0 ? ', ${_formatTotal(totalMs)}' : ''}'
        : 'Aucun morceau à afficher';

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingM,
        AppTheme.spacingL,
        AppTheme.spacingS,
      ),
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandTop.withValues(alpha: 0.22),
            AppTheme.brandBottom.withValues(alpha: 0.08),
            AppTheme.backgroundCard,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tous les morceaux',
            style: AppTheme.headlineMedium.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            summary,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacingL),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _LibraryActionButton(
                  label: 'Tout lire',
                  icon: Icons.play_arrow_rounded,
                  onTap: hasTracks ? () => playAll(context, tracks) : null,
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                flex: 2,
                child: _LibraryActionButton(
                  label: 'Aléatoire',
                  icon: Icons.shuffle_rounded,
                  glass: true,
                  onTap: hasTracks ? () => playShuffled(context, tracks) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          Wrap(
            spacing: AppTheme.spacingS,
            runSpacing: AppTheme.spacingS,
            children: [
              _ToolChip(
                icon: _sortIcon(trackState.sortOption),
                label: trackState.sortOption.label,
                onTap: () => _showSortMenu(trackState.sortOption),
              ),
              _ToolChip(
                icon: Icons.timer_outlined,
                label: minSeconds != null
                    ? 'Plus de $minSeconds s'
                    : 'Masquer les courts',
                active: minSeconds != null,
                onTap: _showMinDurationDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSortMenu(TrackSortOption current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXL),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: AppTheme.spacingM),
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingXL,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Trier par', style: AppTheme.headlineMedium),
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              for (final option in TrackSortOption.values)
                ListTile(
                  selected: option == current,
                  selectedColor: AppTheme.accentPrimary,
                  selectedTileColor:
                      AppTheme.accentPrimary.withValues(alpha: 0.10),
                  leading: Icon(
                    _sortIcon(option),
                    color: option == current
                        ? AppTheme.accentPrimary
                        : AppTheme.textSecondary,
                  ),
                  title: Text(
                    option.label,
                    style: AppTheme.bodyLarge.copyWith(
                      color: option == current
                          ? AppTheme.accentPrimary
                          : AppTheme.textPrimary,
                      fontWeight: option == current
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  trailing: option == current
                      ? Icon(Icons.check_rounded, color: AppTheme.accentPrimary)
                      : null,
                  onTap: () {
                    ref.read(trackProvider.notifier).setSortOption(option);
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: AppTheme.spacingM),
            ],
          ),
        ),
      ),
    );
  }

  void _showMinDurationDialog() {
    final current = ref.read(trackProvider).minDurationSeconds;
    final controller = TextEditingController(
      text: current != null ? current.toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Masquer les morceaux courts', style: AppTheme.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masque de la liste les fichiers audio plus courts que la durée indiquée '
              '(utile pour cacher les sonneries ou notifications importées avec le scan).',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacingM),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: AppTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Durée minimale en secondes',
                hintStyle: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                suffixText: 'secondes',
                filled: true,
                fillColor: AppTheme.backgroundCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () {
                ref.read(trackProvider.notifier).setMinDurationFilter(null);
                Navigator.pop(context);
              },
              child: Text('Réinitialiser',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final seconds = int.tryParse(controller.text.trim());
              if (seconds != null && seconds > 0) {
                ref.read(trackProvider.notifier).setMinDurationFilter(seconds);
              }
              Navigator.pop(context);
            },
            child: Text('Appliquer', style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
    );
  }

  /// État vide. Deux cas bien distincts : la bibliothèque est réellement
  /// vide (on propose un scan), ou des morceaux existent mais le filtre de
  /// durée les cache tous (on propose de le retirer).
  Widget _buildEmptyState(TrackState trackState) {
    final filterHidesAll = trackState.tracks.isNotEmpty &&
        trackState.filteredTracks.isEmpty &&
        trackState.minDurationSeconds != null;

    final title = filterHidesAll
        ? 'Tous vos morceaux sont masqués'
        : 'Rien à écouter pour l\'instant';
    final body = filterHidesAll
        ? 'Le filtre masque les morceaux de moins de '
            '${trackState.minDurationSeconds} secondes, et aucun n\'est plus '
            'long.'
        : 'Aura n\'a trouvé aucun morceau. Lancez un scan pour parcourir la '
            'musique de votre appareil.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXXL,
        AppTheme.spacingXL,
        AppTheme.spacingXL,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: AppTheme.brandGradient,
              boxShadow: AppTheme.coloredShadow(AppTheme.accentPrimary),
            ),
            child: Icon(
              filterHidesAll
                  ? Icons.timer_off_rounded
                  : Icons.library_music_rounded,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXL),
          Text(
            title,
            style: AppTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            body,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spacingXL),
          SizedBox(
            width: 260,
            child: _LibraryActionButton(
              label:
                  filterHidesAll ? 'Retirer le filtre' : 'Scanner mon appareil',
              icon: filterHidesAll
                  ? Icons.filter_alt_off_rounded
                  : Icons.refresh_rounded,
              onTap: () {
                final notifier = ref.read(trackProvider.notifier);
                if (filterHidesAll) {
                  notifier.setMinDurationFilter(null);
                } else {
                  notifier.scanAndLoadTracks();
                }
              },
            ),
          ),
          if (!filterHidesAll) ...[
            const SizedBox(height: AppTheme.spacingM),
            Text(
              'Vous pouvez aussi importer des fichiers depuis votre profil.',
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  void _showMenuSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: AppTheme.spacingM),
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),
              _buildMenuOption(
                icon: Icons.refresh_rounded,
                title: 'Rescanner la bibliothèque',
                onTap: () {
                  Navigator.pop(context);
                  ref.read(trackProvider.notifier).scanAndLoadTracks();
                },
              ),
              _buildMenuOption(
                icon: Icons.mood_rounded,
                title: 'Classifier tous les morceaux',
                onTap: () {
                  Navigator.pop(context);
                  _classifyAllTracks();
                },
              ),
              const Divider(color: AppTheme.divider),
              _buildMenuOption(
                icon: Icons.delete_sweep_rounded,
                title: 'Supprimer tout',
                color: AppTheme.accentError,
                onTap: () {
                  Navigator.pop(context);
                  _confirmClearAllTracks(context);
                },
              ),
              const SizedBox(height: AppTheme.spacingM),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    Color? color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? AppTheme.textPrimary),
      title: Text(
        title,
        style: AppTheme.bodyLarge.copyWith(color: color ?? AppTheme.textPrimary),
      ),
      onTap: onTap,
    );
  }

  void _classifyAllTracks() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Classifier tous les morceaux', style: AppTheme.headlineMedium),
        content: Text(
          'Voulez-vous classifier tous les morceaux non classifiés ? '
          'Cela peut prendre du temps selon le nombre de morceaux.',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(trackProvider.notifier).classifyAllUnclassified();
            },
            child: Text('Classifier', style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllTracks(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Supprimer tous les morceaux', style: AppTheme.headlineMedium),
        content: Text(
          'Êtes-vous sûr de vouloir supprimer tous les morceaux ? '
          'Cette action est irréversible.',
          style: AppTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(trackProvider.notifier).clearAllTracks();
            },
            child: Text('Supprimer', style: TextStyle(color: AppTheme.accentError)),
          ),
        ],
      ),
    );
  }
}

/// Bouton d'action de la bibliothèque (Tout lire, Aléatoire, Scanner…).
/// La version principale suit le style de bouton choisi par l'utilisateur ;
/// la version [glass] reste un bouton secondaire en verre.
class _LibraryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool glass;
  final VoidCallback? onTap;

  const _LibraryActionButton({
    required this.label,
    required this.icon,
    this.glass = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingM,
                vertical: AppTheme.spacingS,
              ),
              decoration: AppTheme.primaryButton(
                pill: true,
                glowBlur: 16,
                glowAlpha: 0.35,
                style: glass ? ButtonStyleKind.glass : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: AppTheme.textPrimary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.labelLarge
                          .copyWith(color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille de réglage (tri, filtre de durée) : l'état actuel est écrit en
/// toutes lettres, et la pastille s'allume quand un filtre est actif.
class _ToolChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.accentPrimary : AppTheme.textSecondary;
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.accentPrimary.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              border: Border.all(
                color: active
                    ? AppTheme.accentPrimary.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTheme.bodySmall.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
