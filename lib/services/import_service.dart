import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../models/track.dart';

class ImportService {
  /// Supported audio file extensions
  static const List<String> supportedExtensions = [
    '.mp3',
    '.wav',
    '.aac',
    '.ogg',
    '.flac',
    '.m4a',
    '.wma',
  ];

  /// Pick single audio file
  Future<ImportResult> pickAudioFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedExtensions.map((e) => e.substring(1)).toList(),
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult.cancelled();
      }

      final file = result.files.first;
      return _processFile(file);
    } catch (e) {
      return ImportResult.error('Erreur lors de la sélection du fichier: $e');
    }
  }

  /// Pick multiple audio files
  Future<ImportResult> pickMultipleAudioFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: supportedExtensions.map((e) => e.substring(1)).toList(),
        allowMultiple: true,
      );

      if (result == null || result.files.isEmpty) {
        return ImportResult.cancelled();
      }

      final tracks = <Track>[];
      final errors = <String>[];

      for (final file in result.files) {
        final importResult = _processFile(file);
        if (importResult.isSuccess && importResult.track != null) {
          tracks.add(importResult.track!);
        } else if (importResult.errorMessage != null) {
          errors.add(importResult.errorMessage!);
        }
      }

      if (tracks.isEmpty && errors.isNotEmpty) {
        return ImportResult.error(errors.join('\n'));
      }

      return ImportResult.success(
        tracks: tracks,
        errors: errors.isNotEmpty ? errors : null,
      );
    } catch (e) {
      return ImportResult.error('Erreur lors de la sélection des fichiers: $e');
    }
  }

  /// Pick folder and import all audio files
  Future<ImportResult> pickFolderAndImport() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();

      if (result == null) {
        return ImportResult.cancelled();
      }

      final directory = Directory(result);
      if (!await directory.exists()) {
        return ImportResult.error('Le dossier sélectionné n\'existe pas');
      }

      final tracks = <Track>[];
      final errors = <String>[];

      await for (final entity in directory.list(recursive: true)) {
        if (entity is File) {
          final ext = path.extension(entity.path).toLowerCase();
          if (supportedExtensions.contains(ext)) {
            final file = PlatformFile(
              name: path.basename(entity.path),
              path: entity.path,
              size: await entity.length(),
            );
            final importResult = _processFile(file);
            if (importResult.isSuccess && importResult.track != null) {
              tracks.add(importResult.track!);
            } else if (importResult.errorMessage != null) {
              errors.add(importResult.errorMessage!);
            }
          }
        }
      }

      if (tracks.isEmpty && errors.isNotEmpty) {
        return ImportResult.error(errors.join('\n'));
      }

      return ImportResult.success(
        tracks: tracks,
        errors: errors.isNotEmpty ? errors : null,
      );
    } catch (e) {
      return ImportResult.error('Erreur lors de l\'import du dossier: $e');
    }
  }

  ImportResult _processFile(PlatformFile file) {
    try {
      if (file.path == null) {
        return ImportResult.error('Chemin du fichier invalide: ${file.name}');
      }

      final filePath = file.path!;
      final fileName = path.basenameWithoutExtension(filePath);
      final fileExtension = path.extension(filePath).toLowerCase();

      // Check if file exists
      if (!File(filePath).existsSync()) {
        return ImportResult.error('Fichier introuvable: $fileName');
      }

      // Parse filename to extract metadata
      // Common formats: "Artist - Title", "Title", "Artist - Album - Title"
      final parsedMetadata = _parseFileName(fileName);

      final track = Track()
        ..title = parsedMetadata.title
        ..artist = parsedMetadata.artist
        ..album = parsedMetadata.album
        ..filePath = filePath
        ..createdAt = DateTime.now()
        ..updatedAt = DateTime.now();

      return ImportResult.success(tracks: [track]);
    } catch (e) {
      return ImportResult.error('Erreur lors du traitement de ${file.name}: $e');
    }
  }

  /// Parse filename to extract artist, album, and title
  /// Supports formats:
  /// - "Artist - Title"
  /// - "Artist - Album - Title"
  /// - "Title" (no artist)
  FileMetadata _parseFileName(String fileName) {
    // Remove common prefixes like track numbers "01. ", "01 - ", etc.
    final cleanName = fileName.replaceAll(RegExp(r'^\d+[\.\-\s]*'), '').trim();

    // Split by " - "
    final parts = cleanName.split(' - ');

    switch (parts.length) {
      case 1:
        return FileMetadata(
          title: parts[0].trim(),
          artist: 'Artiste inconnu',
        );
      case 2:
        return FileMetadata(
          artist: parts[0].trim(),
          title: parts[1].trim(),
        );
      case 3:
        return FileMetadata(
          artist: parts[0].trim(),
          album: parts[1].trim(),
          title: parts[2].trim(),
        );
      default:
        // More than 3 parts: first is artist, last is title, middle is album
        return FileMetadata(
          artist: parts[0].trim(),
          album: parts.sublist(1, parts.length - 1).join(' - ').trim(),
          title: parts.last.trim(),
        );
    }
  }
}

class FileMetadata {
  final String title;
  final String artist;
  final String? album;

  const FileMetadata({
    required this.title,
    required this.artist,
    this.album,
  });
}

class ImportResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? errorMessage;
  final List<Track>? tracks;
  final List<String>? errors;

  ImportResult._({
    required this.isSuccess,
    required this.isCancelled,
    this.errorMessage,
    this.tracks,
    this.errors,
  });

  factory ImportResult.success({List<Track>? tracks, List<String>? errors}) {
    return ImportResult._(
      isSuccess: true,
      isCancelled: false,
      tracks: tracks,
      errors: errors,
    );
  }

  factory ImportResult.cancelled() {
    return ImportResult._(
      isSuccess: false,
      isCancelled: true,
    );
  }

  factory ImportResult.error(String message) {
    return ImportResult._(
      isSuccess: false,
      isCancelled: false,
      errorMessage: message,
    );
  }

  /// Get total tracks imported
  int get trackCount => tracks?.length ?? 0;

  /// Get total errors
  int get errorCount => errors?.length ?? 0;
}