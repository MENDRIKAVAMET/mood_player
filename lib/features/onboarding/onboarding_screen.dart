import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mood_splash.dart';
import '../shell/main_shell.dart';

enum _Step { permission, loading, artist, smartQueue }

/// Parcours de bienvenue, affiché une seule fois (tant que
/// `profile.onboardingCompleted` est faux) : autorisation
/// d'accès à la musique -> scan de la bibliothèque -> artiste préféré
/// (si des morceaux ont été trouvés) -> lecture intelligente. Chaque étape
/// est un simple widget interchangé via un fondu doux, jamais un
/// Navigator.push - on ne veut pas d'un bouton retour qui sorte de ce tunnel
/// à mi-chemin.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// Nombre d'étapes affichées dans l'indicateur (le scan n'en est pas une :
  /// c'est une attente).
  static const int _stepCount = 3;

  _Step _step = _Step.permission;
  List<String> _artists = const [];
  List<String>? _pendingFavoriteArtists;

  int get _stepIndex {
    switch (_step) {
      case _Step.permission:
      case _Step.loading:
        return 0;
      case _Step.artist:
        return 1;
      case _Step.smartQueue:
        return 2;
    }
  }

  Future<void> _grantAccessAndScan() async {
    setState(() => _step = _Step.loading);

    // scanAndLoadTracks() gère elle-même la demande de permission (audio
    // sur Android 13+, storage avant) puis le scan MediaStore - pas besoin
    // de dupliquer cette logique ici.
    await ref.read(trackProvider.notifier).scanAndLoadTracks();
    if (!mounted) return;

    // Demandée ici, explicitement, pendant que l'utilisateur vient déjà
    // de dire "oui" à l'accès à sa musique - plutôt que silencieusement en
    // arrière-plan à l'ouverture de l'onglet Bibliothèque juste après, où
    // la boîte de dialogue système peut passer inaperçue (bibliothèque
    // qui charge en même temps) et se faire refuser par réflexe.
    try {
      final status = await Permission.notification.status;
      if (status.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {
      // Non critique : la lecture fonctionne quoi qu'il arrive, et
      // library_screen retentera de toute façon à l'ouverture de l'app.
    }
    if (!mounted) return;

    final tracks = ref.read(trackProvider).tracks;
    final artists = tracks
        .map((t) => t.artist.trim())
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (artists.isEmpty) {
      // Accès refusé, ou aucune musique trouvée : rien à proposer, mais
      // la question de la lecture intelligente reste posée quoi qu'il
      // arrive - elle ne dépend pas d'avoir des artistes à choisir.
      setState(() => _step = _Step.smartQueue);
      return;
    }

    setState(() {
      _artists = artists;
      _step = _Step.artist;
    });
  }

  void _goToSmartQueueStep([List<String>? favoriteArtists]) {
    _pendingFavoriteArtists = favoriteArtists;
    setState(() => _step = _Step.smartQueue);
  }

  Future<void> _finish([bool smartQueueEnabled = false]) async {
    final favoriteArtists = _pendingFavoriteArtists;
    if (favoriteArtists != null && favoriteArtists.isNotEmpty) {
      await ref.read(profileProvider.notifier).setFavoriteArtists(favoriteArtists);
    }
    await ref.read(profileProvider.notifier).setSmartQueueEnabled(smartQueueEnabled);
    await ref.read(profileProvider.notifier).completeOnboarding();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              if (_step != _Step.loading)
                _StepProgress(current: _stepIndex, total: _stepCount),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppTheme.animVerySlow,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: _buildStep(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.permission:
        return _PermissionStep(
          key: const ValueKey('permission'),
          onAllow: _grantAccessAndScan,
          onSkip: () => _finish(),
        );
      case _Step.loading:
        return const MoodSplash(
          key: ValueKey('loading'),
          caption: 'Analyse de votre bibliothèque…',
        );
      case _Step.artist:
        return _ArtistStep(
          key: const ValueKey('artist'),
          artists: _artists,
          onConfirm: (artists) => _goToSmartQueueStep(artists),
          onSkip: () => _goToSmartQueueStep(),
        );
      case _Step.smartQueue:
        return _SmartQueueStep(
          key: const ValueKey('smartQueue'),
          onChoice: (enabled) => _finish(enabled),
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════════
// BRIQUES COMMUNES
// ═══════════════════════════════════════════════════════════════

/// Indicateur d'avancement : ici les étapes forment bien une suite, donc un
/// segment par étape (rempli en dégradé de marque jusqu'à l'étape en cours).
class _StepProgress extends StatelessWidget {
  final int current;
  final int total;

  const _StepProgress({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Étape ${current + 1} sur $total',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingXL,
            AppTheme.spacingL,
            AppTheme.spacingXL,
            0,
          ),
          child: Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: AppTheme.animSlow,
                    curve: Curves.easeOutCubic,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: i <= current ? AppTheme.brandGradient : null,
                      color: i <= current
                          ? null
                          : Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrée d'un bloc : un seul fondu + léger glissement, pas un effet par
/// élément. Désactivée quand l'utilisateur a demandé moins d'animations.
class _Entrance extends StatelessWidget {
  final Widget child;
  final int delayMs;

  const _Entrance({required this.child, this.delayMs = 0});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final delay = Duration(milliseconds: delayMs);
    return child
        .animate()
        .fadeIn(
          duration: AppTheme.animSlow,
          delay: delay,
          curve: Curves.easeOutCubic,
        )
        .slideY(
          begin: 0.03,
          end: 0,
          duration: AppTheme.animSlow,
          delay: delay,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Grande pastille d'icône en dégradé de marque (étapes sans logo).
class _HeroBadge extends StatelessWidget {
  final IconData icon;

  const _HeroBadge({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: AppTheme.brandGradient,
        boxShadow: AppTheme.coloredShadow(AppTheme.accentPrimary),
      ),
      child: Icon(icon, size: 42, color: Colors.white),
    );
  }
}

/// Ligne « pastille d'icône + titre + explication ».
class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.accentPrimary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
            border: Border.all(
              color: AppTheme.accentPrimary.withValues(alpha: 0.28),
            ),
          ),
          child: Icon(icon, size: 21, color: AppTheme.accentPrimary),
        ),
        const SizedBox(width: AppTheme.spacingM),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bouton principal plein-largeur, dégradé de marque - même style que le
/// bouton "Importer" de la bibliothèque, décliné en pleine largeur.
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const _PrimaryButton({required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(
              vertical: AppTheme.spacingM,
              horizontal: AppTheme.spacingL,
            ),
            decoration: AppTheme.primaryButton(
              pill: true,
              glowBlur: 20,
              glowAlpha: 0.4,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppTheme.textPrimary),
                  const SizedBox(width: AppTheme.spacingS),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTheme.labelLarge
                        .copyWith(color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _SecondaryButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }
}

/// Squelette des étapes « texte » : contenu défilant en haut (pour ne jamais
/// déborder sur un petit écran ou avec un grand texte), boutons fixés en bas.
class _StepFrame extends StatelessWidget {
  final List<Widget> content;
  final List<Widget> actions;

  const _StepFrame({required this.content, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingXL,
              AppTheme.spacingXXL,
              AppTheme.spacingXL,
              AppTheme.spacingL,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingXL,
            AppTheme.spacingS,
            AppTheme.spacingXL,
            AppTheme.spacingM,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: actions,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ÉTAPE 1 : ACCÈS À LA MUSIQUE
// ═══════════════════════════════════════════════════════════════

class _PermissionStep extends StatelessWidget {
  final VoidCallback onAllow;
  final VoidCallback onSkip;

  const _PermissionStep({
    super.key,
    required this.onAllow,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return _StepFrame(
      content: [
        _Entrance(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: AppTheme.coloredShadow(AppTheme.accentPrimary),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 88,
                height: 88,
                errorBuilder: (_, _, _) => const _HeroBadge(
                  icon: Icons.graphic_eq_rounded,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingXL),
        _Entrance(
          delayMs: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bienvenue sur Aura', style: AppTheme.displayMedium),
              const SizedBox(height: AppTheme.spacingS),
              Text(
                'Aura classe votre musique par ambiance. Pour commencer, '
                'elle doit pouvoir lire la liste de vos morceaux.',
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingXL),
              const _FeatureRow(
                icon: Icons.smartphone_rounded,
                title: 'Votre musique, sur cet appareil',
                text: 'Aura repère les morceaux déjà présents sur votre '
                    'téléphone.',
              ),
              const SizedBox(height: AppTheme.spacingL),
              const _FeatureRow(
                icon: Icons.mood_rounded,
                title: 'Classée par ambiance',
                text: 'Chill, énergique, nostalgique… chaque morceau '
                    'trouve sa place.',
              ),
              const SizedBox(height: AppTheme.spacingL),
              const _FeatureRow(
                icon: Icons.notifications_none_rounded,
                title: 'Notification de lecture',
                text: 'Une autorisation de notification vous sera aussi '
                    'demandée pour piloter la lecture.',
              ),
            ],
          ),
        ),
      ],
      actions: [
        _PrimaryButton(
          label: "Autoriser l'accès",
          icon: Icons.check_rounded,
          onPressed: onAllow,
        ),
        _SecondaryButton(label: 'Plus tard', onPressed: onSkip),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// ÉTAPE 2 : ARTISTES PRÉFÉRÉS
// ═══════════════════════════════════════════════════════════════

/// Couleur d'avatar stable pour un nom donné (même artiste = même teinte à
/// chaque ouverture), assez sombre pour garder les initiales blanches
/// lisibles.
Color _avatarColor(String name) {
  var hash = 7;
  for (final unit in name.toLowerCase().codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.50, 0.38).toColor();
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String first(String s) => String.fromCharCode(s.runes.first).toUpperCase();
  if (parts.length == 1) return first(parts.first);
  return first(parts[0]) + first(parts[1]);
}

class _ArtistStep extends StatefulWidget {
  final List<String> artists;
  final ValueChanged<List<String>> onConfirm;
  final VoidCallback onSkip;

  const _ArtistStep({
    super.key,
    required this.artists,
    required this.onConfirm,
    required this.onSkip,
  });

  @override
  State<_ArtistStep> createState() => _ArtistStepState();
}

class _ArtistStepState extends State<_ArtistStep> {
  final _searchController = TextEditingController();
  String _query = '';
  final Set<String> _selected = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String artist) {
    setState(() {
      if (_selected.contains(artist)) {
        _selected.remove(artist);
      } else {
        _selected.add(artist);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.artists
        : widget.artists
            .where((a) => a.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    final count = _selected.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Entrance(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        'Vos artistes préférés',
                        style: AppTheme.headlineLarge,
                      ),
                    ),
                    AnimatedContainer(
                      duration: AppTheme.animNormal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: count > 0
                            ? AppTheme.accentPrimary.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.06),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                      ),
                      child: Text(
                        count == 0
                            ? 'Aucun choix'
                            : '$count choisi${count > 1 ? 's' : ''}',
                        style: AppTheme.labelSmall.copyWith(
                          color: count > 0
                              ? AppTheme.accentPrimary
                              : AppTheme.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  '${widget.artists.length} artiste'
                  '${widget.artists.length > 1 ? 's' : ''} dans votre '
                  'bibliothèque. Vos choix servent aux premières suggestions.',
                  style: AppTheme.bodyMedium
                      .copyWith(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingL),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v.trim()),
            style: AppTheme.bodyLarge,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rechercher un artiste',
              hintStyle:
                  AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppTheme.textTertiary,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.textTertiary,
                        size: 20,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: AppTheme.backgroundCard,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacingM,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                borderSide: BorderSide(
                  color: AppTheme.accentPrimary.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Aucun artiste ne correspond à « $_query ».',
                      textAlign: TextAlign.center,
                      style: AppTheme.bodyMedium
                          .copyWith(color: AppTheme.textTertiary),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.only(
                      top: AppTheme.spacingXS,
                      bottom: AppTheme.spacingS,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final artist = filtered[index];
                      return _ArtistRow(
                        artist: artist,
                        selected: _selected.contains(artist),
                        onTap: () => _toggle(artist),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppTheme.spacingS),
          _PrimaryButton(
            label: count == 0 ? 'Continuer sans choisir' : 'Continuer ($count)',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => widget.onConfirm(_selected.toList()),
          ),
          _SecondaryButton(label: 'Passer cette étape', onPressed: widget.onSkip),
        ],
      ),
    );
  }
}

/// Une ligne d'artiste : avatar à initiales, nom, coche. L'état sélectionné
/// se lit sur tout le fond de la ligne, pas seulement sur la coche.
class _ArtistRow extends StatelessWidget {
  final String artist;
  final bool selected;
  final VoidCallback onTap;

  const _ArtistRow({
    required this.artist,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = _avatarColor(artist);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Semantics(
        button: true,
        selected: selected,
        label: artist,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppTheme.animNormal,
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingM,
                vertical: AppTheme.spacingS,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.accentPrimary.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
                border: Border.all(
                  color: selected
                      ? AppTheme.accentPrimary.withValues(alpha: 0.55)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          base,
                          Color.lerp(base, AppTheme.brandBottom, 0.45)!,
                        ],
                      ),
                    ),
                    child: Text(
                      _initials(artist),
                      style: AppTheme.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    child: Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyLarge.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  AnimatedSwitcher(
                    duration: AppTheme.animFast,
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      key: ValueKey(selected),
                      color: selected
                          ? AppTheme.accentPrimary
                          : AppTheme.textTertiary,
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

// ═══════════════════════════════════════════════════════════════
// ÉTAPE 3 : LECTURE INTELLIGENTE
// ═══════════════════════════════════════════════════════════════

/// Dernière étape : propose la lecture intelligente (une seule fois, à la
/// première ouverture). Le choix reste modifiable plus tard depuis le
/// profil, mais cette question-ci ne revient jamais.
class _SmartQueueStep extends StatelessWidget {
  final ValueChanged<bool> onChoice;

  const _SmartQueueStep({super.key, required this.onChoice});

  @override
  Widget build(BuildContext context) {
    return _StepFrame(
      content: [
        const _Entrance(child: _HeroBadge(icon: Icons.auto_awesome_rounded)),
        const SizedBox(height: AppTheme.spacingXL),
        _Entrance(
          delayMs: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lecture intelligente', style: AppTheme.displayMedium),
              const SizedBox(height: AppTheme.spacingS),
              Text(
                'Une fois un morceau écouté à moitié, Aura peut choisir la '
                'suite selon son ambiance (et si possible le même artiste), '
                "plutôt que de suivre strictement la file d'attente.",
                style: AppTheme.bodyLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppTheme.spacingXL),
              const _FeatureRow(
                icon: Icons.graphic_eq_rounded,
                title: "La suite colle à l'ambiance",
                text: 'Le morceau suivant ressemble à ce que vous écoutez '
                    'en ce moment.',
              ),
              const SizedBox(height: AppTheme.spacingL),
              const _FeatureRow(
                icon: Icons.tune_rounded,
                title: 'Modifiable à tout moment',
                text: 'Le réglage se trouve dans votre profil.',
              ),
            ],
          ),
        ),
      ],
      actions: [
        _PrimaryButton(
          label: 'Activer',
          icon: Icons.check_rounded,
          onPressed: () => onChoice(true),
        ),
        _SecondaryButton(
          label: 'Non merci, je préfère la file classique',
          onPressed: () => onChoice(false),
        ),
      ],
    );
  }
}
