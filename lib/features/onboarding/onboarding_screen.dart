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
/// (si des morceaux ont été trouvés). Chaque étape est un simple widget
/// interchangé via un fondu doux, jamais un Navigator.push - on ne veut
/// pas d'un bouton retour qui sorte de ce tunnel à mi-chemin.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  _Step _step = _Step.permission;
  List<String> _artists = const [];
  List<String>? _pendingFavoriteArtists;

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

/// Bouton principal plein-largeur, dégradé de marque - même style que le
/// bouton "Importer" de la bibliothèque, décliné en pleine largeur.
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const _PrimaryButton({required this.label, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingM),
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          boxShadow: AppTheme.coloredShadow(AppTheme.brandMid),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: AppTheme.textPrimary),
              const SizedBox(width: AppTheme.spacingS),
            ],
            Text(
              label,
              style: AppTheme.labelLarge.copyWith(color: AppTheme.textPrimary),
            ),
          ],
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
      child: Text(
        label,
        style: AppTheme.labelLarge.copyWith(color: AppTheme.textTertiary),
      ),
    );
  }
}

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
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingXL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 56,
            color: AppTheme.accentPrimary,
          ).animate().fadeIn(duration: AppTheme.animSlow).scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1, 1),
                duration: AppTheme.animSlow,
              ),
          const SizedBox(height: AppTheme.spacingXL),
          Text(
            'Bienvenue',
            style: AppTheme.headlineMedium,
            textAlign: TextAlign.center,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 120),
              ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Pour vous proposer votre artiste préféré, on a besoin de '
            'jeter un œil à votre musique, uniquement sur cet appareil.',
            style: AppTheme.bodyLarge,
            textAlign: TextAlign.center,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 220),
              ),
          const SizedBox(height: AppTheme.spacingXXL),
          _PrimaryButton(
            label: "Autoriser l'accès",
            icon: Icons.check_rounded,
            onPressed: onAllow,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 300),
              ),
          _SecondaryButton(
            label: 'Plus tard',
            onPressed: onSkip,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 360),
              ),
        ],
      ),
    );
  }
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingXL,
        AppTheme.spacingL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Des artistes que vous adorez ?',
            style: AppTheme.headlineMedium,
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: AppTheme.animSlow),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Choisissez ceux que vous aimez dans votre bibliothèque - ça '
            'nous aide à vous proposer des suggestions dès le début.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
            textAlign: TextAlign.center,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 100),
              ),
          const SizedBox(height: AppTheme.spacingL),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            style: AppTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: 'Rechercher…',
              hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
              prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textTertiary),
              filled: true,
              fillColor: AppTheme.backgroundCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusL),
                borderSide: BorderSide.none,
              ),
            ),
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 180),
              ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            '${_selected.length} sélectionné${_selected.length > 1 ? 's' : ''}',
            style: AppTheme.labelSmall.copyWith(color: AppTheme.accentPrimary),
          ),
          const SizedBox(height: AppTheme.spacingS),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'Aucun artiste ne correspond.',
                      style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final artist = filtered[index];
                      final isSelected = _selected.contains(artist);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => _toggle(artist),
                        title: Text(
                          artist,
                          style: AppTheme.bodyLarge.copyWith(
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        trailing: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: isSelected
                              ? AppTheme.accentPrimary
                              : AppTheme.textTertiary,
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          _PrimaryButton(
            label: _selected.isEmpty
                ? 'Continuer sans choisir'
                : 'Continuer (${_selected.length})',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => widget.onConfirm(_selected.toList()),
          ),
          _SecondaryButton(label: 'Passer cette étape', onPressed: widget.onSkip),
        ],
      ),
    );
  }
}

/// Dernière étape : propose la lecture intelligente (une seule fois, à la
/// première ouverture). Le choix reste modifiable plus tard depuis le
/// profil, mais cette question-ci ne revient jamais.
class _SmartQueueStep extends StatelessWidget {
  final ValueChanged<bool> onChoice;

  const _SmartQueueStep({super.key, required this.onChoice});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingXL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 56,
            color: AppTheme.accentPrimary,
          ).animate().fadeIn(duration: AppTheme.animSlow).scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1, 1),
                duration: AppTheme.animSlow,
              ),
          const SizedBox(height: AppTheme.spacingXL),
          Text(
            'Lecture intelligente',
            style: AppTheme.headlineMedium,
            textAlign: TextAlign.center,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 120),
              ),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Une fois un morceau écouté à moitié, on peut vous suggérer la '
            'suite selon son ambiance (et si possible le même artiste), '
            'plutôt que de suivre strictement la file d\'attente. '
            'Modifiable à tout moment depuis votre profil.',
            style: AppTheme.bodyLarge,
            textAlign: TextAlign.center,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 220),
              ),
          const SizedBox(height: AppTheme.spacingXXL),
          _PrimaryButton(
            label: 'Activer',
            icon: Icons.check_rounded,
            onPressed: () => onChoice(true),
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 300),
              ),
          _SecondaryButton(
            label: 'Non merci, je préfère la file classique',
            onPressed: () => onChoice(false),
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 360),
              ),
        ],
      ),
    );
  }
}
