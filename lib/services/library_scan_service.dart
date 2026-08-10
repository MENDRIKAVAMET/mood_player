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
  Future<bool> requestPermission() async {
    final hasPermission = await _audioQuery.permissionsStatus();
    if (hasPermission) return true;
    return await _audioQuery.permissionsRequest();
  }

  /// Query every audio file the device knows about.
  Future<LibraryScanResult> scan() async {
    final granted = await requestPermission();
    if (!granted) {
      return const LibraryScanResult(songs: [], permissionGranted: false);
    }

    final songs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      // Don't restrict to isMusic-flagged files only; some ripped/converted
      // files aren't tagged as "music" by the OS but are still valid audio.
      ignoreCase: true,
    );

    return LibraryScanResult(songs: songs, permissionGranted: true);
  }
}
