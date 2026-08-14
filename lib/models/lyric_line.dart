/// A single timestamped line of lyrics, as found in an LRC file.
class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});
}

/// Parses standard LRC-format synced lyrics
/// (e.g. `[00:12.34]Some lyric line`) into a sorted list of [LyricLine].
///
/// Handles the common variations: two- or three-digit fractional seconds
/// (`[00:12.3]` / `[00:12.345]`), multiple timestamps sharing one line of
/// text (`[00:12.34][00:45.67]Chorus`), and metadata tags like `[ar:]`
/// `[ti:]` `[al:]` `[length:]` which are simply skipped.
List<LyricLine> parseLrc(String lrc) {
  final timeTag = RegExp(r'\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  final lines = <LyricLine>[];

  for (final rawLine in lrc.split('\n')) {
    final matches = timeTag.allMatches(rawLine).toList();
    if (matches.isEmpty) continue;

    final text = rawLine.replaceAll(timeTag, '').trim();
    if (text.isEmpty) continue;

    for (final m in matches) {
      final minutes = int.parse(m.group(1)!);
      final seconds = int.parse(m.group(2)!);
      final fraction = m.group(3);
      final milliseconds = fraction == null
          ? 0
          : int.parse(fraction.padRight(3, '0').substring(0, 3));

      lines.add(LyricLine(
        timestamp: Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        ),
        text: text,
      ));
    }
  }

  lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return lines;
}
