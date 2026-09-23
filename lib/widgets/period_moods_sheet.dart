import 'package:flutter/material.dart' hide DayPeriod;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/track.dart';
import '../providers/mood_suggestions_provider.dart';
import '../providers/profile_provider.dart';
import '../theme/app_theme.dart';

/// Feuille de réglage des ambiances d'un moment de la journée. Au moins
/// une ambiance reste toujours sélectionnée.
Future<void> showPeriodMoodsSheet(BuildContext context, DayPeriod period) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.backgroundCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
    ),
    builder: (_) => _PeriodMoodsSheet(period: period),
  );
}

class _PeriodMoodsSheet extends ConsumerWidget {
  final DayPeriod period;

  const _PeriodMoodsSheet({required this.period});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(periodMoodsProvider(period));
    final notifier = ref.read(profileProvider.notifier);
    final moods = MoodType.values.where((m) => m != MoodType.unknown).toList();

    void toggle(MoodType mood, bool on) {
      final next = Set<MoodType>.from(selected);
      on ? next.add(mood) : next.remove(mood);
      if (next.isEmpty) return;
      notifier.setPeriodMoods(period.name, next.map((m) => m.name).toList());
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ambiances · ${labelForPeriod(period)}',
                style: AppTheme.headlineMedium),
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              'Les mixes de ce moment sont composés de morceaux de ces ambiances.',
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacingL),
            Wrap(
              spacing: AppTheme.spacingS,
              runSpacing: AppTheme.spacingS,
              children: [
                for (final mood in moods)
                  FilterChip(
                    avatar: Icon(mood.iconData,
                        size: 16, color: AppTheme.textPrimary),
                    label: Text(mood.displayName),
                    selected: selected.contains(mood),
                    onSelected: (on) => toggle(mood, on),
                    showCheckmark: false,
                    backgroundColor: AppTheme.backgroundCardElevated,
                    selectedColor: AppTheme.accentPrimary.withValues(alpha: 0.6),
                    labelStyle: AppTheme.labelMedium
                        .copyWith(color: AppTheme.textPrimary),
                    side: const BorderSide(color: AppTheme.border),
                  ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingM),
            TextButton.icon(
              onPressed: () => notifier.setPeriodMoods(period.name, null),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Remettre par défaut'),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
