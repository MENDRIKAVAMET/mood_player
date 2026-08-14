import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/import_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mood_card.dart';
import '../../widgets/track_tile.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/classify_progress_banner.dart';
import '../../widgets/custom_mood_card.dart';
import '../../widgets/mood_editor_dialog.dart';
import '../mood/custom_mood_detail_screen.dart';
import '../player/player_screen.dart';
import '../mood/mood_detail_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ImportService _importService = ImportService();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Scan the device's full audio library on every app open: picks up
      // new files automatically and refreshes metadata/duration for tracks
      // already known, without touching their mood classification.
      ref.read(trackProvider.notifier).scanAndLoadTracks();
      ref.read(customMoodProvider.notifier).loadMoods();

      // Required on Android 13+ for the playback notification
      // (audio_service). Requested here rather than before runApp() -
      // doing it too early, before the Activity is fully attached to the
      // Flutter engine, crashes permission_handler when the result comes
      // back ("PluginProvider has not initialized"). Playback still works
      // even if this is denied, just without a visible notification.
      _requestNotificationPermission();
    });
  }

  Future<void> _requestNotificationPermission() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Non-critical: playback works regardless, just skip silently if the
      // platform can't handle the request for some reason.
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    final trackCountByMood = ref.watch(trackCountByMoodProvider);
    final currentTrack = ref.watch(currentTrackProvider);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1A1A2E),
              AppTheme.backgroundPrimary,
            ],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        // Header
                        SliverToBoxAdapter(
                          child: _buildHeader(),
                        ),

                        // Search bar
                        SliverToBoxAdapter(
                          child: _buildSearchBar(),
                        ),

                        // Action buttons
                        SliverToBoxAdapter(
                          child: _buildActionButtons(),
                        ),

                        // Custom user-created moods
                        SliverToBoxAdapter(
                          child: _buildCustomMoodsSection(),
                        ),

                        // Mood sections
                        if (trackCountByMood.values.any((count) => count > 0))
                          SliverToBoxAdapter(
                            child: _buildMoodSections(trackCountByMood),
                          ),

                        // All tracks section
                        SliverToBoxAdapter(
                          child: _buildAllTracksHeader(trackState),
                        ),

                        // Classification progress (elegant, non-spinner)
                        if (trackState.isClassifying)
                          SliverToBoxAdapter(
                            child: ClassifyProgressBanner(
                              progress: trackState.classifyProgress!,
                              total: trackState.classifyTotal!,
                              statusMessage: trackState.classifyStatusMessage,
                            ),
                          ),

                        // Track list
                        if (trackState.isLoading)
                          SliverToBoxAdapter(
                            child: Column(
                              children: List.generate(
                                5,
                                (_) => SkeletonLoader.trackTile(),
                              ),
                            ),
                          )
                        else if (trackState.filteredTracks.isEmpty)
                          SliverToBoxAdapter(
                            child: _buildEmptyState(),
                          )
                        else
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final track = trackState.filteredTracks[index];
                                final isPlaying = currentTrack.valueOrNull?.id == track.id.toString();
                                return TrackTile(
                                  track: track,
                                  index: index,
                                  isPlaying: isPlaying,
                                  onTap: () => _playTrack(track),
                                  onPlay: () => _playTrack(track),
                                );
                              },
                              childCount: trackState.filteredTracks.length,
                            ),
                          ),

                        // Bottom padding for mini player
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 100),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Mini player (at bottom, above any potential bottom nav)
              if (currentTrack.valueOrNull != null)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: MiniPlayer(currentTrack: _mediaItemToTrack(currentTrack.valueOrNull!)),
                ),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_greeting $_greetingEmoji',
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ).animate().fadeIn(duration: AppTheme.animSlow),
              const SizedBox(height: AppTheme.spacingXS),
              Text(
                'Mood Player',
                style: AppTheme.displayLarge,
              ).animate().fadeIn(
                    duration: AppTheme.animSlow,
                    delay: const Duration(milliseconds: 100),
                  ).slideX(
                    begin: 0.05,
                    end: 0,
                    duration: AppTheme.animSlow,
                    delay: const Duration(milliseconds: 100),
                  ),
            ],
          ),
          // Menu button
          GestureDetector(
            onTap: () => _showMenuSheet(context),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                border: Border.all(
                  color: AppTheme.border.withValues(alpha: 0.3),
                  width: 1,
                ),
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
        onTap: () => _showSearchDialog(context),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(
              color: AppTheme.border.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: AppTheme.spacingL),
              Icon(
                Icons.search_rounded,
                color: AppTheme.textTertiary,
                size: 20,
              ),
              const SizedBox(width: AppTheme.spacingM),
              Text(
                'Rechercher morceaux, artistes...',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textTertiary,
                ),
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
            icon: Icons.add_rounded,
            label: 'Ajouter',
            onTap: () => _showAddTrackDialog(context),
          ),
          const SizedBox(width: AppTheme.spacingM),
          _buildActionButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Classifier',
            onTap: () => _classifyAllTracks(),
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
            color: AppTheme.backgroundCard,
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            border: Border.all(
              color: AppTheme.border.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: AppTheme.accentPrimary,
              ),
              const SizedBox(width: AppTheme.spacingS),
              Text(
                label,
                style: AppTheme.labelMedium.copyWith(
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomMoodsSection() {
    final customMoods = ref.watch(customMoodProvider).moods;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Mes moods', customMoods.isEmpty ? null : customMoods.length),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
            itemCount: customMoods.length + 1,
            itemBuilder: (context, index) {
              if (index == customMoods.length) {
                return CreateMoodCard(onTap: _createCustomMood);
              }
              final mood = customMoods[index];
              return CustomMoodCard(
                mood: mood,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CustomMoodDetailScreen(mood: mood),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _createCustomMood() async {
    final result = await showMoodEditorDialog(context);
    if (result == null) return;
    await ref.read(customMoodProvider.notifier).createMood(
          name: result.$1,
          icon: result.$2,
          colorValue: result.$3,
        );
  }

  Widget _buildMoodSections(Map<MoodType, int> trackCountByMood) {
    final moodsWithTracks = trackCountByMood.entries
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList();

    if (moodsWithTracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Par ambiance', null),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingL,
            ),
            itemCount: moodsWithTracks.length,
            itemBuilder: (context, index) {
              final mood = moodsWithTracks[index];
              final count = trackCountByMood[mood] ?? 0;
              return MoodCard(
                mood: mood,
                trackCount: count,
                onTap: () => _openMoodDetail(mood),
              );
            },
          ),
        ),
      ],
    ).animate().fadeIn(
          duration: AppTheme.animSlow,
          delay: const Duration(milliseconds: 400),
        );
  }

  Widget _buildSectionHeader(String title, int? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingS,
      ),
      child: Row(
        children: [
          Text(title, style: AppTheme.headlineMedium),
          if (count != null) ...[
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
                '$count',
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.accentPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllTracksHeader(TrackState trackState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingL,
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
              '${trackState.filteredTracks.length}',
              style: AppTheme.labelSmall.copyWith(color: AppTheme.accentPrimary),
            ),
          ),
          const Spacer(),
          if (trackState.minDurationSeconds != null)
            IconButton(
              tooltip: 'Filtre de durée actif (${trackState.minDurationSeconds}s min)',
              icon: Icon(Icons.timer_outlined, color: AppTheme.accentPrimary, size: 20),
              onPressed: _showMinDurationDialog,
            )
          else
            IconButton(
              tooltip: 'Masquer les morceaux courts',
              icon: Icon(Icons.timer_outlined, color: AppTheme.textSecondary, size: 20),
              onPressed: _showMinDurationDialog,
            ),
          IconButton(
            tooltip: 'Trier',
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
              child: Text('Réinitialiser', style: TextStyle(color: AppTheme.textSecondary)),
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
            ).animate().scale(
                  duration: AppTheme.animSlow,
                ),
            const SizedBox(height: AppTheme.spacingXL),
            Text(
              'Votre bibliothèque est vide',
              style: AppTheme.headlineMedium.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Importez des morceaux pour commencer\nà explorer vos ambiances musicales',
              style: AppTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppTheme.spacingXL),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildEmptyActionButton(
                  icon: Icons.file_upload_rounded,
                  label: 'Importer',
                  onTap: () => _showImportOptions(context),
                ),
                const SizedBox(width: AppTheme.spacingM),
                _buildEmptyActionButton(
                  icon: Icons.add_rounded,
                  label: 'Ajouter',
                  onTap: () => _showAddTrackDialog(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingL,
          vertical: AppTheme.spacingM,
        ),
        decoration: BoxDecoration(
          color: AppTheme.accentPrimary,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.textInverse),
            const SizedBox(width: AppTheme.spacingS),
            Text(
              label,
              style: AppTheme.labelLarge.copyWith(
                color: AppTheme.textInverse,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convert a MediaItem (from the audio service) into a Track for the UI
  Track _mediaItemToTrack(MediaItem item) {
    return Track()
      ..id = int.tryParse(item.id) ?? 0
      ..title = item.title
      ..artist = item.artist ?? 'Artiste inconnu'
      ..album = (item.album?.isNotEmpty ?? false) ? item.album : null
      ..filePath = item.extras?['filePath'] as String?
      ..moodIndex = item.extras?['mood'] != null
          ? MoodTypeExtension.fromString(item.extras!['mood'] as String).index
          : null
      ..moodConfidence = (item.extras?['moodConfidence'] as num?)?.toDouble();
  }

  void _playTrack(Track track) {
    final trackState = ref.read(trackProvider);
    final tracks = trackState.filteredTracks;
    final index = tracks.indexWhere((t) => t.id == track.id);
    
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            PlayerScreen(
              track: track,
              tracks: tracks,
              initialIndex: index >= 0 ? index : 0,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(begin: const Offset(0.0, 1.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: AppTheme.animPageTransition,
      ),
    );
  }

  void _openMoodDetail(MoodType mood) {
    final tracks = ref.read(tracksByMoodProvider(mood));
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MoodDetailScreen(mood: mood, tracks: tracks),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: AppTheme.animPageTransition,
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXL),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
                icon: Icons.edit_rounded,
                title: 'Ajouter manuellement',
                onTap: () {
                  Navigator.pop(context);
                  _showAddTrackDialog(context);
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
        style: AppTheme.bodyLarge.copyWith(
          color: color ?? AppTheme.textPrimary,
        ),
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXL),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
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
              Text(
                'Importer de la musique',
                style: AppTheme.headlineMedium,
              ),
              const SizedBox(height: AppTheme.spacingL),
              _buildImportOption(
                icon: Icons.audio_file_rounded,
                title: 'Fichier audio',
                subtitle: 'Sélectionner un fichier',
                onTap: () async {
                  Navigator.pop(context);
                  await _importSingleFile();
                },
              ),
              _buildImportOption(
                icon: Icons.queue_music_rounded,
                title: 'Plusieurs fichiers',
                subtitle: 'Sélectionner plusieurs fichiers',
                onTap: () async {
                  Navigator.pop(context);
                  await _importMultipleFiles();
                },
              ),
              _buildImportOption(
                icon: Icons.folder_rounded,
                title: 'Dossier complet',
                subtitle: 'Importer tous les fichiers audio',
                onTap: () async {
                  Navigator.pop(context);
                  await _importFolder();
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

  Future<void> _importSingleFile() async {
    final result = await _importService.pickAudioFile();
    _handleImportResult(result);
  }

  Future<void> _importMultipleFiles() async {
    final result = await _importService.pickMultipleAudioFiles();
    _handleImportResult(result);
  }

  Future<void> _importFolder() async {
    final result = await _importService.pickFolderAndImport();
    _handleImportResult(result);
  }

  void _handleImportResult(ImportResult result) {
    if (result.isCancelled) return;

    if (result.isSuccess && result.tracks != null) {
      for (final track in result.tracks!) {
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
          'Voulez-vous classifier tous les morceaux non classifiés avec Gemini ? '
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

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Rechercher', style: AppTheme.headlineMedium),
        content: TextField(
          controller: _searchController,
          style: AppTheme.bodyLarge.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'Rechercher par titre, artiste...',
            hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
            filled: true,
            fillColor: AppTheme.backgroundCard,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              borderSide: BorderSide.none,
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              ref.read(trackProvider.notifier).searchTracks(_searchController.text);
              Navigator.pop(context);
            },
            child: Text('Rechercher', style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
    );
  }

  void _showAddTrackDialog(BuildContext context) {
    final titleController = TextEditingController();
    final artistController = TextEditingController();
    final albumController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text('Ajouter un morceau', style: AppTheme.headlineMedium),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Titre',
                labelStyle: AppTheme.bodyMedium,
                filled: true,
                fillColor: AppTheme.backgroundCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            TextField(
              controller: artistController,
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Artiste',
                labelStyle: AppTheme.bodyMedium,
                filled: true,
                fillColor: AppTheme.backgroundCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingM),
            TextField(
              controller: albumController,
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: 'Album (optionnel)',
                labelStyle: AppTheme.bodyMedium,
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  artistController.text.isNotEmpty) {
                final track = Track()
                  ..title = titleController.text
                  ..artist = artistController.text
                  ..album =
                      albumController.text.isNotEmpty ? albumController.text : null
                  ..createdAt = DateTime.now()
                  ..updatedAt = DateTime.now();

                ref.read(trackProvider.notifier).addTrack(track);
                Navigator.pop(context);
              }
            },
            child: Text('Ajouter', style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
    );
  }
}
