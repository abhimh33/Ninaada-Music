import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/data/models.dart';

// ════════════════════════════════════════════════════════════════
//  SESSION CONTEXT — Volatile real-time micro-context tracker
// ════════════════════════════════════════════════════════════════
//
//  Tracks the last 5 songs played in the CURRENT app session.
//  Completely volatile — clears on app kill / process death.
//  No Hive, no persistence — purely in-memory.
//
//  Purpose: Detect the user's *current mood* by analyzing the
//  most recent songs. If 2 of the last 3 songs share a genre
//  or language, that attribute becomes the [activeSessionVibe].
//
//  The RecommendationEngine reads this vibe and applies a 1.5×
//  multiplier to candidates that match.
//
// ════════════════════════════════════════════════════════════════

/// Maximum number of songs to track per session.
const int kSessionHistoryMax = 5;

/// Minimum frequency threshold: attribute must appear in at least
/// this many of the last [_kWindowSize] songs to become the vibe.
const int _kVibeThreshold = 2;
const int _kWindowSize = 3;

/// Multiplier applied to songs matching the active session vibe.
const double kSessionVibeMultiplier = 1.5;

// ────────────────────────────────────────────────
//  STATE
// ────────────────────────────────────────────────

class SessionContext {
  /// Last N songs played this session (most recent first).
  final List<Song> recentSongs;

  /// The detected dominant genre/language of the current micro-session.
  /// null = no dominant vibe detected yet (too few songs / too diverse).
  final String? activeSessionVibe;

  /// Whether the vibe is a genre match or a language match.
  final SessionVibeDimension vibeDimension;

  const SessionContext({
    this.recentSongs = const [],
    this.activeSessionVibe,
    this.vibeDimension = SessionVibeDimension.none,
  });

  SessionContext copyWith({
    List<Song>? recentSongs,
    String? activeSessionVibe,
    bool clearVibe = false,
    SessionVibeDimension? vibeDimension,
  }) {
    return SessionContext(
      recentSongs: recentSongs ?? this.recentSongs,
      activeSessionVibe: clearVibe ? null : (activeSessionVibe ?? this.activeSessionVibe),
      vibeDimension: clearVibe ? SessionVibeDimension.none : (vibeDimension ?? this.vibeDimension),
    );
  }

  /// Whether a candidate song matches the active session vibe.
  bool matchesVibe(Song candidate) {
    if (activeSessionVibe == null) return false;
    switch (vibeDimension) {
      case SessionVibeDimension.genre:
        return candidate.language.toLowerCase() == activeSessionVibe!.toLowerCase();
      case SessionVibeDimension.artist:
        return candidate.artist.toLowerCase().contains(activeSessionVibe!.toLowerCase());
      case SessionVibeDimension.none:
        return false;
    }
  }
}

enum SessionVibeDimension { none, genre, artist }

// ────────────────────────────────────────────────
//  NOTIFIER
// ────────────────────────────────────────────────

class SessionContextNotifier extends StateNotifier<SessionContext> {
  SessionContextNotifier() : super(const SessionContext());

  /// Record a song play event. Called from PlayerNotifier.
  void onSongPlayed(Song song) {
    final history = [song, ...state.recentSongs];
    final trimmed = history.length > kSessionHistoryMax
        ? history.sublist(0, kSessionHistoryMax)
        : history;

    // ── Detect dominant vibe from last 3 songs ──
    final window = trimmed.take(_kWindowSize).toList();
    String? detectedVibe;
    SessionVibeDimension dimension = SessionVibeDimension.none;

    if (window.length >= _kVibeThreshold) {
      // 1. Check genre/language dominance
      final genreCounts = <String, int>{};
      for (final s in window) {
        if (s.language.isNotEmpty) {
          final lang = s.language.toLowerCase();
          genreCounts[lang] = (genreCounts[lang] ?? 0) + 1;
        }
      }
      for (final entry in genreCounts.entries) {
        if (entry.value >= _kVibeThreshold) {
          detectedVibe = entry.key;
          dimension = SessionVibeDimension.genre;
          break;
        }
      }

      // 2. If no genre dominance, check artist dominance
      if (detectedVibe == null) {
        final artistCounts = <String, int>{};
        for (final s in window) {
          // Split comma-separated artists and count primary
          final primary = s.artist.split(RegExp(r'[,;]')).first.trim().toLowerCase();
          if (primary.isNotEmpty) {
            artistCounts[primary] = (artistCounts[primary] ?? 0) + 1;
          }
        }
        for (final entry in artistCounts.entries) {
          if (entry.value >= _kVibeThreshold) {
            detectedVibe = entry.key;
            dimension = SessionVibeDimension.artist;
            break;
          }
        }
      }
    }

    state = SessionContext(
      recentSongs: trimmed,
      activeSessionVibe: detectedVibe,
      vibeDimension: dimension,
    );
  }

  /// Clear the session (e.g., on queue clear / stop).
  void clear() {
    state = const SessionContext();
  }
}

// ────────────────────────────────────────────────
//  PROVIDER
// ────────────────────────────────────────────────

final sessionContextProvider =
    StateNotifierProvider<SessionContextNotifier, SessionContext>(
  (ref) => SessionContextNotifier(),
);
