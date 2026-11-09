import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/import_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/mood_colors.dart';
import '../../widgets/app_header.dart';
import '../player/equalizer_screen.dart';
import '../../widgets/data_transfer_section.dart';
import '../../widgets/theme_section.dart';

/// Écran de profil : artistes préférés (modifiables), quelques
/// statistiques de bibliothèque. Accessible depuis l'icône profil de
/// l'onglet Bibliothèque - jusqu'ici le profil n'avait ni écran ni point
/// d'entrée, seulement le modèle/service/provider en arrière-plan.
class ProfileScreen extends ConsumerStatefulWidget {
  /// `true` quand l'écran est l'onglet « Profil » de la barre du bas :
  /// en-tête d'onglet (sans bouton retour) au lieu d'une page poussée.
  final bool embedded;

  const ProfileScreen({super.key, this.embedded = false});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ImportService _importService = ImportService();

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final trackState = ref.watch(trackProvider);
    final playCounts = ref.watch(playbackStatsProvider);
    final likedCount = trackState.tracks.where((t) => t.isLiked).length;
    final totalPlays = playCounts.values.fold<int>(0, (a, b) => a + b);

    // Ambiance la plus présente dans la bibliothèque.
    final moodCounts = <MoodType, int>{};
    for (final t in trackState.tracks) {
      final m = t.mood;
      if (m != null && m != MoodType.unknown) {
        moodCounts[m] = (moodCounts[m] ?? 0) + 1;
      }
    }
    final MoodType? topMood = moodCounts.isEmpty
        ? null
        : moodCounts.entries.reduce((a, b) => b.value > a.value ? b : a).key;

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              widget.embedded
                  ? const AppHeader.tab(title: 'Profil')
                  : const AppHeader(title: 'Profil', showBack: true),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingL,
                    AppTheme.spacingS,
                    AppTheme.spacingL,
                    120,
                  ),
                  children: [
                    // Importer : uniquement affiché tant que la bibliothèque
                    // est vide - une fois des morceaux présents, cette
                    // entrée disparaît.
                    if (trackState.tracks.isEmpty) ...[
                      _buildImportBanner(),
                      const SizedBox(height: AppTheme.spacingL),
                    ],

                    _ProfileHero(
                      topMood: topMood,
                      artistCount: profile.favoriteArtists.length,
                    ),
                    const SizedBox(height: AppTheme.spacingM),

                    // Statistiques rapides
                    Row(
                      children: [
                        Expanded(
                          child: _StatCard(
                            label: 'Morceaux',
                            value: '${trackState.tracks.length}',
                            icon: Icons.music_note_rounded,
                            color: AppTheme.accentPrimary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingS),
                        Expanded(
                          child: _StatCard(
                            label: 'Favoris',
                            value: '$likedCount',
                            icon: Icons.favorite_rounded,
                            color: const Color(0xFFEC4899),
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingS),
                        Expanded(
                          child: _StatCard(
                            label: 'Écoutes',
                            value: '$totalPlays',
                            icon: Icons.headphones_rounded,
                            color: const Color(0xFF22D3EE),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppTheme.spacingXL),
                    const _SectionTitle('Lecture'),
                    const SizedBox(height: AppTheme.spacingM),

                    // Égaliseur
                    _SettingTile(
                      icon: Icons.equalizer_rounded,
                      title: 'Égaliseur',
                      subtitle: 'Préréglages, basses, aigus et volume',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EqualizerScreen()),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppTheme.textTertiary),
                    ),
                    const SizedBox(height: AppTheme.spacingS),

                    // Lecture intelligente
                    _SettingTile(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Lecture intelligente',
                      subtitle: 'Suggère la suite par ambiance à mi-morceau, '
                          'au lieu de suivre la file d\'attente.',
                      trailing: Switch(
                        value: profile.smartQueueEnabled,
                        activeThumbColor: AppTheme.accentPrimary,
                        onChanged: (value) => ref
                            .read(profileProvider.notifier)
                            .setSmartQueueEnabled(value),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingS),

                    // Volume uniforme
                    _buildNormalizeCard(),
                    const SizedBox(height: AppTheme.spacingXL),

                    // Thème : couleur de fond de l'application
                    const ThemeSection(),
                    const SizedBox(height: AppTheme.spacingXL),

                    // Artistes préférés
                    _SectionTitle(
                      'Artistes préférés',
                      trailing: _PillButton(
                        label: 'Modifier',
                        icon: Icons.edit_rounded,
                        onTap: () => _editFavoriteArtists(
                          context,
                          trackState.tracks
                              .map((t) => t.artist.trim())
                              .where((a) => a.isNotEmpty)
                              .toSet()
                              .toList()
                            ..sort((a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase())),
                          profile.favoriteArtists,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingM),
                    if (profile.favoriteArtists.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(AppTheme.spacingM),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusL),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.person_search_rounded,
                                size: 20, color: AppTheme.textTertiary),
                            const SizedBox(width: AppTheme.spacingS),
                            Expanded(
                              child: Text(
                                'Aucun artiste choisi pour l\'instant. Ça aide '
                                'les suggestions de "Découvertes" à démarrer '
                                'plus vite.',
                                style: AppTheme.bodySmall.copyWith(
                                    color: AppTheme.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Wrap(
                        spacing: AppTheme.spacingS,
                        runSpacing: AppTheme.spacingS,
                        children: [
                          for (final artist in profile.favoriteArtists)
                            // Un tap sur l'artiste le retire des préférés.
                            _ArtistChip(
                              artist: artist,
                              onRemove: () => _removeFavoriteArtist(artist),
                            ),
                        ],
                      ),
                    const SizedBox(height: AppTheme.spacingXL),

                    // Transfert de données (changement de téléphone,
                    // classifications d'une autre personne)
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

  /// Interrupteur « Volume uniforme » + avancement de l'analyse.
  Widget _buildNormalizeCard() {
    final enabled = ref.watch(equalizerProvider.select((s) => s.normalizeVolume));
    final analysis = ref.watch(loudnessProvider);
    return _SettingTile(
      icon: Icons.volume_up_rounded,
      title: 'Volume uniforme',
      subtitle: 'Égalise le volume des morceaux : plus de musique '
          'trop forte ou trop faible.',
      trailing: Switch(
        value: enabled,
        activeThumbColor: AppTheme.accentPrimary,
        onChanged: (value) async {
          await ref.read(equalizerProvider.notifier).setNormalizeVolume(value);
          if (value) {
            ref.read(loudnessProvider.notifier).analyzeLibrary();
          }
        },
      ),
      footer: (enabled && analysis.running)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppTheme.spacingM),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: analysis.total == 0
                        ? null
                        : analysis.done / analysis.total,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingXS),
                Text(
                  'Analyse de la bibliothèque : ${analysis.done} / ${analysis.total}'
                  ' morceaux (une seule fois, en arrière-plan)',
                  style: AppTheme.bodySmall
                      .copyWith(color: AppTheme.textTertiary),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _removeFavoriteArtist(String artist) async {
    final current = ref.read(profileProvider).favoriteArtists;
    await ref
        .read(profileProvider.notifier)
        .setFavoriteArtists(current.where((a) => a != artist).toList());
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
          border: Border.all(
            color: AppTheme.accentPrimary.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentPrimary.withValues(alpha: 0.18),
              blurRadius: 20,
              spreadRadius: -4,
              offset: const Offset(0, 6),
            ),
          ],
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
              child: Icon(
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
        decoration: BoxDecoration(
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

/// Initiale d'un nom, en capitale (sûr avec les emojis et caractères
/// hors du plan de base).
String _initialOf(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return String.fromCharCode(t.runes.first).toUpperCase();
}

/// Bandeau d'en-tête du profil : avatar lumineux, titre et ambiance
/// dominante de la bibliothèque.
class _ProfileHero extends StatelessWidget {
  final MoodType? topMood;
  final int artistCount;

  const _ProfileHero({required this.topMood, required this.artistCount});

  @override
  Widget build(BuildContext context) {
    final mood = topMood;
    final tint = mood == null
        ? AppTheme.accentPrimary
        : MoodColors.forMood(mood).primary;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.brandTop.withValues(alpha: 0.30),
            AppTheme.brandBottom.withValues(alpha: 0.14),
            AppTheme.backgroundCard,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandMid.withValues(alpha: 0.25),
            blurRadius: 28,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentPrimary.withValues(alpha: 0.55),
                  blurRadius: 24,
                  spreadRadius: -2,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 36,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: AppTheme.spacingL),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ton univers sonore',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.headlineMedium.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingS),
                if (mood != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.18),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusFull),
                      border: Border.all(color: tint.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(mood.iconData, size: 14, color: tint),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            mood.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodySmall.copyWith(
                              color: tint,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    'Classe tes morceaux pour découvrir ton ambiance dominante.',
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textSecondary),
                  ),
                if (mood != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ambiance dominante de ta bibliothèque',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodySmall
                        .copyWith(color: AppTheme.textTertiary),
                  ),
                ],
              ],
            ),
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
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingM,
        vertical: AppTheme.spacingM,
      ),
      decoration: AppTheme.glassDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: AppTheme.spacingS),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTheme.headlineMedium.copyWith(
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodySmall.copyWith(color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Titre de section : liseré de marque + titre, bouton optionnel à droite.
class _SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _SectionTitle(this.title, {this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.brandTop, AppTheme.brandBottom],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          ),
        ),
        const SizedBox(width: AppTheme.spacingM),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.headlineMedium.copyWith(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Carte de réglage : pastille d'icône, titre, description, contrôle à
/// droite (interrupteur, flèche...) et zone optionnelle en bas.
class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? footer;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.footer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        decoration: AppTheme.glassDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTheme.radiusM),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withValues(alpha: 0.30),
                        accent.withValues(alpha: 0.10),
                      ],
                    ),
                    border: Border.all(color: accent.withValues(alpha: 0.30)),
                  ),
                  child: Icon(icon, color: accent, size: 23),
                ),
                const SizedBox(width: AppTheme.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.titleMedium
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTheme.bodySmall
                            .copyWith(color: AppTheme.textTertiary),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppTheme.spacingS),
                  trailing!,
                ],
              ],
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

/// Petit bouton en pastille (« Modifier »...).
class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentPrimary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          border: Border.all(color: accent.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTheme.bodySmall
                  .copyWith(color: accent, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Artiste préféré : pastille avec initiale ; un tap le retire.
class _ArtistChip extends StatelessWidget {
  final String artist;
  final VoidCallback onRemove;

  const _ArtistChip({required this.artist, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.accentPrimary;
    return GestureDetector(
      onTap: onRemove,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(color: accent.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.brandGradient,
                ),
                child: Text(
                  _initialOf(artist),
                  style: AppTheme.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.close_rounded,
                  size: 14, color: AppTheme.textTertiary),
            ],
          ),
        ),
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
      decoration: BoxDecoration(
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
                style: AppTheme.titleLarge.copyWith(fontWeight: FontWeight.w700),
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingM,
                      vertical: 1,
                    ),
                    child: ListTile(
                      onTap: () => _toggle(artist),
                      selected: isSelected,
                      selectedTileColor:
                          AppTheme.accentPrimary.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusM),
                      ),
                      leading: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: isSelected ? AppTheme.brandGradient : null,
                          color: isSelected
                              ? null
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                        child: Text(
                          _initialOf(artist),
                          style: AppTheme.bodySmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodyLarge.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
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
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentPrimary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: const StadiumBorder(),
                  ),
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
