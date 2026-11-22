import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/lyric_line.dart';

/// Paroles « karaoké » d'une carte de partage : seule la ligne en cours est
/// affichée, dans un panneau vitré centré (pas plein écran).
///
/// Pas de remplissage mot par mot : une ligne LRC est souvent un morceau de
/// phrase (« Singin' don't worry » / « about a thing »), donc un balayage
/// par ligne coupait la phrase de façon bizarre. À la place, la ligne entière
/// apparaît en fondu avec un halo lumineux qui se calme, pendant que la
/// précédente s'efface.
class KaraokeLyrics extends StatelessWidget {
  final List<LyricLine> lines;

  /// Position dans le morceau (décalage de l'utilisateur déjà appliqué).
  final int timeMs;

  const KaraokeLyrics({super.key, required this.lines, required this.timeMs});

  /// Durée du fondu entre deux lignes.
  static const int _transitionMs = 450;

  /// Identifie l'aspect de la carte à [timeMs] : deux instants de même clé
  /// donnent la même image (ligne affichée sans transition en cours), ce qui
  /// évite de recapturer des images identiques pour la vidéo. Une clé paire
  /// = image stable ; impaire = transition en cours (jamais réutilisée).
  static int frameKey(List<LyricLine> lines, int timeMs) {
    var cur = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timestamp.inMilliseconds <= timeMs) {
        cur = i;
      } else {
        break;
      }
    }
    if (cur >= 0 &&
        timeMs - lines[cur].timestamp.inMilliseconds < _transitionMs) {
      return (timeMs << 1) | 1;
    }
    return (cur + 1) << 1;
  }

  @override
  Widget build(BuildContext context) {
    var cur = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timestamp.inMilliseconds <= timeMs) {
        cur = i;
      } else {
        break;
      }
    }

    String textAt(int i) => i >= 0 ? lines[i].text.trim() : '';
    final current = textAt(cur);
    final previous = textAt(cur - 1);

    // 0 -> 1 pendant la transition, puis reste à 1.
    final appear = cur < 0
        ? 1.0
        : ((timeMs - lines[cur].timestamp.inMilliseconds) / _transitionMs)
            .clamp(0.0, 1.0);
    // Le halo démarre fort puis se calme sur la ligne affichée.
    final glow = 0.35 + 0.65 * (1 - appear);

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 150),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (previous.isNotEmpty && appear < 1)
                Opacity(
                  opacity: 1 - appear,
                  child: _line(previous, 0.2),
                ),
              Opacity(
                opacity: current.isEmpty ? 0.0 : appear,
                child: current.isEmpty ? const SizedBox.shrink() : _line(current, glow),
              ),
              if (current.isEmpty)
                Opacity(
                  opacity: appear,
                  child: const Text(
                    '♪',
                    style: TextStyle(color: Colors.white54, fontSize: 30),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _line(String text, double glow) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        height: 1.25,
        shadows: [
          Shadow(
            color: Colors.white.withValues(alpha: 0.75 * glow),
            blurRadius: 18,
          ),
          Shadow(
            color: Colors.white.withValues(alpha: 0.45 * glow),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}
