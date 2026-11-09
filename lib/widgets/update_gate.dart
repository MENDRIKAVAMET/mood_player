import 'dart:io';

import 'package:flutter/material.dart';

import '../features/update/update_screen.dart';
import '../services/update_service.dart';

/// À l'ouverture de l'app, vérifie s'il existe une version plus récente et
/// la propose dans un dialogue. Enveloppe l'écran d'accueil.
class UpdateGate extends StatefulWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  @override
  void initState() {
    super.initState();
    // Android seulement (l'installation passe par du code natif), et pas
    // dans les tests.
    if (Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final update = await UpdateService().checkForUpdate();
    if (update == null || !mounted) return;
    await Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, _, _) => UpdateScreen(update: update),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.06), end: Offset.zero)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
