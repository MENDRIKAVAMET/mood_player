import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Réglages de la sauvegarde automatique, gardés dans un petit fichier JSON
/// de l'app (comme le thème). Ils disparaissent avec l'app ; la sauvegarde,
/// elle, reste dans le dossier choisi.
class AutoBackupSettings {
  final bool enabled;
  final String? folderUri;
  final String? folderName;
  final DateTime? lastBackupAt;

  const AutoBackupSettings({
    this.enabled = false,
    this.folderUri,
    this.folderName,
    this.lastBackupAt,
  });

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'folderUri': folderUri,
        'folderName': folderName,
        'lastBackupAt': lastBackupAt?.toUtc().toIso8601String(),
      };

  factory AutoBackupSettings.fromJson(Map<String, dynamic> j) =>
      AutoBackupSettings(
        enabled: j['enabled'] == true,
        folderUri: j['folderUri'] as String?,
        folderName: j['folderName'] as String?,
        lastBackupAt: j['lastBackupAt'] is String
            ? DateTime.tryParse(j['lastBackupAt'] as String)?.toLocal()
            : null,
      );
}

/// Accès au dossier de sauvegarde choisi par l'utilisateur.
///
/// Un fichier dans un dossier de l'app (stockage interne ou
/// `Android/data/...`) est supprimé à la désinstallation. Ici, l'utilisateur
/// choisit un dossier de SON stockage (Documents, par exemple) via le
/// sélecteur Android : le fichier y reste après la désinstallation. À la
/// réinstallation, il suffit de choisir le même dossier pour le retrouver.
class AutoBackupService {
  static const MethodChannel _channel =
      MethodChannel('com.example.mood_player/backup_folder');

  static const String fileName = 'aura_sauvegarde_auto.json';

  /// Copie de la version précédente, gardée au cas où la dernière
  /// sauvegarde serait incomplète.
  static const String previousFileName =
      'aura_sauvegarde_auto_precedente.json';

  Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/auto_backup.json');
  }

  Future<AutoBackupSettings> loadSettings() async {
    try {
      final f = await _settingsFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          return AutoBackupSettings.fromJson(Map<String, dynamic>.from(j));
        }
      }
    } catch (_) {
      // Fichier absent ou abîmé : sauvegarde automatique désactivée.
    }
    return const AutoBackupSettings();
  }

  Future<void> saveSettings(AutoBackupSettings s) async {
    try {
      final f = await _settingsFile();
      await f.writeAsString(jsonEncode(s.toJson()));
    } catch (_) {
      // Le réglage reste valable pour la session.
    }
  }

  /// Ouvre le sélecteur de dossier Android. null = annulé.
  Future<({String uri, String name})?> pickFolder() async {
    final r = await _channel.invokeMapMethod<String, dynamic>('pickFolder');
    if (r == null) return null;
    return (uri: r['uri'] as String, name: (r['name'] as String?) ?? '');
  }

  /// Vrai si l'app a encore le droit d'écrire dans [folderUri].
  Future<bool> hasAccess(String folderUri) async {
    try {
      return await _channel
              .invokeMethod<bool>('hasAccess', {'tree': folderUri}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> write(String folderUri, String content) async {
    await _channel.invokeMethod<bool>('write', {
      'tree': folderUri,
      'name': fileName,
      'content': content,
      'prevName': previousFileName,
    });
  }

  /// Contenu du fichier de sauvegarde du dossier, ou null s'il n'y en a pas.
  Future<String?> read(String folderUri) =>
      _channel.invokeMethod<String>('read', {
        'tree': folderUri,
        'name': fileName,
      });
}
