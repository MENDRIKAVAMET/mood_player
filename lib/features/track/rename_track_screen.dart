import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/track.dart';
import '../../providers/providers.dart';
import '../../services/track_file_service.dart';
import '../../theme/app_theme.dart';

/// Formulaire plein écran de modification d'un morceau : nom d'artiste et
/// titre. Enregistrer renomme aussi le vrai fichier sur l'appareil.
class RenameTrackScreen extends ConsumerStatefulWidget {
  final Track track;

  const RenameTrackScreen({super.key, required this.track});

  @override
  ConsumerState<RenameTrackScreen> createState() => _RenameTrackScreenState();
}

class _RenameTrackScreenState extends ConsumerState<RenameTrackScreen> {
  late final TextEditingController _artistController;
  late final TextEditingController _titleController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _artistController = TextEditingController(text: widget.track.artist);
    _titleController = TextEditingController(text: widget.track.title);
  }

  @override
  void dispose() {
    _artistController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  String get _artist => _artistController.text.trim();
  String get _title => _titleController.text.trim();

  bool get _canSave =>
      !_saving &&
      _artist.isNotEmpty &&
      _title.isNotEmpty &&
      (_artist != widget.track.artist || _title != widget.track.title);

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final error = await ref
        .read(trackProvider.notifier)
        .renameTrack(widget.track, artist: _artist, title: _title);

    if (!mounted) return;
    if (error == null) {
      navigator.pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Morceau et fichier renommés')),
      );
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppTheme.textSecondary),
      filled: true,
      fillColor: AppTheme.backgroundCard,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        borderSide: const BorderSide(color: AppTheme.accentPrimary, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fileName = (_artist.isEmpty || _title.isEmpty)
        ? '—'
        : TrackFileService.fileNameFor(widget.track, _artist, _title);

    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTheme.spacingS, AppTheme.spacingS, AppTheme.spacingL, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: AppTheme.textPrimary),
                      onPressed: _saving ? null : () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text('Modifier le morceau',
                          style: AppTheme.headlineLarge),
                    ),
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentPrimary),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Enregistrer'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppTheme.spacingL),
                  children: [
                    const SizedBox(height: AppTheme.spacingL),
                    TextField(
                      controller: _artistController,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                      style: AppTheme.bodyLarge,
                      decoration:
                          _decoration('Nom de l\'artiste', Icons.person_rounded),
                    ),
                    const SizedBox(height: AppTheme.spacingL),
                    TextField(
                      controller: _titleController,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) {
                        if (_canSave) _save();
                      },
                      style: AppTheme.bodyLarge,
                      decoration: _decoration(
                          'Titre de la musique', Icons.music_note_rounded),
                    ),
                    const SizedBox(height: AppTheme.spacingXL),
                    Text('Nom du fichier après modification',
                        style: AppTheme.labelMedium
                            .copyWith(color: AppTheme.textTertiary)),
                    const SizedBox(height: AppTheme.spacingXS),
                    Text(fileName, style: AppTheme.bodyMedium),
                    const SizedBox(height: AppTheme.spacingM),
                    Text(
                      'Le fichier est renommé sur ton appareil, pas seulement '
                      'dans l\'app. Sur Android 11 et plus, le système peut te '
                      'demander l\'autorisation de modifier le fichier.',
                      style: AppTheme.bodySmall
                          .copyWith(color: AppTheme.textSecondary),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppTheme.spacingL),
                      Text(_error!,
                          style: AppTheme.bodyMedium
                              .copyWith(color: Colors.redAccent)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
