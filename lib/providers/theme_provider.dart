import 'dart:ui' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';

class ThemeSettings {
  /// Couleur de fond choisie, ou null = thème d'origine.
  final Color? background;

  /// Couleur principale choisie, ou null = violet d'origine.
  final Color? accent;

  /// Type de fond (dégradé vertical, halo, uni...).
  final BackgroundStyle backgroundStyle;

  /// Style et forme des boutons principaux.
  final ButtonStyleKind buttonStyle;
  final ButtonShapeKind buttonShape;
  final ButtonSizeKind buttonSize;
  final ControlsLayout controlsLayout;
  final NavLabelsKind navLabels;
  final TextSizeKind textSize;
  final ListDensity density;

  const ThemeSettings({
    this.background,
    this.accent,
    this.backgroundStyle = BackgroundStyle.vertical,
    this.buttonStyle = ButtonStyleKind.gradient,
    this.buttonShape = ButtonShapeKind.round,
    this.buttonSize = ButtonSizeKind.normal,
    this.controlsLayout = ControlsLayout.classic,
    this.navLabels = NavLabelsKind.always,
    this.textSize = TextSizeKind.normal,
    this.density = ListDensity.normal,
  });

  ThemeSettings copyWith({
    Color? Function()? background,
    Color? Function()? accent,
    BackgroundStyle? backgroundStyle,
    ButtonStyleKind? buttonStyle,
    ButtonShapeKind? buttonShape,
    ButtonSizeKind? buttonSize,
    ControlsLayout? controlsLayout,
    NavLabelsKind? navLabels,
    TextSizeKind? textSize,
    ListDensity? density,
  }) {
    return ThemeSettings(
      background: background != null ? background() : this.background,
      accent: accent != null ? accent() : this.accent,
      backgroundStyle: backgroundStyle ?? this.backgroundStyle,
      buttonStyle: buttonStyle ?? this.buttonStyle,
      buttonShape: buttonShape ?? this.buttonShape,
      buttonSize: buttonSize ?? this.buttonSize,
      controlsLayout: controlsLayout ?? this.controlsLayout,
      navLabels: navLabels ?? this.navLabels,
      textSize: textSize ?? this.textSize,
      density: density ?? this.density,
    );
  }
}

/// Thème complet : un clic règle couleurs, fond, boutons et disposition.
class ThemePreset {
  final String name;
  final Color? background;
  final Color? accent;
  final BackgroundStyle backgroundStyle;
  final ButtonStyleKind buttonStyle;
  final ButtonShapeKind buttonShape;
  final ButtonSizeKind buttonSize;
  final ControlsLayout controlsLayout;
  final NavLabelsKind navLabels;

  const ThemePreset({
    required this.name,
    this.background,
    this.accent,
    this.backgroundStyle = BackgroundStyle.vertical,
    this.buttonStyle = ButtonStyleKind.gradient,
    this.buttonShape = ButtonShapeKind.round,
    this.buttonSize = ButtonSizeKind.normal,
    this.controlsLayout = ControlsLayout.classic,
    this.navLabels = NavLabelsKind.always,
  });

  static const List<ThemePreset> all = [
    ThemePreset(name: 'Origine'),
    ThemePreset(
      name: 'Néon',
      background: Color(0xFF000000),
      accent: Color(0xFF06B6D4),
      backgroundStyle: BackgroundStyle.halo,
      buttonStyle: ButtonStyleKind.outline,
      controlsLayout: ControlsLayout.grouped,
    ),
    ThemePreset(
      name: 'Minimal',
      background: Color(0xFF14181F),
      accent: Color(0xFF3B82F6),
      backgroundStyle: BackgroundStyle.solid,
      buttonStyle: ButtonStyleKind.solid,
      buttonShape: ButtonShapeKind.squircle,
      buttonSize: ButtonSizeKind.compact,
      controlsLayout: ControlsLayout.grouped,
      navLabels: NavLabelsKind.selected,
    ),
    ThemePreset(
      name: 'Océan',
      background: Color(0xFF06222E),
      accent: Color(0xFF14B8A6),
      backgroundStyle: BackgroundStyle.bottomGlow,
      buttonStyle: ButtonStyleKind.glass,
    ),
    ThemePreset(
      name: 'Sunset',
      background: Color(0xFF2A0712),
      accent: Color(0xFFF97316),
      backgroundStyle: BackgroundStyle.corner,
      buttonShape: ButtonShapeKind.squircle,
      buttonSize: ButtonSizeKind.large,
      controlsLayout: ControlsLayout.split,
    ),
    ThemePreset(
      name: 'Forêt',
      background: Color(0xFF07200F),
      accent: Color(0xFF22C55E),
      backgroundStyle: BackgroundStyle.diagonal,
      buttonStyle: ButtonStyleKind.solid,
      navLabels: NavLabelsKind.selected,
    ),
  ];

  bool matches(ThemeSettings s) =>
      background?.toARGB32() == s.background?.toARGB32() &&
      accent?.toARGB32() == s.accent?.toARGB32() &&
      backgroundStyle == s.backgroundStyle &&
      buttonStyle == s.buttonStyle &&
      buttonShape == s.buttonShape &&
      buttonSize == s.buttonSize &&
      controlsLayout == s.controlsLayout &&
      navLabels == s.navLabels;
}

T _enumAt<T>(List<T> values, int index) =>
    (index >= 0 && index < values.length) ? values[index] : values.first;

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeSettings>((ref) {
  return ThemeNotifier(ThemeService.instance);
});

class ThemeNotifier extends StateNotifier<ThemeSettings> {
  final ThemeService _service;

