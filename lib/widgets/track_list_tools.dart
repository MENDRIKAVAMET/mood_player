import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../utils/playback_navigation.dart';

/// Outils communs à tous les écrans qui listent des morceaux :
/// - [TrackListScrollbar] : barre de défilement rapide, à saisir et glisser ;
/// - [LocateTrackButton] + [TrackListLocator] : bouton ancre qui ramène la
///   liste sur le morceau en cours de lecture ;
/// - [TrackListActionBar] : Tout lire / Lecture aléatoire / Trier ;
/// - [sortTracks] et [showTrackSortSheet] : tri local à un écran.

/// Trie une copie de [tracks]. Même logique que le tri de la bibliothèque.
List<Track> sortTracks(List<Track> tracks, TrackSortOption option) {
  final sorted = List<Track>.from(tracks);
  switch (option) {
    case TrackSortOption.nameAsc:
      sorted.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case TrackSortOption.nameDesc:
      sorted.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
    case TrackSortOption.dateNewest:
      sorted.sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    case TrackSortOption.dateOldest:
      sorted.sort((a, b) =>
          (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
  }
  return sorted;
}

/// Résultat de [showTrackSortSheet] : [option] null = ordre d'origine.
class TrackSortChoice {
  final TrackSortOption? option;
  const TrackSortChoice(this.option);
}

/// Feuille « Trier par ». Renvoie null si elle est fermée sans choix.
Future<TrackSortChoice?> showTrackSortSheet(
  BuildContext context, {
  TrackSortOption? current,
}) {
  return showModalBottomSheet<TrackSortChoice>(
    context: context,
    backgroundColor: AppTheme.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppTheme.radiusL)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppTheme.spacingM),
          Text('Trier par', style: AppTheme.headlineMedium),
          const SizedBox(height: AppTheme.spacingS),
          ListTile(
            title: Text('Ordre d\'origine', style: AppTheme.bodyMedium),
            trailing: current == null
                ? Icon(Icons.check, color: AppTheme.accentPrimary)
                : null,
            onTap: () => Navigator.pop(context, const TrackSortChoice(null)),
          ),
          for (final option in TrackSortOption.values)
            ListTile(
              title: Text(option.label, style: AppTheme.bodyMedium),
              trailing: option == current
                  ? Icon(Icons.check, color: AppTheme.accentPrimary)
                  : null,
              onTap: () => Navigator.pop(context, TrackSortChoice(option)),
            ),
          const SizedBox(height: AppTheme.spacingM),
        ],
      ),
    ),
  );
}

/// Barre de défilement rapide : poignée toujours visible, à saisir et
/// glisser pour parcourir toute la liste. [controller] doit être celui du
/// défilant enfant.
class TrackListScrollbar extends StatelessWidget {
  final ScrollController controller;
  final Widget child;

  const TrackListScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      interactive: true,
      thickness: 7,
      minThumbLength: 56,
      radius: const Radius.circular(AppTheme.radiusFull),
      thumbColor: AppTheme.accentPrimary.withValues(alpha: 0.65),
      trackColor: AppTheme.backgroundCard.withValues(alpha: 0.4),
      trackBorderColor: Colors.transparent,
      trackVisibility: true,
      child: child,
    );
  }
}

/// Fait défiler une liste jusqu'au morceau en cours. Chaque ligne doit être
/// enveloppée dans `KeyedSubtree(key: locator.keyFor(track.id), ...)`.
/// [leadingKeys] désigne les blocs au-dessus de la liste, dans le même
/// défilant (en-têtes, bandeaux), dont la hauteur est ajoutée au calcul.
class TrackListLocator {
  final ScrollController controller;
  final List<GlobalKey> leadingKeys;
  final Map<int, GlobalKey> _tileKeys = {};

  TrackListLocator({required this.controller, this.leadingKeys = const []});

  GlobalKey keyFor(int trackId) =>
      _tileKeys.putIfAbsent(trackId, () => GlobalKey());

