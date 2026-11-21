import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/lyric_line.dart';
import '../../models/track.dart';
import '../../providers/audio_provider.dart';
import '../../services/audio_handler.dart';
import '../../services/excerpt_service.dart';
import '../../services/lyrics_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_error.dart';
import '../../widgets/app_header.dart';
import 'karaoke_lyrics.dart';
import 'share_card.dart';

/// Partage d'un extrait de 10 s (vidéo MP4 : carte + audio, avec les paroles
/// en karaoké quand elles sont synchronisées).
class ExcerptShareScreen extends ConsumerStatefulWidget {
  final Track track;

  /// Paroles du morceau : le karaoké n'est proposé que si elles sont synchronisées.
  final LyricsResult? lyrics;

  const ExcerptShareScreen({super.key, required this.track, this.lyrics});

  @override
  ConsumerState<ExcerptShareScreen> createState() => _ExcerptShareScreenState();
}

class _ExcerptShareScreenState extends ConsumerState<ExcerptShareScreen> {
  final GlobalKey _cardKey = GlobalKey();

  late final int _totalMs;
  late final int _excerptMs;
  late double _startMs;

  String? _customImagePath;
  bool _sharing = false;
  double _progress = 0;
  bool _karaoke = true;
  final ValueNotifier<int> _karaokeMs = ValueNotifier<int>(0);
  bool _previewing = false;
  Timer? _previewTimer;
  MoodAudioHandler? _handler;

  /// Lignes synchronisées, décalage de l'utilisateur appliqué.
  late final List<LyricLine>? _lines = () {
    final r = widget.lyrics;
    if (r == null || !r.hasSynced) return null;
    return [
      for (final l in r.synced!)
        LyricLine(timestamp: l.timestamp + r.offset, text: l.text),
    ];
  }();

  bool get _useKaraoke => _karaoke && _lines != null;

  int get _maxStartMs => math.max(0, _totalMs - _excerptMs);

  @override
  void initState() {
    super.initState();
    final t = widget.track;
    final isCurrent = ref.read(currentTrackIdProvider) == t.id.toString();
    var total = t.duration ?? 0;
    if (total <= 0 && isCurrent) {
      total = ref.read(durationProvider).valueOrNull?.inMilliseconds ?? 0;
    }
    _totalMs = total;
    // Morceau de moins de 10 s : on prend la durée complète.
    _excerptMs =
        total > 0 ? math.min(ExcerptService.excerptMs, total) : ExcerptService.excerptMs;
    final pos = isCurrent ? ref.read(currentPositionProvider).inMilliseconds : 0;
    _startMs = pos.clamp(0, _maxStartMs).toDouble();
    _karaokeMs.value = _startMs.round();

    unawaited(ref.read(audioHandlerProvider.future).then(
      (h) => _handler = h,
      onError: (_) => null,
    ));
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    if (_previewing) unawaited(_handler?.pause());
    _karaokeMs.dispose();
    super.dispose();
  }

  ImageProvider? _coverProvider() {
    final cover = widget.track.coverUrl;
    if (cover == null || cover.isEmpty) return null;
    if (cover.startsWith('http://') || cover.startsWith('https://')) {
      return NetworkImage(cover);
    }
    return FileImage(File(cover));
  }

