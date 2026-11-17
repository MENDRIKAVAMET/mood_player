import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart';

/// Chef d'orchestre des tâches de fond (pochettes, volume, classification...).
///
/// Règle d'or : une tâche de fond ne doit jamais se faire au moment où
/// l'utilisateur touche l'écran. Avant chaque petite unité de travail, elle
/// appelle [idle] ; l'appel ne rend la main que quand l'écran est tranquille :
///  * plus de défilement depuis un court instant ;
///  * pas de frame lente récente. Si le travail de fond lui-même fait
///    ramer l'écran, il se met donc en pause tout seul (auto-régulation).
///
/// Alimenté par un `NotificationListener<ScrollNotification>` placé à la
/// racine de l'app (voir `main.dart`) : toutes les listes sont couvertes sans
/// toucher à chaque écran.
class UiGate {
  UiGate._();
  static final UiGate instance = UiGate._();

  /// Silence nécessaire après le dernier mouvement de défilement.
  static const Duration _scrollQuiet = Duration(milliseconds: 400);

  /// Silence nécessaire après la dernière frame lente.
  static const Duration _jankQuiet = Duration(milliseconds: 600);

  /// Au-delà, une frame est considérée comme lente (budget 60 Hz : ~16 ms).
  static const Duration _jankThreshold = Duration(milliseconds: 24);

  static final DateTime _never = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastScroll = _never;
  DateTime _lastJank = _never;
  bool _attached = false;

  /// Branche la mesure des frames. À appeler une fois au démarrage.
  void attach() {
    if (_attached) return;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (t.totalSpan > _jankThreshold) {
        _lastJank = DateTime.now();
        return;
      }
    }
  }

  /// À appeler à chaque `ScrollNotification` (début, mise à jour, fin).
  /// On ne compte pas les débuts/fins : un « fin » perdu (liste détruite en
  /// plein défilement) bloquerait sinon les tâches de fond pour toujours.
  void noteScrollActivity() => _lastScroll = DateTime.now();

  /// Vrai si l'écran est en train de défiler ou vient de ramer.
  bool get isBusy {
    final now = DateTime.now();
    return now.difference(_lastScroll) < _scrollQuiet ||
        now.difference(_lastJank) < _jankQuiet;
  }

  /// Rend la main quand l'écran est tranquille. [minGap] laisse en plus
  /// respirer l'UI entre deux unités de travail, même quand tout est calme.
  Future<void> idle({Duration minGap = Duration.zero}) async {
    // Même à Duration.zero, on repasse par la boucle d'événements : l'UI peut
    // traiter ses touches et dessiner ses frames avant la suite.
    await Future<void>.delayed(minGap);
    while (isBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
