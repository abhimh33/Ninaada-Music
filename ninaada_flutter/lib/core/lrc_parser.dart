// ════════════════════════════════════════════════════════════════
//  LRC PARSER — Phase 7: Immersive Playback Engine
// ════════════════════════════════════════════════════════════════
//
//  Pure Dart. Zero dependencies. Zero Flutter imports.
//
//  Parses standard .lrc formatted strings into a time-indexed
//  List<LyricLine> suitable for synchronized scrolling.
//
//  Supported formats:
//    [mm:ss.xx]  Text here       (centiseconds)
//    [mm:ss.xxx] Text here       (milliseconds)
//    [mm:ss]     Text here       (seconds only)
//    [mm:ss.xx]  [mm:ss.xx] Text (multi-timestamp — same text, two lines)
//
//  Also handles plain-text lyrics (no timestamps) by distributing
//  them evenly across the song duration for a graceful fallback.
//
//  Edge cases handled:
//    • Empty lines between lyrics     → filtered out
//    • Metadata tags [ti:], [ar:]     → stripped
//    • Duplicate timestamps           → de-duped
//    • Out-of-order timestamps        → sorted
//    • Last line endTime              → songDuration or startTime + 10s
//
// ════════════════════════════════════════════════════════════════

/// A single line of a time-synced lyric.
class LyricLine {
  /// When this line begins (inclusive).
  final Duration startTime;

  /// When this line ends (exclusive) — calculated from the next line's start.
  final Duration endTime;

  /// The lyric text for this line.
  final String text;

  const LyricLine({
    required this.startTime,
    required this.endTime,
    required this.text,
  });

  /// Whether [position] falls within this line's active window.
  bool isActive(Duration position) =>
      position >= startTime && position < endTime;

  @override
  String toString() => 'LyricLine(${startTime.inMilliseconds}ms–'
      '${endTime.inMilliseconds}ms: "$text")';
}

/// Pure Dart LRC parser — stateless, all static methods.
class LrcParser {
  LrcParser._();

  // ── Regex: matches [mm:ss.xx] or [mm:ss.xxx] or [mm:ss] ──
  static final _timestampRegex = RegExp(
    r'\[(\d{1,3}):(\d{2})(?:\.(\d{2,3}))?\]',
  );

  // ── Metadata tags to strip ──
  static final _metadataRegex = RegExp(
    r'^\[(ti|ar|al|au|by|offset|re|ve|length):',
    caseSensitive: false,
  );

  /// Parse an LRC string into a sorted [List<LyricLine>].
  ///
  /// [lrcText] — raw LRC content (may include metadata headers).
  /// [songDuration] — total song duration, used to set the last line's
  ///   endTime. If null, defaults to lastLine.startTime + 10 seconds.
  ///
  /// If the text contains NO timestamps at all, falls back to
  /// [parsePlainText] which distributes lines evenly.
  static List<LyricLine> parse(String lrcText, {Duration? songDuration}) {
    if (lrcText.trim().isEmpty) return const [];

    final rawLines = lrcText.split('\n');
    final parsed = <_RawLyric>[];

    for (final line in rawLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Skip metadata tags
      if (_metadataRegex.hasMatch(trimmed)) continue;

      // Extract all timestamps from this line
      final matches = _timestampRegex.allMatches(trimmed).toList();
      if (matches.isEmpty) continue;

      // The text is everything after the last timestamp bracket
      final lastMatch = matches.last;
      final text = trimmed.substring(lastMatch.end).trim();
      if (text.isEmpty) continue;

      // Each timestamp maps to the same text (multi-timestamp lines)
      for (final match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final subSecondStr = match.group(3);

        int milliseconds = 0;
        if (subSecondStr != null) {
          if (subSecondStr.length == 2) {
            // Centiseconds → milliseconds
            milliseconds = int.parse(subSecondStr) * 10;
          } else {
            // Already milliseconds
            milliseconds = int.parse(subSecondStr);
          }
        }

        final startTime = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );

        parsed.add(_RawLyric(startTime: startTime, text: text));
      }
    }

    // No timestamps found → fall back to plain text distribution
    if (parsed.isEmpty) {
      return parsePlainText(lrcText, songDuration: songDuration);
    }

    // Sort by start time (handles out-of-order LRC files)
    parsed.sort((a, b) => a.startTime.compareTo(b.startTime));

    // De-duplicate: same startTime → keep first occurrence
    final deduped = <_RawLyric>[];
    for (int i = 0; i < parsed.length; i++) {
      if (i == 0 || parsed[i].startTime != parsed[i - 1].startTime) {
        deduped.add(parsed[i]);
      }
    }

    // Calculate endTime for each line (= next line's startTime)
    final result = <LyricLine>[];
    for (int i = 0; i < deduped.length; i++) {
      final endTime = (i + 1 < deduped.length)
          ? deduped[i + 1].startTime
          : (songDuration ?? deduped[i].startTime + const Duration(seconds: 10));

      result.add(LyricLine(
        startTime: deduped[i].startTime,
        endTime: endTime,
        text: deduped[i].text,
      ));
    }

    return result;
  }

  /// Distribute plain-text lyrics evenly across the song duration.
  ///
  /// Used when the lyrics contain no LRC timestamps at all
  /// (e.g., Ninaada returns HTML lyrics without timing data).
  static List<LyricLine> parsePlainText(
    String text, {
    Duration? songDuration,
  }) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return const [];

    final totalMs =
        (songDuration ?? const Duration(minutes: 4)).inMilliseconds;
    final interval = totalMs ~/ lines.length;

    return List.generate(lines.length, (i) {
      final start = Duration(milliseconds: i * interval);
      final end = (i + 1 < lines.length)
          ? Duration(milliseconds: (i + 1) * interval)
          : Duration(milliseconds: totalMs);
      return LyricLine(startTime: start, endTime: end, text: lines[i]);
    });
  }

  /// Strip HTML tags from Ninaada lyrics responses.
  /// Ninaada often returns lyrics wrapped in <br>, <p>, etc.
  static String stripHtml(String html) {
    // Replace <br> and <br/> with newlines
    var cleaned = html.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    // Remove all other HTML tags
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]*>'), '');
    // Decode common HTML entities
    cleaned = cleaned
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return cleaned.trim();
  }

  /// Find the index of the active [LyricLine] for [position].
  ///
  /// Returns -1 if position is before the first line.
  /// Uses binary search for O(log n) performance on large lyric sets.
  static int findActiveIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    if (position < lines.first.startTime) return -1;
    if (position >= lines.last.startTime) return lines.length - 1;

    // Binary search: find the last line where startTime <= position
    int low = 0;
    int high = lines.length - 1;
    int result = -1;

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].startTime <= position) {
        result = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return result;
  }
}

/// Internal: raw parsed lyric before endTime calculation.
class _RawLyric {
  final Duration startTime;
  final String text;
  const _RawLyric({required this.startTime, required this.text});
}
