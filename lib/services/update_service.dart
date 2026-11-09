import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Une version plus récente publiée sur GitHub Releases.
class AppUpdate {
  /// Numéro de version sans le « v » (ex. « 1.0.9 »).
  final String version;
  final Uri apkUrl;

  /// Taille annoncée de l'APK en octets (sert à la progression et à
  /// vérifier que le téléchargement est complet).
  final int? size;

  /// Notes de la release GitHub (corps du texte), affichées comme
  /// « Nouveautés » dans l'écran de mise à jour. Peut être vide.
  final String notes;

  const AppUpdate({
    required this.version,
    required this.apkUrl,
    this.size,
    this.notes = '',
  });
}

/// État local d'une mise à jour : APK complet, partiel ou rien.
class LocalUpdateState {
  /// APK complet, prêt à être installé (null sinon).
  final File? apk;

  /// Octets déjà écrits sur le disque (APK complet ou fichier partiel).
  final int downloadedBytes;

  const LocalUpdateState({this.apk, this.downloadedBytes = 0});

  bool get isComplete => apk != null;
  bool get isPartial => apk == null && downloadedBytes > 0;
}

/// Vérifie les releases GitHub du dépôt, télécharge l'APK et lance
/// l'installation (côté Android, voir `MainActivity.kt`).
///
/// Le dépôt est public : l'API ne demande aucune clé. La mise à jour n'est
/// proposée que si le numéro de version de la dernière release est
/// strictement supérieur à celui de l'app installée ; Android vérifie de
/// toute façon que l'APK est signé avec la même clé que l'app en place.
class UpdateService {
  static const String repo = 'MENDRIKAVAMET/mood_player';
  static const MethodChannel _channel =
      MethodChannel('com.example.mood_player/updater');

