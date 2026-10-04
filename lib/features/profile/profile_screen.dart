import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/import_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';
import '../../widgets/data_transfer_section.dart';

/// Écran de profil : artistes préférés (modifiables), quelques
/// statistiques de bibliothèque. Accessible depuis l'icône profil de
/// l'onglet Bibliothèque - jusqu'ici le profil n'avait ni écran ni point
/// d'entrée, seulement le modèle/service/provider en arrière-plan.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ImportService _importService = ImportService();

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
          bottom: false,
          child: Column(
            children: [
              const AppHeader(title: 'Profil', showBack: true),
              Expanded(
                child: ListView(
            padding: const EdgeInsets.all(AppTheme.spacingXL),
            children: [

              // Importer : uniquement affiché tant que la bibliothèque est
              // vide - une fois des morceaux présents, cette entrée
              // disparaît (elle vivait avant dans l'onglet Bibliothèque).
              if (trackState.tracks.isEmpty) ...[
                _buildImportBanner(),
                const SizedBox(height: AppTheme.spacingXL),
              ],

              // Avatar
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    size: 40,
                    color: AppTheme.textPrimary,
                  ),
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

              // Lecture intelligente
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingL),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundCard,
                  borderRadius: BorderRadius.circular(AppTheme.radiusL),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppTheme.radiusM),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: AppTheme.accentPrimary,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingM),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Lecture intelligente', style: AppTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            'Suggère la suite par ambiance à mi-morceau, au '
                            'lieu de suivre la file d\'attente.',
                            style: AppTheme.bodySmall.copyWith(
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: profile.smartQueueEnabled,
                      activeThumbColor: AppTheme.accentPrimary,
                      onChanged: (value) => ref
                          .read(profileProvider.notifier)
                          .setSmartQueueEnabled(value),
                    ),
                  ],
                ),
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
              const SizedBox(height: AppTheme.spacingXL),

              // Transfert de données (changement de téléphone, classifications
              // d'une autre personne)
              const DataTransferSection(),
              const SizedBox(height: AppTheme.spacingXL),
            ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  Widget _buildImportBanner() {
    return GestureDetector(
      onTap: () => _showImportOptions(context),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppTheme.radiusM),
              ),
              child: const Icon(
                Icons.file_upload_rounded,
                color: AppTheme.accentPrimary,
              ),
            ),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Importer de la musique', style: AppTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    'Aucun morceau trouvé - ajoutez vos fichiers audio',
                    style: AppTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }

  void _showImportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
              const SizedBox(height: AppTheme.spacingL),
              Text('Importer de la musique', style: AppTheme.headlineMedium),
              const SizedBox(height: AppTheme.spacingL),
              _buildImportOption(
                icon: Icons.audio_file_rounded,
                title: 'Fichier audio',
                subtitle: 'Sélectionner un fichier',
                onTap: () async {
                  Navigator.pop(context);
                  _handleImportResult(await _importService.pickAudioFile());
                },
              ),
              _buildImportOption(
                icon: Icons.queue_music_rounded,
                title: 'Plusieurs fichiers',
                subtitle: 'Sélectionner plusieurs fichiers',
                onTap: () async {
                  Navigator.pop(context);
                  _handleImportResult(await _importService.pickMultipleAudioFiles());
                },
              ),
              _buildImportOption(
                icon: Icons.folder_rounded,
                title: 'Dossier complet',
                subtitle: 'Importer tous les fichiers audio',
                onTap: () async {
                  Navigator.pop(context);
                  _handleImportResult(await _importService.pickFolderAndImport());
                },
              ),
              const SizedBox(height: AppTheme.spacingL),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.accentPrimary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppTheme.radiusM),
        ),
        child: Icon(icon, color: AppTheme.accentPrimary),
      ),
      title: Text(title, style: AppTheme.titleMedium),
      subtitle: Text(subtitle, style: AppTheme.bodySmall),
      onTap: onTap,
    );
  }

  void _handleImportResult(ImportResult result) {
    if (!mounted || result.isCancelled) return;

    if (result.isSuccess && result.tracks != null) {
      for (final Track track in result.tracks!) {
        ref.read(trackProvider.notifier).addTrack(track);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.trackCount} morceau(x) importé(s)',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          ),
          backgroundColor: AppTheme.backgroundCardElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
          action: result.errorCount > 0
              ? SnackBarAction(
                  label: 'Voir erreurs',
                  textColor: AppTheme.accentPrimary,
                  onPressed: () => _showImportErrors(result.errors),
                )
              : null,
        ),
      );
    } else if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage!,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          ),
          backgroundColor: AppTheme.accentError,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusM),
          ),
        ),
      );
    }
  }

  void _showImportErrors(List<String>? errors) {
    if (errors == null || errors.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
        ),
        title: Text("Erreurs d'import", style: AppTheme.headlineMedium),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: errors
                .map((error) => Padding(
                      padding: const EdgeInsets.only(bottom: AppTheme.spacingS),
                      child: Text('• $error', style: AppTheme.bodyMedium),
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Fermer', style: TextStyle(color: AppTheme.accentPrimary)),
          ),
        ],
      ),
    );
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
