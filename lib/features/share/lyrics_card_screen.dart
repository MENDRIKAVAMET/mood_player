import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/track.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_error.dart';
import '../../widgets/app_header.dart';
import 'share_card.dart';

/// Aperçu et partage en IMAGE des paroles choisies (carte 9:16 en PNG).
class LyricsCardScreen extends StatefulWidget {
  final Track track;

  /// Lignes choisies ; une chaîne vide marque un saut de strophe.
  final List<String> lines;

  /// Même sélection en texte brut, pour l'option « Partager en texte ».
  final String text;

  const LyricsCardScreen({
    super.key,
    required this.track,
    required this.lines,
    required this.text,
  });

  @override
  State<LyricsCardScreen> createState() => _LyricsCardScreenState();
}

class _LyricsCardScreenState extends State<LyricsCardScreen> {
  final GlobalKey _cardKey = GlobalKey();
  String? _customImagePath;
  bool _sharing = false;

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        // Évite la compression native (« Permission denied » sur certains
        // appareils), comme dans l'écran d'extrait.
        compressionQuality: 0,
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null || !mounted) return;
      setState(() => _customImagePath = path);
    } catch (e) {
      if (mounted) {
        showAppError(context, 'Image impossible. ${friendlyError(e)}');
      }
    }
  }

  /// Supprime les anciennes cartes laissées dans le cache.
  Future<void> _cleanOld(Directory dir) async {
    try {
      await for (final e in dir.list()) {
        if (e is File && e.uri.pathSegments.last.startsWith('aura_paroles_')) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _shareImage() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('carte indisponible');

      // S'assure que l'image de fond (surtout http) est bien chargée.
      final bg = shareCustomProvider(_customImagePath) ??
          shareCoverProvider(widget.track);
      if (bg != null) {
        await precacheImage(bg, context, onError: (_, _) {});
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted) return;

      // 360 x 640 à 3x = 1080 x 1920 px.
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('image vide');

      final dir = await getTemporaryDirectory();
      await _cleanOld(dir);
      final file = File(
        '${dir.path}/aura_paroles_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!mounted) return;

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: '${widget.track.title} - ${widget.track.artist}',
      );
    } catch (e) {
      if (mounted) {
        showAppError(context, 'Partage impossible. ${friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareText() async {
    if (_sharing) return;
    try {
      await Share.share(widget.text);
    } catch (e) {
      if (mounted) {
        showAppError(context, 'Partage impossible. ${friendlyError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardHeight =
        (MediaQuery.sizeOf(context).height * 0.55).clamp(280.0, 560.0);
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(title: 'Partager en image', showBack: true),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  child: Column(
                    children: [
                      SizedBox(
                        height: cardHeight,
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: RepaintBoundary(
                              key: _cardKey,
                              child: LyricsImageCard(
                                track: widget.track,
                                lines: widget.lines,
                                custom: shareCustomProvider(_customImagePath),
                                cover: shareCoverProvider(widget.track),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingL),
                      Wrap(
                        spacing: AppTheme.spacingS,
                        runSpacing: AppTheme.spacingS,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _sharing ? null : _pickImage,
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Changer l\'image'),
                          ),
                          if (_customImagePath != null)
                            TextButton(
                              onPressed: _sharing
                                  ? null
                                  : () =>
                                      setState(() => _customImagePath = null),
                              child: const Text('Image par défaut'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacingL,
                  0,
                  AppTheme.spacingL,
                  AppTheme.spacingL,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _sharing ? null : _shareImage,
                        icon: _sharing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.share_rounded),
                        label: Text(
                            _sharing ? 'Création de l\'image…' : 'Partager l\'image'),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingS),
                    TextButton(
                      onPressed: _sharing ? null : _shareText,
                      child: const Text('Partager en texte à la place'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