  final Dio _dio;

  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {'Accept': 'application/vnd.github+json'},
            ));

  /// Compare deux versions « 1.2.3 » (un « v » initial et un suffixe
  /// « +build » sont ignorés). > 0 si [a] est plus récente que [b].
  static int compareVersions(String a, String b) {
    List<int> parse(String v) {
      var s = v.trim();
      if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
      s = s.split('+').first.split('-').first;
      return s.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final pa = parse(a), pb = parse(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  /// La dernière release si elle est plus récente que l'app installée,
  /// sinon null. Toute erreur (hors ligne, limite d'API, release sans APK…)
  /// renvoie null : une vérification de mise à jour ne doit jamais gêner
  /// l'ouverture de l'app.
  Future<AppUpdate?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final res = await _dio
          .get<Map<String, dynamic>>('https://api.github.com/repos/$repo/releases/latest');
      final data = res.data;
      if (data == null) return null;
      if (data['draft'] == true || data['prerelease'] == true) return null;

      final tag = data['tag_name'];
      if (tag is! String) return null;
      if (compareVersions(tag, info.version) <= 0) return null;

      final assets = data['assets'];
      if (assets is! List) return null;
      for (final a in assets) {
        if (a is! Map) continue;
        final name = a['name'];
        final url = a['browser_download_url'];
        if (name is String &&
            name.toLowerCase().endsWith('.apk') &&
            url is String) {
          final uri = Uri.tryParse(url);
          // N'accepte que le téléchargement depuis GitHub.
          if (uri == null || uri.scheme != 'https' || !_isGithubHost(uri.host)) {
            continue;
          }
          final size = a['size'];
          return AppUpdate(
            version: tag.startsWith('v') ? tag.substring(1) : tag,
            apkUrl: uri,
            size: size is int ? size : null,
            notes: data['body'] is String ? (data['body'] as String).trim() : '',
          );
        }
      }
    } catch (_) {
      // Silencieux, voir ci-dessus.
    }
    return null;
  }

  static bool _isGithubHost(String host) =>
      host == 'github.com' || host.endsWith('.github.com') ||
      host.endsWith('.githubusercontent.com');

  /// Dossier persistant où l'APK est écrit (`files/updates`). Contrairement
  /// au cache, Android ne le vide pas tout seul : un téléchargement
  /// interrompu peut donc être repris plus tard.
  Future<Directory> updatesDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  File _apkFile(Directory dir, AppUpdate u) =>
      File('${dir.path}/aura-${u.version}.apk');
  File _partFile(Directory dir, AppUpdate u) =>
      File('${dir.path}/aura-${u.version}.apk.part');

  /// Ce qui est déjà sur le disque pour [update] : APK complet (prêt à
  /// installer) ou téléchargement partiel (à reprendre). Supprime au
  /// passage les fichiers des autres versions.
  Future<LocalUpdateState> localState(AppUpdate update) async {
    final dir = await updatesDir();
    final apk = _apkFile(dir, update);
    final part = _partFile(dir, update);

    await for (final e in dir.list()) {
      if (e is File && e.path != apk.path && e.path != part.path) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }

    final expected = update.size;
    if (await apk.exists()) {
      final len = await apk.length();
      if (expected == null || len == expected) {
        return LocalUpdateState(apk: apk, downloadedBytes: len);
      }
      await apk.delete(); // Fichier corrompu / incomplet.
    }
    if (await part.exists()) {
      final len = await part.length();
      if (len > 0 && (expected == null || len < expected)) {
        return LocalUpdateState(downloadedBytes: len);
      }
      await part.delete();
    }
    return const LocalUpdateState();
  }

  /// Télécharge l'APK dans [updatesDir]. Reprend là où le téléchargement
  /// s'était arrêté si un fichier partiel existe, et renvoie directement
  /// l'APK s'il est déjà complet. [onProgress] reçoit une valeur entre 0
  /// et 1.
  Future<File> download(
    AppUpdate update, {
    required void Function(double progress) onProgress,
    bool allowResume = true,
  }) async {
    final dir = await updatesDir();
    final apk = _apkFile(dir, update);
    final part = _partFile(dir, update);
    final expected = update.size;

    final state = await localState(update);
    if (state.isComplete) {
      onProgress(1);
      return state.apk!;
    }

    var existing = allowResume && await part.exists() ? await part.length() : 0;
    if (existing == 0 && await part.exists()) await part.delete();

    final res = await _dio.get<ResponseBody>(
      update.apkUrl.toString(),
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 2),
        followRedirects: true,
        headers: existing > 0 ? {'range': 'bytes=$existing-'} : null,
        validateStatus: (c) => c == 200 || c == 206 || c == 416,
      ),
    );

    if (res.statusCode == 416) {
      // Le fichier partiel ne correspond plus : on repart de zéro.
      await part.delete();
      if (!allowResume) throw const FileSystemException('Reprise impossible');
      return download(update, onProgress: onProgress, allowResume: false);
    }

    // 206 = le serveur reprend à l'octet demandé ; 200 = il renvoie tout.
    final resumed = res.statusCode == 206 && existing > 0;
    if (!resumed) existing = 0;

    final contentLength =
        int.tryParse(res.headers.value(Headers.contentLengthHeader) ?? '');
    final total = expected ??
        (contentLength != null ? contentLength + existing : 0);

    var received = existing;
    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    try {
      if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
      await for (final chunk in res.data!.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
      }
      await sink.flush();
    } finally {
      // Le fichier partiel est conservé en cas d'erreur pour la reprise.
      await sink.close();
    }

    final len = await part.length();
    if (expected != null && len != expected) {
      if (len > expected) await part.delete();
      throw const FileSystemException('Téléchargement incomplet');
    }
    if (await apk.exists()) await apk.delete();
    await part.rename(apk.path);
    return apk;
  }

  /// Android autorise-t-il cette app à installer des APK ?
  Future<bool> canInstall() async =>
      (await _channel.invokeMethod<bool>('canInstall')) ?? false;

  /// Ouvre le réglage « Installer des applications inconnues » de l'app.
  Future<void> openInstallSettings() =>
      _channel.invokeMethod<void>('openInstallSettings');

  /// Lance l'installateur système sur [apk].
  Future<void> install(File apk) =>
      _channel.invokeMethod<void>('installApk', {'path': apk.path});
}
