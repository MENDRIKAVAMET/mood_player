import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_mood.dart';
import '../models/custom_mood_image.dart';
import '../models/mood_image_catalog.dart';
import '../providers/custom_mood_image_provider.dart';
import '../theme/app_theme.dart';
import '../theme/mood_icons.dart';
import 'custom_mood_image_view.dart';

/// Ouvre la feuille qui permet de choisir l'image d'un mood créé par
/// l'utilisateur : n'importe quelle image de l'app (photos d'ambiance ou
/// animé) ou une image importée depuis l'appareil.
Future<void> showCustomMoodImageSheet(BuildContext context, CustomMood mood) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _CustomMoodImageSheet(mood: mood),
  );
}

class _CustomMoodImageSheet extends ConsumerStatefulWidget {
  final CustomMood mood;

  const _CustomMoodImageSheet({required this.mood});

  @override
  ConsumerState<_CustomMoodImageSheet> createState() =>
      _CustomMoodImageSheetState();
}

class _CustomMoodImageSheetState extends ConsumerState<_CustomMoodImageSheet> {
  /// Message d'erreur affiché dans la feuille (un SnackBar serait caché
  /// derrière elle).
  String? _error;

  Future<void> _import() async {
    final notifier = ref.read(customMoodImageProvider.notifier);
    final moodId = widget.mood.id;
    setState(() => _error = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null) return; // Annulé.
      await notifier.importImage(moodId, path);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Impossible d\'utiliser cette image');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    final color = Color(mood.colorValue);
    final notifier = ref.read(customMoodImageProvider.notifier);
    final image = ref.watch(customMoodImageProvider.select((m) => m[mood.id])) ??
        CustomMoodImage.none;
    final hasImage = CustomMoodImageView.hasImage(ref, mood.id);
    final importedPath = image.customPath;

    List<Widget> section(String title, List<MoodImageOption> options) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                top: AppTheme.spacingL,
                bottom: AppTheme.spacingS,
              ),
              child: Text(title, style: AppTheme.titleLarge),
            ),
          ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.1,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final option = options[i];
                return _ImageTile(
                  label: option.label,
                  selected: image.kind == CustomMoodImageKind.asset &&
                      image.assetPath == option.asset,
                  onTap: () => notifier.setAsset(mood.id, option.asset),
                  child: Image.asset(
                    option.asset,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black26),
                  ),
                );
              },
              childCount: options.length,
            ),
          ),
        ];

    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * 0.88,
        margin: const EdgeInsets.all(AppTheme.spacingM),
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingL,
          AppTheme.spacingL,
          AppTheme.spacingL,
          0,
        ),
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary,
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
          border: Border.all(color: AppTheme.border, width: 1),
        ),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Image de « ${mood.name} »',
                    style: AppTheme.headlineMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppTheme.spacingM),

                  // Aperçu, comme la carte du mood.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusL),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  color.withValues(alpha: 0.55),
                                  color.withValues(alpha: 0.2),
                                  AppTheme.backgroundCard,
                                ],
                              ),
                            ),
                          ),
                          CustomMoodImageView(moodId: mood.id),
                          if (hasImage)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    color.withValues(alpha: 0.18),
                                    Colors.black.withValues(alpha: 0.25),
                                    Colors.black.withValues(alpha: 0.78),
                                  ],
                                  stops: const [0.0, 0.45, 1.0],
                                ),
                              ),
                            )
                          else
                            Center(
                              child: Icon(
                                MoodIcons.iconDataForKey(mood.icon),
                                size: 40,
                                color: color,
                              ),
                            ),
                          Positioned(
                            left: AppTheme.spacingM,
                            right: AppTheme.spacingM,
                            bottom: AppTheme.spacingM,
                            child: Text(
                              mood.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.titleLarge
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingM),

                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.photo_library_rounded,
                          label: 'Depuis l\'appareil',
                          highlighted: true,
                          onTap: _import,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingS),
                      Expanded(
                        child: _ActionButton(
                          icon: Icons.hide_image_outlined,
                          label: 'Aucune image',
                          enabled: image.kind != CustomMoodImageKind.none,
                          onTap: () => notifier.setNone(mood.id),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppTheme.spacingS),
                      child: Text(
                        _error!,
                        style: AppTheme.bodySmall.copyWith(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),

            // L'image importée, pour pouvoir y revenir après avoir essayé
            // une image de l'app.
            if (importedPath != null) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: AppTheme.spacingL,
                    bottom: AppTheme.spacingS,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Mon image', style: AppTheme.titleLarge),
                      ),
                      TextButton(
                        onPressed: () => notifier.clearImported(mood.id),
                        child: Text(
                          'Supprimer',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.1,
                ),
                delegate: SliverChildListDelegate([
                  _ImageTile(
                    label: 'Importée',
                    selected: image.kind == CustomMoodImageKind.custom,
                    onTap: () => notifier.useImported(mood.id),
                    child: Image.file(
                      File(importedPath),
                      fit: BoxFit.cover,
                      cacheWidth: 300,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Colors.black26),
                    ),
                  ),
                ]),
              ),
            ],

            ...section('Photos', MoodImageCatalog.photos),
            ...section('Anime', MoodImageCatalog.anime),
            const SliverToBoxAdapter(child: SizedBox(height: AppTheme.spacingXL)),
          ],
        ),
      ),
    );
  }
}

/// Une image de la grille, encadrée et marquée d'une coche quand elle est
/// sélectionnée.
class _ImageTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  const _ImageTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                    stops: const [0.55, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 6,
                right: 6,
                bottom: 4,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppTheme.accentPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? AppTheme.textTertiary
        : highlighted
            ? AppTheme.accentPrimary
            : AppTheme.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(
            color: highlighted && enabled ? AppTheme.accentPrimary : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.labelMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
