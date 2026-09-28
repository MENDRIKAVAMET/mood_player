import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/lyrics_service.dart';

final lyricsServiceProvider = Provider<LyricsService>((ref) => LyricsService());

/// Fetches lyrics for a given track. Keyed by a record (title, artist,
/// duration, filePath) rather than the Track object itself - records have
/// structural equality, so this caches correctly even if a fresh Track
/// instance with the same data is passed in, unlike relying on Track's
/// (default, identity-based) equality. autoDispose clears the cache entry
/// once nothing is watching it anymore.
final lyricsProvider = FutureProvider.family.autoDispose<LyricsResult,
    (String title, String artist, int? durationMs, String? filePath)>(
        (ref, key) async {
  final service = ref.watch(lyricsServiceProvider);
  return service.fetch(
    title: key.$1,
    artist: key.$2,
    duration: key.$3 != null ? Duration(milliseconds: key.$3!) : null,
    filePath: key.$4,
  );
});

/// Convenience to build the provider's key from a [Track].
(String, String, int?, String?) lyricsKeyFor(Track track) =>
    (track.title, track.artist, track.duration, track.filePath);
