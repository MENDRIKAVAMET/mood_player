import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import '../../theme/app_theme.dart';

/// Écran de profil : nom, artistes préférés (modifiables), quelques
/// statistiques de bibliothèque. Accessible depuis l'icône profil de
/// l'onglet Bibliothèque - jusqu'ici le profil n'avait ni écran ni point
/// d'entrée, seulement le modèle/service/provider en arrière-plan.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final trackState = ref.watch(trackProvider);
    final likedCount = trackState.tracks.where((t) => t.isLiked).length;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingXL),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: AppTheme.spacingS),
                  Text('Profil', style: AppTheme.headlineLarge),
                ],
              ),
              const SizedBox(height: AppTheme.spacingXL),

              // Avatar + nom
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        gradient: AppTheme.brandGradient,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (profile.name?.isNotEmpty == true)
                            ? profile.name![0].toUpperCase()
                            : '?',
                        style: AppTheme.displayLarge.copyWith(
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                    Text(
                      profile.name?.isNotEmpty == true
                          ? profile.name!
                          : 'Sans nom',
                      style: AppTheme.headlineMedium,
                    ),
                    TextButton.icon(
                      onPressed: () => _editName(context, profile.name),
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: const Text('Modifier le nom'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingXL),

              // Statistiques rapides
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Morceaux',
                      value: '${trackState.tracks.length}',
                      icon: Icons.music_note_rounded,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingM),
                  Expanded(
                    child: _StatCard(
                      label: 'Favoris',
                      value: '$likedCount',
                      icon: Icons.favorite_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingXL),

              // Artistes préférés
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Artistes préférés', style: AppTheme.titleLarge),
                  TextButton(
                    onPressed: () => _editFavoriteArtists(
                      context,
                      trackState.tracks
                          .map((t) => t.artist.trim())
                          .where((a) => a.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
                      profile.favoriteArtists,
                    ),
                    child: const Text('Modifier'),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingS),
              if (profile.favoriteArtists.isEmpty)
                Text(
                  'Aucun artiste choisi pour l\'instant. Ça aide les '
                  'suggestions de "Pour vous" à démarrer plus vite.',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textTertiary),
                )
              else
                Wrap(
                  spacing: AppTheme.spacingS,
                  runSpacing: AppTheme.spacingS,
                  children: [
                    for (final artist in profile.favoriteArtists)
                      Chip(
                        label: Text(artist),
                        backgroundColor: AppTheme.backgroundCard,
                        labelStyle: AppTheme.bodyMedium,
                        side: BorderSide.none,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editName(BuildContext context, String? currentName) async {
    final controller = TextEditingController(text: currentName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: const Text('Votre prénom'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      await ref.read(profileProvider.notifier).setName(name);
    }
  }

  Future<void> _editFavoriteArtists(
    BuildContext context,
    List<String> allArtists,
    List<String> current,
  ) async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ArtistPickerSheet(
        allArtists: allArtists,
        initiallySelected: current,
      ),
    );
    if (result != null && mounted) {
      await ref.read(profileProvider.notifier).setFavoriteArtists(result);
    }
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.accentPrimary, size: 20),
          const SizedBox(height: AppTheme.spacingS),
          Text(value, style: AppTheme.headlineMedium),
          Text(label, style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary)),
        ],
      ),
    );
  }
}

/// Sélecteur d'artistes (aucune limite), réutilisé pour modifier le choix
/// fait à l'onboarding depuis l'écran de profil.
class _ArtistPickerSheet extends StatefulWidget {
  final List<String> allArtists;
  final List<String> initiallySelected;

  const _ArtistPickerSheet({
    required this.allArtists,
    required this.initiallySelected,
  });

  @override
  State<_ArtistPickerSheet> createState() => _ArtistPickerSheetState();
}

class _ArtistPickerSheetState extends State<_ArtistPickerSheet> {
  late final Set<String> _selected = {...widget.initiallySelected};
  String _query = '';

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
        ? widget.allArtists
        : widget.allArtists
            .where((a) => a.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXL)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppTheme.spacingM),
              decoration: BoxDecoration(
                color: AppTheme.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: Text(
                'Artistes préférés (${_selected.length})',
                style: AppTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingL),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Rechercher…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: AppTheme.backgroundCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusL),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final artist = filtered[index];
                  final isSelected = _selected.contains(artist);
                  return ListTile(
                    onTap: () => _toggle(artist),
                    title: Text(
                      artist,
                      style: AppTheme.bodyLarge.copyWith(color: AppTheme.textPrimary),
                    ),
                    trailing: Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                      color: isSelected ? AppTheme.accentPrimary : AppTheme.textTertiary,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingL),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _selected.toList()),
                  child: const Text('Enregistrer'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
