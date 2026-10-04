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
  /// l'attend elle-même avant d'écrire par-dessus. Sans ça, une valeur saisie
  /// tout de suite (avant la fin de cette lecture) se ferait silencieusement
  /// écraser par le profil vide chargé juste après.
  late final Future<void> _ready;

  ProfileNotifier(this._service) : super(const UserProfile.empty()) {
    _ready = _load();
  }

  Future<void> _load() async {
    state = await _service.load();
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

  /// Applique les réglages venant d'une sauvegarde importée. Les listes
  /// vides sont ignorées (elles n'effacent rien) et les ambiances par
  /// moment de la journée sont fusionnées avec celles déjà choisies.
  Future<void> applyImported({
    List<String>? favoriteArtists,
    Map<String, List<String>>? periodMoods,
    bool? smartQueueEnabled,
  }) async {
    await _ready;
    state = state.copyWith(
      favoriteArtists:
          (favoriteArtists != null && favoriteArtists.isNotEmpty)
              ? favoriteArtists
              : null,
      periodMoods: (periodMoods != null && periodMoods.isNotEmpty)
          ? {...state.periodMoods, ...periodMoods}
          : null,
      smartQueueEnabled: smartQueueEnabled,
    );
    await _service.save(state);
  }

  Future<void> completeOnboarding() async {
    await _ready;
    state = state.copyWith(onboardingCompleted: true);
    await _service.save(state);
  }

  /// Active/désactive la lecture intelligente. Utilisé à la fois par
  /// l'étape d'onboarding (premier choix) et par l'écran de profil
  /// (modification ultérieure).
  Future<void> setSmartQueueEnabled(bool enabled) async {
    await _ready;
    state = state.copyWith(smartQueueEnabled: enabled);
    await _service.save(state);
  }
}
