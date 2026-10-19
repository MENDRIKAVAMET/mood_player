import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/mood_image_choice.dart';
import '../models/track.dart';
import '../providers/mood_image_provider.dart';
import '../theme/app_theme.dart';
import '../theme/mood_colors.dart';
import 'mood_image.dart';

/// Ouvre la feuille qui permet de choisir l'image d'UNE ambiance :
/// photo d'origine (défaut), illustration d'animé, icône seule, ou une
/// image importée par l'utilisateur.
Future<void> showMoodImageSheet(BuildContext context, MoodType mood) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MoodImageSheet(mood: mood),
  );
}

String _styleName(MoodImageSource source) => switch (source) {
      MoodImageSource.original => 'Origine',
      MoodImageSource.anime => 'Anime',
      MoodImageSource.icon => 'Icône',
      MoodImageSource.custom => 'Mon image',
    };

class _MoodImageSheet extends ConsumerWidget {
  final MoodType mood;

  const _MoodImageSheet({required this.mood});

  /// Ouvre le sélecteur de fichiers et importe l'image pour cette ambiance.
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    // Tout ce qui dépend du contexte/ref est récupéré AVANT l'attente du
    // sélecteur de fichiers : la feuille peut être fermée entre-temps.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(moodImageProvider.notifier);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null) return; // Annulé.

      await notifier.importImage(mood, path);
      if (navigator.mounted) navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Image « ${mood.displayName} » mise à jour')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Impossible d\'utiliser cette image')),
      );
    }
  }

  Future<void> _applyToAll(
    BuildContext context,
    WidgetRef ref,
    MoodImageSource source,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(moodImageProvider.notifier);

    await notifier.applyToAll(source);
    if (navigator.mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Style « ${_styleName(source)} » appliqué à toutes les ambiances',
        ),
      ),
    );
  }

  Future<void> _clearImported(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final notifier = ref.read(moodImageProvider.notifier);

    await notifier.clearImported(mood);
    if (navigator.mounted) navigator.pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Image importée supprimée pour « ${mood.displayName} »')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moodColors = MoodColors.forMood(mood);
    final choice = ref.watch(moodImageProvider.select((m) => m[mood]));
    final source = choice?.source ?? MoodImageSource.original;
    final customPath = choice?.customPath;
    final notifier = ref.read(moodImageProvider.notifier);
    final onPrimary =
        ThemeData.estimateBrightnessForColor(moodColors.primary) ==
                Brightness.light
            ? Colors.black87
            : Colors.white;

    Widget iconThumb() => DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [moodColors.primary, moodColors.secondary],
            ),
          ),
          child: Center(child: Icon(mood.iconData, size: 26, color: onPrimary)),
        );

    Widget addThumb() => ColoredBox(
          color: moodColors.cardBg,
          child: Center(
            child: Icon(Icons.add_photo_alternate_rounded,
                size: 26, color: AppTheme.textSecondary),
          ),
        );

    Widget assetThumb(String? asset, {required Widget fallback}) {
      if (asset == null) return fallback;
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        cacheWidth: 200,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    final animeAsset = mood.animeImageAsset;

    return SafeArea(
      child: SingleChildScrollView(
        child: Container(
          margin: const EdgeInsets.all(AppTheme.spacingM),
          padding: const EdgeInsets.all(AppTheme.spacingL),
          decoration: BoxDecoration(
            color: AppTheme.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Image de l\'ambiance ${mood.displayName}',
                style: AppTheme.headlineMedium,
              ),
              const SizedBox(height: AppTheme.spacingM),

              // Aperçu du choix actuel, avec le même voile que la carte.
              ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusL),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: moodColors.cardBg),
                      MoodImage(
                        mood: mood,
                        fallback: (_) => Center(
                          child: Icon(
                            mood.iconData,
                            size: 40,
                            color: moodColors.primary,
                          ),
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              moodColors.primary.withValues(alpha: 0.18),
                              Colors.black.withValues(alpha: 0.25),
                              Colors.black.withValues(alpha: 0.78),
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        left: AppTheme.spacingM,
                        bottom: AppTheme.spacingM,
                        child: Text(
                          mood.displayName,
                          style: AppTheme.titleLarge
                              .copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingL),

              // Les choix : origine (défaut), animé, icône, image importée.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SourceTile(
                      label: 'Origine',
                      selected: source == MoodImageSource.original,
                      onTap: () =>
                          notifier.setSource(mood, MoodImageSource.original),
                      child: assetThumb(mood.imageAsset, fallback: iconThumb()),
                    ),
                  ),
                  if (animeAsset != null) ...[
                    const SizedBox(width: AppTheme.spacingS),
                    Expanded(
                      child: _SourceTile(
                        label: 'Anime',
                        selected: source == MoodImageSource.anime,
                        onTap: () =>
                            notifier.setSource(mood, MoodImageSource.anime),
                        child: assetThumb(animeAsset, fallback: iconThumb()),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppTheme.spacingS),
                  Expanded(
                    child: _SourceTile(
                      label: 'Icône',
                      selected: source == MoodImageSource.icon,
                      onTap: () =>
                          notifier.setSource(mood, MoodImageSource.icon),
                      child: iconThumb(),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  Expanded(
                    child: _SourceTile(
                      label: 'Mon image',
                      selected: source == MoodImageSource.custom,
                      // Pas encore d'image importée : le choix ouvre
                      // directement le sélecteur de fichiers.
                      onTap: () => customPath != null
                          ? notifier.setSource(mood, MoodImageSource.custom)
                          : _import(context, ref),
                      child: customPath != null
                          ? Image.file(
                              File(customPath),
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                              errorBuilder: (_, _, _) => addThumb(),
                            )
                          : addThumb(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingM),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.photo_library_rounded,
                    color: AppTheme.accentPrimary),
                title: Text(
                  customPath == null ? 'Importer une image' : 'Changer mon image',
                  style: AppTheme.bodyLarge,
                ),
                subtitle: Text(
                  'Depuis ta galerie ou tes fichiers',
                  style: AppTheme.bodySmall,
                ),
                onTap: () => _import(context, ref),
              ),
              if (customPath != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded,
                      color: AppTheme.textSecondary),
                  title: Text('Supprimer mon image importée',
                      style: AppTheme.bodyLarge),
                  onTap: () => _clearImported(context, ref),
                ),
              if (source != MoodImageSource.custom)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_awesome_motion_rounded,
                      color: AppTheme.textSecondary),
                  title: Text(
                    'Appliquer « ${_styleName(source)} » à toutes les ambiances',
                    style: AppTheme.bodyLarge,
                  ),
                  onTap: () => _applyToAll(context, ref, source),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Une vignette de choix (miniature + libellé), encadrée quand elle est
/// sélectionnée.
class _SourceTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _SourceTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accentPrimary : AppTheme.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected ? AppTheme.accentPrimary : AppTheme.border,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: child,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.labelSmall.copyWith(
              color: color,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
