import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_mood_card.dart';
import '../../widgets/mood_card.dart';
import '../../widgets/mood_editor_dialog.dart';
import 'custom_mood_detail_screen.dart';
import 'mood_detail_screen.dart';

/// Onglet dédié aux ambiances : les moods créés par l'utilisateur et les
/// ambiances détectées automatiquement.
///
/// Ces deux carrousels vivaient auparavant en haut de l'accueil, où ils
/// mangeaient environ 400 px de hauteur avant même que la liste des
/// morceaux ne commence. Ici, ils ont toute la place — et la
/// bibliothèque respire.
class MoodsScreen extends ConsumerWidget {
  const MoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customMoods = ref.watch(customMoodProvider).moods;
    final trackCountByMood = ref.watch(trackCountByMoodProvider);
    final moodsWithTracks = trackCountByMood.entries
        .where((entry) => entry.value > 0)
        .map((entry) => entry.key)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), AppTheme.backgroundPrimary],
            stops: [0.0, 0.3],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingXL,
                  AppTheme.spacingL,
                  AppTheme.spacingXL,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ambiances', style: AppTheme.displayLarge),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(
                      'Tes moods et ceux détectés automatiquement',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              _sectionHeader('Mes moods', customMoods.isEmpty ? null : customMoods.length),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                  itemCount: customMoods.length + 1,
                  itemBuilder: (context, index) {
                    if (index == customMoods.length) {
                      return CreateMoodCard(
                        onTap: () => _createCustomMood(context, ref),
                      );
                    }
                    final mood = customMoods[index];
                    return CustomMoodCard(
                      mood: mood,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomMoodDetailScreen(mood: mood),
                        ),
                      ),
                    );
                  },
                ),
              ),

              _sectionHeader('Par ambiance', null),
              if (moodsWithTracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingXL),
                  child: Text(
                    'Aucune ambiance détectée pour l\'instant. Lance « Classifier » '
                    'depuis la bibliothèque pour analyser tes morceaux.',
                    style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                  ),
                )
              else
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
                    itemCount: moodsWithTracks.length,
                    itemBuilder: (context, index) {
                      final mood = moodsWithTracks[index];
                      return MoodCard(
                        mood: mood,
                        trackCount: trackCountByMood[mood] ?? 0,
                        onTap: () => _openMoodDetail(context, ref, mood),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, int? count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingS,
      ),
      child: Row(
        children: [
          Text(title, style: AppTheme.headlineMedium),
          if (count != null) ...[
            const SizedBox(width: AppTheme.spacingS),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingS,
                vertical: AppTheme.spacingXXS,
              ),
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusS),
              ),
              child: Text(
                '$count',
                style: AppTheme.labelSmall.copyWith(color: AppTheme.accentPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createCustomMood(BuildContext context, WidgetRef ref) async {
    final result = await showMoodEditorDialog(context);
    if (result == null) return;
    await ref.read(customMoodProvider.notifier).createMood(
          name: result.$1,
          icon: result.$2,
          colorValue: result.$3,
        );
  }

  void _openMoodDetail(BuildContext context, WidgetRef ref, MoodType mood) {
    final tracks = ref.read(tracksByMoodProvider(mood));
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MoodDetailScreen(mood: mood, tracks: tracks),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: AppTheme.animPageTransition,
      ),
    );
  }
}
