import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/media_theme_engine.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/data/models.dart';

// ════════════════════════════════════════════════════════════════
//  PREFETCH ENGINE — Predictive L3 pre-loading
// ════════════════════════════════════════════════════════════════
//
//  Triggers at 80% of current track duration to prefetch:
//
//  ┌──────────────────────────────────────┐
//  │  1. Palette extraction (isolate)     │  Next 2 queue tracks
//  │  2. Album art download (disk cache)  │  Next 2 queue tracks
//  │  3. Similar songs API call           │  Only if near queue-end + autoPlay
//  └──────────────────────────────────────┘
//
//  Guard rails:
//  ● Only triggers ONCE per song (debounced by song ID)
//  ● Skips if queue is empty or in radio/stream mode
//  ● Fire-and-forget with error swallowing — never blocks playback
//  ● Respects CachedNetworkImage's internal cache (no duplicate downloads)
//  ● Respects PaletteExtractor's per-ID cache (no re-computation)
//
//  Integration:
//    Called from PlayerNotifier's position stream listener.
//    PlayerNotifier passes { progress, duration, queue, currentIndex,
//    autoPlay, currentSongId } on every position tick (~5×/sec).
//    PrefetchEngine checks the 80% threshold and fires once.
//
// ════════════════════════════════════════════════════════════════

class PrefetchEngine {
  PrefetchEngine._();

  /// Tracks which song ID we've already prefetched for.
  /// Resets when the song changes — ensures exactly one prefetch cycle per song.
  static String? _lastPrefetchedSongId;

  /// Whether a prefetch is currently in progress (prevents overlapping).
  static bool _prefetching = false;

  /// Pre-fetched similar songs cache: songId → List<Song>
  /// Used by PlayerNotifier when it needs similar songs at queue end.
  static final Map<String, List<Song>> _similarCache = {};
  static const int _similarCacheMax = 30;

  // ════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════

  /// Call on every position tick. Internally gates to fire only once at 80%.
  ///
  /// [progress]      — current playback position in seconds
  /// [duration]      — total track duration in seconds
  /// [queue]         — current playback queue
  /// [currentIndex]  — index of the currently playing track in queue
  /// [currentSongId] — ID of the currently playing song
  /// [autoPlay]      — whether auto-play similar is enabled
  static void onPositionTick({
    required double progress,
    required double duration,
    required List<Song> queue,
    required int currentIndex,
    required String currentSongId,
    required bool autoPlay,
  }) {
    // ── Guard: skip short tracks, invalid state, or already-prefetched ──
    if (duration < 30) return; // Skip very short tracks
    if (currentIndex < 0 || queue.isEmpty) return;
    if (_lastPrefetchedSongId == currentSongId) return;
    if (_prefetching) return;

    // ── Check 80% threshold ──
    final threshold = duration * 0.80;
    if (progress < threshold) return;

    // ── Fire! ──
    _lastPrefetchedSongId = currentSongId;
    _prefetching = true;

    debugPrint('=== NINAADA PREFETCH: triggered at ${progress.toStringAsFixed(0)}s '
        '/ ${duration.toStringAsFixed(0)}s (${(progress / duration * 100).toStringAsFixed(0)}%) '
        'for queue[$currentIndex] ===');

    _executePrefetch(
      queue: queue,
      currentIndex: currentIndex,
      currentSongId: currentSongId,
      autoPlay: autoPlay,
    ).whenComplete(() => _prefetching = false);
  }

  /// Reset prefetch tracking — call when song changes
  /// (ensures the next song gets its own 80% trigger).
  static void onSongChanged(String newSongId) {
    if (_lastPrefetchedSongId != newSongId) {
      _lastPrefetchedSongId = null;
    }
  }

  /// Retrieve pre-fetched similar songs for a given song ID.
  /// Returns null if not yet prefetched. The caller (PlayerNotifier)
  /// can then fall back to a live API call.
  static List<Song>? getSimilar(String songId) => _similarCache[songId];

  /// Clear all prefetch caches.
  static void clearCache() {
    _similarCache.clear();
    _lastPrefetchedSongId = null;
    _prefetching = false;
  }

