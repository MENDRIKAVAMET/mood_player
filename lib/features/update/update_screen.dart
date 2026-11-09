import 'package:flutter/material.dart';

import '../../services/update_service.dart';
import '../../theme/app_theme.dart';

enum _Step {
  offer,
  needPermission,
  downloading,
  installing,
  installCancelled,
  error,
}

/// Écran plein écran de mise à jour : version, taille, nouveautés de la
/// release, puis étapes téléchargement / installation avec progression.
class UpdateScreen extends StatefulWidget {
  final AppUpdate update;

  const UpdateScreen({super.key, required this.update});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen>
    with WidgetsBindingObserver {
  final UpdateService _service = UpdateService();
  _Step _step = _Step.offer;
  double _progress = 0;
  String? _error;
  bool _leftApp = false;

  bool get _busy => _step == _Step.downloading || _step == _Step.installing;

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
        _start();
      } else if (_step == _Step.installing && mounted) {
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

  /// Lignes de la release : on retire les puces / titres markdown pour
  /// n'afficher que du texte propre.
  List<String> get _notes {
    return widget.update.notes
        .split('\n')
        .map((l) => l
            .trim()
            .replaceFirst(RegExp(r'^(#{1,6}\s*|[-*+]\s+|\d+\.\s+)'), '')
            .replaceAll('**', '')
            .replaceAll('`', '')
            .trim())
        .where((l) => l.isNotEmpty)
        .take(14)
        .toList();
  }

  static String _formatSize(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        body: Container(
          decoration: BoxDecoration(gradient: AppTheme.screenGradient),
          child: SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: _busy
                        ? const SizedBox(height: 48)
                        : IconButton(
                            icon: Icon(Icons.close_rounded,
                                color: AppTheme.textSecondary),
                            onPressed: _close,
                          ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingXL),
                    children: [
                      _buildHero(),
                      const SizedBox(height: AppTheme.spacingXL),
                      _buildBody(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppTheme.spacingXL, 8, AppTheme.spacingXL, 20),
                  child: _buildActions(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon {
    switch (_step) {
      case _Step.offer:
        return Icons.rocket_launch_rounded;
      case _Step.needPermission:
        return Icons.shield_rounded;
      case _Step.downloading:
        return Icons.downloading_rounded;
      case _Step.installing:
        return Icons.install_mobile_rounded;
      case _Step.installCancelled:
        return Icons.pause_circle_rounded;
      case _Step.error:
        return Icons.error_outline_rounded;
    }
  }

  String get _title {
    switch (_step) {
      case _Step.offer:
        return 'Une nouvelle version\nd\'Aura est prête';
      case _Step.needPermission:
        return 'Une autorisation\nest nécessaire';
      case _Step.downloading:
        return 'Téléchargement\nen cours';
      case _Step.installing:
        return 'Installation';
      case _Step.installCancelled:
        return 'Installation\ninterrompue';
      case _Step.error:
        return 'Mise à jour\nimpossible';
    }
  }

  String get _subtitle {
    switch (_step) {
      case _Step.offer:
        return 'Reste à jour pour profiter des dernières améliorations.';
      case _Step.needPermission:
        return 'Autorise Aura à installer des applications dans les réglages, puis reviens ici : la mise à jour reprendra toute seule.';
      case _Step.downloading:
        return 'Ne ferme pas l\'application pendant le téléchargement.';
      case _Step.installing:
        return 'Confirme l\'installation, l\'application va redémarrer.';
      case _Step.installCancelled:
        return 'L\'installation n\'a pas été terminée. Tu peux réessayer.';
      case _Step.error:
        return _error ?? '';
    }
  }

  Widget _buildHero() {
    final failed = _step == _Step.error;
    final top = failed ? AppTheme.accentError : AppTheme.brandTop;
    final bottom = failed ? AppTheme.accentError : AppTheme.brandBottom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppTheme.spacingL),
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
            boxShadow: [
              BoxShadow(
                color: bottom.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: _step == _Step.installing
              ? const Padding(
                  padding: EdgeInsets.all(26),
                  child: CircularProgressIndicator(
                      strokeWidth: 3.5, color: Colors.white),
                )
              : Icon(_icon, color: Colors.white, size: 42),
        ),
        const SizedBox(height: AppTheme.spacingXL),
        if (_step == _Step.offer) ...[
          Wrap(
            spacing: 8,
            children: [
              _pill('v${widget.update.version}', filled: true),
              if (widget.update.size != null)
                _pill(_formatSize(widget.update.size!)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
        ],
        Text(
          _title,
          style: AppTheme.headlineMedium.copyWith(
            fontSize: 32,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        Text(_subtitle, style: AppTheme.bodyLarge.copyWith(
            color: AppTheme.textSecondary, height: 1.4)),
      ],
    );
  }

  Widget _pill(String text, {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: filled
            ? AppTheme.accentPrimary.withValues(alpha: 0.2)
            : AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(
          color: filled
              ? AppTheme.accentPrimary.withValues(alpha: 0.4)
              : AppTheme.border.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        text,
        style: AppTheme.labelMedium.copyWith(
          color: filled ? AppTheme.accentPrimary : AppTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_step == _Step.downloading) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacingL),
        decoration: BoxDecoration(
          color: AppTheme.backgroundCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusL),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${(_progress * 100).round()} %',
                style: AppTheme.headlineMedium
                    .copyWith(fontSize: 40, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppTheme.spacingM),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 10,
                color: AppTheme.accentPrimary,
                backgroundColor: AppTheme.textTertiary.withValues(alpha: 0.25),
              ),
            ),
            if (widget.update.size != null) ...[
              const SizedBox(height: AppTheme.spacingS),
              Text(
                '${_formatSize((widget.update.size! * _progress).round())} '
                'sur ${_formatSize(widget.update.size!)}',
                style: AppTheme.bodySmall,
              ),
            ],
          ],
        ),
      );
    }
    if (_step != _Step.offer) return const SizedBox.shrink();

    final notes = _notes;
    if (notes.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      decoration: BoxDecoration(
        color: AppTheme.backgroundCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
              Text('Nouveautés',
                  style: AppTheme.titleLarge
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.auto_awesome_rounded,
                        size: 16, color: AppTheme.accentPrimary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(n,
                        style: AppTheme.bodyMedium
                            .copyWith(color: AppTheme.textPrimary, height: 1.35)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _primary(String label, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        child: Ink(
          height: 56,
          decoration: BoxDecoration(
            gradient: AppTheme.brandGradient,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentPrimary.withValues(alpha: 0.4),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(label,
                  style: AppTheme.labelLarge
                      .copyWith(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _secondary(String label) => TextButton(
        onPressed: _close,
        style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14)),
        child: Text(label,
            style: AppTheme.labelLarge.copyWith(color: AppTheme.textTertiary)),
      );

  Widget _buildActions() {
    switch (_step) {
      case _Step.offer:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _primary('Mettre à jour', Icons.download_rounded, _start),
          _secondary('Pas maintenant'),
        ]);
      case _Step.needPermission:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _primary('Ouvrir les réglages', Icons.settings_rounded,
              _service.openInstallSettings),
          _secondary('Annuler'),
        ]);
      case _Step.downloading:
      case _Step.installing:
        return const SizedBox(height: 8);
      case _Step.installCancelled:
      case _Step.error:
        return Column(mainAxisSize: MainAxisSize.min, children: [
          _primary('Réessayer', Icons.refresh_rounded, _start),
          _secondary('Fermer'),
        ]);
    }
  }
}
