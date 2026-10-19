import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// Carte « Thème » de l'écran de profil : choix de la couleur de fond de
/// l'app (préréglages ou composée soi-même) et de la couleur principale
/// (boutons, curseurs, éléments actifs) : préréglages suggérés, ou composée
/// librement (teinte / intensité / clarté) avec « Perso ».
///
/// Les textes de l'app restent clairs, donc une couleur trop claire est
/// assombrie automatiquement (voir [ThemePalette]) : l'aperçu montre
/// toujours ce qui sera réellement appliqué.
class ThemeSection extends ConsumerStatefulWidget {
  const ThemeSection({super.key});

  @override
  ConsumerState<ThemeSection> createState() => _ThemeSectionState();
}

class _ThemeSectionState extends ConsumerState<ThemeSection> {
  static const List<(String, Color?)> _presets = [
    ('Origine', null),
    ('Minuit', Color(0xFF0B1030)),
    ('Océan', Color(0xFF06222E)),
    ('Forêt', Color(0xFF07200F)),
    ('Bordeaux', Color(0xFF2A0712)),
    ('Café', Color(0xFF241408)),
    ('Ardoise', Color(0xFF14181F)),
    ('Noir', Color(0xFF000000)),
  ];

  /// Couleurs principales suggérées (boutons, curseurs, éléments actifs).
  /// null = violet d'origine.
  static const List<(String, Color?)> _accentPresets = [
    ('Violet', null),
    ('Rose', Color(0xFFEC4899)),
    ('Rouge', Color(0xFFEF4444)),
    ('Orange', Color(0xFFF97316)),
    ('Ambre', Color(0xFFF59E0B)),
    ('Vert', Color(0xFF22C55E)),
    ('Turquoise', Color(0xFF14B8A6)),
    ('Cyan', Color(0xFF06B6D4)),
    ('Bleu', Color(0xFF3B82F6)),
    ('Indigo', Color(0xFF6366F1)),
  ];

  /// Violet d'origine, point de départ du sélecteur de couleur principale.
  static const Color _defaultAccent = Color(0xFFA855F7);

