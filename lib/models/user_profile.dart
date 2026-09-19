/// Profil local de l'utilisateur : pour l'instant juste un nom et un
/// artiste préféré (choisi dans sa propre bibliothèque au premier
/// lancement), plus le drapeau qui dit si l'écran d'accueil "bienvenue"
/// a déjà été passé.
class UserProfile {
  final String? name;
  final String? favoriteArtist;
  final bool onboardingCompleted;

  const UserProfile({
    this.name,
    this.favoriteArtist,
    this.onboardingCompleted = false,
  });

  const UserProfile.empty()
      : name = null,
        favoriteArtist = null,
        onboardingCompleted = false;

  UserProfile copyWith({
    String? name,
    String? favoriteArtist,
    bool? onboardingCompleted,
  }) {
    return UserProfile(
      name: name ?? this.name,
      favoriteArtist: favoriteArtist ?? this.favoriteArtist,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'favoriteArtist': favoriteArtist,
        'onboardingCompleted': onboardingCompleted,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String?,
      favoriteArtist: json['favoriteArtist'] as String?,
      onboardingCompleted: json['onboardingCompleted'] as bool? ?? false,
    );
  }
}
