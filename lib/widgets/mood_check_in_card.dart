import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/chat/library_chat_screen.dart';
import '../features/journal/mood_journal_screen.dart';
import '../models/mood_journal_entry.dart';
import '../providers/mood_journal_provider.dart';
import '../providers/track_provider.dart';
import '../services/mood_journal_service.dart';
import '../theme/app_theme.dart';
import '../utils/playback_navigation.dart';

/// Lance un mix de 20 morceaux pour [feeling] : les ambiances que
/// l'utilisateur écoute d'habitude dans cet état si l'app a assez de recul,
/// sinon celles proposées par défaut.
void playFeelingMix(BuildContext context, WidgetRef ref, Feeling feeling) {
  final moods = MoodJournalInsights.moodsFor(
    feeling,
    ref.read(feelingInsightsProvider),
  );
  final mix = MoodJournalInsights.mixFor(
    ref.read(trackProvider).tracks,
    moods,
  );
  if (mix.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Aucun morceau classé pour cette humeur. Lance d\'abord la '
          'classification.',
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.backgroundCardElevated,
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  playAll(context, mix);
}

/// Carte « Comment tu te sens ? » de l'écran Découvertes : une ligne
/// d'emojis pour noter son humeur en un geste, puis un mix adapté.
class MoodCheckInCard extends ConsumerStatefulWidget {
  const MoodCheckInCard({super.key});

  @override
  ConsumerState<MoodCheckInCard> createState() => _MoodCheckInCardState();
}

class _MoodCheckInCardState extends ConsumerState<MoodCheckInCard> {
  bool _changing = false;

  Future<void> _pick(Feeling feeling) async {
    await ref.read(moodJournalProvider.notifier).add(feeling);
    if (mounted) setState(() => _changing = false);
  }

  @override
  Widget build(BuildContext context) {
    final journal = ref.watch(moodJournalProvider);
    final insights = ref.watch(feelingInsightsProvider);
    final latest = journal.isEmpty ? null : journal.last;
    final active = !_changing &&
        latest != null &&
        DateTime.now().difference(latest.at) <
            MoodJournalInsights.listenWindow;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingL,
        AppTheme.spacingL,
        0,
      ),
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: AppTheme.glassDecoration,
      child: active
          ? _buildActive(latest, insights)
          : _buildPrompt(),
    );
  }

  Widget _buildPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comment tu te sens ?', style: AppTheme.titleMedium),
        const SizedBox(height: AppTheme.spacingXS),
        Text(
          'Note ton humeur : l\'app apprend ce que tu écoutes selon ton état.',
          style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingM),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in Feeling.values)
                _FeelingButton(feeling: f, onTap: () => _pick(f)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActive(MoodJournalEntry latest, List<FeelingInsight> insights) {
    final feeling = latest.feeling;
    final insight = MoodJournalInsights.insightFor(feeling, insights);
    final moods = MoodJournalInsights.moodsFor(feeling, insights);
    final names = moods.map((m) => m.displayName).join(' + ');
    final habit = insight != null && insight.reliable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(feeling.emoji, style: const TextStyle(fontSize: 34)),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tu te sens ${feeling.adjective}',
                      style: AppTheme.titleMedium),
                  Text(
                    habit
                        ? 'D\'habitude, tu écoutes surtout $names.'
                        : 'Un mix $names pour ça.',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _changing = true),
              child: const Text('Changer'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingM),
        Row(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
              ),
              onPressed: () => playFeelingMix(context, ref, feeling),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Écouter un mix'),
            ),
            const SizedBox(width: AppTheme.spacingS),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MoodJournalScreen()),
              ),
              child: const Text('Journal'),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeelingButton extends StatelessWidget {
  final Feeling feeling;
  final VoidCallback onTap;

  const _FeelingButton({required this.feeling, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(feeling.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(height: 2),
              Text(
                feeling.label,
                style: AppTheme.labelSmall
                    .copyWith(color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Deux raccourcis sous la carte d'humeur : le chat et le journal.
class DiscoverShortcuts extends StatelessWidget {
  const DiscoverShortcuts({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingL,
        AppTheme.spacingM,
        AppTheme.spacingL,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: _ShortcutTile(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Discuter',
              subtitle: 'Parle à ta bibliothèque',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LibraryChatScreen()),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: _ShortcutTile(
              icon: Icons.mood_rounded,
              title: 'Journal',
              subtitle: 'Humeur et musique',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MoodJournalScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingM),
        decoration: AppTheme.glassDecoration,
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accentPrimary),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    subtitle,
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textTertiary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
