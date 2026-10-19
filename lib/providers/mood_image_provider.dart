import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mood_image_choice.dart';
import '../models/track.dart';
import '../services/mood_image_service.dart';

/// Choix d'image de chaque ambiance : `MoodType` → [MoodImageChoice].
/// Une ambiance absente de la table est en « origine » (le défaut).
final moodImageProvider = StateNotifierProvider<MoodImageNotifier,
    Map<MoodType, MoodImageChoice>>((ref) {
  return MoodImageNotifier(MoodImageService.instance);
});

class MoodImageNotifier extends StateNotifier<Map<MoodType, MoodImageChoice>> {
  final MoodImageService _service;

  /// Le chargement initial est asynchrone : chaque méthode qui modifie
  /// l'état l'attend d'abord, pour ne pas être écrasée par la lecture
  /// disque qui se termine après (même schéma que `ProfileNotifier`).
  late final Future<void> _ready;

  MoodImageNotifier(this._service) : super(const {}) {
    _ready = _load();
  }

  Future<void> _load() async {
    state = await _service.load();
  }

  /// Origine, animé, icône, ou image importée (si elle existe déjà).
  Future<void> setSource(MoodType mood, MoodImageSource source) async {
    await _ready;
    state = await _service.setSource(mood, source);
  }

  /// Applique un style (origine / animé / icône) à toutes les ambiances.
  Future<void> applyToAll(MoodImageSource source) async {
    await _ready;
    state = await _service.setSourceForAll(source);
  }

  /// Importe [sourcePath] comme image de [mood] et l'active.
  Future<void> importImage(MoodType mood, String sourcePath) async {
    await _ready;
    state = await _service.importImage(mood, sourcePath);
  }

  /// Supprime l'image importée de [mood].
  Future<void> clearImported(MoodType mood) async {
    await _ready;
    state = await _service.clearImported(mood);
  }
}
