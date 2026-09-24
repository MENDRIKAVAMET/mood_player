import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../services/profile_service.dart';

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService();
});

final profileProvider =
    StateNotifierProvider<ProfileNotifier, UserProfile>((ref) {
  return ProfileNotifier(ref.watch(profileServiceProvider));
});

class ProfileNotifier extends StateNotifier<UserProfile> {
  final ProfileService _service;

  /// Le chargement initial est asynchrone (lecture disque) et n'est pas
  /// attendu dans le constructeur, donc chaque méthode qui modifie l'état
  /// l'attend elle-même avant d'écrire par-dessus. Sans ça, un prénom saisi
  /// tout de suite sur l'écran d'accueil (avant la fin de cette lecture)
  /// se faisait silencieusement écraser par le profil vide chargé juste
  /// après - le prénom disparaissait alors qu'il venait d'être enregistré.
  late final Future<void> _ready;

  ProfileNotifier(this._service) : super(const UserProfile.empty()) {
    _ready = _load();
  }

  Future<void> _load() async {
    state = await _service.load();
  }

  Future<void> setName(String name) async {
    await _ready;
    state = state.copyWith(name: name);
    await _service.save(state);
  }

  Future<void> setFavoriteArtists(List<String> artists) async {
    await _ready;
    state = state.copyWith(favoriteArtists: artists);
    await _service.save(state);
  }

  /// Enregistre les ambiances d'un moment de la journée ([periodKey] =
  /// `DayPeriod.name`). Passer `null` revient aux valeurs par défaut.
  Future<void> setPeriodMoods(String periodKey, List<String>? moodNames) async {
    await _ready;
    final updated = Map<String, List<String>>.from(state.periodMoods);
    if (moodNames == null) {
      updated.remove(periodKey);
    } else {
      updated[periodKey] = moodNames;
    }
    state = state.copyWith(periodMoods: updated);
    await _service.save(state);
  }

  Future<void> completeOnboarding() async {
    await _ready;
    state = state.copyWith(onboardingCompleted: true);
    await _service.save(state);
  }
}
