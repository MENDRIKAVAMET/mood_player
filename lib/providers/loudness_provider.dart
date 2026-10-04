import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/loudness_service.dart';
import 'equalizer_provider.dart';
import 'track_provider.dart';

class LoudnessState {
  final bool running;
  final int done;
  final int total;

  const LoudnessState({this.running = false, this.done = 0, this.total = 0});
}

final loudnessProvider =
    StateNotifierProvider<LoudnessNotifier, LoudnessState>((ref) {
  return LoudnessNotifier(ref);
});

/// Analyse en arrière-plan, un morceau à la fois, des morceaux qui n'ont
/// pas encore de volume mesuré. Ne tourne que si « Volume uniforme » est
/// activé, et s'arrête dès qu'on le désactive.
class LoudnessNotifier extends StateNotifier<LoudnessState> {
  final Ref _ref;

  LoudnessNotifier(this._ref) : super(const LoudnessState());

  bool get _enabled => _ref.read(equalizerProvider).normalizeVolume;

  Future<void> analyzeLibrary() async {
    if (state.running) return;
    await _ref.read(equalizerProvider.notifier).ensureLoaded();
    if (!mounted || !_enabled) return;

    final pending = <Track>[];
    for (final t in _ref.read(trackProvider).tracks) {
      final key = LoudnessService.keyFor(t.filePath, t.uri);
      if (key == null || await LoudnessService.isKnown(key)) continue;
      pending.add(t);
    }
    if (pending.isEmpty) return;

    state = LoudnessState(running: true, done: 0, total: pending.length);
    for (var i = 0; i < pending.length; i++) {
      if (!mounted || !_enabled) break;
      await LoudnessService.analyze(pending[i]);
      if (mounted) {
        state = LoudnessState(running: true, done: i + 1, total: pending.length);
      }
    }
    await LoudnessService.flush();
    if (mounted) state = const LoudnessState();
  }
}
