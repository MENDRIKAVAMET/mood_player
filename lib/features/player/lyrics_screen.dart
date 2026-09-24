import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/lyric_line.dart';
import '../../providers/audio_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/lyrics_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';
import 'lyrics_search_screen.dart';

/// How much one tap of the sync buttons shifts the lyrics. 300ms is small
/// enough to fine-tune without overshooting, big enough to feel like it
/// did something.
const _kOffsetStep = Duration(milliseconds: 300);

/// Karaoke-style synced lyrics: fetches LRC lyrics for the given track
/// (preferring a .lrc sitting next to the audio file) and auto-scrolls,
/// filling the current line word-by-word as playback advances.
class LyricsScreen extends ConsumerStatefulWidget {
  final Track track;

  const LyricsScreen({super.key, required this.track});

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;

  /// Offset the user has dialled in this session. Initialised from
  /// whatever was loaded with the lyrics, then edited by the +/- buttons.
  Duration? _offset;
  bool _showSyncControls = false;

  /// Accès à tous les fichiers accordé ? Null tant qu'on n'a pas vérifié.
  bool? _hasFileAccess;

  /// True entre le moment où on ouvre l'écran système "Accès à tous les
  /// fichiers" et le retour de l'utilisateur dans l'app.
  ///
  /// Nécessaire parce que `Permission.manageExternalStorage.request()`
  /// n'attend pas vraiment que l'utilisateur bascule le réglage : cet
  /// écran système n'est pas une boîte de dialogue de permission normale,
  /// Android ne renvoie donc pas de résultat à `permission_handler`, et
  /// son Future se termine avant que la permission soit réellement
  /// accordée. La seule façon fiable de savoir ce qui s'est passé est de
  /// revérifier la permission quand l'app redevient active.
  bool _awaitingFileAccessResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkFileAccess();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingFileAccessResume) {
      _awaitingFileAccessResume = false;
      _recheckFileAccessAfterSettings();
    }
  }

  Future<void> _checkFileAccess() async {
    final granted = await LyricsService.hasAllFilesAccess();
    if (mounted) setState(() => _hasFileAccess = granted);
  }

  Future<void> _requestFileAccess() async {
    _awaitingFileAccessResume = true;
    // Ouvre l'écran système. On ignore volontairement la valeur renvoyée
    // (voir la note sur `_awaitingFileAccessResume`) : la vérité vient de
    // `_recheckFileAccessAfterSettings`, appelé au retour dans l'app.
    await LyricsService.requestAllFilesAccess();
  }

  Future<void> _recheckFileAccessAfterSettings() async {
    final granted = await LyricsService.hasAllFilesAccess();
    if (!mounted) return;
    setState(() => _hasFileAccess = granted);
    if (granted) {
      // Relance la recherche : les .lrc du téléphone sont enfin lisibles.
      ref.invalidate(lyricsProvider(lyricsKeyFor(widget.track)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  int _activeIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var index = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= position) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  /// Fraction (0..1) of the way through the active line, used to sweep the
  /// karaoke fill across the text.
  double _lineProgress(List<LyricLine> lines, int index, Duration position) {
    if (index < 0 || index >= lines.length) return 0;
    final start = lines[index].timestamp;
    final end = index + 1 < lines.length
        ? lines[index + 1].timestamp
        : start + const Duration(seconds: 4);
    final total = (end - start).inMilliseconds;
    if (total <= 0) return 1;
    final elapsed = (position - start).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  void _maybeAutoScroll(int activeIndex) {
    if (activeIndex == _lastActiveIndex || activeIndex < 0) return;
    _lastActiveIndex = activeIndex;
    if (!_scrollController.hasClients) return;

    const itemExtent = 64.0;
    final target = (activeIndex * itemExtent) - 160;
    _scrollController.animateTo(
      target.clamp(0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _adjustOffset(LyricsResult result, Duration delta) async {
    final next = (_offset ?? result.offset) + delta;
    setState(() => _offset = next);

    await ref.read(lyricsServiceProvider).saveOffset(
          trackKey: '${widget.track.artist} - ${widget.track.title}',
          offset: next,
          localPath: result.localPath,
        );
  }

  Future<void> _openSearch() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LyricsSearchScreen(track: widget.track),
      ),
    );
    // Au retour, même sans import (l'utilisateur a juste regardé), pas de
    // souci à revalider : le provider garde son cache si rien n'a changé.
    if (mounted) ref.invalidate(lyricsProvider(lyricsKeyFor(widget.track)));
  }

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(widget.track.mood);
    final position = ref.watch(currentPositionProvider);
    final lyricsAsync = ref.watch(lyricsProvider(lyricsKeyFor(widget.track)));

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text(widget.track.title,
                style: AppTheme.labelMedium.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(widget.track.artist,
                style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary)),
          ],
        ),
        centerTitle: true,
        actions: [
          // Toujours disponible : les paroles trouvées automatiquement
          // peuvent être fausses (mauvaise version, mauvais artiste...),
          // l'utilisateur doit pouvoir corriger à la main à tout moment,
          // pas seulement quand rien n'a été trouvé.
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Rechercher les paroles',
            onPressed: () => _openSearch(),
          ),
          // Only meaningful for synced lyrics, so it's enabled below once
          // we know we actually have some.
          if (lyricsAsync.valueOrNull?.hasSynced == true)
            IconButton(
              icon: Icon(
                Icons.tune_rounded,
                color: _showSyncControls
                    ? moodColors.primary
                    : AppTheme.textSecondary,
              ),
              tooltip: 'Régler la synchronisation',
              onPressed: () =>
                  setState(() => _showSyncControls = !_showSyncControls),
            ),
        ],
      ),
      body: GestureDetector(
        // Horizontal only (not a full Pan) so it never competes with the
        // lyrics list's own vertical scroll - swiping up/down here keeps
        // scrolling through the lyrics as normal.
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 200) {
            // Swipe right -> back to Now Playing
            Navigator.of(context).pop();
          }
        },
        child: lyricsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        error: (_, _) => const _EmptyState(
          icon: Icons.wifi_off_rounded,
          message: "Impossible de récupérer les paroles pour l'instant.",
        ),
        data: (result) {
          if (result.instrumental) {
            return const _EmptyState(
              icon: Icons.piano_off_outlined,
              message: 'Ce morceau est instrumental.',
            );
          }

          if (result.hasSynced) {
            final lines = result.synced!;
            final offset = _offset ?? result.offset;
            final adjusted = position - offset;
            final activeIndex = _activeIndex(lines, adjusted);
            final progress = _lineProgress(lines, activeIndex, adjusted);

            WidgetsBinding.instance
                .addPostFrameCallback((_) => _maybeAutoScroll(activeIndex));

            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Padding vertical fixe habituel (200) pour garder
                      // l'effet "focus" pendant le défilement des longues
                      // paroles - mais si le morceau est court et que tout
                      // tient sur l'écran, ça laisse le texte collé en
                      // haut au lieu d'être centré. On agrandit alors le
                      // padding pour centrer réellement le contenu.
                      const itemExtent = 64.0;
                      final contentHeight = lines.length * itemExtent;
                      final extraPadding =
                          (constraints.maxHeight - contentHeight) / 2;
                      final verticalPadding =
                          extraPadding > 200 ? extraPadding : 200.0;

                      return ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingL,
                          vertical: verticalPadding,
                        ),
                        itemCount: lines.length,
                        itemExtent: itemExtent,
                        itemBuilder: (context, index) {
                          return _KaraokeLine(
                            text: lines[index].text,
                            isActive: index == activeIndex,
                            isPast: index < activeIndex,
                            progress: index == activeIndex ? progress : 0,
                            color: moodColors.primary,
                          );
                        },
                      );
                    },
                  ),
                ),
                if (_showSyncControls)
                  _SyncControls(
                    offset: offset,
                    color: moodColors.primary,
                    onEarlier: () => _adjustOffset(result, -_kOffsetStep),
                    onLater: () => _adjustOffset(result, _kOffsetStep),
                    onReset: () async {
                      setState(() => _offset = Duration.zero);
                      await ref.read(lyricsServiceProvider).saveOffset(
                            trackKey:
                                '${widget.track.artist} - ${widget.track.title}',
                            offset: Duration.zero,
                            localPath: result.localPath,
                          );
                    },
                  ),
              ],
            );
          }

          if (result.plain != null && result.plain!.isNotEmpty) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  child: ConstrainedBox(
                    // Force le contenu à occuper au moins toute la
                    // hauteur visible : quand le texte est plus court que
                    // l'écran, le Center ci-dessous peut alors vraiment
                    // centrer verticalement au lieu de rester collé en
                    // haut. Quand le texte est plus long, ce minimum n'a
                    // aucun effet et le défilement normal reprend.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight -
                          (AppTheme.spacingL * 2),
                    ),
                    child: Center(
                      child: Text(
                        result.plain!,
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyLarge.copyWith(
                          color: AppTheme.textPrimary.withValues(alpha: 0.85),
                          height: 1.8,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }

          return _EmptyState(
            icon: Icons.lyrics_outlined,
            message: _hasFileAccess == false
                ? "Aucune parole trouvée en ligne, et l'app n'a pas encore le "
                    "droit de lire les fichiers .lrc de ton téléphone.\n\n"
                    "Android ne considère pas un .lrc comme un fichier "
                    "musical : la permission « musique » ne suffit pas, il "
                    "faut l'accès à tous les fichiers."
                : "Paroles introuvables pour ce morceau.",
            action: _hasFileAccess == false
                ? _EmptyStateAction(
                    label: "Autoriser l'accès aux fichiers",
                    onPressed: _requestFileAccess,
                  )
                : _EmptyStateAction(
                    label: 'Rechercher les paroles',
                    onPressed: _openSearch,
                  ),
          );
        },
      ),
      ),
    );
  }
}

