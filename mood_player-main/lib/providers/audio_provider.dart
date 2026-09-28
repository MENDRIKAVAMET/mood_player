import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_handler.dart';

// Audio handler provider
final audioHandlerProvider = FutureProvider<MoodAudioHandler>((ref) async {
  try {
    return await initAudioService();
  } catch (e, st) {
    // ignore: avoid_print
    print('audioHandlerProvider: failed to initialize audio service: $e\n$st');
    rethrow;
  }
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
    error: (_, _) => false,
  );
});

// Current position provider
final currentPositionProvider = Provider.autoDispose<Duration>((ref) {
  final playbackState = ref.watch(playbackStateProvider);
  return playbackState.when(
    data: (state) => state.updatePosition,
    loading: () => Duration.zero,
    error: (_, _) => Duration.zero,
  );
});

// Duration provider
final durationProvider = StreamProvider.autoDispose<Duration>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.durationStream;
});

// Repeat mode provider
final repeatModeProvider = StreamProvider.autoDispose<PlayerRepeatMode>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.repeatModeStream;
});

// Shuffle mode provider
final shuffleModeProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final audioHandler = await ref.watch(audioHandlerProvider.future);
  yield* audioHandler.shuffleModeStream;
});