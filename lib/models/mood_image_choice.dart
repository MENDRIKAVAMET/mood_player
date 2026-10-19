/// D'où vient l'image affichée pour une ambiance.
enum MoodImageSource {
  /// Photo d'origine de l'app (assets/moods/). Choix par défaut.
  original,

  /// Illustrations d'animé (assets/moods/anime/).
  anime,

  /// Pas d'image : dégradé de couleur + icône de l'ambiance.
  icon,

  /// Image importée par l'utilisateur.
  custom,
}

/// Choix d'affichage d'UNE ambiance.
///
/// [customPath] est conservé même quand [source] n'est plus `custom` :
/// l'utilisateur peut repasser à l'animé puis revenir à son image
/// importée sans devoir la réimporter.
class MoodImageChoice {
  final MoodImageSource source;
  final String? customPath;

  const MoodImageChoice(this.source, {this.customPath});

  @override
  bool operator ==(Object other) =>
      other is MoodImageChoice &&
      other.source == source &&
      other.customPath == customPath;

  @override
  int get hashCode => Object.hash(source, customPath);
}
