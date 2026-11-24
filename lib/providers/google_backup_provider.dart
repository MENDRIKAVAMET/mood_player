import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../services/backup_service.dart';
import '../services/google_drive_backup_service.dart';
import '../utils/app_error.dart';
import 'providers.dart';

/// Résultat d'une sauvegarde sur Google Drive.
enum GoogleBackupOutcome {
  /// Le fichier du compte est à jour.
  done,

  /// Rien à sauvegarder pour le moment, ou sauvegarde impossible (voir
  /// [GoogleBackupState.error]).
  skipped,

  /// Le compte contient une sauvegarde plus riche que les données de cet
  /// appareil : rien n'a été écrasé. L'appelant peut demander confirmation
  /// puis relancer avec `overwriteRicher: true`.
  remoteRicher,
}

class GoogleBackupState {
  final bool loaded;

  /// Adresse du compte connecté, null si l'utilisateur n'est pas connecté.
  final String? email;
  final bool enabled;
  final DateTime? lastBackupAt;
  final bool busy;
  final String? error;

  const GoogleBackupState({
    this.loaded = false,
    this.email,
    this.enabled = false,
    this.lastBackupAt,
    this.busy = false,
    this.error,
  });

  bool get connected => email != null;

  GoogleBackupState copyWith({
    bool? loaded,
    String? Function()? email,
    bool? enabled,
    DateTime? lastBackupAt,
    bool? busy,
    String? Function()? error,
  }) =>
      GoogleBackupState(
        loaded: loaded ?? this.loaded,
        email: email != null ? email() : this.email,
        enabled: enabled ?? this.enabled,
        lastBackupAt: lastBackupAt ?? this.lastBackupAt,
        busy: busy ?? this.busy,
        error: error != null ? error() : this.error,
      );
}

final googleBackupProvider =
    StateNotifierProvider<GoogleBackupController, GoogleBackupState>(
  (ref) => GoogleBackupController(ref),
);

/// Sauvegarde de toutes les données de l'app dans le Google Drive de
/// l'utilisateur (dossier caché de l'app, voir [GoogleDriveBackupService]).
///
/// Même logique que `AutoBackupController` : déclenchée au démarrage et à
/// la mise en arrière-plan, au plus une fois toutes les [minInterval], et
/// le fichier n'est réécrit que si les données ont changé.
class GoogleBackupController extends StateNotifier<GoogleBackupState> {
  static const Duration minInterval = Duration(minutes: 10);

  final Ref _ref;
  final GoogleDriveBackupService _service = GoogleDriveBackupService();
  late final Future<void> _ready = _load();

  DateTime? _lastAttempt;
  String? _lastDigest;

  /// Le fichier du compte n'est comparé aux données locales qu'une fois par
  /// session (voir [backupNow]).
  bool _remoteChecked = false;

  GoogleBackupController(this._ref) : super(const GoogleBackupState()) {
    _ready.ignore();
  }