  late HSLColor _hsl;
  late HSLColor _accentHsl;
  bool _customOpen = false;
  bool _accentCustomOpen = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(themeProvider).background;
    _hsl = HSLColor.fromColor(current ?? const Color(0xFF1B1038));
    final currentAccent = ref.read(themeProvider).accent;
    _accentHsl = HSLColor.fromColor(currentAccent ?? _defaultAccent);
    // Une couleur déjà choisie à la main ouvre directement les curseurs.
    _accentCustomOpen = currentAccent != null &&
        !_accentPresets.any((p) => _isSelected(p.$2, currentAccent));
  }

  void _applyAccent(Color? color) =>
      ref.read(themeProvider.notifier).setAccent(color);

  void _apply(Color? color) =>
      ref.read(themeProvider.notifier).setBackground(color);

  bool _isSelected(Color? preset, Color? current) =>
      preset?.toARGB32() == current?.toARGB32();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(themeProvider);
    final current = settings.background;
    final accent = settings.accent;
    final isPreset = _presets.any((p) => _isSelected(p.$2, current));
    final preview = _hsl.toColor();

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Icon(Icons.palette_rounded,
                    color: AppTheme.accentPrimary),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thème', style: AppTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      'Couleurs de l\'application',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingL),
          _buildPresetsSection(settings),
          const SizedBox(height: AppTheme.spacingXL),
          Text('Fond', style: AppTheme.labelLarge),
          const SizedBox(height: AppTheme.spacingS),
          Wrap(
            spacing: AppTheme.spacingM,
            runSpacing: AppTheme.spacingM,
            children: [
              for (final preset in _presets)
                _Swatch(
                  label: preset.$1,
                  palette: preset.$2 == null
                      ? ThemePalette.standard
                      : ThemePalette.fromBase(preset.$2!),
                  selected: _isSelected(preset.$2, current),
                  onTap: () => _apply(preset.$2),
                ),
              _Swatch(
                label: 'Perso',
                palette: ThemePalette.fromBase(preview),
                selected: !isPreset,
                icon: Icons.tune_rounded,
                onTap: () {
                  setState(() => _customOpen = !_customOpen);
                  if (_customOpen) _apply(preview);
                },
              ),
            ],
          ),
          if (_customOpen) ...[
            const SizedBox(height: AppTheme.spacingL),
            _buildSlider(
              label: 'Teinte',
              value: _hsl.hue,
              max: 360,
              onChanged: (v) => setState(() => _hsl = _hsl.withHue(v)),
            ),
            _buildSlider(
              label: 'Intensité',
              value: _hsl.saturation,
              max: 1,
              onChanged: (v) => setState(() => _hsl = _hsl.withSaturation(v)),
            ),
            _buildSlider(
              label: 'Clarté',
              value: _hsl.lightness.clamp(0.0, 0.4).toDouble(),
              max: 0.4,
              onChanged: (v) => setState(() => _hsl = _hsl.withLightness(v)),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text(
              'Les couleurs trop claires sont assombries automatiquement '
              'pour que le texte reste lisible.',
              style:
                  AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
            ),
          ],
          const SizedBox(height: AppTheme.spacingXL),
          _buildBackgroundStyleSection(settings.backgroundStyle),
          const SizedBox(height: AppTheme.spacingXL),
          _buildAccentSection(accent),
          const SizedBox(height: AppTheme.spacingXL),
          _buildButtonSection(settings),
          const SizedBox(height: AppTheme.spacingXL),
          _buildLayoutSection(settings),
          const SizedBox(height: AppTheme.spacingXL),
          _buildComfortSection(settings),
        ],
      ),
    );
  }

  /// Thèmes complets : un clic règle tout (couleurs, fond, boutons,
  /// disposition). Les réglages détaillés restent modifiables dessous.
  Widget _buildPresetsSection(ThemeSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Thèmes complets', style: AppTheme.labelLarge),
        const SizedBox(height: 2),
        Text(
          'Un clic règle tout ; tu peux ensuite ajuster en détail',
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
        ),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final preset in ThemePreset.all)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _hsl = HSLColor.fromColor(
                        preset.background ?? const Color(0xFF1B1038));
                    _accentHsl = HSLColor.fromColor(
                        preset.accent ?? _defaultAccent);
                    _customOpen = false;
                    _accentCustomOpen = false;
                  });
                  ref.read(themeProvider.notifier).applyPreset(preset);
                },
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 84,
                  child: Column(
                    children: [
                      _PresetPreview(
                        preset: preset,
                        selected: preset.matches(settings),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        preset.name,
                        style: AppTheme.labelSmall.copyWith(
                          color: preset.matches(settings)
                              ? AppTheme.textPrimary
                              : AppTheme.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Confort de lecture : taille du texte (toute l'app) et densité de la
  /// liste des morceaux.
  Widget _buildComfortSection(ThemeSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Taille du texte', style: AppTheme.labelLarge),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final size in TextSizeKind.values)
              _PreviewTile(
                label: size.label,
                selected: size == settings.textSize,
                width: 64,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                // textScaler fixe : l'aperçu montre l'écart entre les
                // tailles, sans être lui-même agrandi par le choix en cours.
                child: Text(
                  'Aa',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: 18 * size.scale,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                onTap: () =>
                    ref.read(themeProvider.notifier).setTextSize(size),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingL),
        Text('Densité de la liste', style: AppTheme.labelLarge),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final density in ListDensity.values)
              _PreviewTile(
                label: density.label,
                selected: density == settings.density,
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Container(
                        width: 40,
                        height: 8,
                        margin: EdgeInsets.symmetric(
                            vertical: density.gap / 2 + density.pad / 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
                onTap: () =>
                    ref.read(themeProvider.notifier).setDensity(density),
              ),
          ],
        ),
      ],
    );
  }

  /// Type de fond : même couleur, mais le dégradé change de forme.
  Widget _buildBackgroundStyleSection(BackgroundStyle current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type de fond', style: AppTheme.labelLarge),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final style in BackgroundStyle.values)
              _PreviewTile(
                label: style.label,
                selected: style == current,
                width: 64,
                height: 88,
                decoration: BoxDecoration(
                  gradient: AppTheme.screenGradientFor(style),
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                onTap: () => ref
                    .read(themeProvider.notifier)
                    .setBackgroundStyle(style),
              ),
          ],
        ),
      ],
    );
  }

  /// Style et forme des boutons principaux (lecture, classifier...).
  Widget _buildButtonSection(ThemeSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Boutons', style: AppTheme.labelLarge),
        const SizedBox(height: 2),
        Text(
          'Style et forme des boutons de lecture et d\'action',
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
        ),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final style in ButtonStyleKind.values)
              _PreviewTile(
                label: style.label,
                selected: style == settings.buttonStyle,
                width: 64,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: AppTheme.primaryButton(
                    size: 36,
                    style: style,
                    shapeKind: settings.buttonShape,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 22, color: Colors.white),
                ),
                onTap: () =>
                    ref.read(themeProvider.notifier).setButtonStyle(style),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final size in ButtonSizeKind.values)
              _PreviewTile(
                label: size.label,
                selected: size == settings.buttonSize,
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Container(
                  width: 36 * size.scale,
                  height: 36 * size.scale,
                  decoration: AppTheme.primaryButton(
                    size: 36 * size.scale,
                    style: settings.buttonStyle,
                    shapeKind: settings.buttonShape,
                  ),
                  child: Icon(Icons.play_arrow_rounded,
                      size: 22 * size.scale, color: Colors.white),
                ),
                onTap: () =>
                    ref.read(themeProvider.notifier).setButtonSize(size),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final shape in ButtonShapeKind.values)
              _PreviewTile(
                label: shape.label,
                selected: shape == settings.buttonShape,
                width: 84,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: AppTheme.primaryButton(
                    size: 36,
                    style: settings.buttonStyle,
                    shapeKind: shape,
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 22, color: Colors.white),
                ),
                onTap: () =>
                    ref.read(themeProvider.notifier).setButtonShape(shape),
              ),
          ],
        ),
      ],
    );
  }

  /// Emplacement : disposition des contrôles du lecteur et libellés de la
  /// barre du bas.
  Widget _buildLayoutSection(ThemeSettings settings) {
    Widget dot(IconData icon, {bool big = false}) => Icon(icon,
        size: big ? 16 : 11, color: Colors.white.withValues(alpha: 0.85));

    Widget preview(ControlsLayout layout) {
      final shuffle = dot(Icons.shuffle_rounded);
      final queue = dot(Icons.queue_music_rounded);
      final transport = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot(Icons.skip_previous_rounded),
          dot(Icons.play_circle_fill_rounded, big: true),
          dot(Icons.skip_next_rounded),
        ],
      );
      switch (layout) {
        case ControlsLayout.classic:
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [shuffle, transport, queue],
          );
        case ControlsLayout.grouped:
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [shuffle, transport, queue],
          );
        case ControlsLayout.split:
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              transport,
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [shuffle, queue],
              ),
            ],
          );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Contrôles du lecteur', style: AppTheme.labelLarge),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final layout in ControlsLayout.values)
              _PreviewTile(
                label: layout.label,
                selected: layout == settings.controlsLayout,
                width: 92,
                height: 56,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: preview(layout),
                ),
                onTap: () => ref
                    .read(themeProvider.notifier)
                    .setControlsLayout(layout),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingL),
        Text('Barre du bas', style: AppTheme.labelLarge),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final kind in NavLabelsKind.values)
              _PreviewTile(
                label: kind.label,
                selected: kind == settings.navLabels,
                width: 84,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimary,
                  borderRadius: BorderRadius.circular(AppTheme.radiusM),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle,
                              size: 10,
                              color: i == 0
                                  ? AppTheme.accentPrimary
                                  : Colors.white.withValues(alpha: 0.5)),
                          if (kind == NavLabelsKind.always ||
                              (kind == NavLabelsKind.selected && i == 0))
                            Container(
                              margin: const EdgeInsets.only(top: 3),
                              width: 14,
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                onTap: () =>
                    ref.read(themeProvider.notifier).setNavLabels(kind),
              ),
          ],
        ),
      ],
    );
  }

  /// Couleur principale : préréglages suggérés + « Perso » pour composer sa
  /// propre couleur. Sa clarté est bornée (0.50-0.72) pour rester visible
  /// sur le fond sombre ; les pastilles montrent ce qui est réellement
  /// appliqué.
  Widget _buildAccentSection(Color? accent) {
    final preview = _accentHsl.toColor();
    final isPreset = _accentPresets.any((p) => _isSelected(p.$2, accent));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Couleur principale', style: AppTheme.labelLarge),
        const SizedBox(height: 2),
        Text(
          'Boutons, curseurs et éléments actifs',
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
        ),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingM,
          runSpacing: AppTheme.spacingM,
          children: [
            for (final preset in _accentPresets)
              _AccentSwatch(
                label: preset.$1,
                color: preset.$2 ?? _defaultAccent,
                selected: _isSelected(preset.$2, accent),
                onTap: () {
                  setState(() {
                    _accentCustomOpen = false;
                    _accentHsl =
                        HSLColor.fromColor(preset.$2 ?? _defaultAccent);
                  });
                  _applyAccent(preset.$2);
                },
              ),
            _AccentSwatch(
              label: 'Perso',
              color: preview,
              selected: !isPreset,
              icon: Icons.tune_rounded,
              onTap: () {
                setState(() => _accentCustomOpen = !_accentCustomOpen);
                if (_accentCustomOpen) _applyAccent(preview);
              },
            ),
          ],
        ),
        if (_accentCustomOpen) ...[
          const SizedBox(height: AppTheme.spacingM),
          Container(
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              gradient: LinearGradient(colors: [
                _accentHsl.withHue((_accentHsl.hue + 12) % 360).toColor(),
                preview,
                _accentHsl.withHue((_accentHsl.hue + 348) % 360).toColor(),
              ]),
              border: Border.all(color: AppTheme.border),
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Row(
            children: [
              SizedBox(
                  width: 76, child: Text('Teinte', style: AppTheme.bodyMedium)),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Piste arc-en-ciel derrière le curseur.
                    Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: LinearGradient(colors: [
                          for (var h = 0; h <= 360; h += 60)
                            HSLColor.fromAHSL(1, h.toDouble(), 1, 0.5)
                                .toColor(),
                        ]),
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                      ),
                      child: Slider(
                        value: _accentHsl.hue.clamp(0.0, 360.0).toDouble(),
                        min: 0,
                        max: 360,
                        onChanged: (v) =>
                            setState(() => _accentHsl = _accentHsl.withHue(v)),
                        onChangeEnd: (_) => _applyAccent(_accentHsl.toColor()),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _buildAccentSlider(
            label: 'Intensité',
            value: _accentHsl.saturation,
            min: 0,
            max: 1,
            onChanged: (v) =>
                setState(() => _accentHsl = _accentHsl.withSaturation(v)),
          ),
          _buildAccentSlider(
            label: 'Clarté',
            value: _accentHsl.lightness,
            min: 0.5,
            max: 0.72,
            onChanged: (v) =>
                setState(() => _accentHsl = _accentHsl.withLightness(v)),
          ),
        ],
      ],
    );
  }

  Widget _buildAccentSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 76, child: Text(label, style: AppTheme.bodyMedium)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: (_) => _applyAccent(_accentHsl.toColor()),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 76,
          child: Text(label, style: AppTheme.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max).toDouble(),
            min: 0,
            max: max,
            onChanged: onChanged,
            // On applique à la fin du geste : changer le fond reconstruit
            // toute l'app, inutile de le faire à chaque pixel.
            onChangeEnd: (_) => _apply(_hsl.toColor()),
          ),
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final String label;
  final ThemePalette palette;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _Swatch({
    required this.label,
    required this.palette,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.cardElevated, palette.primary],
                ),
                border: Border.all(
                  color: selected
                      ? AppTheme.accentPrimary
                      : Colors.white.withValues(alpha: 0.25),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: icon != null
                  ? Icon(icon, size: 20, color: AppTheme.textPrimary)
                  : (selected
                      ? const Icon(Icons.check_rounded,
                          size: 20, color: AppTheme.textPrimary)
                      : null),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(
                color: selected ? AppTheme.textPrimary : AppTheme.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pastille de couleur principale : cercle plein (dégradé de la couleur telle
/// qu'elle sera appliquée) avec coche quand elle est active.
class _AccentSwatch extends StatelessWidget {
  final String label;
  final Color color;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  const _AccentSwatch({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    // Même bornage de clarté que AppTheme.applyAccent : la pastille montre
    // le rendu réel, pas la couleur brute.
    final hsl = HSLColor.fromColor(Color(color.toARGB32() | 0xFF000000));
    final l = hsl.lightness.clamp(0.50, 0.72).toDouble();
    final top = hsl
        .withHue((hsl.hue + 12) % 360)
        .withLightness(0.50)
        .toColor();
    final bottom = hsl
        .withHue((hsl.hue + 348) % 360)
        .withLightness(0.50)
        .toColor();
    final main = hsl.withLightness(l).toColor();

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [top, main, bottom],
                ),
                border: Border.all(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.25),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: icon != null
                  ? Icon(icon, size: 20, color: Colors.white)
                  : (selected
                      ? const Icon(Icons.check_rounded,
                          size: 20, color: Colors.white)
                      : null),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(
                color: selected ? AppTheme.textPrimary : AppTheme.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tuile d'aperçu (fond ou bouton) avec libellé et contour quand elle est
/// active.
class _PreviewTile extends StatelessWidget {
  final String label;
  final bool selected;
  final double width;
  final double height;
  final BoxDecoration decoration;
  final Widget? child;
  final VoidCallback onTap;

  const _PreviewTile({
    required this.label,
    required this.selected,
    required this.width,
    required this.height,
    required this.decoration,
    required this.onTap,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              decoration: decoration.copyWith(
                border: Border.all(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.25),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: child,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTheme.labelSmall.copyWith(
                color: selected ? AppTheme.textPrimary : AppTheme.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Aperçu d'un thème complet : fond (avec son type), bouton (style, forme,
/// taille) et couleur principale du préréglage, indépendamment du thème
/// actuellement appliqué.
class _PresetPreview extends StatelessWidget {
  final ThemePreset preset;
  final bool selected;

  const _PresetPreview({required this.preset, required this.selected});

  @override
  Widget build(BuildContext context) {
    final bg = preset.background == null
        ? ThemePalette.standard.primary
        : ThemePalette.fromBase(preset.background!).primary;
    final accent = preset.accent ?? const Color(0xFFA855F7);
    final glow = accent.withValues(alpha: 0.38);

    final Gradient? gradient;
    switch (preset.backgroundStyle) {
      case BackgroundStyle.vertical:
        gradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [glow, bg],
          stops: const [0.0, 0.7],
        );
      case BackgroundStyle.diagonal:
        gradient = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [glow, bg],
          stops: const [0.0, 0.8],
        );
      case BackgroundStyle.halo:
        gradient = RadialGradient(
          center: const Alignment(0, -0.95),
          radius: 0.95,
          colors: [glow, bg],
        );
      case BackgroundStyle.bottomGlow:
        gradient = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [glow, bg],
          stops: const [0.0, 0.7],
        );
      case BackgroundStyle.corner:
        gradient = RadialGradient(
          center: const Alignment(1, -1),
          radius: 1.25,
          colors: [glow, bg],
        );
      case BackgroundStyle.solid:
        gradient = null;
    }

    final side = 22.0 * preset.buttonSize.scale;
    final round = preset.buttonShape == ButtonShapeKind.round;
    final Color? fill;
    final Gradient? fillGradient;
    Border? border;
    switch (preset.buttonStyle) {
      case ButtonStyleKind.gradient:
        fill = null;
        fillGradient = LinearGradient(colors: [
          HSLColor.fromColor(accent).withLightness(0.55).toColor(),
          HSLColor.fromColor(accent).withLightness(0.42).toColor(),
        ]);
      case ButtonStyleKind.solid:
        fill = accent;
        fillGradient = null;
      case ButtonStyleKind.outline:
        fill = accent.withValues(alpha: 0.14);
        fillGradient = null;
        border = Border.all(color: accent, width: 1.5);
      case ButtonStyleKind.glass:
        fill = Colors.white.withValues(alpha: 0.16);
        fillGradient = null;
        border = Border.all(color: Colors.white.withValues(alpha: 0.3));
    }

    return Container(
      width: 84,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        gradient: gradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(
          color: selected ? Colors.white : Colors.white.withValues(alpha: 0.25),
          width: selected ? 2.5 : 1,
        ),
      ),
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          color: fill,
          gradient: fillGradient,
          border: border,
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: round ? null : BorderRadius.circular(side * 0.32),
        ),
        child: Icon(Icons.play_arrow_rounded,
            size: side * 0.62, color: Colors.white),
      ),
    );
  }
}
