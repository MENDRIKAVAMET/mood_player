import 'package:flutter/material.dart';
import '../models/custom_mood.dart';
import '../theme/app_theme.dart';

const List<String> kMoodIconChoices = [
  '🎵', '🔥', '💤', '😢', '🎉', '💖', '🧠', '💪',
  '🌙', '⚡', '🎧', '🌸', '☀️', '🌧️', '🚗', '📚',
];

const List<int> kMoodColorChoices = [
  0xFF1DB954, // green
  0xFFE91E63, // pink
  0xFF9C27B0, // purple
  0xFF3F51B5, // indigo
  0xFF2196F3, // blue
  0xFF00BCD4, // cyan
  0xFFFF9800, // orange
  0xFFFF5722, // deep orange
  0xFFFFC107, // amber
  0xFF795548, // brown
];

/// Shows a dialog to create a new custom mood, or edit an existing one if
/// [existing] is provided. Returns the chosen (name, icon, colorValue), or
/// null if cancelled - the caller decides what to do with it.
Future<(String name, String icon, int colorValue)?> showMoodEditorDialog(
  BuildContext context, {
  CustomMood? existing,
}) {
  final controller = TextEditingController(text: existing?.name ?? '');
  String selectedIcon = existing?.icon ?? kMoodIconChoices.first;
  int selectedColor = existing?.colorValue ?? kMoodColorChoices.first;

  return showDialog<(String, String, int)>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppTheme.backgroundSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusL),
            ),
            title: Text(
              existing != null ? 'Modifier le mood' : 'Créer un mood',
              style: AppTheme.headlineMedium,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    style: AppTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Nom du mood (ex: Road trip, Focus...)',
                      hintStyle: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
                      filled: true,
                      fillColor: AppTheme.backgroundCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusM),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text('Icône', style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(height: AppTheme.spacingS),
                  Wrap(
                    spacing: AppTheme.spacingS,
                    runSpacing: AppTheme.spacingS,
                    children: [
                      for (final icon in kMoodIconChoices)
                        GestureDetector(
                          onTap: () => setState(() => selectedIcon = icon),
                          child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: icon == selectedIcon
                                  ? Color(selectedColor).withValues(alpha: 0.25)
                                  : AppTheme.backgroundCard,
                              borderRadius: BorderRadius.circular(AppTheme.radiusM),
                              border: icon == selectedIcon
                                  ? Border.all(color: Color(selectedColor), width: 1.5)
                                  : null,
                            ),
                            child: Text(icon, style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingL),
                  Text('Couleur', style: AppTheme.labelSmall.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(height: AppTheme.spacingS),
                  Wrap(
                    spacing: AppTheme.spacingS,
                    runSpacing: AppTheme.spacingS,
                    children: [
                      for (final color in kMoodColorChoices)
                        GestureDetector(
                          onTap: () => setState(() => selectedColor = color),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: color == selectedColor
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Annuler', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, (name, selectedIcon, selectedColor));
                },
                child: Text(
                  existing != null ? 'Enregistrer' : 'Créer',
                  style: TextStyle(color: AppTheme.accentPrimary),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
