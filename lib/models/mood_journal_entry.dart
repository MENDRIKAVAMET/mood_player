import 'track.dart';

/// Ce que l'utilisateur peut dire ressentir dans le journal d'humeur.
///
/// [defaultMoods] : ambiances musicales proposées tant que l'app n'a pas
/// assez d'écoutes pour savoir ce que l'utilisateur écoute vraiment dans
/// cet état.
enum Feeling {
  joyful('😄', 'Joyeux', [MoodType.festive, MoodType.energetic]),
  calm('😌', 'Calme', [MoodType.chill, MoodType.concentration]),
  motivated('🤩', 'Motivé', [MoodType.motivating, MoodType.energetic]),
  inLove('🥰', 'Amoureux', [MoodType.romantic, MoodType.chill]),
  tired('😴', 'Fatigué', [MoodType.chill, MoodType.sleep]),
  stressed('😤', 'Stressé', [MoodType.chill, MoodType.classical]),
  sad('😔', 'Triste', [MoodType.melancholic, MoodType.nostalgic]),
  angry('😡', 'En colère', [MoodType.angry, MoodType.energetic]);

  final String emoji;
  final String label;
  final List<MoodType> defaultMoods;

  const Feeling(this.emoji, this.label, this.defaultMoods);

  /// « stressé », « en colère » : se lit après « Quand tu es ».
  String get adjective => label.toLowerCase();

  static Feeling? fromName(String? name) {
    if (name == null) return null;
    for (final f in Feeling.values) {
      if (f.name == name) return f;
    }
    return null;
  }
}

/// Une humeur notée à un instant donné, avec une note facultative.
class MoodJournalEntry {
  final DateTime at;
  final Feeling feeling;
  final String? note;

  const MoodJournalEntry({
    required this.at,
    required this.feeling,
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'f': feeling.name,
        if (note != null && note!.isNotEmpty) 'n': note,
      };

  /// Null si la ligne est inexploitable (humeur inconnue, date absente).
  static MoodJournalEntry? tryFromJson(Map<String, dynamic> json) {
    final feeling = Feeling.fromName(json['f'] as String?);
    final at = json['at'];
    if (feeling == null || at is! num) return null;
    final note = json['n'];
    return MoodJournalEntry(
      at: DateTime.fromMillisecondsSinceEpoch(at.toInt()),
      feeling: feeling,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MoodJournalEntry &&
      other.at == at &&
      other.feeling == feeling &&
      other.note == note;

  @override
  int get hashCode => Object.hash(at, feeling, note);
}
