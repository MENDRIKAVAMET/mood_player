import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../models/lyric_line.dart';
import '../../providers/audio_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../services/lyrics_service.dart';
import '../../services/lyrics_text_settings.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';
import 'lyrics_search_screen.dart';

/// How much one tap of the sync buttons shifts the lyrics. 300ms is small
/// enough to fine-tune without overshooting, big enough to feel like it
/// did something.
const _kOffsetStep = Duration(milliseconds: 300);

/// Délai sans toucher l'écran avant que le défilement automatique reprenne
/// après que l'utilisateur a fait défiler les paroles lui-même.
const _kAutoScrollResumeDelay = Duration(seconds: 3);

/// Paroles synchronisées, ligne par ligne : la ligne en cours est mise en
/// valeur en entier (pas mot par mot, pour que le décalage éventuel avec
/// le rythme réel ne se voie pas) et la liste défile automatiquement.
/// Quand seules des paroles non synchronisées existent, le texte défile
/// automatiquement en fonction de l'avancement du morceau.
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

  /// Une clé par ligne synchronisée, pour pouvoir centrer la ligne active
  /// même quand les lignes ont des hauteurs différentes (retours à la
  /// ligne, taille de texte réglable).
  final Map<int, GlobalKey> _lineKeys = {};

  /// Réglages du bouton « T » (alignement + taille).
  LyricsTextSettings _text = const LyricsTextSettings();

  /// Vrai tant que l'utilisateur touche/fait défiler les paroles : le
  /// défilement automatique se met alors en pause.
  bool _userInteracting = false;
  Timer? _resumeTimer;

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
    LyricsTextSettings.load().then((value) {
      if (mounted) {
        setState(() {
          _text = value;
          _lastActiveIndex = -1;
        });
      }
    });
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
    _resumeTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Défilement automatique ------------------------------------------

  void _onUserTouchStart() {
    _resumeTimer?.cancel();
    _userInteracting = true;
  }

  void _onUserTouchEnd() {
    _resumeTimer?.cancel();
    _resumeTimer = Timer(_kAutoScrollResumeDelay, () {
      if (!mounted) return;
      setState(() {
        _userInteracting = false;
        // Force le recentrage sur la ligne active au prochain build.
        _lastActiveIndex = -1;
      });
    });
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

  /// Paroles synchronisées : centre la ligne active (à ~40 % de la hauteur)
  /// à chaque changement de ligne.
  void _maybeAutoScroll(int activeIndex) {
    if (activeIndex < 0 || _userInteracting) return;
    if (activeIndex == _lastActiveIndex) return;
    final ctx = _lineKeys[activeIndex]?.currentContext;
    if (ctx == null || !_scrollController.hasClients) return;
    _lastActiveIndex = activeIndex;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  /// Paroles NON synchronisées : pas de timestamps, donc on fait défiler
  /// le texte proportionnellement à l'avancement du morceau. Approximatif,
  /// mais ça évite de devoir faire défiler à la main ; un léger décalage
  /// au début/à la fin laisse la place à l'intro et à l'outro.
  void _autoScrollPlain(Duration position, Duration total) {
    if (_userInteracting || !_scrollController.hasClients) return;
    if (total <= Duration.zero) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;

    final t = position.inMilliseconds / total.inMilliseconds;
    final progress = ((t - 0.06) / 0.86).clamp(0.0, 1.0);
    final target = max * progress;
    final gap = (target - _scrollController.offset).abs();
    if (gap < 2) return;

    _scrollController.animateTo(
      target,
      duration: Duration(milliseconds: gap > 300 ? 500 : 250),
      curve: gap > 300 ? Curves.easeOutCubic : Curves.linear,
    );
  }

  // --- Actions -----------------------------------------------------------

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

  Future<void> _openTextSettings(Color color) async {
    final initial = _text;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.backgroundCardElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusXL),
        ),
      ),
      builder: (_) => _LyricsTextSheet(
        initial: _text,
        color: color,
        // Aperçu en direct derrière la feuille.
        onChanged: (value) => setState(() {
          _text = value;
          _lastActiveIndex = -1;
        }),
      ),
    );

    if (saved == true) {
      await _text.save();
    } else if (mounted) {
      // Fermée sans « Sauvegarder » : on revient aux réglages d'avant.
      setState(() {
        _text = initial;
        _lastActiveIndex = -1;
      });
    }
  }

  TextAlign get _textAlign => _text.alignment == LyricsAlignment.start
      ? TextAlign.start
      : TextAlign.center;

  TextStyle get _lyricStyle => AppTheme.bodyLarge.copyWith(
        fontSize: _text.fontSize,
        height: 1.4,
        fontWeight: FontWeight.w600,
      );

  @override
  Widget build(BuildContext context) {
    final moodColors = MoodColors.forMood(widget.track.mood);
    final position = ref.watch(currentPositionProvider);
    final totalDuration = ref.watch(durationProvider).valueOrNull ??
        Duration(milliseconds: widget.track.duration ?? 0);
    final lyricsAsync = ref.watch(lyricsProvider(lyricsKeyFor(widget.track)));
    final hasText = lyricsAsync.valueOrNull != null &&
        !lyricsAsync.valueOrNull!.instrumental &&
        (lyricsAsync.valueOrNull!.hasSynced ||
            (lyricsAsync.valueOrNull!.plain?.isNotEmpty ?? false));

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
          // Bouton « T » : alignement et taille du texte des paroles.
          if (hasText)
            IconButton(
              tooltip: 'Style du texte',
              onPressed: () => _openTextSettings(moodColors.primary),
              icon: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.textSecondary, width: 1.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'T',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
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
        // Le Listener voit les doigts sans les consommer : il sert
        // uniquement à mettre le défilement automatique en pause.
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _onUserTouchStart(),
          onPointerUp: (_) => _onUserTouchEnd(),
          onPointerCancel: (_) => _onUserTouchEnd(),
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
                return _buildSynced(result, position, moodColors.primary);
              }

              if (result.plain != null && result.plain!.isNotEmpty) {
                return _buildPlain(result.plain!, position, totalDuration);
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
      ),
    );
  }

  /// Version karaoké : la ligne en cours est mise en valeur en entier.
  Widget _buildSynced(LyricsResult result, Duration position, Color color) {
    final lines = result.synced!;
    final offset = _offset ?? result.offset;
    final activeIndex = _activeIndex(lines, position - offset);

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeAutoScroll(activeIndex));

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                controller: _scrollController,
                // Marges haute/basse ~ une demi-hauteur d'écran pour que
                // même la première et la dernière ligne puissent être
                // amenées au point de focus.
                padding: EdgeInsets.fromLTRB(
                  AppTheme.spacingL,
                  constraints.maxHeight * 0.4,
                  AppTheme.spacingL,
                  constraints.maxHeight * 0.5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < lines.length; i++)
                      _KaraokeLine(
                        key: _lineKeys.putIfAbsent(i, () => GlobalKey()),
                        text: lines[i].text,
                        isActive: i == activeIndex,
                        isPast: i < activeIndex,
                        color: color,
                        style: _lyricStyle,
                        textAlign: _textAlign,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_showSyncControls)
          _SyncControls(
            offset: offset,
            color: color,
            onEarlier: () => _adjustOffset(result, -_kOffsetStep),
            onLater: () => _adjustOffset(result, _kOffsetStep),
            onReset: () async {
              setState(() => _offset = Duration.zero);
              await ref.read(lyricsServiceProvider).saveOffset(
                    trackKey: '${widget.track.artist} - ${widget.track.title}',
                    offset: Duration.zero,
                    localPath: result.localPath,
                  );
            },
          ),
      ],
    );
  }

  /// Paroles sans timestamps : texte simple qui défile tout seul selon
  /// l'avancement du morceau (mis en pause dès qu'on le touche).
  Widget _buildPlain(String plain, Duration position, Duration total) {
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _autoScrollPlain(position, total));

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppTheme.spacingL),
          child: ConstrainedBox(
            // Force le contenu à occuper au moins toute la hauteur
            // visible : un texte court est alors vraiment centré
            // verticalement ; un texte long défile normalement.
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - (AppTheme.spacingL * 2),
            ),
            child: Align(
              alignment: _text.alignment == LyricsAlignment.start
                  ? Alignment.centerLeft
                  : Alignment.center,
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  plain,
                  textAlign: _textAlign,
                  style: _lyricStyle.copyWith(
                    color: AppTheme.textPrimary.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                    height: 1.8,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Une ligne de paroles. La ligne active est simplement colorée en entier
/// (pas de remplissage mot par mot) : plus fiable quand les timestamps ne
/// collent pas parfaitement au rythme.
class _KaraokeLine extends StatelessWidget {
  final String text;
  final bool isActive;
  final bool isPast;
  final Color color;
  final TextStyle style;
  final TextAlign textAlign;

  const _KaraokeLine({
    super.key,
    required this.text,
    required this.isActive,
    required this.isPast,
    required this.color,
    required this.style,
    required this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final lineColor = isActive
        ? color
        : AppTheme.textPrimary.withValues(alpha: isPast ? 0.35 : 0.6);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 250),
        style: style.copyWith(color: lineColor),
        textAlign: textAlign,
        child: Text(text, textAlign: textAlign),
      ),
    );
  }
}

