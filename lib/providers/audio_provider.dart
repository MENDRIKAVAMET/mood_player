import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_handler.dart';

// Audio handler provider
final audioHandlerProvider = FutureProvider<MoodAudioHandler>((ref) async {
  return await initAudioService();
});

// Current track provider
final currentTrackProvider = StreamProvider.autoDispose<MediaItem?>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.mediaItem;
});

// Playback state provider
final playbackStateProvider = StreamProvider.autoDispose<PlaybackState>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.playbackState;
});

// Queue provider
final queueProvider = StreamProvider.autoDispose<List<MediaItem>>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.queue;
});

// Is playing provider
final isPlayingProvider = Provider.autoDispose<bool>((ref) {
  final playbackState = ref.watch(playbackStateProvider);
  return playbackState.when(
    data: (state) => state.playing,
    loading: () => false,
    error: (_, __) => false,
  );
});

// Current position provider
final currentPositionProvider = Provider.autoDispose<Duration>((ref) {
  final playbackState = ref.watch(playbackStateProvider);
  return playbackState.when(
    data: (state) => state.updatePosition,
    loading: () => Duration.zero,
    error: (_, __) => Duration.zero,
  );
});

// Duration provider
final durationProvider = Provider.autoDispose<Duration>((ref) {
  final playbackState = ref.watch(playbackStateProvider);
  return playbackState.when(
    data: (state) => state.duration ?? Duration.zero,
    loading: () => Duration.zero,
    error: (_, __) => Duration.zero,
  );
});

// Repeat mode provider
final repeatModeProvider = StreamProvider.autoDispose<RepeatMode>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.repeatModeStream;
});

// Shuffle mode provider
final shuffleModeProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.shuffleModeStream;
});