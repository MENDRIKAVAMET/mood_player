import 'package:flutter/material.dart';

import '../../models/lyric_line.dart';

/// Paroles « karaoké » d'une carte de partage : la ligne précédente et la
/// suivante en retrait, la ligne courante se remplit de gauche à droite au
/// fil de [timeMs]. Les paroles LRC n'ont pas de minutage par mot : la
/// progression est répartie sur la durée de la ligne.
class KaraokeLyrics extends StatelessWidget {
  final List<LyricLine> lines;

  /// Position dans le morceau (décalage de l'utilisateur déjà appliqué).
  final int timeMs;

  const KaraokeLyrics({super.key, required this.lines, required this.timeMs});

  /// Durée maximale pendant laquelle une ligne se remplit (au-delà, la ligne
  /// est considérée comme finie : passage instrumental).
  static const int _maxLineMs = 7000;

  @override
  Widget build(BuildContext context) {
    // Lignes vides (pauses) ignorées : la dernière ligne chantée reste à
    // l'écran, remplie, pendant un passage instrumental.
    final ls = lines.where((l) => l.text.trim().isNotEmpty).toList();
    if (ls.isEmpty) return const SizedBox.shrink();

    var cur = -1;
    for (var i = 0; i < ls.length; i++) {
      if (ls[i].timestamp.inMilliseconds <= timeMs) {
        cur = i;
      } else {
        break;
      }
    }

    double progress = 0;
    if (cur >= 0) {
      final start = ls[cur].timestamp.inMilliseconds;
      var end = cur + 1 < ls.length
          ? ls[cur + 1].timestamp.inMilliseconds
          : start + _maxLineMs;
      if (end - start > _maxLineMs) end = start + _maxLineMs;
      progress = end > start ? ((timeMs - start) / (end - start)) : 1;
      progress = progress.clamp(0.0, 1.0);
    }

    // Avant la première ligne : on annonce la suivante, rien n'est rempli.
    final prev = cur - 1 >= 0 ? ls[cur - 1].text.trim() : null;
    final current = cur >= 0 ? ls[cur].text.trim() : null;
    final nextIdx = cur + 1;
    final next = nextIdx < ls.length ? ls[nextIdx].text.trim() : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dim(prev),
        const SizedBox(height: 18),
        if (current != null)
          _Active(text: current, progress: progress)
        else
          _dim(null, placeholder: true),
        const SizedBox(height: 18),
        _dim(cur < 0 ? (next ?? '') : next),
      ],
    );
  }

  Widget _dim(String? text, {bool placeholder = false}) {
    if (text == null || text.isEmpty) return const SizedBox(height: 26);
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
  }
}

class _Active extends StatelessWidget {
  final String text;
  final double progress;

  const _Active({required this.text, required this.progress});

  static const TextStyle _style = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 4,
          style: _style.copyWith(color: Colors.white38),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => LinearGradient(
            colors: const [Colors.white, Colors.white, Colors.transparent, Colors.transparent],
            stops: [0, progress, progress, 1],
          ).createShader(rect),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 4,
            style: _style.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}