  // ════════════════════════════════════════════════
  //  INTERNAL — the actual prefetch work
  // ════════════════════════════════════════════════

  static Future<void> _executePrefetch({
    required List<Song> queue,
    required int currentIndex,
    required String currentSongId,
    required bool autoPlay,
  }) async {
    try {
      // ── Determine upcoming songs (next 2 in queue) ──
      final upcoming = <Song>[];
      for (int i = currentIndex + 1;
          i < queue.length && upcoming.length < 2;
          i++) {
        upcoming.add(queue[i]);
      }

      final nearQueueEnd = currentIndex >= queue.length - 2;

      // ── Fire all prefetch operations in parallel ──
      final futures = <Future>[];

      // 1. Palette pre-warm for next 2 tracks (isolate-based)
      if (upcoming.isNotEmpty) {
        futures.add(_prefetchPalettes(upcoming));
      }

      // 2. Album art pre-warm for next 2 tracks (CachedNetworkImage disk cache)
      if (upcoming.isNotEmpty) {
        futures.add(_prefetchAlbumArt(upcoming));
      }

      // 3. Similar songs API pre-fetch (only if near end + autoPlay)
      if (nearQueueEnd && autoPlay) {
        futures.add(_prefetchSimilar(currentSongId));
      }

      await Future.wait(futures);

      debugPrint('=== NINAADA PREFETCH: completed '
          '(${upcoming.length} palettes, '
          '${upcoming.length} art, '
          '${nearQueueEnd && autoPlay ? "similar" : "no-similar"}) ===');
    } catch (e) {
      debugPrint('=== NINAADA PREFETCH: error (non-fatal): $e ===');
    }
  }

  /// Pre-extract palettes for upcoming songs via isolate.
  /// Uses PaletteExtractor which has its own per-ID cache.
  static Future<void> _prefetchPalettes(List<Song> songs) async {
    try {
      await PaletteExtractor.preWarm(songs);
    } catch (e) {
      debugPrint('=== NINAADA PREFETCH: palette warm failed: $e ===');
    }
  }

  /// Pre-download album art into CachedNetworkImage's disk cache.
  /// resolve() triggers the download; the actual painting is skipped.
  static Future<void> _prefetchAlbumArt(List<Song> songs) async {
    for (final song in songs) {
      try {
        final url = safeImageUrl(song.image);
        // Resolve triggers download + disk-caching without rendering
        final provider = CachedNetworkImageProvider(url);
        final stream = provider.resolve(const ImageConfiguration());
        // We don't need the result — just kick-start the download.
        // Listening briefly ensures the stream starts fetching.
        final completer = Completer<void>();
        late ImageStreamListener listener;
        listener = ImageStreamListener(
          (_, __) {
            if (!completer.isCompleted) completer.complete();
            stream.removeListener(listener);
          },
          onError: (error, _) {
            if (!completer.isCompleted) completer.complete(); // swallow
            stream.removeListener(listener);
          },
        );
        stream.addListener(listener);
        // Timeout — don't block forever on slow images
        await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            stream.removeListener(listener);
          },
        );
      } catch (_) {
        // Swallow — prefetch is best-effort
      }
    }
  }

  /// Pre-fetch similar songs for the current track.
  /// Stored in _similarCache for instant retrieval at queue end.
  static Future<void> _prefetchSimilar(String songId) async {
    // Already cached?
    if (_similarCache.containsKey(songId)) return;

    try {
      final api = ApiService();
      final similar = await api.fetchSimilarSongs(songId);
      if (similar.isNotEmpty) {
        _evictSimilarIfNeeded();
        _similarCache[songId] = similar;
        debugPrint('=== NINAADA PREFETCH: cached ${similar.length} '
            'similar songs for $songId ===');
      }
    } catch (e) {
      debugPrint('=== NINAADA PREFETCH: similar fetch failed: $e ===');
    }
  }

  static void _evictSimilarIfNeeded() {
    while (_similarCache.length >= _similarCacheMax) {
      _similarCache.remove(_similarCache.keys.first);
    }
  }
}
