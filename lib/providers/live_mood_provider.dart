import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/live_context.dart';
import '../services/live_context_service.dart';

final liveContextServiceProvider = Provider<LiveContextService>((ref) {
  return LiveContextService();
});

/// Contexte du moment. Gardé 10 minutes en mémoire : revenir sur
/// Découvertes ne relance pas 3 secondes de lecture du capteur à chaque
/// fois. Le bouton « Actualiser » et les réglages invalident ce provider.
final liveContextProvider = FutureProvider.autoDispose<LiveContext>((ref) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 10), link.close);
  ref.onDispose(timer.cancel);
  return ref.read(liveContextServiceProvider).gather();
});
