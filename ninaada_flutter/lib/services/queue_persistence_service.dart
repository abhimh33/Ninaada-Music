import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ninaada_music/core/queue_manager.dart';

// ================================================================
//  QUEUE PERSISTENCE SERVICE — Phase 8: State Restoration
// ================================================================
//
//  Persists the playback queue state to Hive so the app can restore
//  the exact queue after an OS kill / cold boot.
//
//  Architecture:
//  ┌────────────────────────────────────────────────────────────┐
//  │  Throttled Write Pipeline (5-second debounce)              │
//  │                                                            │
//  │  trackChanged / queueMutated                               │
//  │       ↓                                                    │
//  │  scheduleWrite(snapshot, positionMs)                        │
//  │       ↓                                                    │
//  │  _debounceTimer (5s) ── cancel previous pending write      │
//  │       ↓                                                    │
//  │  _persist() → Hive.put('queue_state', json)                │
//  └────────────────────────────────────────────────────────────┘
//
//  Data Shape (JSON in Hive 'playback_state' box):
//  {
//    "snapshot": { ... QueueSnapshot.toJson() },
//    "positionMs": 42000,
//    "shuffle": false,
//    "repeat": "off",
//    "autoPlay": true,
//    "playbackSpeed": 1.0,
//    "savedAt": 1718000000000
//  }
//
//  Cold Boot Read:
//    QueuePersistenceService.loadSavedState() → SavedPlaybackState?
//    Max staleness: 7 days (auto-clears ancient snapshots).
// ================================================================

/// Saved playback state for cold boot restoration.
class SavedPlaybackState {
  final QueueSnapshot snapshot;
  final int positionMs;
  final bool shuffle;
  final String repeat;
  final bool autoPlay;
  final double playbackSpeed;
  final DateTime savedAt;

  const SavedPlaybackState({
    required this.snapshot,
    required this.positionMs,
    required this.shuffle,
    required this.repeat,
    required this.autoPlay,
    required this.playbackSpeed,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'snapshot': snapshot.toJson(),
        'positionMs': positionMs,
        'shuffle': shuffle,
        'repeat': repeat,
        'autoPlay': autoPlay,
        'playbackSpeed': playbackSpeed,
        'savedAt': savedAt.millisecondsSinceEpoch,
      };

  factory SavedPlaybackState.fromJson(Map<String, dynamic> json) {
    return SavedPlaybackState(
      snapshot: QueueSnapshot.fromJson(
        json['snapshot'] as Map<String, dynamic>,
      ),
      positionMs: (json['positionMs'] as int?) ?? 0,
      shuffle: (json['shuffle'] as bool?) ?? false,
      repeat: (json['repeat'] as String?) ?? 'off',
      autoPlay: (json['autoPlay'] as bool?) ?? true,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      savedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['savedAt'] as int?) ?? 0,
      ),
    );
  }
}

/// Singleton service for persisting and restoring queue state.
class QueuePersistenceService {
  QueuePersistenceService._();
  static final QueuePersistenceService _instance =
      QueuePersistenceService._();
  static QueuePersistenceService get instance => _instance;

  static const String _boxName = 'playback_state';
  static const String _key = 'queue_state';
  static const Duration _debounceDelay = Duration(seconds: 5);

  /// Max staleness — saved states older than 7 days are auto-cleared.
  static const Duration _maxStaleness = Duration(days: 7);

  Box? _box;
  Timer? _debounceTimer;

  /// Pending write data — accumulated while debounce timer is active.
  Map<String, dynamic>? _pendingWrite;

  // ══════════════════════════════════════════════════
  //  INITIALIZATION
  // ══════════════════════════════════════════════════

  /// Initialize the persistence service. Call once during app startup.
  Future<void> init() async {
    try {
      _box = await Hive.openBox(_boxName);
      debugPrint('=== QUEUE PERSIST: initialized ===');
    } catch (e) {
      debugPrint('=== QUEUE PERSIST: init FAILED: $e ===');
    }
  }

  // ══════════════════════════════════════════════════
  //  THROTTLED WRITE
  // ══════════════════════════════════════════════════

  /// Schedule a debounced write of the current playback state.
  /// Replaces any pending write — only the latest snapshot is persisted.
  ///
  /// Call this on:
  /// - Track changes (gapless advance / user skip)
  /// - Queue mutations (add, remove, reorder)
  /// - Periodic position snapshots
  void scheduleWrite({
    required QueueSnapshot snapshot,
    required int positionMs,
    bool shuffle = false,
    String repeat = 'off',
    bool autoPlay = true,
    double playbackSpeed = 1.0,
  }) {
    if (snapshot.isEmpty) return;

    _pendingWrite = SavedPlaybackState(
      snapshot: snapshot,
      positionMs: positionMs,
      shuffle: shuffle,
      repeat: repeat,
      autoPlay: autoPlay,
      playbackSpeed: playbackSpeed,
      savedAt: DateTime.now(),
    ).toJson();

    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, _persist);
  }

  /// Force an immediate write (e.g., on app background / onTaskRemoved).
  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    if (_pendingWrite != null) {
      await _persist();
    }
  }

  Future<void> _persist() async {
    final data = _pendingWrite;
    if (data == null || _box == null) return;
    _pendingWrite = null;

    try {
      await _box!.put(_key, jsonEncode(data));
      debugPrint('=== QUEUE PERSIST: saved (${data['snapshot']?['items']?.length ?? 0} songs) ===');
    } catch (e) {
      debugPrint('=== QUEUE PERSIST: write FAILED: $e ===');
    }
  }

  // ══════════════════════════════════════════════════
  //  COLD BOOT READ
  // ══════════════════════════════════════════════════

  /// Load the saved playback state from Hive.
  /// Returns null if no saved state, or if the state is stale (>7 days).
  SavedPlaybackState? loadSavedState() {
    if (_box == null) return null;

    try {
      final raw = _box!.get(_key);
      if (raw == null) return null;

      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final saved = SavedPlaybackState.fromJson(json);

      // Staleness check
      if (DateTime.now().difference(saved.savedAt) > _maxStaleness) {
        debugPrint('=== QUEUE PERSIST: stale state (${saved.savedAt}), clearing ===');
        clearSavedState();
        return null;
      }

      if (saved.snapshot.isEmpty) return null;

      debugPrint(
        '=== QUEUE PERSIST: loaded ${saved.snapshot.items.length} songs, '
        'index=${saved.snapshot.currentIndex}, '
        'pos=${saved.positionMs}ms ===',
      );
      return saved;
    } catch (e) {
      debugPrint('=== QUEUE PERSIST: load FAILED: $e ===');
      return null;
    }
  }

  // ══════════════════════════════════════════════════
  //  CLEAR
  // ══════════════════════════════════════════════════

  /// Clear saved state (e.g., on explicit queue dismiss).
  Future<void> clearSavedState() async {
    _debounceTimer?.cancel();
    _pendingWrite = null;
    try {
      await _box?.delete(_key);
      debugPrint('=== QUEUE PERSIST: cleared ===');
    } catch (e) {
      debugPrint('=== QUEUE PERSIST: clear FAILED: $e ===');
    }
  }

  /// Release resources.
  void dispose() {
    _debounceTimer?.cancel();
    _pendingWrite = null;
  }
}
