import 'package:flutter/material.dart';

import '../models/track.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';

/// Carte de synthèse de l'onglet Ambiances : une barre colorée montre la
/// répartition des ambiances de la bibliothèque, les trois principales sont
/// détaillées, et les morceaux encore sans ambiance proposent un accès
/// direct à la classification.
class MoodPaletteCard extends StatelessWidget {
  /// Nombre de morceaux par ambiance (les zéros sont ignorés).
  final Map<MoodType, int> counts;

  /// Nombre total de morceaux de la bibliothèque.
  final int totalTracks;
  final bool isClassifying;
  final VoidCallback? onClassifyRest;

  const MoodPaletteCard({
    super.key,
    required this.counts,
    required this.totalTracks,
    this.isClassifying = false,
    this.onClassifyRest,
  });

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();

    final classified = entries.fold<int>(0, (sum, e) => sum + e.value);
    final rest = (totalTracks - classified).clamp(0, totalTracks).toInt();
    final top = entries.take(3).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingM,
        AppTheme.spacingL,
        0,
      ),
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandTop.withValues(alpha: 0.22),
            AppTheme.brandBottom.withValues(alpha: 0.08),
            AppTheme.backgroundCard,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ta palette sonore',
            style: AppTheme.headlineMedium.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${entries.length} ambiance${entries.length > 1 ? 's' : ''}'
            ' · $classified morceau${classified > 1 ? 'x' : ''} classé${classified > 1 ? 's' : ''}',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppTheme.spacingM),

          // Barre de répartition : un segment par ambiance, proportionnel
          // à son nombre de morceaux.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (var i = 0; i < entries.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: entries[i].value,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              MoodColors.forMood(entries[i].key).primary,
                              MoodColors.forMood(entries[i].key).secondary,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),

          // Les trois ambiances les plus présentes.
          Wrap(
            spacing: AppTheme.spacingL,
            runSpacing: AppTheme.spacingS,
            children: [
              for (final e in top)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: MoodColors.forMood(e.key).primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: MoodColors.forMood(e.key)
                                .primary
                                .withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      e.key.displayName,
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(e.value * 100 / classified).round()}%',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textTertiary),
                    ),
                  ],
                ),
            ],
          ),

          // Morceaux sans ambiance : accès direct à la classification.
          if (rest > 0) ...[
            const SizedBox(height: AppTheme.spacingM),
            Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: AppTheme.spacingM),
            Row(
              children: [
                Icon(
                  isClassifying
                      ? Icons.hourglass_top_rounded
                      : Icons.help_outline_rounded,
                  size: 16,
                  color: AppTheme.textTertiary,
                ),
                const SizedBox(width: AppTheme.spacingS),
                Expanded(
                  child: Text(
                    isClassifying
                        ? 'Classification en cours…'
                        : '$rest morceau${rest > 1 ? 'x' : ''} sans ambiance',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ),
                if (!isClassifying && onClassifyRest != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClassifyRest,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppTheme.accentPrimary.withValues(alpha: 0.16),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        border: Border.all(
                          color: AppTheme.accentPrimary.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mood_rounded,
                              size: 14, color: AppTheme.accentPrimary),
                          const SizedBox(width: 6),
                          Text(
                            'Classer',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.accentPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
