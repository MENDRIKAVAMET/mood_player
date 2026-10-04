/// Profil local de l'utilisateur : ses artistes préférés
/// (choisis dans sa propre bibliothèque au premier lancement, servent de
/// base aux suggestions tant qu'il n'y a pas d'historique d'écoute), plus
/// le drapeau qui dit si l'écran d'accueil "bienvenue" a déjà été passé.
class UserProfile {
  final List<String> favoriteArtists;
  final bool onboardingCompleted;

  /// Ambiances choisies par l'utilisateur pour chaque moment de la journée
  /// (clé = nom du moment : morning / midday / evening, valeur = noms de
  /// [MoodType]). Une clé absente signifie « valeurs par défaut » - voir
  /// `defaultMoodsForPeriod` dans mood_suggestions_provider.dart.
  final Map<String, List<String>> periodMoods;

  /// "Lecture intelligente" : au lieu de suivre strictement la file
  /// d'attente, une fois la piste en cours écoutée à 50%, la suivante est
  /// choisie par ambiance (et si possible même artiste) plutôt que par la
  /// file prévue à l'origine. Proposé une seule fois, à la première
  /// ouverture de l'app (voir onboarding) ; ensuite modifiable uniquement
  /// depuis le profil.
  final bool smartQueueEnabled;

  const UserProfile({
    this.favoriteArtists = const [],
    this.onboardingCompleted = false,
    this.periodMoods = const {},
    this.smartQueueEnabled = false,
  });

  const UserProfile.empty()
      : favoriteArtists = const [],
        onboardingCompleted = false,
        periodMoods = const {},
        smartQueueEnabled = false;

  UserProfile copyWith({
    List<String>? favoriteArtists,
    bool? onboardingCompleted,
    Map<String, List<String>>? periodMoods,
    bool? smartQueueEnabled,
  }) {
    return UserProfile(
      favoriteArtists: favoriteArtists ?? this.favoriteArtists,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      periodMoods: periodMoods ?? this.periodMoods,
      smartQueueEnabled: smartQueueEnabled ?? this.smartQueueEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'favoriteArtists': favoriteArtists,
        'onboardingCompleted': onboardingCompleted,
        'periodMoods': periodMoods,
        'smartQueueEnabled': smartQueueEnabled,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // Compatibilité avec l'ancien format à un seul artiste
    // ('favoriteArtist', singulier) déjà persisté sur certains appareils.
    final legacySingle = json['favoriteArtist'] as String?;
    final list = json['favoriteArtists'] as List<dynamic>?;

    return UserProfile(
      favoriteArtists: list != null
          ? list.map((e) => e as String).toList()
          : (legacySingle != null ? [legacySingle] : const []),
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      periodMoods: (json['periodMoods'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(
                k,
                (v as List<dynamic>).map((e) => e.toString()).toList(),
              )),
      // Absent sur les profils déjà persistés avant l'ajout de la
      // fonctionnalité : reste désactivée par défaut plutôt que d'imposer
      // un choix jamais fait par l'utilisateur.
      smartQueueEnabled: json['smartQueueEnabled'] as bool? ?? false,
    );
  }
}
