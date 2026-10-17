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

  const AppUpdate({required this.version, required this.apkUrl, this.size});
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

  /// Télécharge l'APK dans le cache de l'app. [onProgress] reçoit une
  /// valeur entre 0 et 1.
  Future<File> download(
    AppUpdate update, {
    required void Function(double progress) onProgress,
  }) async {
    final cache = await getTemporaryDirectory();
    final dir = Directory('${cache.path}/updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}/mood_player-${update.version}.apk');

    await _dio.download(
      update.apkUrl.toString(),
      file.path,
      options: Options(
        receiveTimeout: const Duration(minutes: 2),
        followRedirects: true,
      ),
      onReceiveProgress: (received, total) {
        final t = total > 0 ? total : (update.size ?? 0);
        if (t > 0) onProgress((received / t).clamp(0.0, 1.0));
      },
    );

    final expected = update.size;
    if (expected != null && await file.length() != expected) {
      await file.delete();
      throw const FileSystemException('Téléchargement incomplet');
    }
    return file;
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
