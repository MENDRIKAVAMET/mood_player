import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;
import 'package:path_provider/path_provider.dart';

/// Persiste le choix de thème dans un petit fichier JSON local, comme le
/// profil : deux ou trois valeurs lues/réécrites en bloc, pas besoin d'un
/// schéma Isar.
///
/// Singleton : `main()` le charge avant `runApp` pour que le tout premier
/// affichage ait déjà la bonne couleur de fond (pas de flash du thème
/// d'origine au démarrage).
class ThemeService {
  ThemeService._();
  static final ThemeService instance = ThemeService._();

  Color? _background;
  Color? _accent;
  int _bgStyle = 0;
  int _buttonStyle = 0;
  int _buttonShape = 0;
  int _buttonSize = 1;
  int _controlsLayout = 0;
  int _navLabels = 0;
  int _textSize = 1;
  int _density = 1;

  /// Couleur de fond choisie, ou null = thème d'origine.
  Color? get background => _background;

  /// Couleur principale choisie, ou null = violet d'origine.
  Color? get accent => _accent;

  /// Index des styles (voir [BackgroundStyle], [ButtonStyleKind],
  /// [ButtonShapeKind]) : 0 = style d'origine.
  int get bgStyle => _bgStyle;
  int get buttonStyle => _buttonStyle;
  int get buttonShape => _buttonShape;
  int get buttonSize => _buttonSize;
  int get controlsLayout => _controlsLayout;
  int get navLabels => _navLabels;
  int get textSize => _textSize;
  int get density => _density;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/theme_settings.json');
  }

  Future<Color?> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        final bg = json is Map ? json['background'] : null;
        final ac = json is Map ? json['accent'] : null;
        _background = bg is int ? Color(bg) : null;
        _accent = ac is int ? Color(ac) : null;
        _bgStyle = json is Map && json['bgStyle'] is int ? json['bgStyle'] : 0;
        _buttonStyle =
            json is Map && json['buttonStyle'] is int ? json['buttonStyle'] : 0;
        _buttonShape =
            json is Map && json['buttonShape'] is int ? json['buttonShape'] : 0;
        _buttonSize =
            json is Map && json['buttonSize'] is int ? json['buttonSize'] : 1;
        _controlsLayout = json is Map && json['controlsLayout'] is int
            ? json['controlsLayout']
            : 0;
        _navLabels =
            json is Map && json['navLabels'] is int ? json['navLabels'] : 0;
        _textSize =
            json is Map && json['textSize'] is int ? json['textSize'] : 1;
        _density = json is Map && json['density'] is int ? json['density'] : 1;
      }
    } catch (_) {
      // Fichier absent ou corrompu : thème d'origine plutôt que de bloquer
      // le démarrage pour une préférence d'affichage.
      _background = null;
      _accent = null;
    }
    return _background;
  }

  Future<void> save({Color? background, Color? accent}) async {
    _background = background;
    _accent = accent;
    await _write();
  }

  Future<void> saveStyles({
    int? bgStyle,
    int? buttonStyle,
    int? buttonShape,
    int? buttonSize,
    int? controlsLayout,
    int? navLabels,
    int? textSize,
    int? density,
  }) async {
    if (bgStyle != null) _bgStyle = bgStyle;
    if (buttonStyle != null) _buttonStyle = buttonStyle;
    if (buttonShape != null) _buttonShape = buttonShape;
    if (buttonSize != null) _buttonSize = buttonSize;
    if (controlsLayout != null) _controlsLayout = controlsLayout;
    if (navLabels != null) _navLabels = navLabels;
    if (textSize != null) _textSize = textSize;
    if (density != null) _density = density;
    await _write();
  }

  Future<void> _write() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'background': _background?.toARGB32(),
          'accent': _accent?.toARGB32(),
          'bgStyle': _bgStyle,
          'buttonStyle': _buttonStyle,
          'buttonShape': _buttonShape,
          'buttonSize': _buttonSize,
          'controlsLayout': _controlsLayout,
          'navLabels': _navLabels,
          'textSize': _textSize,
          'density': _density,
        }),
      );
    } catch (_) {
      // Le choix reste valable pour la session même si l'écriture échoue.
    }
  }
}
