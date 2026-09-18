import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/import_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/classify_progress_banner.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/track_options_sheet.dart';
import '../search/search_screen.dart';

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
  final ImportService _importService = ImportService();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Scan de toute la bibliothèque audio de l'appareil à chaque
      // ouverture : récupère les nouveaux fichiers et rafraîchit les
      // métadonnées des morceaux déjà connus, sans toucher à leur
      // classification.
      ref.read(trackProvider.notifier).scanAndLoadTracks();
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

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'Bonne nuit';
    if (hour < 12) return 'Bonjour';
    if (hour < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  String get _greetingEmoji {
    final hour = DateTime.now().hour;
    if (hour < 6) return '🌙';
    if (hour < 12) return '☀️';
    if (hour < 18) return '🌤️';
    return '🌅';
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
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildSearchBar()),
              SliverToBoxAdapter(child: _buildActionButtons()),
              SliverToBoxAdapter(child: _buildAllTracksHeader(trackState)),

              if (trackState.isClassifying)
                SliverToBoxAdapter(
                  child: ClassifyProgressBanner(
                    progress: trackState.classifyProgress!,
                    total: trackState.classifyTotal!,
                    statusMessage: trackState.classifyStatusMessage,
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
                      return TrackTile(
                        track: track,
                        index: index,
                        isPlaying: isPlaying,
                        onTap: () => openPlayer(
                          context,
                          track: track,
                          tracks: trackState.filteredTracks,
                        ),
                        onPlay: () => openPlayer(
                          context,
                          track: track,
                          tracks: trackState.filteredTracks,
                        ),
                        onMore: () => showTrackOptionsSheet(context, ref, track),
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
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingL,
        AppTheme.spacingL,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$_greeting $_greetingEmoji',
                  style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
                ).animate().fadeIn(duration: AppTheme.animSlow),
                const SizedBox(height: AppTheme.spacingXS),
                Text('Mood Player', style: AppTheme.displayLarge)
                    .animate()
                    .fadeIn(
                      duration: AppTheme.animSlow,
                      delay: const Duration(milliseconds: 100),
                    )
                    .slideX(
                      begin: 0.05,
                      end: 0,
                      duration: AppTheme.animSlow,
                      delay: const Duration(milliseconds: 100),
                    ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _showMenuSheet(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: AppTheme.cardGradient,
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                border: Border.all(color: AppTheme.border, width: 1),
              ),
              child: const Icon(
                Icons.more_horiz_rounded,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingL,
        AppTheme.spacingXL,
        0,
      ),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SearchScreen()),
        ),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: AppTheme.cardGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Row(
            children: [
              const SizedBox(width: AppTheme.spacingL),
              Icon(Icons.search_rounded, color: AppTheme.textTertiary, size: 20),
              const SizedBox(width: AppTheme.spacingM),
              Text(
                'Rechercher morceaux, artistes...',
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(
            duration: AppTheme.animSlow,
            delay: const Duration(milliseconds: 200),
          ),
    );
  }

  /// Deux actions seulement : importer et classifier. Le bouton
  /// « Ajouter » (saisie manuelle titre/artiste) a été retiré — il créait
  /// une fiche sans fichier audio associé, donc un morceau impossible à
  /// lire.
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingL,
        AppTheme.spacingXL,
        0,
      ),
      child: Row(
        children: [
          _buildActionButton(
            icon: Icons.file_upload_rounded,
            label: 'Importer',
            onTap: () => _showImportOptions(context),
          ),
          const SizedBox(width: AppTheme.spacingM),
          _buildActionButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Classifier',
            onTap: _classifyAllTracks,
          ),
        ],
      ).animate().fadeIn(
            duration: AppTheme.animSlow,
            delay: const Duration(milliseconds: 300),
          ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            gradient: AppTheme.cardGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: AppTheme.accentPrimary),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                label,
                style: AppTheme.labelMedium.copyWith(color: AppTheme.textPrimary),
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
              child: const Icon(
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
            const SizedBox(height: AppTheme.spacingXL),
            GestureDetector(
              onTap: () => _showImportOptions(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingL,
                  vertical: AppTheme.spacingM,
                ),
                decoration: BoxDecoration(
                  gradient: AppTheme.brandGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  boxShadow: AppTheme.coloredShadow(AppTheme.brandMid),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.file_upload_rounded,
                        size: 18, color: AppTheme.textPrimary),
                    const SizedBox(width: AppTheme.spacingS),
                    Text(
                      'Importer',
                      style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ),
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
        decoration: const BoxDecoration(
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

  void _showImportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
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
              Text('Importer de la musique', style: AppTheme.headlineMedium),
              const SizedBox(height: AppTheme.spacingL),
              _buildImportOption(
                icon: Icons.audio_file_rounded,
                title: 'Fichier audio',
                subtitle: 'Sélectionner un fichier',
                onTap: () async {
                  Navigator.pop(context);
                  _handleImportResult(await _importService.pickAudioFile());
                },
              ),
              _buildImportOption(
                icon: Icons.queue_music_rounded,
                title: 'Plusieurs fichiers',
                subtitle: 'Sélectionner plusieurs fichiers',
                onTap: () async {
                  Navigator.pop(context);
                  _handleImportResult(await _importService.pickMultipleAudioFiles());
                },
              ),
              _buildImportOption(
                icon: Icons.folder_rounded,
                title: 'Dossier complet',
                subtitle: 'Importer tous les fichiers audio',
                onTap: () async {
                  Navigator.pop(context);
                  _handleImportResult(await _importService.pickFolderAndImport());
                },
              ),
              const SizedBox(height: AppTheme.spacingL),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.accentPrimary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: Icon(icon, color: AppTheme.accentPrimary),
      ),
      title: Text(title, style: AppTheme.titleMedium),
      subtitle: Text(subtitle, style: AppTheme.bodySmall),
      onTap: onTap,
    );
  }

  void _handleImportResult(ImportResult result) {
    if (!mounted || result.isCancelled) return;

    if (result.isSuccess && result.tracks != null) {
      for (final Track track in result.tracks!) {
        ref.read(trackProvider.notifier).addTrack(track);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.trackCount} morceau(x) importé(s)',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          ),
          backgroundColor: AppTheme.backgroundCardElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          action: result.errorCount > 0
              ? SnackBarAction(
                  label: 'Voir erreurs',
                  textColor: AppTheme.accentPrimary,
                  onPressed: () => _showImportErrors(result.errors),
                )
              : null,
        ),
      );
    } else if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage!,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          ),
          backgroundColor: AppTheme.accentError,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
        ),
      );
    }
  }

  void _showImportErrors(List<String>? errors) {
    if (errors == null || errors.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text("Erreurs d'import", style: AppTheme.headlineMedium),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: errors
                .map((error) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
                      child: Text('• $error', style: AppTheme.bodyMedium),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fermer', style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
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