/// Feuille du bouton « T » : alignement du texte + taille du texte.
class _LyricsTextSheet extends StatefulWidget {
  final LyricsTextSettings initial;
  final Color color;
  final ValueChanged<LyricsTextSettings> onChanged;

  const _LyricsTextSheet({
    required this.initial,
    required this.color,
    required this.onChanged,
  });

  @override
  State<_LyricsTextSheet> createState() => _LyricsTextSheetState();
}

class _LyricsTextSheetState extends State<_LyricsTextSheet> {
  late LyricsTextSettings _s = widget.initial;

  void _update(LyricsTextSettings value) {
    setState(() => _s = value);
    widget.onChanged(value);
  }

  Widget _alignmentRow(String label, LyricsAlignment value) {
    final selected = _s.alignment == value;
    return InkWell(
      onTap: () => _update(_s.copyWith(alignment: value)),
      borderRadius: BorderRadius.circular(AppTheme.radiusM),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingS),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? widget.color : AppTheme.textSecondary,
            ),
            const SizedBox(width: AppTheme.spacingM),
            Text(
              label,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.spacingL,
          AppTheme.spacingM,
          AppTheme.spacingL,
          AppTheme.spacingL,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textTertiary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingL),
            Text('Alignement du texte', style: AppTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingS),
            _alignmentRow('Début de l\'alignement du texte', LyricsAlignment.start),
            _alignmentRow('Centre de l\'alignement du texte', LyricsAlignment.center),
            const SizedBox(height: AppTheme.spacingL),
            Text('Taille du texte', style: AppTheme.titleMedium),
            const SizedBox(height: AppTheme.spacingS),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: widget.color,
                inactiveTrackColor: AppTheme.textTertiary.withValues(alpha: 0.4),
                thumbColor: Colors.white,
                activeTickMarkColor: Colors.transparent,
                inactiveTickMarkColor: Colors.transparent,
                overlayColor: widget.color.withValues(alpha: 0.15),
              ),
              child: Slider(
                min: 0,
                max: 3,
                divisions: 3,
                value: _s.sizeIndex.toDouble(),
                onChanged: (v) => _update(_s.copyWith(sizeIndex: v.round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingS),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final label in LyricsTextSettings.sizeLabels)
                    Text(
                      label,
                      style: AppTheme.labelSmall
                          .copyWith(color: AppTheme.textTertiary),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingXL),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Sauvegarder'),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                  foregroundColor: AppTheme.textInverse,
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
