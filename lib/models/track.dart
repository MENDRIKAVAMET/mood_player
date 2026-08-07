import 'package:isar/isar.dart';

part 'track.g.dart';

@collection
class Track {
  Id id = Isar.autoIncrement;

  @Index()
  late String title;

  late String artist;

  String? album;

  String? filePath;

  String? coverUrl;

  int? moodIndex;

  @ignore
  MoodType? get mood => moodIndex != null ? MoodType.values[moodIndex!] : null;

  set mood(MoodType? value) => moodIndex = value?.index;

  double? moodConfidence;

  DateTime? lastClassified;

  DateTime? createdAt;

  DateTime? updatedAt;

  @ignore
  bool get isClassified => mood != null;

  @ignore
  String get moodDisplayName {
    switch (mood) {
      case MoodType.energetic:
        return 'Énergique';
      case MoodType.chill:
        return 'Chill';
      case MoodType.melancholic:
        return 'Mélancolique';
      case MoodType.festive:
        return 'Festif';
      case MoodType.romantic:
        return 'Romantique';
      case MoodType.concentration:
        return 'Concentration';
      case MoodType.motivating:
        return 'Motivant';
      case MoodType.sad:
        return 'Triste';
      case MoodType.unknown:
        return 'Inconnu';
      case null:
        return 'Inconnu';
    }
  }
}

enum MoodType {
  unknown,
  energetic,
  chill,
  melancholic,
  festive,
  romantic,
  concentration,
  motivating,
  sad,
}

extension MoodTypeExtension on MoodType {
  String get displayName {
    switch (this) {
      case MoodType.energetic:
        return 'Énergique';
      case MoodType.chill:
        return 'Chill';
      case MoodType.melancholic:
        return 'Mélancolique';
      case MoodType.festive:
        return 'Festif';
      case MoodType.romantic:
        return 'Romantique';
      case MoodType.concentration:
        return 'Concentration';
      case MoodType.motivating:
        return 'Motivant';
      case MoodType.sad:
        return 'Triste';
      case MoodType.unknown:
        return 'Inconnu';
    }
  }

  String get icon {
    switch (this) {
      case MoodType.energetic:
        return '⚡';
      case MoodType.chill:
        return '🌊';
      case MoodType.melancholic:
        return '🌧️';
      case MoodType.festive:
        return '🎉';
      case MoodType.romantic:
        return '💕';
      case MoodType.concentration:
        return '🧠';
      case MoodType.motivating:
        return '🔥';
      case MoodType.sad:
        return '😢';
      case MoodType.unknown:
        return '🎵';
    }
  }

  static MoodType fromString(String moodString) {
    switch (moodString.toLowerCase()) {
      case 'énergique':
      case 'energetic':
        return MoodType.energetic;
      case 'chill':
        return MoodType.chill;
      case 'mélancolique':
      case 'melancholic':
        return MoodType.melancholic;
      case 'festif':
      case 'festive':
        return MoodType.festive;
      case 'romantique':
      case 'romantic':
        return MoodType.romantic;
      case 'concentration':
        return MoodType.concentration;
      case 'motivant':
      case 'motivating':
        return MoodType.motivating;
      case 'triste':
      case 'sad':
        return MoodType.sad;
      default:
        return MoodType.unknown;
    }
  }
}