  // ─────────────────────────── Réglages ───────────────────────────

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/google_backup.json');
  }

  Future<void> _load() async {
    String? email;
    var enabled = false;
    DateTime? last;
    try {
      final f = await _settingsFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          email = j['email'] as String?;
          enabled = j['enabled'] == true && email != null;
          last = j['lastBackupAt'] is String
              ? DateTime.tryParse(j['lastBackupAt'] as String)?.toLocal()
              : null;
        }
      }
    } catch (_) {
      // Fichier absent ou abîmé : on repart déconnecté.
    }
    if (!mounted) return;
    state = GoogleBackupState(
      loaded: true,
      email: email,
      enabled: enabled,
      lastBackupAt: last,
    );
  }

  Future<void> _persist() async {
    try {
      final f = await _settingsFile();
      await f.writeAsString(jsonEncode({
        'email': state.email,
        'enabled': state.enabled,
        'lastBackupAt': state.lastBackupAt?.toUtc().toIso8601String(),
      }));
    } catch (_) {
      // Le réglage reste valable pour la session.
    }
  }

  // ─────────────────────────── Connexion ───────────────────────────

  /// Ouvre la connexion Google. Retourne vrai si un compte est connecté ;
  /// faux si l'utilisateur a annulé ou si une erreur est survenue (voir
  /// [GoogleBackupState.error]).
  Future<bool> signIn() async {
    await _ready;
    state = state.copyWith(busy: true, error: () => null);
    try {
      final account = await _service.signIn();
      if (account == null) return false;
      _lastDigest = null;
      _remoteChecked = false;
      state = state.copyWith(email: () => account.email);
      await _persist();
      return true;
    } catch (e) {
      state = state.copyWith(error: () => _describe(e));
      return false;
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  Future<void> signOut() async {
    await _ready;
    await _service.signOut();
    _lastDigest = null;
    _remoteChecked = false;
    state = GoogleBackupState(
      loaded: true,
      email: null,
      enabled: false,
      lastBackupAt: state.lastBackupAt,
    );
    await _persist();
  }

  Future<void> setEnabled(bool enabled) async {
    await _ready;
    if (enabled && !state.connected) return;
    state = state.copyWith(enabled: enabled);
    await _persist();
  }

  /// Vrai si une session Google est utilisable ; tente de reprendre la
  /// précédente sans rien afficher.
  Future<bool> _ensureSession() async {
    if (_service.hasSession) return true;
    try {
      await _service.signInSilently();
    } catch (_) {
      // Pas de réseau, par exemple : traité comme « pas de session ».
    }
    if (_service.hasSession) return true;
    state = state.copyWith(
      error: () => 'Session Google expirée : reconnecte-toi.',
    );
    return false;
  }

  // ─────────────────────────── Lecture ───────────────────────────

  /// Sauvegarde du compte, si elle existe. Retourne null s'il n'y en a pas ;
  /// lève [BackupFormatException] (message affichable) en cas de problème.
  Future<BackupData?> readBackup() async {
    await _ready;
    if (!state.connected) return null;
    if (!await _ensureSession()) {
      throw GoogleDriveException(state.error ?? 'Connexion Google impossible.');
    }
    try {
      final text = await _service.readText();
      if (text == null || text.trim().isEmpty) return null;
      return BackupService.parse(text);
    } on BackupFormatException {
      rethrow;
    } catch (e) {
      throw GoogleDriveException(_describe(e));
    }
  }

  /// Comme [readBackup], mais sans jamais lever d'erreur.
  Future<BackupData?> peekBackup() async {
    try {
      return await readBackup();
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────── Écriture ───────────────────────────

  /// Éléments « de valeur » d'une sauvegarde : sert à repérer qu'on
  /// s'apprête à écraser une sauvegarde bien plus riche par des données
  /// presque vides (réinstallation, nouveau téléphone).
  static int _richness(BackupData d) =>
      d.classifiedCount +
      d.likedRefs.length +
      d.playCounts.length +
      d.customMoods.length;

  /// Sauvegarde maintenant. [force] ignore la limite de fréquence et le
  /// test « rien n'a changé ». Si le compte contient une sauvegarde plus
  /// riche que les données locales, rien n'est écrasé (résultat
  /// [GoogleBackupOutcome.remoteRicher]) sauf avec [overwriteRicher].
  Future<GoogleBackupOutcome> backupNow({
    bool force = false,
    bool overwriteRicher = false,
  }) async {
    await _ready;
    if (!state.connected || state.busy) return GoogleBackupOutcome.skipped;
    state = state.copyWith(busy: true, error: () => null);
    _lastAttempt = DateTime.now();
    try {
      if (!await _ensureSession()) return GoogleBackupOutcome.skipped;

      final data = await BackupService(_ref.read(storageServiceProvider))
          .buildBackup(
        profile: _ref.read(profileProvider),
        categories: {...BackupCategory.values},
      );
      // Rien à sauvegarder (app toute neuve, bibliothèque pas encore
      // chargée...) : on ne remplace surtout pas une sauvegarde existante
      // par un fichier vide.
      if (data.tracks.isEmpty && data.customMoods.isEmpty) {
        return GoogleBackupOutcome.skipped;
      }

      final json = data.toJson()..remove('exportedAt');
      final digest = jsonEncode(json);
      if (!force && digest == _lastDigest) return GoogleBackupOutcome.done;

      if (!overwriteRicher && (!_remoteChecked || force)) {
        final text = await _service.readText();
        if (text != null && text.trim().isNotEmpty) {
          BackupData? remote;
          try {
            remote = BackupService.parse(text);
          } catch (_) {
            remote = null; // Fichier illisible : on peut le remplacer.
          }
          if (remote != null && _richness(remote) > _richness(data)) {
            state = state.copyWith(
              error: () => 'Une sauvegarde plus complète existe sur ton '
                  'compte Google : restaure-la avant de sauvegarder.',
            );
            return GoogleBackupOutcome.remoteRicher;
          }
        }
        _remoteChecked = true;
      }

      await _service.writeText(jsonEncode(data.toJson()));
      _remoteChecked = true;
      _lastDigest = digest;
      state = state.copyWith(lastBackupAt: DateTime.now());
      await _persist();
      return GoogleBackupOutcome.done;
    } catch (e) {
      state = state.copyWith(error: () => _describe(e));
      return GoogleBackupOutcome.skipped;
    } finally {
      if (mounted) state = state.copyWith(busy: false);
    }
  }

  /// Appelée au démarrage et à la mise en arrière-plan : sauvegarde si
  /// l'option est active et que la dernière tentative n'est pas trop récente.
  Future<void> backupIfDue() async {
    await _ready;
    if (!state.enabled || !state.connected) return;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < minInterval) return;
    await backupNow();
  }

  // ─────────────────────────── Messages ───────────────────────────

  static String _describe(Object e) {
    if (e is GoogleDriveException) return e.message;
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 401) return 'Session Google expirée : reconnecte-toi.';
      if (status == 403) {
        return 'Google Drive a refusé l\'accès. Vérifie que l\'autorisation '
            'Drive a bien été accordée et que la Drive API est activée.';
      }
      if (status == 429) {
        return 'Trop de requêtes pour le moment. Réessaie dans quelques minutes.';
      }
      if (status == null) return 'Pas de connexion à Internet.';
    }
    if (e is PlatformException) {
      final text = '${e.code} ${e.message}'.toLowerCase();
      if (text.contains('network')) return 'Pas de connexion à Internet.';
      if (RegExp(r'apiexception: 10\b').hasMatch(text)) {
        return 'Configuration Google invalide (nom du package ou SHA-1 '
            'non reconnu dans Google Cloud).';
      }
      if (text.contains('apiexception: 12500')) {
        return 'Connexion Google impossible : vérifie l\'écran de '
            'consentement et ton compte testeur dans Google Cloud.';
      }
    }
    return friendlyError(e);
  }
}
