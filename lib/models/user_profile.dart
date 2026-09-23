/// Profil local de l'utilisateur : un nom, jusqu'à 3 artistes préférés
/// (choisis dans sa propre bibliothèque au premier lancement, servent de
/// base aux suggestions tant qu'il n'y a pas d'historique d'écoute), plus
/// le drapeau qui dit si l'écran d'accueil "bienvenue" a déjà été passé.
class UserProfile {
  final String? name;
  final List<String> favoriteArtists;
  final bool onboardingCompleted;

  /// Ambiances choisies par l'utilisateur pour chaque moment de la journée
  /// (clé = nom du moment : morning / midday / evening, valeur = noms de
  /// [MoodType]). Une clé absente signifie « valeurs par défaut » - voir
  /// `defaultMoodsForPeriod` dans mood_suggestions_provider.dart.
  final Map<String, List<String>> periodMoods;

  const UserProfile({
    this.name,
    this.favoriteArtists = const [],
    this.onboardingCompleted = false,
    this.periodMoods = const {},
  });

  const UserProfile.empty()
      : name = null,
        favoriteArtists = const [],
        onboardingCompleted = false,
        periodMoods = const {};

  UserProfile copyWith({
    String? name,
    List<String>? favoriteArtists,
    bool? onboardingCompleted,
    Map<String, List<String>>? periodMoods,
  }) {
    return UserProfile(
      name: name ?? this.name,
      favoriteArtists: favoriteArtists ?? this.favoriteArtists,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      periodMoods: periodMoods ?? this.periodMoods,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'favoriteArtists': favoriteArtists,
        'onboardingCompleted': onboardingCompleted,
        'periodMoods': periodMoods,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    // Compatibilité avec l'ancien format à un seul artiste
    // ('favoriteArtist', singulier) déjà persisté sur certains appareils.
    final legacySingle = json['favoriteArtist'] as String?;
    final list = json['favoriteArtists'] as List<dynamic>?;

    return UserProfile(
      name: json['name'] as String?,
      favoriteArtists: list != null
          ? list.map((e) => e as String).toList()
          : (legacySingle != null ? [legacySingle] : const []),
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
      periodMoods: (json['periodMoods'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(
                k,
                (v as List<dynamic>).map((e) => e.toString()).toList(),
              )),
    );
  }
}
