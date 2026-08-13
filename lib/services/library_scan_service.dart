import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';

/// Result of a device library scan.
class LibraryScanResult {
  final List<SongModel> songs;
  final bool permissionGranted;

  const LibraryScanResult({
    required this.songs,
    required this.permissionGranted,
  });
}

/// Scans the device's entire media library for audio files using Android's
/// MediaStore (via on_audio_query). This picks up every audio format the
/// system itself indexes (mp3, m4a/aac, flac, wav, ogg, opus, wma, amr...),
/// not just files the user manually imports, and gives accurate durations
/// straight from the OS instead of having to open every file to probe it.
class LibraryScanService {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  /// Request storage/audio permission if needed. Returns true if granted.
  ///
  /// Right after the OS permission dialog is dismissed, the Activity can
  /// briefly detach/reattach from the Flutter engine on some devices. If
  /// on_audio_query's native side receives a query call during that window,
  /// its internal (lateinit) Activity context isn't ready yet and it throws
  /// `PlatformException(..., lateinit property context has not been
  /// initialized, ...)`. Giving it a brief moment to settle right after a
  /// *fresh* grant (not when permission was already granted) avoids that
  /// race without adding any perceptible delay in the common case.
  Future<bool> requestPermission() async {
    final hasPermission = await _audioQuery.permissionsStatus();
    if (hasPermission) return true;

    final granted = await _audioQuery.permissionsRequest();
    if (granted) {
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return granted;
  }

  /// Query every audio file the device knows about.
  Future<LibraryScanResult> scan() async {
    final granted = await requestPermission();
    if (!granted) {
      return const LibraryScanResult(songs: [], permissionGranted: false);
    }

    final songs = await _querySongsWithRetry();
    return LibraryScanResult(songs: songs, permissionGranted: true);
  }

  /// Runs querySongs(), retrying once after a short delay if the plugin
  /// throws the "lateinit property context has not been initialized" race
  /// described above. A real permission/query error is rethrown as-is.
  Future<List<SongModel>> _querySongsWithRetry() async {
    try {
      return await _querySongs();
    } on PlatformException catch (e) {
      final isContextRace =
          (e.message ?? '').contains('has not been initialized');
      if (!isContextRace) rethrow;

      await Future.delayed(const Duration(milliseconds: 500));
      return await _querySongs();
    }
  }

  Future<List<SongModel>> _querySongs() {
    return _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      // Don't restrict to isMusic-flagged files only; some ripped/converted
      // files aren't tagged as "music" by the OS but are still valid audio.
      ignoreCase: true,
    );
  }
}
