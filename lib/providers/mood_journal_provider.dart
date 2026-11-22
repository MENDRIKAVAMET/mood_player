import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mood_journal_entry.dart';
import '../services/mood_journal_service.dart';
import 'play_log_provider.dart';

/// Journal d'humeur, du plus ancien au plus récent.
class MoodJournalNotifier extends StateNotifier<List<MoodJournalEntry>> {
  final MoodJournalService _service;
  late final Future<void> _ready;

  /// Au-delà, les notes les plus anciennes sont jetées.
  static const Duration retention = Duration(days: 730);
  static const int maxEntries = 3000;

  MoodJournalNotifier(this._service) : super(const []) {
    _ready = _load();
  }

  Future<void> _load() async {
    final loaded = await _service.load();
    if (!mounted) return;
    final merged = [...loaded, ...state]
      ..sort((a, b) => a.at.compareTo(b.at));
    state = _prune(merged, DateTime.now());
  }

  Future<MoodJournalEntry> add(
    Feeling feeling, {
    String? note,
    DateTime? at,
  }) async {
    await _ready;
    final now = at ?? DateTime.now();
    final trimmed = note?.trim();
    final entry = MoodJournalEntry(
      at: now,
      feeling: feeling,
      note: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
    if (mounted) {
      state = _prune([...state, entry], now);
      await _service.save(state);
    }
    return entry;
  }

  Future<void> remove(MoodJournalEntry entry) async {
    await _ready;
    if (!mounted) return;
    state = [
      for (final e in state)
        if (e != entry) e,
    ];
    await _service.save(state);
  }

  static List<MoodJournalEntry> _prune(
    List<MoodJournalEntry> entries,
    DateTime now,
  ) {
    final cutoff = now.subtract(retention);
    final kept = [
      for (final e in entries)
        if (!e.at.isBefore(cutoff)) e,
    ];
    return kept.length <= maxEntries
        ? kept
        : kept.sublist(kept.length - maxEntries);
  }
}

final moodJournalProvider =
    StateNotifierProvider<MoodJournalNotifier, List<MoodJournalEntry>>((ref) {
  return MoodJournalNotifier(MoodJournalService());
});

/// Ce que l'utilisateur écoute selon son humeur, recalculé quand le journal
/// d'humeur ou le journal d'écoute change.
final feelingInsightsProvider = Provider<List<FeelingInsight>>((ref) {
  final journal = ref.watch(moodJournalProvider);
  final log = ref.watch(playLogProvider);
  return MoodJournalInsights.compute(journal, log);
});
