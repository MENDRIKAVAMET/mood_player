import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/equalizer_settings.dart';
import '../../providers/providers.dart';
import '../../services/audio_handler.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';

/// Égaliseur : préréglages, curseurs par bande et renforcement du volume.
/// S'appuie sur l'égaliseur système Android (via just_audio), qui ne
/// s'attache qu'une fois un morceau chargé.
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  EqualizerBands? _bands;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBands();
  }

  Future<void> _loadBands() async {
    setState(() => _loading = true);
    EqualizerBands? bands;
    try {
      final handler = await ref.read(audioHandlerProvider.future);
      bands = await handler.equalizerBands();
    } catch (_) {
      bands = null;
    }
    if (!mounted) return;
    setState(() {
      _bands = bands;
      _loading = false;
    });
  }

  static String _freqLabel(double hz) {
    if (hz >= 1000) {
      final k = hz / 1000;
      return '${k.toStringAsFixed(k == k.roundToDouble() ? 0 : 1)} kHz';
    }
    return '${hz.round()} Hz';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(equalizerProvider);
    final notifier = ref.read(equalizerProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const AppHeader(title: 'Égaliseur', showBack: true),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingXL),
                  children: [
                    _card(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Activer l\'égaliseur',
                                    style: AppTheme.titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                  'S\'applique à toute la lecture',
                                  style: AppTheme.bodySmall.copyWith(
                                      color: AppTheme.textTertiary),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: settings.enabled,
                            activeThumbColor: AppTheme.accentPrimary,
                            onChanged: Platform.isAndroid
                                ? notifier.setEnabled
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXL),
                    if (!Platform.isAndroid)
                      _hint('L\'égaliseur n\'est disponible que sur Android.')
                    else ...[
                      Text('Préréglages', style: AppTheme.titleLarge),
                      const SizedBox(height: AppTheme.spacingM),
                      Wrap(
                        spacing: AppTheme.spacingS,
                        runSpacing: AppTheme.spacingS,
                        children: [
                          for (final p in EqualizerSettings.presets)
                            ChoiceChip(
                              label: Text(p.name),
                              selected: settings.preset == p.name,
                              onSelected: (_) => notifier.selectPreset(p.name),
                              selectedColor:
                                  AppTheme.accentPrimary.withValues(alpha: 0.35),
                              backgroundColor: AppTheme.backgroundCard,
                              labelStyle: AppTheme.bodyMedium,
                              side: BorderSide.none,
                            ),
                          if (settings.preset == EqualizerSettings.customName)
                            ChoiceChip(
                              label: const Text(EqualizerSettings.customName),
                              selected: true,
                              onSelected: (_) {},
                              selectedColor:
                                  AppTheme.accentPrimary.withValues(alpha: 0.35),
                              labelStyle: AppTheme.bodyMedium,
                              side: BorderSide.none,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingXL),
                      Text('Bandes', style: AppTheme.titleLarge),
                      const SizedBox(height: AppTheme.spacingM),
                      _buildBands(settings, notifier),
                      const SizedBox(height: AppTheme.spacingXL),
                      Text('Renforcement du volume',
                          style: AppTheme.titleLarge),
                      const SizedBox(height: AppTheme.spacingXS),
                      Text(
                        '+${settings.loudnessDb.toStringAsFixed(1)} dB'
                        '  ·  un réglage trop fort peut saturer le son',
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textTertiary),
                      ),
                      Slider(
                        value: settings.loudnessDb,
                        min: 0,
                        max: EqualizerSettings.maxLoudnessDb,
                        divisions: 16,
                        activeColor: AppTheme.accentPrimary,
                        onChanged: settings.enabled ? notifier.setLoudness : null,
                        onChangeEnd: (_) => notifier.persist(),
                      ),
                      const SizedBox(height: AppTheme.spacingM),
                      Center(
                        child: TextButton.icon(
                          onPressed: notifier.reset,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('Réinitialiser'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBands(EqualizerSettings settings, EqualizerNotifier notifier) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppTheme.spacingXL),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final bands = _bands;
    if (bands == null) {
      return Column(
        children: [
          _hint('Lancez un morceau pour régler les bandes : l\'égaliseur '
              'n\'est disponible qu\'une fois la lecture démarrée. Vos '
              'préréglages et le volume ci-dessous s\'appliqueront dès le '
              'premier morceau.'),
          TextButton.icon(
            onPressed: _loadBands,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Réessayer'),
          ),
        ],
      );
    }

    final count = bands.centerFrequenciesHz.length;
    final gains = settings.gainsFor(count);
    return Opacity(
      opacity: settings.enabled ? 1 : 0.5,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Column(
                children: [
                  Text(
                    '${gains[i] >= 0 ? '+' : ''}${gains[i].toStringAsFixed(1)}',
                    style: AppTheme.labelSmall,
                  ),
                  SizedBox(
                    height: 220,
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Slider(
                        value: gains[i].clamp(bands.minDb, bands.maxDb).toDouble(),
                        min: bands.minDb,
                        max: bands.maxDb,
                        activeColor: AppTheme.accentPrimary,
                        onChanged: settings.enabled
                            ? (v) => notifier.setBandGain(i, v, count)
                            : null,
                        onChangeEnd: (_) => notifier.persist(),
                      ),
                    ),
                  ),
                  Text(
                    _freqLabel(bands.centerFrequenciesHz[i]),
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        child: child,
      );

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
        child: Text(
          text,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
        ),
      );
}