  static double _heightOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    return (box != null && box.hasSize) ? box.size.height : 0;
  }

  /// Hauteur d'une ligne, mesurée sur une ligne actuellement affichée.
  double get _itemExtent {
    for (final key in _tileKeys.values) {
      final h = _heightOf(key);
      if (h > 0) return h;
    }
    return 76;
  }

  /// Renvoie false si le morceau n'est pas dans [tracks].
  Future<bool> locate(List<Track> tracks, int trackId) async {
    final index = tracks.indexWhere((t) => t.id == trackId);
    if (index < 0 || !controller.hasClients) return false;

    var above = 0.0;
    for (final key in leadingKeys) {
      above += _heightOf(key);
    }
    final target = (above + index * _itemExtent - AppTheme.spacingS)
        .clamp(0.0, controller.position.maxScrollExtent)
        .toDouble();

    await controller.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );

    // Ajustement fin une fois la ligne réellement construite.
    final tileContext = _tileKeys[trackId]?.currentContext;
    if (tileContext != null && tileContext.mounted) {
      await Scrollable.ensureVisible(
        tileContext,
        duration: const Duration(milliseconds: 200),
        alignment: 0.1,
      );
    }
    return true;
  }
}

/// Bouton ancre, à placer dans un `Stack` au-dessus de la liste. Visible
/// seulement quand un morceau est en cours ET présent dans [tracks].
/// [bottom] : distance au bas (laisser la place du mini-lecteur si
/// l'écran en affiche un).
class LocateTrackButton extends ConsumerStatefulWidget {
  final TrackListLocator locator;
  final List<Track> tracks;
  final double bottom;

  const LocateTrackButton({
    super.key,
    required this.locator,
    required this.tracks,
    this.bottom = 24,
  });

  @override
  ConsumerState<LocateTrackButton> createState() => _LocateTrackButtonState();
}

class _LocateTrackButtonState extends ConsumerState<LocateTrackButton> {
  Timer? _fadeTimer;
  bool _dimmed = false;

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  Future<void> _onTap(int trackId) async {
    final found = await widget.locator.locate(widget.tracks, trackId);
    if (!found || !mounted) return;
    // Petit effacement de confirmation, puis le bouton revient.
    _fadeTimer?.cancel();
    setState(() => _dimmed = true);
    _fadeTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _dimmed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentTrackProvider).valueOrNull;
    final currentId = current == null ? null : int.tryParse(current.id);
    final visible = currentId != null &&
        widget.tracks.any((t) => t.id == currentId);
    if (!visible) return const SizedBox.shrink();

    return Positioned(
      right: AppTheme.spacingL,
      bottom: widget.bottom,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 260),
        opacity: _dimmed ? 0.0 : 1.0,
        child: IgnorePointer(
          ignoring: _dimmed,
          child: GestureDetector(
            onTap: () => _onTap(currentId),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.backgroundCard,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accentPrimary.withValues(alpha: 0.4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.anchor_rounded,
                color: AppTheme.accentPrimary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Les trois boutons : Tout lire, Lecture aléatoire, Trier. [onSort] reçoit
/// le choix de l'utilisateur ; [sort] null = ordre d'origine.
class TrackListActionBar extends StatelessWidget {
  final List<Track> tracks;
  final TrackSortOption? sort;
  final ValueChanged<TrackSortChoice>? onSort;
  final Color? _color;

  /// Par défaut la couleur principale choisie par l'utilisateur.
  Color get color => _color ?? AppTheme.accentPrimary;

  const TrackListActionBar({
    super.key,
    required this.tracks,
    this.sort,
    this.onSort,
    Color? color,
  }) : _color = color;

  @override
  Widget build(BuildContext context) {
    final hasTracks = tracks.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Tout lire',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.play_circle_fill_rounded,
            color: hasTracks ? color : AppTheme.textTertiary,
            size: 26,
          ),
          onPressed: hasTracks ? () => playAll(context, tracks) : null,
        ),
        IconButton(
          tooltip: 'Lecture aléatoire',
          visualDensity: VisualDensity.compact,
          icon: Icon(
            Icons.shuffle_rounded,
            color: hasTracks ? color : AppTheme.textTertiary,
            size: 22,
          ),
          onPressed: hasTracks ? () => playShuffled(context, tracks) : null,
        ),
        if (onSort != null)
          IconButton(
            tooltip: 'Trier',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.sort_rounded,
              color: sort != null ? color : AppTheme.textSecondary,
              size: 22,
            ),
            onPressed: hasTracks
                ? () async {
                    final choice =
                        await showTrackSortSheet(context, current: sort);
                    if (choice != null) onSort!(choice);
                  }
                : null,
          ),
      ],
    );
  }
}
