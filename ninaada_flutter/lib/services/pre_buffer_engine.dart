import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/services/ninaada_audio_handler.dart';
import 'package:ninaada_music/services/prefetch_engine.dart';

// ================================================================
//  PRE-BUFFER ENGINE — Rolling 10-ahead queue replenishment
// ================================================================
//
//  Ensures the ConcatenatingAudioSource always has at least
//  [bufferTarget] upcoming AudioSources ready for instant playback.
//
//  Trigger points:
//    1. onTrackChanged callback (gapless advance, skip next/prev)
//    2. After playSong() completes
//
//  Replenishment strategy:
//    • Check L3 prefetch cache first (PrefetchEngine._similarCache)
//    • Fall back to live API call (fetchSimilarSongs)
//    • Append atomically via handler.appendToQueue (mutex-protected)
//    • No-op when autoPlay is disabled or queue has enough tracks
//
//  Guard rails:
//    • Single-flight: only one replenishment in progress at a time
//    • Per-song dedup: won't re-fetch for the same song twice
//    • Fire-and-forget: errors are logged but never block playback
// ================================================================

class PreBufferEngine {
  PreBufferEngine._(); // non-instantiable

  /// How many upcoming tracks to maintain ahead of the current index.
  static const int bufferTarget = 10;

  /// Prevents overlapping replenishment operations.
  static bool _replenishing = false;

  /// Last song ID we replenished for (prevents duplicate fetches).
  static String? _lastReplenishSongId;

  // ════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════

  /// Call after every track change. Checks if the queue needs
  /// replenishment and fires an async append if so.
  ///
  /// [handler]  — the singleton audio handler
  /// [autoPlay] — whether auto-play similar is enabled
  static void onTrackAdvanced({
    required NinaadaAudioHandler handler,
    required bool autoPlay,
  }) {
    if (!autoPlay) return;
    if (_replenishing) return;
    if (handler.inStreamMode) return;

    final q = handler.songQueue;
    final curIdx = handler.currentIndex;
    if (curIdx < 0 || q.isEmpty) return;

    final remaining = q.length - curIdx - 1;
    if (remaining >= bufferTarget) return;

    final current = handler.currentSong;
    if (current == null) return;
    if (_lastReplenishSongId == current.id) return;

    _replenishing = true;
    _lastReplenishSongId = current.id;

    _replenish(handler, current).whenComplete(() => _replenishing = false);
  }

  /// Reset state — call when queue is replaced or cleared.
  static void reset() {
    _replenishing = false;
    _lastReplenishSongId = null;
  }

  // ════════════════════════════════════════════════
  //  INTERNAL
  // ════════════════════════════════════════════════

  static Future<void> _replenish(
    NinaadaAudioHandler handler,
    Song seed,
  ) async {
    try {
      // 1. Try L3 prefetch cache
      List<Song>? similar = PrefetchEngine.getSimilar(seed.id);

      // 2. Fall back to live API
      similar ??= await ApiService().fetchSimilarSongs(seed.id);

      if (similar.isEmpty) return;

      // 3. Filter out the current song and existing queue IDs
      final existingIds = handler.songQueue.map((s) => s.id).toSet();
      final fresh = similar
          .where((s) => s.id != seed.id && !existingIds.contains(s.id))
          .toList();

      if (fresh.isEmpty) return;

      // 4. Append atomically (handler's mutex serializes this)
      await handler.appendToQueue(fresh);

      debugPrint('=== PRE-BUFFER: replenished +${fresh.length} tracks '
          '(queue now ${handler.songQueue.length}) ===');
    } catch (e) {
      debugPrint('=== PRE-BUFFER: replenish error (non-fatal): $e ===');
    }
  }
}
