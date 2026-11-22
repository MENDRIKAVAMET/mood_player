import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auto_backup_service.dart';
import '../services/backup_service.dart';
import 'providers.dart';

class AutoBackupState {
  final bool loaded;
  final bool enabled;
  final String? folderUri;
  final String? folderName;
  final DateTime? lastBackupAt;
  final bool busy;

  /// Dernier problème (dossier inaccessible...), null si tout va bien.
  final String? error;

  const AutoBackupState({
    this.loaded = false,
    this.enabled = false,
    this.folderUri,
    this.folderName,
    this.lastBackupAt,
    this.busy = false,
    this.error,
  });

  bool get hasFolder => folderUri != null;

  AutoBackupState copyWith({
    bool? loaded,
    bool? enabled,
    String? Function()? folderUri,
    String? Function()? folderName,
    DateTime? lastBackupAt,
    bool? busy,
    String? Function()? error,
  }) =>
      AutoBackupState(
        loaded: loaded ?? this.loaded,
        enabled: enabled ?? this.enabled,
        folderUri: folderUri != null ? folderUri() : this.folderUri,
        folderName: folderName != null ? folderName() : this.folderName,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        busy: busy ?? this.busy,
        error: error != null ? error() : this.error,
      );
}

final autoBackupProvider =
    StateNotifierProvider<AutoBackupController, AutoBackupState>(
  (ref) => AutoBackupController(ref),
);

/// Sauvegarde automatique de toutes les données de l'app dans un fichier du
/// dossier choisi par l'utilisateur (voir [AutoBackupService]).
///
/// Déclenchée quand l'app passe en arrière-plan et peu après le démarrage,
/// au plus une fois toutes les [minInterval] ; le fichier n'est réécrit que
/// si les données ont changé.
class AutoBackupController extends StateNotifier<AutoBackupState> {
  static const Duration minInterval = Duration(minutes: 5);

  final Ref _ref;
  final AutoBackupService _service = AutoBackupService();
  late final Future<void> _ready = _load();

  DateTime? _lastAttempt;
  String? _lastDigest;

  AutoBackupController(this._ref) : super(const AutoBackupState()) {
    _ready.ignore();
  }

  Future<void> _load() async {
    final s = await _service.loadSettings();
    if (!mounted) return;
    state = AutoBackupState(
      loaded: true,
      enabled: s.enabled && s.folderUri != null,
      folderUri: s.folderUri,
      folderName: s.folderName,
      lastBackupAt: s.lastBackupAt,
    );
  }

  Future<void> _persist() => _service.saveSettings(AutoBackupSettings(
        enabled: state.enabled,
        folderUri: state.folderUri,
        folderName: state.folderName,
        lastBackupAt: state.lastBackupAt,
      ));

  BackupService get _backup =>
      BackupService(_ref.read(storageServiceProvider));

  /// Ouvre le sélecteur de dossier. Retourne vrai si un dossier a été choisi.
  Future<bool> chooseFolder() async {
    await _ready;
    final picked = await _service.pickFolder();
    if (picked == null) return false;
    _lastDigest = null;
    state = state.copyWith(
      folderUri: () => picked.uri,
      folderName: () => picked.name,
      error: () => null,
    );
    await _persist();
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    await _ready;
    if (enabled && !state.hasFolder) return;
    state = state.copyWith(enabled: enabled);
    await _persist();
  }

  /// Sauvegarde du dossier, si elle existe et qu'elle est lisible.
  /// Retourne null s'il n'y en a pas ; lève [BackupFormatException] si le
  /// fichier existe mais n'est pas utilisable.
  Future<BackupData?> readBackup() async {
    await _ready;
    final uri = state.folderUri;
    if (uri == null) return null;
    final text = await _service.read(uri);
    if (text == null || text.trim().isEmpty) return null;
    return BackupService.parse(text);
  }

  /// Comme [readBackup], mais sans jamais lever d'erreur.
  Future<BackupData?> peekBackup() async {
    try {
      return await readBackup();
    } catch (_) {
      return null;
    }
  }

  /// Sauvegarde maintenant. [force] ignore la limite de fréquence et le
  /// test « rien n'a changé ». Retourne vrai si le fichier est à jour.
  Future<bool> backupNow({bool force = false}) async {
    await _ready;
    final uri = state.folderUri;
    if (uri == null || state.busy) return false;
    state = state.copyWith(busy: true, error: () => null);
    _lastAttempt = DateTime.now();
    try {
      if (!await _service.hasAccess(uri)) {
        state = state.copyWith(
          error: () => 'Dossier inaccessible : choisissez-le à nouveau.',
        );
        return false;
      }
      final data = await _backup.buildBackup(
        profile: _ref.read(profileProvider),
        categories: {...BackupCategory.values},
      );
      // Rien à sauvegarder (app toute neuve, bibliothèque pas encore
      // chargée...) : on ne remplace surtout pas une sauvegarde existante
      // par un fichier vide.
      if (data.tracks.isEmpty && data.customMoods.isEmpty) return false;

      final json = data.toJson()..remove('exportedAt');
      final digest = jsonEncode(json);
      if (!force && digest == _lastDigest) return true;

      await _service.write(uri, jsonEncode(data.toJson()));
      _lastDigest = digest;
      state = state.copyWith(lastBackupAt: DateTime.now());
      await _persist();
      return true;
    } catch (e) {
      state = state.copyWith(error: () => 'Sauvegarde impossible : $e');
      return false;
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Appelée au démarrage et à la mise en arrière-plan : sauvegarde si
  /// l'option est active et que la dernière tentative n'est pas trop récente.
  Future<void> backupIfDue() async {
    await _ready;
    if (!state.enabled || !state.hasFolder) return;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < minInterval) return;
    await backupNow();
  }
}