  ImageProvider? _customProvider() {
    final p = _customImagePath;
    if (p == null) return null;
    return ResizeImage(FileImage(File(p)), width: 1080);
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        // Évite la compression native (« Permission denied » sur certains
        // appareils), comme dans custom_mood_image_sheet.dart.
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

  Future<void> _stopPreview() async {
    _previewTimer?.cancel();
    if (_previewing) {
      _previewing = false;
      if (mounted) setState(() {});
      await _handler?.pause();
    }
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      await _stopPreview();
      return;
    }
    try {
      final MoodAudioHandler handler =
          await ref.read(audioHandlerProvider.future);
      _handler = handler;
      await handler.seek(Duration(milliseconds: _startMs.round()));
      await handler.play();
      if (!mounted) {
        unawaited(handler.pause());
        return;
      }
      setState(() => _previewing = true);
      _previewTimer?.cancel();
      _previewTimer = Timer(Duration(milliseconds: _excerptMs), () {
        unawaited(handler.pause());
        if (mounted) setState(() => _previewing = false);
      });
    } catch (e) {
      if (mounted) {
        showAppError(context, 'Lecture impossible. ${friendlyError(e)}');
      }
    }
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await _stopPreview();
      if (!mounted) return;
      _progress = 0;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('carte indisponible');

      // S'assure que l'image de fond (surtout http) est bien chargée.
      final bg = _customProvider() ?? _coverProvider();
      if (bg != null) {
        await precacheImage(bg, context, onError: (_, _) {});
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!mounted) return;
      final ctx = await ExcerptService.prepare();
      final paths = <String>[];
      int fps;
      if (_useKaraoke) {
        // Une image par trame : on avance l'horloge du karaoké, on attend que
        // la carte soit repeinte, puis on la capture (540 x 960 px).
        fps = ExcerptService.karaokeFps;
        final frames = (_excerptMs * fps / 1000).round();
        for (var i = 0; i < frames; i++) {
          _karaokeMs.value = _startMs.round() + (i * 1000 / fps).round();
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
          paths.add(await _capture(boundary, ctx, i, 1.5));
          if (mounted) setState(() => _progress = (i + 1) / frames);
        }
        _karaokeMs.value = _startMs.round();
      } else {
        // Image fixe : une seule capture (720 x 1280 px), répétée.
        fps = 2;
        final p = await _capture(boundary, ctx, 0, 2);
        paths.addAll(List<String>.filled((_excerptMs * fps / 1000).ceil(), p));
      }
      if (mounted) setState(() => _progress = 1);

      final path = await ExcerptService.createVideo(
        track: widget.track,
        ctx: ctx,
        imagePaths: paths,
        fps: fps,
        startMs: _startMs.round(),
        durationMs: _excerptMs,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(path, mimeType: 'video/mp4')],
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

  Future<String> _capture(
    RenderRepaintBoundary boundary,
    ({Directory dir, String stamp}) ctx,
    int index,
    double pixelRatio,
  ) async {
    if (kDebugMode && boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // 360 x 640 logiques : 1,5x = 540 x 960, 2x = 720 x 1280 (tailles paires).
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('image vide');
    return ExcerptService.writeFrame(ctx, index, data.buffer.asUint8List());
  }

  static String _fmt(int ms) {
    final s = ms ~/ 1000;
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  @override
  Widget build(BuildContext context) {
    final isCurrent =
        ref.watch(currentTrackIdProvider) == widget.track.id.toString();
    final start = _startMs.round();
    final cardHeight =
        (MediaQuery.sizeOf(context).height * 0.5).clamp(280.0, 520.0);
    final canSlide = _maxStartMs > 0;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              const AppHeader(title: 'Partager un extrait', showBack: true),
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
                              child: _ExcerptCard(
                                track: widget.track,
                                custom: _customProvider(),
                                cover: _coverProvider(),
                                lines: _useKaraoke ? _lines : null,
                                karaokeMs: _karaokeMs,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingL),
                      Text(
                        '${_fmt(start)} → ${_fmt(start + _excerptMs)}',
                        style: AppTheme.titleMedium,
                      ),
                      Slider(
                        value: canSlide ? _startMs.clamp(0, _maxStartMs).toDouble() : 0,
                        min: 0,
                        max: canSlide ? _maxStartMs.toDouble() : 1,
                        activeColor: AppTheme.accentPrimary,
                        onChanged: canSlide
                            ? (v) => setState(() {
                                  _startMs = v;
                                  _karaokeMs.value = v.round();
                                })
                            : null,
                      ),
                      if (_lines != null)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Paroles en karaoké'),
                          value: _karaoke,
                          onChanged: _sharing
                              ? null
                              : (v) => setState(() => _karaoke = v),
                        ),
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
                                  : () => setState(() => _customImagePath = null),
                              child: const Text('Image par défaut'),
                            ),
                          if (isCurrent)
                            OutlinedButton.icon(
                              onPressed: _sharing ? null : _togglePreview,
                              icon: Icon(_previewing
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded),
                              label: Text(_previewing
                                  ? 'Arrêter l\'écoute'
                                  : 'Écouter l\'extrait'),
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
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: _sharing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.share_rounded),
                    label: Text(_sharing
                        ? 'Création de la vidéo… ${(_progress * 100).round()} %'
                        : 'Partager'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte 9:16 (360 x 640) exportée en PNG puis transformée en vidéo.
class _ExcerptCard extends StatelessWidget {
  final Track track;
  final ImageProvider? custom;
  final ImageProvider? cover;
  final List<LyricLine>? lines;
  final ValueListenable<int> karaokeMs;

  const _ExcerptCard({
    required this.track,
    required this.custom,
    required this.cover,
    required this.lines,
    required this.karaokeMs,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 360,
      height: 640,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ShareCardBackground(
              track: track,
              custom: custom,
              cover: cover,
              showCoverInCenter: lines == null,
            ),
            // Dégradé sombre pour la lisibilité du texte.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.35),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                  stops: const [0, 0.3, 0.6, 1],
                ),
              ),
            ),
            Positioned(
              left: 24,
              top: 28,
              child: Row(
                children: [
                  const Icon(Icons.graphic_eq_rounded,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Aura',
                    style: AppTheme.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (lines != null)
              Positioned(
                left: 24,
                right: 24,
                top: 90,
                bottom: 150,
                child: Center(
                  child: ValueListenableBuilder<int>(
                    valueListenable: karaokeMs,
                    builder: (_, ms, _) =>
                        KaraokeLyrics(lines: lines!, timeMs: ms),
                  ),
                ),
              ),
            Positioned(
              left: 28,
              right: 28,
              bottom: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headlineLarge.copyWith(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyLarge.copyWith(
                      color: Colors.white70,
                      fontSize: 18,
                    ),
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