  ThemeNotifier(this._service)
      : super(ThemeSettings(
          background: _service.background,
          accent: _service.accent,
          backgroundStyle: _enumAt(BackgroundStyle.values, _service.bgStyle),
          buttonStyle: _enumAt(ButtonStyleKind.values, _service.buttonStyle),
          buttonShape: _enumAt(ButtonShapeKind.values, _service.buttonShape),
          buttonSize: _enumAt(ButtonSizeKind.values, _service.buttonSize),
          controlsLayout:
              _enumAt(ControlsLayout.values, _service.controlsLayout),
          navLabels: _enumAt(NavLabelsKind.values, _service.navLabels),
          textSize: _enumAt(TextSizeKind.values, _service.textSize),
          density: _enumAt(ListDensity.values, _service.density),
        ));

  /// Applique au démarrage les styles chargés depuis le disque.
  static void applyLoaded(ThemeService service) {
    AppTheme.applyUiStyle(
      background: _enumAt(BackgroundStyle.values, service.bgStyle),
      button: _enumAt(ButtonStyleKind.values, service.buttonStyle),
      shape: _enumAt(ButtonShapeKind.values, service.buttonShape),
      size: _enumAt(ButtonSizeKind.values, service.buttonSize),
      controls: _enumAt(ControlsLayout.values, service.controlsLayout),
      nav: _enumAt(NavLabelsKind.values, service.navLabels),
      text: _enumAt(TextSizeKind.values, service.textSize),
      density: _enumAt(ListDensity.values, service.density),
    );
  }

  /// Change la couleur de fond (null = revenir au thème d'origine).
  ///
  /// La palette est appliquée à [AppTheme] AVANT de changer l'état : quand
  /// MyApp réagit au changement, les getters renvoient déjà les nouvelles
  /// couleurs.
  Future<void> setBackground(Color? color) async {
    if (color?.toARGB32() == state.background?.toARGB32()) return;
    AppTheme.applyBackground(color);
    state = state.copyWith(background: () => color);
    await _service.save(background: color, accent: state.accent);
  }

  /// Change la couleur principale (null = revenir au violet d'origine).
  Future<void> setAccent(Color? color) async {
    if (color?.toARGB32() == state.accent?.toARGB32()) return;
    AppTheme.applyAccent(color);
    state = state.copyWith(accent: () => color);
    await _service.save(background: state.background, accent: color);
  }

  Future<void> setBackgroundStyle(BackgroundStyle style) async {
    if (style == state.backgroundStyle) return;
    AppTheme.applyUiStyle(background: style);
    state = state.copyWith(backgroundStyle: style);
    await _service.saveStyles(bgStyle: style.index);
  }

  Future<void> setButtonStyle(ButtonStyleKind style) async {
    if (style == state.buttonStyle) return;
    AppTheme.applyUiStyle(button: style);
    state = state.copyWith(buttonStyle: style);
    await _service.saveStyles(buttonStyle: style.index);
  }

  Future<void> setButtonShape(ButtonShapeKind shape) async {
    if (shape == state.buttonShape) return;
    AppTheme.applyUiStyle(shape: shape);
    state = state.copyWith(buttonShape: shape);
    await _service.saveStyles(buttonShape: shape.index);
  }

  Future<void> setButtonSize(ButtonSizeKind size) async {
    if (size == state.buttonSize) return;
    AppTheme.applyUiStyle(size: size);
    state = state.copyWith(buttonSize: size);
    await _service.saveStyles(buttonSize: size.index);
  }

  Future<void> setControlsLayout(ControlsLayout layout) async {
    if (layout == state.controlsLayout) return;
    AppTheme.applyUiStyle(controls: layout);
    state = state.copyWith(controlsLayout: layout);
    await _service.saveStyles(controlsLayout: layout.index);
  }

  Future<void> setNavLabels(NavLabelsKind kind) async {
    if (kind == state.navLabels) return;
    AppTheme.applyUiStyle(nav: kind);
    state = state.copyWith(navLabels: kind);
    await _service.saveStyles(navLabels: kind.index);
  }

  /// Applique un thème complet d'un coup : une seule reconstruction de l'app
  /// au lieu d'une par réglage.
  Future<void> applyPreset(ThemePreset p) async {
    AppTheme.applyBackground(p.background);
    AppTheme.applyAccent(p.accent);
    AppTheme.applyUiStyle(
      background: p.backgroundStyle,
      button: p.buttonStyle,
      shape: p.buttonShape,
      size: p.buttonSize,
      controls: p.controlsLayout,
      nav: p.navLabels,
    );
    state = ThemeSettings(
      background: p.background,
      accent: p.accent,
      backgroundStyle: p.backgroundStyle,
      buttonStyle: p.buttonStyle,
      buttonShape: p.buttonShape,
      buttonSize: p.buttonSize,
      controlsLayout: p.controlsLayout,
      navLabels: p.navLabels,
      // Taille du texte et densité : préférences de confort, pas de style,
      // donc un thème complet ne les écrase pas.
      textSize: state.textSize,
      density: state.density,
    );
    await _service.save(background: p.background, accent: p.accent);
    await _service.saveStyles(
      bgStyle: p.backgroundStyle.index,
      buttonStyle: p.buttonStyle.index,
      buttonShape: p.buttonShape.index,
      buttonSize: p.buttonSize.index,
      controlsLayout: p.controlsLayout.index,
      navLabels: p.navLabels.index,
    );
  }

  Future<void> setTextSize(TextSizeKind size) async {
    if (size == state.textSize) return;
    AppTheme.applyUiStyle(text: size);
    state = state.copyWith(textSize: size);
    await _service.saveStyles(textSize: size.index);
  }

  Future<void> setDensity(ListDensity density) async {
    if (density == state.density) return;
    AppTheme.applyUiStyle(density: density);
    state = state.copyWith(density: density);
    await _service.saveStyles(density: density.index);
  }
}
