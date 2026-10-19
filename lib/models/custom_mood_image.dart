/// D'où vient l'image d'un mood créé par l'utilisateur.
enum CustomMoodImageKind {
  /// Pas d'image : dégradé de couleur + icône (comportement d'origine).
  none,

  /// Une image fournie avec l'app (photo d'ambiance ou animé).
  asset,

  /// Une image importée depuis l'appareil.
  custom,
}

/// Image d'UN mood créé par l'utilisateur.
///
/// [assetPath] et [customPath] sont conservés même quand ils ne sont pas
/// actifs : l'utilisateur peut essayer une image de l'app puis revenir à
/// celle qu'il avait importée sans la réimporter.
class CustomMoodImage {
  final CustomMoodImageKind kind;
  final String? assetPath;
  final String? customPath;

  const CustomMoodImage(this.kind, {this.assetPath, this.customPath});

  static const none = CustomMoodImage(CustomMoodImageKind.none);

  @override
  bool operator ==(Object other) =>
      other is CustomMoodImage &&
      other.kind == kind &&
      other.assetPath == assetPath &&
      other.customPath == customPath;

  @override
  int get hashCode => Object.hash(kind, assetPath, customPath);
}
