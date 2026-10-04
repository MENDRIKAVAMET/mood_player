import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/equalizer_settings.dart';
import '../services/equalizer_service.dart';
import 'audio_provider.dart';

final equalizerServiceProvider = Provider<EqualizerService>((ref) {
  return EqualizerService();
});

final equalizerProvider =
    StateNotifierProvider<EqualizerNotifier, EqualizerSettings>((ref) {
  return EqualizerNotifier(ref, ref.watch(equalizerServiceProvider));
});

class EqualizerNotifier extends StateNotifier<EqualizerSettings> {
  final Ref _ref;
  final EqualizerService _service;
  late final Future<void> _ready;

  EqualizerNotifier(this._ref, this._service)
      : super(const EqualizerSettings()) {
    _ready = _load();
  }

  Future<void> _load() async {
    final loaded = await _service.load();
    if (mounted) state = loaded;
  }

  Future<void> _commit(EqualizerSettings next, {bool persist = true}) async {
    await _ready;
    if (!mounted) return;
    state = next;
    if (persist) unawaited(_service.save(next));
    try {
      final handler = await _ref.read(audioHandlerProvider.future);
      unawaited(handler.applyEqualizerSettings(next));
    } catch (_) {
      // Service audio indisponible : les réglages sont quand même sauvegardés
      // et seront appliqués au prochain démarrage.
    }
  }

  /// Écrit les réglages courants sur disque (fin de glissement d'un curseur).
  Future<void> persist() => _service.save(state);

  Future<void> setEnabled(bool enabled) =>
      _commit(state.copyWith(enabled: enabled));

  Future<void> selectPreset(String name) =>
      _commit(state.copyWith(preset: name));

  /// Règle une bande ; le résultat devient un réglage personnalisé.
  Future<void> setBandGain(int index, double db, int bandCount) {
    final gains = state.gainsFor(bandCount);
    if (index < 0 || index >= gains.length) return Future.value();
    gains[index] = db;
    return _commit(
      state.copyWith(preset: EqualizerSettings.customName, gains: gains),
      persist: false,
    );
  }

  Future<void> setLoudness(double db) =>
      _commit(state.copyWith(loudnessDb: db), persist: false);

  Future<void> reset() => _commit(
        EqualizerSettings(enabled: state.enabled),
      );
}
