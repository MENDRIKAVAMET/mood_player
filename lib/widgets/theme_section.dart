import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';

/// Carte « Thème » de l'écran de profil : choix de la couleur de fond de
/// l'app (préréglages ou composée soi-même) et de la couleur principale
/// (le violet d'origine) : cette dernière n'a aucun préréglage, c'est
/// l'utilisateur qui la compose librement (teinte / intensité / clarté).
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

  /// Violet d'origine, point de départ du sélecteur de couleur principale.
  static const Color _defaultAccent = Color(0xFFA855F7);

  late HSLColor _hsl;
  late HSLColor _accentHsl;
  bool _customOpen = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(themeProvider).background;
    _hsl = HSLColor.fromColor(current ?? const Color(0xFF1B1038));
    _accentHsl = HSLColor.fromColor(
        ref.read(themeProvider).accent ?? _defaultAccent);
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
          _buildAccentSection(accent),
        ],
      ),
    );
  }

  /// Couleur principale : aucune couleur imposée, l'utilisateur choisit
  /// librement. Sa clarté est bornée (0.50-0.72) pour rester visible sur
  /// le fond sombre ; les curseurs reflètent exactement ce qui est appliqué.
  Widget _buildAccentSection(Color? accent) {
    final preview = _accentHsl.toColor();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Couleur principale', style: AppTheme.labelLarge),
            ),
            if (accent != null)
              TextButton(
                onPressed: () {
                  setState(() => _accentHsl = HSLColor.fromColor(_defaultAccent));
                  _applyAccent(null);
                },
                child: Text('Violet d\'origine',
                    style: AppTheme.labelMedium
                        .copyWith(color: AppTheme.accentPrimary)),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingS),
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
            SizedBox(width: 76, child: Text('Teinte', style: AppTheme.bodyMedium)),
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
                          HSLColor.fromAHSL(1, h.toDouble(), 1, 0.5).toColor(),
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
