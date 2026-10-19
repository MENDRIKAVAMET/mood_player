import 'track.dart';

/// Une image fournie avec l'app, proposée aux moods créés par l'utilisateur.
class MoodImageOption {
  final String asset;
  final String label;

  const MoodImageOption(this.asset, this.label);
}

/// Toutes les images de l'app : les photos d'origine des ambiances et les
/// illustrations d'animé. Construit depuis [MoodType], donc une nouvelle
/// ambiance (avec ses images) apparaît ici sans rien ajouter.
class MoodImageCatalog {
  MoodImageCatalog._();

  /// Photos d'origine (assets/moods/).
  static List<MoodImageOption> get photos => [
        for (final mood in MoodType.values)
          if (mood.imageAsset != null)
            MoodImageOption(mood.imageAsset!, mood.displayName),
      ];

  /// Illustrations d'animé (assets/moods/anime/).
  static List<MoodImageOption> get anime => [
        for (final mood in MoodType.values)
          if (mood.animeImageAsset != null)
            MoodImageOption(mood.animeImageAsset!, mood.displayName),
      ];
}