/// One lyric line. The active line is drawn twice: a dim base layer and a
/// bright copy clipped to [progress], which produces the classic karaoke
/// left-to-right fill as the line is sung.
class _KaraokeLine extends StatelessWidget {
  final String text;
  final bool isActive;
  final bool isPast;
  final double progress;
  final Color color;

  const _KaraokeLine({
    required this.text,
    required this.isActive,
    required this.isPast,
    required this.progress,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = (isActive ? AppTheme.titleLarge : AppTheme.bodyLarge)
        .copyWith(
      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
    );

    if (!isActive) {
      return Container(
        alignment: Alignment.center,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 250),
          style: baseStyle.copyWith(
            color: AppTheme.textPrimary.withValues(alpha: isPast ? 0.35 : 0.6),
          ),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
    }

    return Container(
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: baseStyle.copyWith(
              color: AppTheme.textPrimary.withValues(alpha: 0.35),
            ),
          ),
          ClipRect(
            clipper: _ProgressClipper(progress),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: baseStyle.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips its child to the left [progress] fraction of its width.
class _ProgressClipper extends CustomClipper<Rect> {
  final double progress;

  const _ProgressClipper(this.progress);

  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * progress, size.height);

  @override
  bool shouldReclip(_ProgressClipper oldClipper) =>
      oldClipper.progress != progress;
}

/// Bottom bar letting the user nudge the lyrics earlier or later when a
/// .lrc's timings don't quite line up with their copy of the song.
class _SyncControls extends StatelessWidget {
  final Duration offset;
  final Color color;
  final VoidCallback onEarlier;
  final VoidCallback onLater;
  final VoidCallback onReset;

  const _SyncControls({
    required this.offset,
    required this.color,
    required this.onEarlier,
    required this.onLater,
    required this.onReset,
  });

  String get _label {
    final ms = offset.inMilliseconds;
    if (ms == 0) return 'Synchronisé';
    final seconds = (ms / 1000).toStringAsFixed(1);
    return ms > 0 ? 'Retardé de ${seconds}s' : 'Avancé de ${seconds.substring(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingL,
        vertical: AppTheme.spacingM,
      ),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCardElevated,
        border: Border(
          top: BorderSide(color: AppTheme.border.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: AppTheme.labelSmall.copyWith(color: AppTheme.textTertiary),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SyncButton(
                  icon: Icons.fast_rewind_rounded,
                  label: '-0,3 s',
                  color: color,
                  onTap: onEarlier,
                ),
                const SizedBox(width: AppTheme.spacingM),
                TextButton(
                  onPressed: onReset,
                  child: Text(
                    'Réinitialiser',
                    style: AppTheme.labelSmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingM),
                _SyncButton(
                  icon: Icons.fast_forward_rounded,
                  label: '+0,3 s',
                  color: color,
                  onTap: onLater,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SyncButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingM,
          vertical: AppTheme.spacingS,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppTheme.spacingXS),
            Text(label, style: AppTheme.labelSmall.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

/// Bouton optionnel affiché sous un message d'état vide.
class _EmptyStateAction {
  final String label;
  final VoidCallback onPressed;

  const _EmptyStateAction({required this.label, required this.onPressed});
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final _EmptyStateAction? action;

  const _EmptyState({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppTheme.textTertiary),
            const SizedBox(height: AppTheme.spacingM),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
            ),
            if (action != null) ...[
              const SizedBox(height: AppTheme.spacingL),
              FilledButton(
                onPressed: action!.onPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  foregroundColor: AppTheme.textPrimary,
                ),
                child: Text(action!.label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
