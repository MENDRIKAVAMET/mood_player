import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/custom_mood_image.dart';
import '../services/custom_mood_image_service.dart';

/// Image de chaque mood créé par l'utilisateur : id du mood →
/// [CustomMoodImage]. Un mood absent de la table n'a pas d'image.
final customMoodImageProvider =
    StateNotifierProvider<CustomMoodImageNotifier, Map<int, CustomMoodImage>>(
        (ref) {
  return CustomMoodImageNotifier(CustomMoodImageService.instance);
});

class CustomMoodImageNotifier extends StateNotifier<Map<int, CustomMoodImage>> {
  final CustomMoodImageService _service;

  /// Le chargement initial est asynchrone : chaque méthode qui modifie
  /// l'état l'attend d'abord, pour ne pas être écrasée par la lecture
  /// disque qui se termine après (même schéma que `ProfileNotifier`).
  late final Future<void> _ready;

  CustomMoodImageNotifier(this._service) : super(const {}) {
    _ready = _load();
  }

  Future<void> _load() async {
    state = await _service.load();
  }

  Future<void> setNone(int moodId) async {
    await _ready;
    state = await _service.setNone(moodId);
  }

  Future<void> setAsset(int moodId, String asset) async {
    await _ready;
    state = await _service.setAsset(moodId, asset);
  }

  Future<void> useImported(int moodId) async {
    await _ready;
    state = await _service.useImported(moodId);
  }

  Future<void> importImage(int moodId, String sourcePath) async {
    await _ready;
    state = await _service.importImage(moodId, sourcePath);
  }

  Future<void> clearImported(int moodId) async {
    await _ready;
    state = await _service.clearImported(moodId);
  }

  Future<void> forget(int moodId) async {
    await _ready;
    state = await _service.forget(moodId);
  }
}
