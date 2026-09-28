import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Alignement du texte des paroles.
enum LyricsAlignment { start, center }

/// Réglages d'affichage des paroles (bouton « T ») : alignement et taille.
/// Sauvegardés dans un petit fichier JSON local, sans dépendance en plus.
class LyricsTextSettings {
  final LyricsAlignment alignment;

  /// 0 = Petit, 1 = Standard, 2 = Moyen, 3 = Grand.
  final int sizeIndex;

  const LyricsTextSettings({
    this.alignment = LyricsAlignment.center,
    this.sizeIndex = 1,
  });

  static const List<String> sizeLabels = ['Petit', 'Standard', 'Moyen', 'Grand'];
  static const List<double> _fontSizes = [16, 20, 24, 28];

  double get fontSize => _fontSizes[sizeIndex.clamp(0, 3)];

  LyricsTextSettings copyWith({LyricsAlignment? alignment, int? sizeIndex}) =>
      LyricsTextSettings(
        alignment: alignment ?? this.alignment,
        sizeIndex: sizeIndex ?? this.sizeIndex,
      );

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/lyrics_text_settings.json');
  }

  static Future<LyricsTextSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const LyricsTextSettings();
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return LyricsTextSettings(
        alignment: json['alignment'] == 'start'
            ? LyricsAlignment.start
            : LyricsAlignment.center,
        sizeIndex: ((json['size'] as num?)?.toInt() ?? 1).clamp(0, 3),
      );
    } catch (_) {
      return const LyricsTextSettings();
    }
  }

  Future<void> save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'alignment': alignment == LyricsAlignment.start ? 'start' : 'center',
        'size': sizeIndex,
      }));
    } catch (_) {
      // Non bloquant : les réglages restent appliqués pour la session.
    }
  }
}
