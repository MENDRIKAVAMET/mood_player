import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/lyric_line.dart';
import '../../providers/audio_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';

/// Karaoke-style synced lyrics: fetches LRC lyrics for the given track and
/// auto-scrolls, highlighting whichever line is current based on playback
/// position - the classic line-by-line karaoke look, no AI/audio analysis
/// involved, just timestamps matched against the position stream.
class LyricsScreen extends ConsumerStatefulWidget {
  final Track track;

  const LyricsScreen({super.key, required this.track});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int _activeIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  void _maybeAutoScroll(int activeIndex) {
    if (activeIndex == _lastActiveIndex || activeIndex < 0) return;
    _lastActiveIndex = activeIndex;
    if (!_scrollController.hasClients) return;

    // Each line item is a fixed height (see itemExtent below), so the
    // target offset is a simple multiply - centers the active line a
    // little above screen middle rather than pinned to the very top.
    const itemExtent = 56.0;
    final target = (activeIndex * itemExtent) - 160;
    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(widget.track.mood);
    final position = ref.watch(currentPositionProvider);
    final lyricsAsync =
        ref.watch(lyricsProvider(lyricsKeyFor(widget.track)));

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(widget.track.title,
                style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(widget.track.artist,
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary)),
          ],
        ),
        centerTitle: true,
      ),
      body: lyricsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (_, __) => _EmptyState(
          icon: Icons.wifi_off_rounded,
          message: "Impossible de récupérer les paroles pour l'instant.",
        ),
        data: (result) {
          if (result.instrumental) {
            return const _EmptyState(
              icon: Icons.piano_off_outlined,
              message: 'Ce morceau est instrumental.',
            );
          }

          if (result.hasSynced) {
            final lines = result.synced!;
            final activeIndex = _activeIndex(lines, position);
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _maybeAutoScroll(activeIndex));

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingL, vertical: 200),
              itemCount: lines.length,
              itemExtent: 56,
              itemBuilder: (context, index) {
                final isActive = index == activeIndex;
                final isPast = index < activeIndex;
                return Container(
                  alignment: Alignment.center,
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 250),
                    style: (isActive
                            ? AppTheme.titleLarge
                            : AppTheme.bodyLarge)
                        .copyWith(
                      color: isActive
                          ? moodColors.primary
                          : AppTheme.textPrimary
                              .withValues(alpha: isPast ? 0.35 : 0.6),
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    ),
                    child: Text(
                      lines[index].text,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              },
            );
          }

          if (result.plain != null && result.plain!.isNotEmpty) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Text(
                result.plain!,
                textAlign: TextAlign.center,
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textPrimary.withValues(alpha: 0.85),
                  height: 1.8,
                ),
              ),
            );
          }

          return const _EmptyState(
            icon: Icons.lyrics_outlined,
            message: "Paroles introuvables pour ce morceau.",
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
