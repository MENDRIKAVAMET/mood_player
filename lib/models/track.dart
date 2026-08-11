import 'package:isar/isar.dart';

part 'track.g.dart';

String _twoDigits(int n) => n.toString().padLeft(2, '0');

@collection
class Track {
  Id id = Isar.autoIncrement;

  @Index()
  late String title;

  late String artist;

  String? album;

  String? filePath;

  /// content:// URI from the device's MediaStore. Required to actually
  /// play/read the file on Android 10+ (scoped storage blocks direct
  /// filesystem access to other apps' media via the raw [filePath]).
  String? uri;

  /// Track duration in milliseconds, read from the device's media library.
  int? duration;

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
  String get durationFormatted {
    final d = duration;
    if (d == null || d <= 0) return '--:--';
    final total = Duration(milliseconds: d);
    final minutes = total.inMinutes.remainder(60);
    final seconds = total.inSeconds.remainder(60);
    final hours = total.inHours;
    return hours > 0
        ? '$hours:${_twoDigits(minutes)}:${_twoDigits(seconds)}'
        : '$minutes:${_twoDigits(seconds)}';
  }

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