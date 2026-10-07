import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/custom_mood.dart';
import '../models/track.dart';
import '../providers/custom_mood_provider.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import '../theme/mood_icons.dart';

/// Opens the bottom sheet letting the user manually set [track]'s mood
/// and confidence, overriding the automatic Groq classification. Shown
/// when the mood card on the player screen is tapped.
void showMoodEditSheet(BuildContext context, WidgetRef ref, Track track) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _MoodEditSheet(track: track),
  );
}

class _MoodEditSheet extends ConsumerStatefulWidget {
  final Track track;

  const _MoodEditSheet({required this.track});

  @override
  ConsumerState<_MoodEditSheet> createState() => _MoodEditSheetState();
}

class _MoodEditSheetState extends ConsumerState<_MoodEditSheet> {
  late MoodType _selectedMood =
      widget.track.mood ?? MoodType.unknown;
  late double _confidence = widget.track.moodConfidence ?? 1.0;
  bool _saving = false;

  /// Toutes les ambiances intégrées sauf [MoodType.unknown], qui est l'état
  /// « pas encore classé » et non un choix volontaire. Calculé depuis l'enum
  /// pour qu'une ambiance ajoutée plus tard apparaisse sans autre changement.
  static final List<MoodType> _selectableMoods =
      MoodType.values.where((m) => m != MoodType.unknown).toList();

  /// Ambiances personnalisées auxquelles le morceau appartient (ids), et
  /// état initial pour ne modifier que ce qui a changé à l'enregistrement.
  late final Set<int> _initialCustom = {
    for (final m in ref.read(customMoodProvider).moods)
      if (m.trackIds.contains(widget.track.id)) m.id,
  };
  late final Set<int> _selectedCustom = {..._initialCustom};

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(trackProvider.notifier).setTrackMood(
          widget.track,
          mood: _selectedMood,
          confidence: _confidence,
        );
    final customNotifier = ref.read(customMoodProvider.notifier);
    for (final id in _selectedCustom.difference(_initialCustom)) {
      await customNotifier.addTrack(id, widget.track,
          percentage: (_confidence * 100).roundToDouble());
    }
    for (final id in _initialCustom.difference(_selectedCustom)) {
      await customNotifier.removeTrack(id, widget.track.id);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(_selectedMood);
    final customMoods = ref.watch(customMoodProvider).moods;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppTheme.spacingL,
            right: AppTheme.spacingL,
            bottom: AppTheme.spacingL,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
                  decoration: BoxDecoration(
                    color: AppTheme.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Modifier l\'ambiance', style: AppTheme.titleMedium),
              const SizedBox(height: AppTheme.spacingXXS),
              Text(
                widget.track.title,
                style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppTheme.spacingL),
              Wrap(
                spacing: AppTheme.spacingS,
                runSpacing: AppTheme.spacingS,
                children: [
                  for (final mood in _selectableMoods)
                    _MoodChip(
                      mood: mood,
                      selected: mood == _selectedMood,
                      onTap: () => setState(() => _selectedMood = mood),
                    ),
                ],
              ),
              if (customMoods.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacingL),
                Text('Mes ambiances', style: AppTheme.labelLarge),
                const SizedBox(height: AppTheme.spacingS),
                Wrap(
                  spacing: AppTheme.spacingS,
                  runSpacing: AppTheme.spacingS,
                  children: [
                    for (final m in customMoods)
                      _CustomMoodChip(
                        mood: m,
                        selected: _selectedCustom.contains(m.id),
                        onTap: () => setState(() {
                          if (!_selectedCustom.remove(m.id)) {
                            _selectedCustom.add(m.id);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppTheme.spacingL),
              Row(
                children: [
                  Text('Degré de confiance', style: AppTheme.bodyMedium),
                  const Spacer(),
                  Text(
                    '${(_confidence * 100).toStringAsFixed(0)}%',
                    style: AppTheme.bodyMedium.copyWith(
                      color: moodColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: moodColors.primary,
                  thumbColor: moodColors.primary,
                  inactiveTrackColor: moodColors.primary.withValues(alpha: 0.2),
                  overlayColor: moodColors.primary.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: _confidence,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  onChanged: (value) => setState(() => _confidence = value),
                ),
              ),
              const SizedBox(height: AppTheme.spacingM),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: moodColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusM),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Enregistrer'),
                ),
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomMoodChip extends StatelessWidget {
  final CustomMood mood;
  final bool selected;
  final VoidCallback onTap;

  const _CustomMoodChip({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(mood.colorValue);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingS,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              MoodIcons.iconDataForKey(mood.icon),
              size: 16,
              color: selected ? color : AppTheme.textSecondary,
            ),
            const SizedBox(width: AppTheme.spacingXXS),
            Text(
              mood.name,
              style: AppTheme.bodySmall.copyWith(
                color: selected ? color : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodChip extends StatelessWidget {
  final MoodType mood;
  final bool selected;
  final VoidCallback onTap;

  const _MoodChip({
    required this.mood,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = MoodColors.forMood(mood);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.animFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingS,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: selected ? colors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mood.iconData,
              size: 16,
              color: selected ? colors.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: AppTheme.spacingXXS),
            Text(
              mood.displayName,
              style: AppTheme.bodySmall.copyWith(
                color: selected ? colors.primary : AppTheme.textSecondary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
