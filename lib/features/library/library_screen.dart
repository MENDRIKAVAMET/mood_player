import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
      // sans attendre que l'utilisateur visite « Pour vous ».
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: AppTheme.backgroundCardElevated,
            duration: const Duration(seconds: 4),
          ),
        );
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
                title: 'Mood Player',
                actions: [
                  AppHeaderButton(
                    icon: Icons.auto_awesome_rounded,
                    tooltip: 'Classifier',
                    color: AppTheme.accentPrimary,
                    onTap: _classifyAllTracks,
                  ),
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
                      statusMessage: trackState.classifyStatusMessage,
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
                SliverToBoxAdapter(child: _buildEmptyState())
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

  Widget _buildAllTracksHeader(TrackState trackState) {
    final tracks = trackState.filteredTracks;
    final hasTracks = tracks.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingS,
        AppTheme.spacingS,
      ),
      child: Row(
        children: [
          Text('Tous les morceaux', style: AppTheme.headlineMedium),
          const SizedBox(width: AppTheme.spacingS),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingS,
              vertical: AppTheme.spacingXXS,
            ),
            decoration: BoxDecoration(
              color: AppTheme.accentPrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusS),
            ),
            child: Text(
              '${tracks.length}',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.accentPrimary),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Tout lire',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.play_circle_fill_rounded,
              color: hasTracks ? AppTheme.accentPrimary : AppTheme.textTertiary,
              size: 26,
            ),
            onPressed: hasTracks ? () => playAll(context, tracks) : null,
          ),
          IconButton(
            tooltip: 'Lecture aléatoire',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.shuffle_rounded,
              color: hasTracks ? AppTheme.accentPrimary : AppTheme.textTertiary,
              size: 22,
            ),
            onPressed: hasTracks ? () => playShuffled(context, tracks) : null,
          ),
          IconButton(
            tooltip: trackState.minDurationSeconds != null
                ? 'Filtre de durée actif (${trackState.minDurationSeconds}s min)'
                : 'Masquer les morceaux courts',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.timer_outlined,
              color: trackState.minDurationSeconds != null
                  ? AppTheme.accentPrimary
                  : AppTheme.textSecondary,
              size: 20,
            ),
            onPressed: _showMinDurationDialog,
          ),
          IconButton(
            tooltip: 'Trier',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.sort_rounded, color: AppTheme.textSecondary, size: 22),
            onPressed: () => _showSortMenu(trackState.sortOption),
          ),
        ],
      ),
    );
  }

  void _showSortMenu(TrackSortOption current) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppTheme.spacingM),
              Text('Trier par', style: AppTheme.headlineMedium),
              const SizedBox(height: AppTheme.spacingS),
              for (final option in TrackSortOption.values)
                ListTile(
                  title: Text(option.label, style: AppTheme.bodyMedium),
                  trailing: option == current
                      ? Icon(Icons.check, color: AppTheme.accentPrimary)
                      : null,
                  onTap: () {
                    ref.read(trackProvider.notifier).setSortOption(option);
                    Navigator.pop(context);
                  },
                ),
              const SizedBox(height: AppTheme.spacingM),
            ],
          ),
        );
      },
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXXXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: 48,
                color: AppTheme.accentPrimary,
              ),
            ).animate().scale(duration: AppTheme.animSlow),
            const SizedBox(height: AppTheme.spacingXL),
            Text(
              'Votre bibliothèque est vide',
              style: AppTheme.headlineMedium.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Importez des morceaux pour commencer\nà explorer vos ambiances musicales',
              style: AppTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Rendez-vous dans votre profil pour importer votre musique.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
                icon: Icons.auto_awesome_rounded,
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
