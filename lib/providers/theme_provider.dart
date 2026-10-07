import 'dart:ui' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';

class ThemeSettings {
  /// Couleur de fond choisie, ou null = thème d'origine.
  final Color? background;
  const ThemeSettings({this.background});
}

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeSettings>((ref) {
  return ThemeNotifier(ThemeService.instance);
});

class ThemeNotifier extends StateNotifier<ThemeSettings> {
  final ThemeService _service;

  ThemeNotifier(this._service)
      : super(ThemeSettings(background: _service.background));

  /// Change la couleur de fond (null = revenir au thème d'origine).
  ///
  /// La palette est appliquée à [AppTheme] AVANT de changer l'état : quand
  /// MyApp réagit au changement, les getters renvoient déjà les nouvelles
  /// couleurs.
  Future<void> setBackground(Color? color) async {
    if (color?.toARGB32() == state.background?.toARGB32()) return;
    AppTheme.applyBackground(color);
    state = ThemeSettings(background: color);
    await _service.save(color);
  }
}
