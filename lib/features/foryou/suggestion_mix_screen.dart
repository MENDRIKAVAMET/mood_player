import 'package:flutter/material.dart';

import '../../providers/mood_suggestions_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/playback_navigation.dart';
import '../../widgets/foryou_list_row.dart';

/// Contenu d'un mix : ses 20 morceaux, avec lecture dans l'ordre ou en
/// aléatoire.
class SuggestionMixScreen extends StatelessWidget {
  final SuggestionMix mix;

  const SuggestionMixScreen({super.key, required this.mix});

  @override
  Widget build(BuildContext context) {
    final tracks = mix.tracks;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingS, AppTheme.spacingS, AppTheme.spacingL, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppTheme.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        '${mix.title} · ${labelForPeriod(mix.period)}',
                        style: AppTheme.headlineLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppTheme.spacingL,
                    AppTheme.spacingXS, AppTheme.spacingL, AppTheme.spacingM),
                child: Text(
                  '${tracks.length} morceaux · ${mix.artistsSummary}',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingL),
                child: Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () => playAll(context, tracks),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Jouer'),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentPrimary),
                    ),
                    const SizedBox(width: AppTheme.spacingS),
                    OutlinedButton.icon(
                      onPressed: () => playShuffled(context, tracks),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Aléatoire'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingS),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: tracks.length,
                  itemBuilder: (context, i) => ForYouListRow(
                    track: tracks[i],
                    onTap: () =>
                        openPlayer(context, track: tracks[i], tracks: tracks),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
