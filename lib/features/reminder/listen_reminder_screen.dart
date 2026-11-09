import 'package:flutter/material.dart';

import '../../models/listen_event.dart';
import '../../models/track.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';
import '../../widgets/track_artwork.dart';

/// Écran plein écran « Ça te dit de réécouter ? ».
///
/// Le morceau principal est mis en scène en grand, sur un fond aux couleurs
/// de son ambiance ; les autres rappels sont listés dessous. Se ferme avec
/// le [Track] choisi (ou `null` pour « Plus tard »).
class ListenReminderScreen extends StatelessWidget {
  final List<(ListenReminder, Track)> items;

  const ListenReminderScreen({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final (heroReminder, heroTrack) = items.first;
    final mood = heroTrack.mood;
    final tint = MoodColors.forMood(mood).primary;
    final others = items.skip(1).toList();
    final showMood = mood != null && mood != MoodType.unknown;
    final width = MediaQuery.of(context).size.width;
    final cover = (width - 2 * AppTheme.spacingXL).clamp(200.0, 340.0);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.55, 1],
            colors: [
              Color.alphaBlend(
                  tint.withValues(alpha: 0.38), AppTheme.backgroundPrimary),
              Color.alphaBlend(
                  tint.withValues(alpha: 0.08), AppTheme.backgroundPrimary),
              AppTheme.backgroundPrimary,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 30),
                      color: AppTheme.textPrimary,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.18),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded, color: tint, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'DÉJÀ ÉCOUTÉ',
                            style: AppTheme.bodySmall.copyWith(
                              color: tint,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingXL),
                  children: [
                    const SizedBox(height: AppTheme.spacingL),
                    Text(
                      'Ça te dit de\nréécouter ?',
                      textAlign: TextAlign.center,
                      style: AppTheme.headlineMedium.copyWith(
                        fontSize: 30,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(heroReminder.whenLabel,
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyLarge
                            .copyWith(color: AppTheme.textSecondary)),
                    const SizedBox(height: AppTheme.spacingXL),
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: tint.withValues(alpha: 0.45),
                              blurRadius: 50,
                              offset: const Offset(0, 22),
                            ),
                          ],
                        ),
                        child: TrackArtwork(
                          track: heroTrack,
                          size: cover,
                          radius: 32,
                          placeholderFontSize: 90,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingXL),
                    Text(
                      heroTrack.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.headlineMedium
                          .copyWith(fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      heroTrack.artist,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyLarge
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                    if (showMood) ...[
                      const SizedBox(height: AppTheme.spacingM),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: tint.withValues(alpha: 0.16),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(mood.iconData, size: 14, color: tint),
                              const SizedBox(width: 6),
                              Text(
                                mood.displayName,
                                style: AppTheme.bodySmall.copyWith(
                                    color: tint, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: AppTheme.spacingXL),
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: tint,
                              borderRadius: BorderRadius.circular(
                                  AppTheme.radiusFull),
                            ),
                          ),
                          const SizedBox(width: AppTheme.spacingM),
                          Text('Aussi à réécouter',
                              style: AppTheme.titleLarge
                                  .copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingS),
                      for (final (reminder, track) in others)
                        _OtherRow(
                          reminder: reminder,
                          track: track,
                          onTap: () => Navigator.pop(context, track),
                        ),
                    ],
                    const SizedBox(height: AppTheme.spacingL),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingXL, 4, AppTheme.spacingXL, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context, heroTrack),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        child: Ink(
                          height: 58,
                          decoration: BoxDecoration(
                            gradient: AppTheme.brandGradient,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusFull),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accentPrimary
                                    .withValues(alpha: 0.4),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 28),
                              const SizedBox(width: 6),
                              Text('Écouter',
                                  style: AppTheme.labelLarge.copyWith(
                                      color: Colors.white, fontSize: 17)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text('Plus tard',
                          style: AppTheme.labelLarge
                              .copyWith(color: AppTheme.textTertiary)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherRow extends StatelessWidget {
  final ListenReminder reminder;
  final Track track;
  final VoidCallback onTap;

  const _OtherRow({
    required this.reminder,
    required this.track,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            TrackArtwork(
                track: track, size: 52, radius: 14, placeholderFontSize: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyLarge.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600)),
                  Text('${track.artist} · ${reminder.whenLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodySmall),
                ],
              ),
            ),
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.play_arrow_rounded,
                  color: AppTheme.accentPrimary, size: 24),
            ),
          ],
        ),
      ),
    );
  }
}
