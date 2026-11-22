import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/live_context.dart';
import '../models/track.dart';
import '../providers/live_mood_provider.dart';
import '../providers/track_provider.dart';
import '../services/live_context_service.dart';
import '../services/live_mood_engine.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import '../utils/playback_navigation.dart';

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
      ),
      backgroundColor: AppTheme.backgroundCardElevated,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Carte « Maintenant » de Découvertes : lit le contexte (heure, météo de
/// la ville choisie, mouvement, casque) et propose un mix adapté.
class LiveMoodCard extends ConsumerWidget {
  const LiveMoodCard({super.key});

  static IconData _weatherIcon(WeatherInfo w) {
    switch (w.condition) {
      case WeatherCondition.clear:
        return w.isDay ? Icons.wb_sunny_rounded : Icons.nightlight_round;
      case WeatherCondition.cloudy:
        return Icons.cloud_rounded;
      case WeatherCondition.fog:
        return Icons.cloud_queue_rounded;
      case WeatherCondition.rain:
        return Icons.water_drop_rounded;
      case WeatherCondition.snow:
        return Icons.ac_unit_rounded;
      case WeatherCondition.storm:
        return Icons.bolt_rounded;
    }
  }

  void _play(BuildContext context, WidgetRef ref, LiveSuggestion s) {
    final mix = LiveMoodEngine.mix(ref.read(trackProvider).tracks, s);
    if (mix.isEmpty) {
      _snack(
        context,
        'Aucun morceau classé pour ce moment. Lance d\'abord la '
        'classification.',
      );
      return;
    }
    playAll(context, mix);
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundSecondary,
      builder: (_) => const _LiveSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(liveContextProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingL,
        AppTheme.spacingL,
        0,
      ),
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: AppTheme.glassDecoration,
      child: async.when(
        loading: () => Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppTheme.spacingM),
            Text(
              'Je regarde autour de toi…',
              style: AppTheme.bodyMedium
                  .copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        error: (_, __) => Row(
          children: [
            Expanded(
              child: Text(
                'Impossible de lire le contexte pour l\'instant.',
                style: AppTheme.bodyMedium
                    .copyWith(color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(liveContextProvider),
              child: const Text('Réessayer'),
            ),
          ],
        ),
        data: (c) => _buildData(context, ref, c),
      ),
    );
  }

  Widget _buildData(BuildContext context, WidgetRef ref, LiveContext c) {
    final suggestion = LiveMoodEngine.suggest(c);
    final w = c.weather;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sensors_rounded, color: AppTheme.accentPrimary),
            const SizedBox(width: AppTheme.spacingS),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MAINTENANT',
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textTertiary),
                  ),
                  Text(suggestion.title, style: AppTheme.titleMedium),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Actualiser',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                ref.read(liveContextServiceProvider).clearWeatherCache();
                ref.invalidate(liveContextProvider);
              },
            ),
            IconButton(
              tooltip: 'Réglages',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => _openSettings(context),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingS),
        Wrap(
          spacing: AppTheme.spacingS,
          runSpacing: AppTheme.spacingXS,
          children: [
            _ContextChip(
                icon: Icons.schedule_rounded, text: '${c.now.hour} h'),
            if (w != null)
              _ContextChip(
                icon: _weatherIcon(w),
                text: '${w.label} · ${w.tempC.round()}°',
              ),
            if (c.motion == MotionState.moving)
              const _ContextChip(
                  icon: Icons.directions_walk_rounded, text: 'En mouvement'),
            if (c.motion == MotionState.still)
              const _ContextChip(
                  icon: Icons.self_improvement_rounded, text: 'Au calme'),
            if (c.headphones)
              const _ContextChip(
                  icon: Icons.headphones_rounded, text: 'Casque ou Bluetooth'),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        Text(
          suggestion.reason,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingM),
        Wrap(
          spacing: AppTheme.spacingS,
          children: [
            for (final m in suggestion.weights.keys)
              Chip(
                avatar: CircleAvatar(
                  radius: 5,
                  backgroundColor: MoodColors.forMood(m).primary,
                ),
                label: Text(m.displayName),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (!c.hasPlace || c.weatherFailed) ...[
          const SizedBox(height: AppTheme.spacingS),
          Text(
            !c.hasPlace
                ? 'Ajoute ta ville pour que la météo compte dans la suggestion.'
                : 'Météo indisponible (hors ligne ?) : suggestion sans la météo.',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
          ),
        ],
        const SizedBox(height: AppTheme.spacingM),
        Row(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
              ),
              onPressed: () => _play(context, ref, suggestion),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Écouter'),
            ),
            if (!c.hasPlace) ...[
              const SizedBox(width: AppTheme.spacingS),
              TextButton(
                onPressed: () => _openSettings(context),
                child: const Text('Ajouter ma ville'),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

extension on LiveContext {
  bool get hasPlace => placeName != null;
}

class _ContextChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _ContextChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(text,
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

/// Réglages du mood live : ville pour la météo, détection de mouvement.
class _LiveSettingsSheet extends ConsumerStatefulWidget {
  const _LiveSettingsSheet();

  @override
  ConsumerState<_LiveSettingsSheet> createState() => _LiveSettingsSheetState();
}

class _LiveSettingsSheetState extends ConsumerState<_LiveSettingsSheet> {
  final TextEditingController _controller = TextEditingController();
  LiveSettings _settings = const LiveSettings();
  bool _loaded = false;
  bool _searching = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await ref.read(liveContextServiceProvider).settingsService.load();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _controller.text = s.city ?? '';
      _loaded = true;
    });
  }

  Future<void> _commit(LiveSettings next) async {
    final service = ref.read(liveContextServiceProvider);
    await service.settingsService.save(next);
    service.clearWeatherCache();
    ref.invalidate(liveContextProvider);
    if (mounted) setState(() => _settings = next);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;
    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final GeoPlace? place =
          await ref.read(liveContextServiceProvider).weather.geocode(query);
      if (!mounted) return;
      if (place == null) {
        setState(() => _message = 'Ville introuvable. Essaie un autre nom.');
      } else {
        await _commit(_settings.copyWith(
          city: place.name,
          lat: place.lat,
          lon: place.lon,
        ));
        if (mounted) {
          setState(() {
            _controller.text = place.name;
            _message = 'Ville enregistrée : ${place.label}';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Recherche impossible (hors ligne ?).');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingL,
        AppTheme.spacingL,
        AppTheme.spacingL + bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Réglages du mood live', style: AppTheme.titleMedium),
              const SizedBox(height: AppTheme.spacingM),
              Text('Ville pour la météo', style: AppTheme.bodyLarge),
              const SizedBox(height: AppTheme.spacingS),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: _loaded && !_searching,
                      style: AppTheme.bodyLarge,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: 'Ex. Fianarantsoa',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentPrimary,
                    ),
                    onPressed: (_loaded && !_searching) ? _search : null,
                    child: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Chercher'),
                  ),
                ],
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacingS),
                  child: Text(
                    _message!,
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ),
              if (_settings.hasPlace)
                TextButton(
                  onPressed: () async {
                    await _commit(_settings.withoutPlace());
                    if (mounted) {
                      setState(() {
                        _controller.clear();
                        _message = 'Ville retirée.';
                      });
                    }
                  },
                  child: const Text('Retirer la ville'),
                ),
              const SizedBox(height: AppTheme.spacingS),
              Text(
                'Seules les coordonnées de la ville sont envoyées au service '
                'météo (Open-Meteo). La position du téléphone n\'est jamais '
                'utilisée.',
                style:
                    AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
              ),
              const Divider(height: AppTheme.spacingXL),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Détecter si je bouge', style: AppTheme.bodyLarge),
                subtitle: Text(
                  'Lit l\'accéléromètre 3 secondes à l\'ouverture de '
                  'Découvertes et à chaque actualisation, jamais en continu.',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
                activeThumbColor: AppTheme.accentPrimary,
                value: _settings.motionEnabled,
                onChanged: _loaded
                    ? (v) => _commit(_settings.copyWith(motionEnabled: v))
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
