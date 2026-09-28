import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/listen_event.dart';
import '../models/track.dart';
import '../providers/listen_history_provider.dart';
import '../providers/providers.dart';
import '../services/reminder_notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/playback_navigation.dart';
import 'track_artwork.dart';

/// Widget invisible qui affiche le pop-up « tu écoutais ça à cette heure »
/// quand l'app est ouverte. Quand elle ne l'est pas, c'est la notification
/// programmée qui s'en charge ; ici on annule cette notification juste
/// avant l'heure pour ne pas avoir les deux en même temps.
class ListenReminderHost extends ConsumerStatefulWidget {
  const ListenReminderHost({super.key});

  @override
  ConsumerState<ListenReminderHost> createState() => _ListenReminderHostState();
}

class _ListenReminderHostState extends ConsumerState<ListenReminderHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _showing = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    // En arrière-plan (ex. musique qui continue de jouer), c'est la
    // notification qui doit s'afficher : on ne touche à rien.
    if (!mounted || _showing || _lifecycle != AppLifecycleState.resumed) return;

    final notifier = ref.read(listenHistoryProvider.notifier);
    await notifier.ensureLoaded();
    if (!mounted) return;

    final now = DateTime.now();
    final pending = notifier.pendingReminders(now);
    if (pending.isEmpty) return;

    for (final r in pending) {
      unawaited(ReminderNotificationService.cancel(r.notificationId)
          .catchError((_) {}));
    }

    final due = pending.where((r) => !now.isBefore(r.scheduledAt)).toList();
    if (due.isEmpty) return;

    final library = ref.read(trackProvider).tracks;
    final items = <(ListenReminder, Track)>[];
    final seen = <int>{};
    for (final r in due) {
      final track = library.where((t) => t.id == r.event.trackId).firstOrNull;
      if (track != null && seen.add(track.id)) items.add((r, track));
    }

    // Marqués comme présentés dans tous les cas : un rappel dont le
    // morceau a disparu de la bibliothèque ne doit pas revenir.
    await notifier.markShown(due);
    if (items.isEmpty || !mounted) return;

    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _ReminderDialog(
          items: items.take(3).toList(),
          onPlay: (track) {
            Navigator.pop(dialogContext);
            openPlayer(
              context,
              track: track,
              tracks: items.map((i) => i.$2).toList(),
            );
          },
        ),
      );
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ReminderDialog extends StatelessWidget {
  final List<(ListenReminder, Track)> items;
  final void Function(Track track) onPlay;

  const _ReminderDialog({required this.items, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.backgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
      ),
      title: Text('Ça te dit de réécouter ?', style: AppTheme.headlineMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (reminder, track) in items)
            InkWell(
              onTap: () => onPlay(track),
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingXS),
                child: Row(
                  children: [
                    TrackArtwork(
                      track: track,
                      size: 48,
                      radius: AppTheme.radiusS,
                      placeholderFontSize: 18,
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodyMedium.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${track.artist} · ${reminder.whenLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodySmall
                                .copyWith(color: AppTheme.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_circle_fill_rounded,
                        color: AppTheme.accentPrimary, size: 30),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Plus tard',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
      ],
    );
  }
}
