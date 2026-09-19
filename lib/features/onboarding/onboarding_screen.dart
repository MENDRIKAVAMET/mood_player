import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/mood_splash.dart';
import '../shell/main_shell.dart';

enum _Step { name, permission, loading, artist }

/// Parcours de bienvenue, affiché une seule fois (tant que
/// `profile.onboardingCompleted` est faux) : prénom -> autorisation
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
  _Step _step = _Step.name;
  List<String> _artists = const [];

  Future<void> _submitName(String name) async {
    await ref.read(profileProvider.notifier).setName(name);
    if (!mounted) return;
    setState(() => _step = _Step.permission);
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
      // Accès refusé, ou aucune musique trouvée : rien à proposer, on ne
      // pose pas la question pour rien.
      await _finish();
      return;
    }

    setState(() {
      _artists = artists;
      _step = _Step.artist;
    });
  }

  Future<void> _finish([List<String>? favoriteArtists]) async {
    if (favoriteArtists != null && favoriteArtists.isNotEmpty) {
      await ref.read(profileProvider.notifier).setFavoriteArtists(favoriteArtists);
    }
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
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
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
      case _Step.name:
        return _NameStep(key: const ValueKey('name'), onSubmit: _submitName);
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
          onConfirm: (artists) => _finish(artists),
          onSkip: () => _finish(),
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

class _NameStep extends StatefulWidget {
  final ValueChanged<String> onSubmit;

  const _NameStep({super.key, required this.onSubmit});

  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends State<_NameStep> {
  final _controller = TextEditingController();
  bool get _canSubmit => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingXL),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Bienvenue.',
            style: AppTheme.headlineLarge,
            textAlign: TextAlign.center,
          ).animate().fadeIn(duration: AppTheme.animSlow),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Comment souhaitez-vous qu\'on vous appelle ?',
            style: AppTheme.bodyLarge,
            textAlign: TextAlign.center,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 120),
              ),
          const SizedBox(height: AppTheme.spacingXXL),
          TextField(
            controller: _controller,
            autofocus: true,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            style: AppTheme.titleLarge,
            onChanged: (_) => setState(() {}),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) widget.onSubmit(value.trim());
            },
            decoration: InputDecoration(
              hintText: 'Votre prénom',
              hintStyle: AppTheme.titleLarge.copyWith(color: AppTheme.textTertiary),
              filled: true,
              fillColor: AppTheme.backgroundCard,
              contentPadding: const EdgeInsets.symmetric(
                vertical: AppTheme.spacingL,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusL),
                borderSide: BorderSide.none,
              ),
            ),
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 220),
              ),
          const SizedBox(height: AppTheme.spacingXXL),
          _PrimaryButton(
            label: 'Continuer',
            icon: Icons.arrow_forward_rounded,
            onPressed: _canSubmit
                ? () => widget.onSubmit(_controller.text.trim())
                : null,
          ).animate().fadeIn(
                duration: AppTheme.animSlow,
                delay: const Duration(milliseconds: 300),
              ),
        ],
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
            'Un dernier détail',
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
  static const _maxSelection = 3;

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
      } else if (_selected.length < _maxSelection) {
        _selected.add(artist);
      }
      // Déjà à 3 et on tape un 4e : on ignore simplement le tap plutôt
      // que de remplacer un choix existant sans le dire - plus simple à
      // comprendre que "pourquoi mon premier choix a disparu ?".
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
            'Choisissez-en jusqu\'à 3 dans votre bibliothèque - ça nous '
            'aide à vous proposer des suggestions dès le début.',
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
            '${_selected.length}/$_maxSelection sélectionné${_selected.length > 1 ? 's' : ''}',
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
                      final isDisabled =
                          !isSelected && _selected.length >= _maxSelection;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: isDisabled ? null : () => _toggle(artist),
                        title: Text(
                          artist,
                          style: AppTheme.bodyLarge.copyWith(
                            color: isDisabled
                                ? AppTheme.textTertiary
                                : AppTheme.textPrimary,
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
