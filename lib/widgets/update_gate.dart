import 'dart:io';

import 'package:flutter/material.dart';

import '../services/update_service.dart';
import '../theme/app_theme.dart';

/// À l'ouverture de l'app, vérifie s'il existe une version plus récente et
/// la propose dans un dialogue. Enveloppe l'écran d'accueil.
class UpdateGate extends StatefulWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  @override
  void initState() {
    super.initState();
    // Android seulement (l'installation passe par du code natif), et pas
    // dans les tests.
    if (Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
  }

  Future<void> _check() async {
    final update = await UpdateService().checkForUpdate();
    if (update == null || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(update: update),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _Step {
  offer, // « Télécharger » / « Pas maintenant »
  needPermission, // autoriser l'installation d'applis depuis Mood Player
  downloading,
  installing,
  installCancelled,
  error,
}

class _UpdateDialog extends StatefulWidget {
  final AppUpdate update;

  const _UpdateDialog({required this.update});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog>
    with WidgetsBindingObserver {
  final UpdateService _service = UpdateService();
  _Step _step = _Step.offer;
  double _progress = 0;
  String? _error;
  bool _leftApp = false;

  bool get _busy =>
      _step == _Step.downloading || _step == _Step.installing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _leftApp = true;
    } else if (state == AppLifecycleState.resumed && _leftApp) {
      _leftApp = false;
      if (_step == _Step.needPermission) {
        // Retour des réglages : on reprend là où on s'était arrêté.
        _start();
      } else if (_step == _Step.installing && mounted) {
        // On est revenu sans que l'app ait été remplacée : l'installation
        // a été annulée (ou a échoué) dans l'installateur système.
        setState(() => _step = _Step.installCancelled);
      }
    }
  }

  Future<void> _start() async {
    try {
      if (!await _service.canInstall()) {
        if (mounted) setState(() => _step = _Step.needPermission);
        return;
      }
      if (!mounted) return;
      setState(() {
        _step = _Step.downloading;
        _progress = 0;
      });
      final apk = await _service.download(
        widget.update,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _step = _Step.installing);
      _leftApp = false;
      await _service.install(apk);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _Step.error;
        _error = 'Le téléchargement a échoué. Vérifie ta connexion et réessaie.';
      });
    }
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Rien n'est possible pendant le téléchargement / l'installation.
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: AppTheme.backgroundCardElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        ),
        title: Row(
          children: [
            Icon(Icons.system_update_rounded, color: AppTheme.accentPrimary),
            const SizedBox(width: AppTheme.spacingM),
            Expanded(
              child: Text(_title, style: AppTheme.titleLarge),
            ),
          ],
        ),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }

  String get _title {
    switch (_step) {
      case _Step.offer:
        return 'Mise à jour disponible';
      case _Step.needPermission:
        return 'Autorisation requise';
      case _Step.downloading:
        return 'Téléchargement…';
      case _Step.installing:
        return 'Installation…';
      case _Step.installCancelled:
        return 'Installation interrompue';
      case _Step.error:
        return 'Mise à jour impossible';
    }
  }

  Widget _buildContent() {
    switch (_step) {
      case _Step.offer:
        final size = widget.update.size;
        return Text(
          'La version ${widget.update.version} de Mood Player est disponible'
          '${size != null ? ' (${_formatSize(size)})' : ''}.',
          style: AppTheme.bodyMedium,
        );
      case _Step.needPermission:
        return Text(
          'Pour installer la mise à jour, autorise Mood Player à installer '
          'des applications dans les réglages, puis reviens ici.',
          style: AppTheme.bodyMedium,
        );
      case _Step.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${widget.update.version}. Ne ferme pas l\'application.',
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spacingL),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 8,
                color: AppTheme.accentPrimary,
                backgroundColor: AppTheme.textTertiary.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: AppTheme.spacingS),
            Text('${(_progress * 100).round()} %', style: AppTheme.labelMedium),
          ],
        );
      case _Step.installing:
        return Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.accentPrimary,
              ),
            ),
            const SizedBox(width: AppTheme.spacingL),
            Expanded(
              child: Text(
                'Confirme l\'installation, l\'application va redémarrer.',
                style: AppTheme.bodyMedium,
              ),
            ),
          ],
        );
      case _Step.installCancelled:
        return Text(
          'L\'installation n\'a pas été terminée. Tu peux réessayer.',
          style: AppTheme.bodyMedium,
        );
      case _Step.error:
        return Text(_error ?? '', style: AppTheme.bodyMedium);
    }
  }

  List<Widget> _buildActions() {
    switch (_step) {
      case _Step.offer:
        return [
          TextButton(
            onPressed: _close,
            child: Text('Pas maintenant',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: AppTheme.textInverse),
            onPressed: _start,
            child: const Text('Télécharger'),
          ),
        ];
      case _Step.needPermission:
        return [
          TextButton(
            onPressed: _close,
            child: Text('Annuler',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: AppTheme.textInverse),
            onPressed: _service.openInstallSettings,
            child: const Text('Ouvrir les réglages'),
          ),
        ];
      case _Step.downloading:
      case _Step.installing:
        return const [];
      case _Step.installCancelled:
      case _Step.error:
        return [
          TextButton(
            onPressed: _close,
            child: Text('Fermer',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentPrimary,
                foregroundColor: AppTheme.textInverse),
            onPressed: _start,
            child: const Text('Réessayer'),
          ),
        ];
    }
  }

  static String _formatSize(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
}
