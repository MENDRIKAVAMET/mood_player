import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/user_profile.dart';

/// Persiste le profil utilisateur dans un simple fichier JSON local -
/// même approche que le cache des paroles importées : pas besoin d'un
/// schéma Isar pour deux ou trois champs qui ne seront jamais interrogés
/// (filtrés, triés...), juste lus et réécrits en bloc.
class ProfileService {
  UserProfile? _cache;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/user_profile.json');
  }

  Future<UserProfile> load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        _cache = UserProfile.fromJson(Map<String, dynamic>.from(json));
      } else {
        _cache = const UserProfile.empty();
      }
    } catch (_) {
      // Fichier absent, corrompu... on repart d'un profil vide plutôt que
      // de bloquer le démarrage de l'app pour ça.
      _cache = const UserProfile.empty();
    }
    return _cache!;
  }

  Future<void> save(UserProfile profile) async {
    _cache = profile;
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(profile.toJson()));
    } catch (_) {
      // Le cache mémoire garde la valeur pour le reste de la session même
      // si l'écriture disque échoue.
    }
  }
}
