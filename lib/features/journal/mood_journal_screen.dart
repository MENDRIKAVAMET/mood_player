import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mood_journal_entry.dart';
import '../../providers/mood_journal_provider.dart';
import '../../services/mood_journal_service.dart';
import '../../models/track.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/feeling_widgets.dart';
import '../../widgets/mood_check_in_card.dart';

/// Journal d'humeur : noter son humeur (avec une note facultative), voir ce
/// qu'on écoute selon son état, et relire l'historique. Tout reste sur le
/// téléphone.
class MoodJournalScreen extends ConsumerWidget {
  const MoodJournalScreen({super.key});

  static const _days = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];
  static const _months = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
    'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  static String _dayLabel(DateTime d) =>
      '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  static String _time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  Future<void> _addWithNote(
    BuildContext context,
    WidgetRef ref,
    Feeling feeling,
  ) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: Row(
          children: [
            FeelingIcon(feeling: feeling, size: 24),
            const SizedBox(width: AppTheme.spacingS),
            Text(feeling.label, style: AppTheme.titleMedium),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 140,
          maxLines: 3,
          minLines: 1,
          style: AppTheme.bodyLarge,
          decoration: const InputDecoration(
            hintText: 'Une note ? (facultatif)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await ref
        .read(moodJournalProvider.notifier)
        .add(feeling, note: controller.text);
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(
          top: AppTheme.spacingXL,
          bottom: AppTheme.spacingM,
        ),
        child: Text(text, style: AppTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal = ref.watch(moodJournalProvider);
    final insights = ref.watch(feelingInsightsProvider);

    FeelingInsight? headline;
    for (final i in insights) {
      if (i.reliable) {
        headline = i;
        break;
      }
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(title: 'Journal d\'humeur', showBack: true),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  children: [
                    Text('Comment tu te sens ?', style: AppTheme.titleMedium),
                    const SizedBox(height: AppTheme.spacingM),
                    FeelingChipWrap(
                      onSelected: (f) => _addWithNote(context, ref, f),
                    ),
                    if (headline != null) ...[
                      const SizedBox(height: AppTheme.spacingL),
                      _buildHeadline(headline),
                    ],
                    _sectionTitle('Ce que tu écoutes selon ton humeur'),
                    if (insights.isEmpty)
                      Text(
                        'Note ton humeur quelques fois et écoute de la '
                        'musique : ici apparaîtront les ambiances que tu '
                        'écoutes selon ton état.',
                        style: AppTheme.bodyMedium
                            .copyWith(color: AppTheme.textSecondary),
                      )
                    else
                      for (final i in insights) _buildInsight(context, ref, i),
                    _sectionTitle('Historique'),
                    if (journal.isEmpty)
                      Text(
                        'Aucune humeur notée pour le moment.',
                        style: AppTheme.bodyMedium
                            .copyWith(color: AppTheme.textSecondary),
                      )
                    else
                      ..._buildHistory(context, ref, journal),
                    const SizedBox(height: AppTheme.spacingXL),
                    Text(
                      'Ton journal reste sur ton téléphone. Les constats '
                      'montrent ce que tu écoutes dans les 3 heures qui '
                      'suivent une note : ils ne prouvent pas que cette '
                      'musique te fait du bien.',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textTertiary),
                    ),
                    const SizedBox(height: AppTheme.spacingXL),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeadline(FeelingInsight i) {
    final top = i.topMoods.first;
    final percent = (top.value * 100).round();
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: AppTheme.glassDecoration,
      child: Row(
        children: [
          FeelingIcon(feeling: i.feeling, size: 30),
          const SizedBox(width: AppTheme.spacingM),
          Expanded(
            child: Text(
              'Quand tu es ${i.feeling.adjective}, tu écoutes surtout '
              '${top.key.displayName} ($percent %).',
              style: AppTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsight(BuildContext context, WidgetRef ref, FeelingInsight i) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingM),
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: AppTheme.glassDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FeelingIcon(feeling: i.feeling, size: 24),
              const SizedBox(width: AppTheme.spacingS),
              Expanded(
                child: Text(
                  '${i.feeling.label} · noté ${i.entries} fois',
                  style: AppTheme.bodyLarge,
                ),
              ),
              TextButton(
                onPressed: () => playFeelingMix(context, ref, i.feeling),
                child: const Text('Écouter'),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingS),
          if (i.topMoods.isEmpty)
            Text(
              'Pas encore d\'écoute après cette humeur.',
              style: AppTheme.bodySmall
                  .copyWith(color: AppTheme.textTertiary),
            )
          else ...[
            for (final e in i.topMoods)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(e.key.displayName,
                          style: AppTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(
                      child: FeelingBar(value: e.value),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${(e.value * 100).round()} %',
                        textAlign: TextAlign.right,
                        style: AppTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            if (!i.reliable)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.spacingXS),
                child: Text(
                  'Pas encore assez d\'écoutes pour conclure '
                  '(${i.listens}/${MoodJournalInsights.minListens}).',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textTertiary),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildHistory(
    BuildContext context,
    WidgetRef ref,
    List<MoodJournalEntry> journal,
  ) {
    final recent = journal.reversed.take(60).toList();
    final widgets = <Widget>[];
    String? lastDay;
    for (final e in recent) {
      final day = _dayLabel(e.at);
      if (day != lastDay) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(
            top: AppTheme.spacingM,
            bottom: AppTheme.spacingXS,
          ),
          child: Text(
            day,
            style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary),
          ),
        ));
        lastDay = day;
      }
      widgets.add(
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: FeelingIcon(feeling: e.feeling, size: 26),
          title: Text('${e.feeling.label} · ${_time(e.at)}',
              style: AppTheme.bodyLarge),
          subtitle: e.note == null
              ? null
              : Text(e.note!,
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textSecondary)),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.textTertiary),
            tooltip: 'Supprimer',
            onPressed: () =>
                ref.read(moodJournalProvider.notifier).remove(e),
          ),
        ),
      );
    }
    return widgets;
  }
}
