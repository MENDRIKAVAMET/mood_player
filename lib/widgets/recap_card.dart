import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/recap_builder.dart';
import '../theme/mood_colors.dart';

/// Carte-image du bilan du mois (format story 9:16).
///
/// Taille de conception FIXE : l'image partagée est identique sur tous les
/// téléphones et ne dépend ni du thème de l'app ni de la taille de police
/// du système (d'où les styles explicites et le texte non mis à l'échelle).
/// L'écran l'affiche réduite avec un `FittedBox` et la capture à 3x.
class RecapCard extends StatelessWidget {
  static const double width = 360;
  static const double height = 640;

  final MonthlyRecap recap;

  const RecapCard({super.key, required this.recap});

  @override
  Widget build(BuildContext context) {
    final mood = recap.dominantMood;
    final colors = MoodColors.forMood(mood);
    final hour = recap.favoriteHour;

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: SizedBox(
        width: width,
        height: height,
        child: Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(colors.gradientStart, colors.primary, 0.55)!,
                  colors.gradientStart,
                  const Color(0xFF0A0A0A),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
            child: Stack(
              children: [
                // Halo de la couleur de l'ambiance, en haut à droite.
                Positioned(
                  top: -90,
                  right: -90,
                  width: 340,
                  height: 340,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          colors.primary.withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'AURA',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            RecapBuilder.monthLabel(recap.month),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Text(
                        'Ton ambiance du mois',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 14),
                      if (mood != null) ..._moodBlock(mood, colors)
                      else ..._noMoodBlock(),
                      const Spacer(),
                      const Text(
                        'Tes morceaux du mois',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < recap.topTracks.length; i++)
                        _TrackRow(
                          rank: i + 1,
                          track: recap.topTracks[i],
                          accent: colors.primary,
                        ),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: _Stat(
                              label: 'HEURE FAVORITE',
                              value: hour == null
                                  ? '—'
                                  : RecapBuilder.hourLabel(hour),
                              sub: hour == null
                                  ? ''
                                  : RecapBuilder.dayPeriod(hour),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _Stat(
                              label: 'ÉCOUTES',
                              value: '${recap.totalPlays}',
                              sub: 'jusqu\'au bout',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _moodBlock(MoodType mood, MoodColors colors) {
    final pct = (recap.dominantShare * 100).round();
    return [
      Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primary.withValues(alpha: 0.25),
          border: Border.all(color: colors.primary, width: 2),
        ),
        child: Icon(mood.iconData, size: 34, color: Colors.white),
      ),
      const SizedBox(height: 14),
      Text(
        mood.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.w800,
          height: 1.05,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        '$pct % de tes écoutes',
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
    ];
  }

  List<Widget> _noMoodBlock() => [
        Text(
          '${recap.totalPlays} écoutes',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.w800,
            height: 1.05,
          ),
        ),
      ];
}

class _TrackRow extends StatelessWidget {
  final int rank;
  final RecapTrack track;
  final Color accent;

  const _TrackRow({
    required this.rank,
    required this.track,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              style: TextStyle(
                color: accent,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '×${track.plays}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final String sub;

  const _Stat({required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
