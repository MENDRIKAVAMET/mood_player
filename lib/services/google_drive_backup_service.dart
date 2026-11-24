import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'backup_service.dart' show BackupFormatException;

/// Problème de sauvegarde Google Drive avec un message déjà prêt pour
/// l'utilisateur. Hérite de [BackupFormatException] pour être affiché tel
/// quel par l'écran d'import.
class GoogleDriveException extends BackupFormatException {
  const GoogleDriveException(super.message);
}

/// Connexion à un compte Google et stockage d'un fichier de sauvegarde dans
/// le dossier caché `appDataFolder` de Google Drive.
///
/// Ce dossier est réservé à l'app : le fichier n'apparaît pas dans le Drive
/// de l'utilisateur, et le scope `drive.appdata` ne donne accès à rien
/// d'autre. Les appels passent par l'API REST de Drive avec Dio : pas besoin
/// du paquet `googleapis`.
class GoogleDriveBackupService {
  static const String fileName = 'aura_sauvegarde.json';
  static const String _scope =
      'https://www.googleapis.com/auth/drive.appdata';
  static const String _api = 'https://www.googleapis.com';

  final GoogleSignIn _signIn = GoogleSignIn(scopes: const [_scope]);
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 40),
    receiveTimeout: const Duration(seconds: 40),
  ));

  GoogleSignInAccount? _account;

  bool get hasSession => _account != null;
  String? get email => _account?.email;

  /// Ouvre la fenêtre de connexion Google. null = l'utilisateur a annulé.
  Future<GoogleSignInAccount?> signIn() async {
    _account = await _signIn.signIn();
    return _account;
  }

  /// Reprend la session précédente sans rien afficher. null = pas de
  /// session (jamais connecté, ou accès retiré dans le compte Google).
  Future<GoogleSignInAccount?> signInSilently() async {
    _account = await _signIn.signInSilently();
    return _account;
  }

  Future<void> signOut() async {
    _account = null;
    try {
      await _signIn.signOut();
    } catch (_) {
      // Déjà déconnecté.
    }
  }

  /// Envoie une requête avec le jeton Google ; si le jeton a expiré (401),
  /// il est renouvelé et la requête est rejouée une fois.
  Future<Response<T>> _send<T>(
    Future<Response<T>> Function(Map<String, String> headers) call,
  ) async {
    final account = _account;
    if (account == null) {
      throw const GoogleDriveException(
          'Connecte-toi à ton compte Google pour continuer.');
    }
    try {
      return await call(await account.authHeaders);
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
      await account.clearAuthCache();
      return await call(await account.authHeaders);
    }
  }

  Future<String?> _findFileId() async {
    final r = await _send((h) => _dio.get<Map<String, dynamic>>(
          '$_api/drive/v3/files',
          queryParameters: {
            'spaces': 'appDataFolder',
            'q': "name = '$fileName' and trashed = false",
            'fields': 'files(id,modifiedTime)',
            'orderBy': 'modifiedTime desc',
            'pageSize': 1,
          },
          options: Options(headers: h),
        ));
    final files = (r.data?['files'] as List?) ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map)['id'] as String?;
  }

  /// Contenu du fichier de sauvegarde, ou null s'il n'y en a pas encore.
  Future<String?> readText() async {
    final id = await _findFileId();
    if (id == null) return null;
    final r = await _send((h) => _dio.get<String>(
          '$_api/drive/v3/files/$id',
          queryParameters: {'alt': 'media'},
          options: Options(headers: h, responseType: ResponseType.plain),
        ));
    return r.data;
  }

  /// Crée le fichier de sauvegarde, ou remplace son contenu s'il existe.
  Future<void> writeText(String content) async {
    final id = await _findFileId();
    if (id != null) {
      await _send((h) => _dio.patch<dynamic>(
            '$_api/upload/drive/v3/files/$id',
            queryParameters: {'uploadType': 'media'},
            data: content,
            options: Options(
              headers: h,
              contentType: 'text/plain; charset=utf-8',
            ),
          ));
      return;
    }

    const boundary = 'aura_backup_boundary_7f3a';
    final metadata = '{"name":"$fileName","parents":["appDataFolder"]}';
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$content\r\n'
        '--$boundary--';
    await _send((h) => _dio.post<dynamic>(
          '$_api/upload/drive/v3/files',
          queryParameters: {'uploadType': 'multipart'},
          data: body,
          options: Options(
            headers: h,
            contentType: 'multipart/related; boundary=$boundary',
          ),
        ));
  }
}
