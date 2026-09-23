import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/foryou/suggestion_mix_screen.dart';
import '../providers/mood_suggestions_provider.dart';
import '../theme/app_theme.dart';
import 'period_moods_sheet.dart';
import 'suggestion_mix_card.dart';

/// Section « Pour vous » du moment de la journée en cours : titre, ambiances
/// actives (modifiables) et carrousel horizontal de 5 mixes de 20 morceaux.
class PeriodMixesSection extends ConsumerWidget {
  final DayPeriod period;

  const PeriodMixesSection({super.key, required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mixes = ref.watch(periodMixesProvider(period));
    final moods = ref.watch(periodMoodsProvider(period));
    final moodsLabel = moods.map((m) => m.displayName).join(' + ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingL,
            AppTheme.spacingXL,
            AppTheme.spacingS,
            AppTheme.spacingM,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      labelForPeriod(period),
                      style: AppTheme.labelMedium
                          .copyWith(color: AppTheme.accentSecondary),
                    ),
                    Text(titleForPeriod(period), style: AppTheme.headlineLarge),
                    const SizedBox(height: 2),
                    Text(
                      moodsLabel,
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Modifier les ambiances',
                icon: const Icon(Icons.tune_rounded,
                    color: AppTheme.textSecondary),
                onPressed: () => showPeriodMoodsSheet(context, period),
              ),
            ],
          ),
        ),
        if (mixes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
            child: Text(
              'Aucun morceau classé en $moodsLabel pour le moment.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
            ),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
              itemCount: mixes.length,
              itemBuilder: (context, i) => SuggestionMixCard(
                mix: mixes[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SuggestionMixScreen(mix: mixes[i]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
