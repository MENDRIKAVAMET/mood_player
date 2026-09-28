import 'dart:io';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

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
  /// on_audio_query 2.x predates Android 13's split media permissions and
  /// still asks for READ_EXTERNAL_STORAGE, which the system silently
  /// ignores on API 33+: the dialog appears, the user grants it, and every
  /// MediaStore query then comes back empty. permission_handler knows the
  /// difference, so the actual request goes through it - Permission.audio
  /// maps to READ_MEDIA_AUDIO on API 33+ and to READ_EXTERNAL_STORAGE
  /// below that.
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
    if (!Platform.isAndroid) {
      // on_audio_query's own check is fine on other platforms.
      return await _audioQuery.permissionsStatus();
    }

    // Permission.audio is READ_MEDIA_AUDIO (Android 13+);
    // Permission.storage is READ_EXTERNAL_STORAGE (Android 12 and below).
    // Rather than probing the SDK level, try whichever one the device
    // actually honours: the irrelevant one simply reports as denied/
    // restricted and is ignored.
    if (await Permission.audio.isGranted) return true;
    if (await Permission.storage.isGranted) return true;

    final audioStatus = await Permission.audio.request();
    if (audioStatus.isGranted) {
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }

    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) {
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }

    return false;
  }

  /// Whether the audio permission was permanently denied, meaning the OS
  /// will no longer show the dialog and the user has to go through app
  /// settings.
  Future<bool> isPermissionPermanentlyDenied() async {
    if (!Platform.isAndroid) return false;
    return await Permission.audio.isPermanentlyDenied ||
        await Permission.storage.isPermanentlyDenied;
  }

  /// Opens the app's system settings page so the user can grant the
  /// permission after a permanent denial.
  Future<void> openPermissionSettings() => openAppSettings();

  /// Query every audio file the device knows about.
  Future<LibraryScanResult> scan() async {
    final granted = await requestPermission();
    if (!granted) {
      return const LibraryScanResult(songs: [], permissionGranted: false);
    }

    final songs = await _querySongsWithRetry();
    return LibraryScanResult(songs: songs, permissionGranted: true);
  }

  /// Runs querySongs(), retrying the "lateinit property context has not
  /// been initialized" race described above with backoff. On slower
  /// devices/cold starts, on_audio_query's native side can still not be
  /// attached to the Activity a full second after the first frame, so a
  /// single 500ms retry wasn't always enough - this retries up to 5 times
  /// with growing delays (total ~6s worst case) before giving up. A real
  /// permission/query error (not this race) is rethrown immediately.
  Future<List<SongModel>> _querySongsWithRetry() async {
    const delays = [
      Duration(milliseconds: 500),
      Duration(milliseconds: 800),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 2),
    ];

    for (var attempt = 0; ; attempt++) {
      try {
        return await _querySongs();
      } on PlatformException catch (e) {
        final isContextRace =
            (e.message ?? '').contains('has not been initialized');
        if (!isContextRace || attempt >= delays.length) rethrow;

        await Future.delayed(delays[attempt]);
      }
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
