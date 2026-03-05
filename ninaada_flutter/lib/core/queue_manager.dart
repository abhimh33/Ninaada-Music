import 'dart:math';
import 'dart:convert';
import 'package:ninaada_music/data/models.dart';

// ================================================================
//  QUEUE MANAGER — Immutable playback queue engine
// ================================================================
//
//  Every operation returns a new [QueueSnapshot]. Zero mutation.
//  Decoupled from audio playback — pure data logic.
//
//  Features:
//  ● Immutable snapshots for Riverpod state safety
//  ● Back-history stack for proper "previous" navigation
//  ● Forward lookahead for preloading (upcoming N songs)
//  ● Deduplication on insert/append
//  ● Fisher–Yates shuffle
//
//  Integration:
//    PlayerNotifier holds QueueSnapshot in PlayerState.
//    NinaadaAudioHandler's ConcatenatingAudioSource mirrors queue items.
//    On queue change → QueueManager produces new snapshot → state update
//                     → handler syncs ConcatenatingAudioSource
// ================================================================

/// Immutable snapshot of the playback queue at a point in time.
class QueueSnapshot {
  /// Ordered list of songs in the queue.
  final List<Song> items;

  /// Index of the currently playing song (-1 if empty).
  final int currentIndex;

  /// Stack of previously played songs (most recent at end).
  final List<Song> history;

  /// Optional context label (album name, playlist name, etc.)
  final String? context;

  /// Boundary between user-intent songs and algorithmic (autoplay) songs.
  /// Everything at indices `[0 .. autoPlayStartIndex-1]` is explicit user
  /// intent. Everything at `[autoPlayStartIndex .. items.length-1]` is
  /// algorithmically suggested. Defaults to `items.length` (no autoplay tail).
  final int autoPlayStartIndex;

  const QueueSnapshot({
    this.items = const [],
    this.currentIndex = -1,
    this.history = const [],
    this.context,
    int? autoPlayStartIndex,
  }) : autoPlayStartIndex = autoPlayStartIndex ?? -1;

  /// Resolved boundary — if not explicitly set, equals items.length
  /// (i.e. the entire queue is user-intent).
  int get effectiveAutoPlayStart =>
      autoPlayStartIndex >= 0 ? autoPlayStartIndex : items.length;

  /// Whether the queue has an autoplay tail.
  bool get hasAutoPlayTail => effectiveAutoPlayStart < items.length;

  /// Number of user-intent songs (before the boundary).
  int get userIntentCount => effectiveAutoPlayStart;

  /// Number of autoplay songs (at or after the boundary).
  int get autoPlayCount => items.length - effectiveAutoPlayStart;

  /// Currently playing song, or null if queue is empty.
  Song? get currentSong =>
      currentIndex >= 0 && currentIndex < items.length
          ? items[currentIndex]
          : null;

  /// Next song in linear order, or null if at the end.
  Song? get nextSong {
    final n = currentIndex + 1;
    return n < items.length ? items[n] : null;
  }

  /// Previous song (from history stack or queue index).
  Song? get previousSong {
    if (history.isNotEmpty) return history.last;
    if (currentIndex > 0) return items[currentIndex - 1];
    return null;
  }

  bool get hasNext => currentIndex + 1 < items.length;
  bool get hasPrevious => history.isNotEmpty || currentIndex > 0;
  bool get isEmpty => items.isEmpty;
  int get length => items.length;

  /// Next N upcoming songs after current (for preloading).
  List<Song> upcoming(int count) {
    final start = currentIndex + 1;
    if (start >= items.length || count <= 0) return [];
    final end = (start + count).clamp(start, items.length);
    return items.sublist(start, end);
  }

  static const empty = QueueSnapshot();

  /// Copy with overrides — preserves autoPlayStartIndex unless overridden.
  QueueSnapshot copyWith({
    List<Song>? items,
    int? currentIndex,
    List<Song>? history,
    String? context,
    int? autoPlayStartIndex,
  }) {
    return QueueSnapshot(
      items: items ?? this.items,
      currentIndex: currentIndex ?? this.currentIndex,
      history: history ?? this.history,
      context: context ?? this.context,
      autoPlayStartIndex: autoPlayStartIndex ?? this.autoPlayStartIndex,
    );
  }

  // ══════════════════════════════════════════════════
  //  SERIALIZATION — Phase 8: State Restoration
  // ══════════════════════════════════════════════════

  /// Serialize the QueueSnapshot to a JSON-encodable map.
  /// History is intentionally omitted — it's session-ephemeral.
  Map<String, dynamic> toJson() {
    return {
      'items': items.map((s) => s.toJson()).toList(),
      'currentIndex': currentIndex,
      'context': context,
      'autoPlayStartIndex': autoPlayStartIndex,
    };
  }

  /// Serialize the QueueSnapshot to a JSON string.
  String toJsonString() => jsonEncode(toJson());

  /// Deserialize from a JSON map. Returns [QueueSnapshot.empty] on failure.
  factory QueueSnapshot.fromJson(Map<String, dynamic> json) {
    try {
      final itemsList = (json['items'] as List?)
          ?.map((s) => Song.fromJson(s as Map<String, dynamic>))
          .toList();
      if (itemsList == null || itemsList.isEmpty) return QueueSnapshot.empty;
      return QueueSnapshot(
        items: List.unmodifiable(itemsList),
        currentIndex: (json['currentIndex'] as int?) ?? 0,
        context: json['context'] as String?,
        autoPlayStartIndex: json['autoPlayStartIndex'] as int?,
      );
    } catch (_) {
      return QueueSnapshot.empty;
    }
  }

  /// Deserialize from a JSON string. Returns [QueueSnapshot.empty] on failure.
  factory QueueSnapshot.fromJsonString(String jsonString) {
    try {
      return QueueSnapshot.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
    } catch (_) {
      return QueueSnapshot.empty;
    }
  }
}

/// Pure functional queue operations.
/// Every method returns a new [QueueSnapshot] — never mutates input.
class QueueManager {
  QueueManager._(); // Non-instantiable

  // ══════════════════════════════════════════════════
  //  CREATE / REPLACE
  // ══════════════════════════════════════════════════

  /// Create a new queue from a list of songs.
  static QueueSnapshot create(
    List<Song> songs, {
    int startIndex = 0,
    String? context,
    int? autoPlayStartIndex,
  }) {
    if (songs.isEmpty) return QueueSnapshot.empty;
    return QueueSnapshot(
      items: List.unmodifiable(songs),
      currentIndex: startIndex.clamp(0, songs.length - 1),
      context: context,
      autoPlayStartIndex: autoPlayStartIndex,
    );
  }

  // ══════════════════════════════════════════════════
  //  NAVIGATION
  // ══════════════════════════════════════════════════

  /// Advance to the next track. Returns same snapshot if at end.
  static QueueSnapshot next(QueueSnapshot q) {
    if (q.items.isEmpty || q.currentIndex + 1 >= q.items.length) return q;
    final history = q.currentSong != null
        ? List<Song>.unmodifiable([...q.history, q.currentSong!])
        : q.history;
    return QueueSnapshot(
      items: q.items,
      currentIndex: q.currentIndex + 1,
      history: history,
      context: q.context,
      autoPlayStartIndex: q.autoPlayStartIndex,
    );
  }

  /// Go to the previous track (from history stack or queue index).
  static QueueSnapshot previous(QueueSnapshot q) {
    if (q.history.isNotEmpty) {
      final prev = q.history.last;
      final newHistory = List<Song>.unmodifiable(
        q.history.sublist(0, q.history.length - 1),
      );
      final idx = q.items.indexWhere((s) => s.id == prev.id);
      return QueueSnapshot(
        items: q.items,
        currentIndex: idx >= 0 ? idx : (q.currentIndex - 1).clamp(0, q.items.length - 1),
        history: newHistory,
        context: q.context,
        autoPlayStartIndex: q.autoPlayStartIndex,
      );
    }
    if (q.currentIndex > 0) {
      return QueueSnapshot(
        items: q.items,
        currentIndex: q.currentIndex - 1,
        history: q.history,
        context: q.context,
        autoPlayStartIndex: q.autoPlayStartIndex,
      );
    }
    // Wrap to end of queue
    if (q.items.isNotEmpty) {
      return QueueSnapshot(
        items: q.items,
        currentIndex: q.items.length - 1,
        history: q.history,
        context: q.context,
        autoPlayStartIndex: q.autoPlayStartIndex,
      );
    }
    return q;
  }

  /// Jump to a specific index. Pushes current to history.
  static QueueSnapshot jumpTo(QueueSnapshot q, int index) {
    if (index < 0 || index >= q.items.length) return q;
    if (index == q.currentIndex) return q;
    final history = q.currentSong != null
        ? List<Song>.unmodifiable([...q.history, q.currentSong!])
        : q.history;
    return QueueSnapshot(
      items: q.items,
      currentIndex: index,
      history: history,
      context: q.context,
      autoPlayStartIndex: q.autoPlayStartIndex,
    );
  }

  /// Jump to a song by ID. Returns same snapshot if not found.
  static QueueSnapshot jumpToSong(QueueSnapshot q, String songId) {
    final idx = q.items.indexWhere((s) => s.id == songId);
    if (idx < 0) return q;
    return jumpTo(q, idx);
  }

  // ══════════════════════════════════════════════════
  //  MODIFICATION
  // ══════════════════════════════════════════════════

  /// Insert song immediately after the current track (with dedup).
  /// User-intent: adjusts autoPlayStartIndex to include the inserted song.
  static QueueSnapshot insertNext(QueueSnapshot q, Song song) {
    final items = List<Song>.from(q.items);
    final currentId = q.currentSong?.id;
    int boundary = q.effectiveAutoPlayStart;

    // Remove duplicate if present — adjust boundary if removal was before it
    final dupIdx = items.indexWhere((s) => s.id == song.id);
    if (dupIdx >= 0) {
      if (dupIdx < boundary) boundary--;
      items.removeAt(dupIdx);
    }

    // Re-find current index after possible removal
    final curIdx = currentId != null
        ? items.indexWhere((s) => s.id == currentId)
        : q.currentIndex.clamp(0, items.length);
    final insertAt = (curIdx >= 0 ? curIdx + 1 : items.length).clamp(0, items.length);

    items.insert(insertAt, song);

    // This is user intent — ensure boundary covers the inserted song
    if (insertAt < boundary) {
      boundary++;
    } else {
      // Inserted at or after boundary → expand user zone to include it
      boundary = insertAt + 1;
    }

    final newCurIdx = currentId != null
        ? items.indexWhere((s) => s.id == currentId)
        : curIdx;

    return QueueSnapshot(
      items: List.unmodifiable(items),
      currentIndex: (newCurIdx >= 0 ? newCurIdx : 0).clamp(0, items.length - 1),
      history: q.history,
      context: q.context,
      autoPlayStartIndex: boundary.clamp(0, items.length),
    );
  }

  /// Insert multiple songs immediately after the current track (with dedup).
  /// Songs are inserted in order — song[0] will be closest to current.
  /// User-intent: adjusts autoPlayStartIndex to include inserted songs.
  static QueueSnapshot insertAllNext(QueueSnapshot q, List<Song> songs) {
    if (songs.isEmpty) return q;
    final items = List<Song>.from(q.items);
    final currentId = q.currentSong?.id;
    int boundary = q.effectiveAutoPlayStart;

    // Collect IDs of incoming songs for O(1) lookup
    final incomingIds = songs.map((s) => s.id).toSet();

    // Remove any existing duplicates — adjust boundary for each removal
    for (int i = items.length - 1; i >= 0; i--) {
      if (incomingIds.contains(items[i].id) && items[i].id != currentId) {
        if (i < boundary) boundary--;
        items.removeAt(i);
      }
    }

    // Re-find current index after removals
    final curIdx = currentId != null
        ? items.indexWhere((s) => s.id == currentId)
        : q.currentIndex.clamp(0, items.length);
    final insertAt = (curIdx >= 0 ? curIdx + 1 : items.length).clamp(0, items.length);

    // Filter out the currently-playing song from the batch
    final filtered = currentId != null
        ? songs.where((s) => s.id != currentId).toList()
        : songs;

    items.insertAll(insertAt, filtered);

    // User intent — ensure boundary covers all inserted songs
    if (insertAt < boundary) {
      boundary += filtered.length;
    } else {
      boundary = insertAt + filtered.length;
    }

    final newCurIdx = currentId != null
        ? items.indexWhere((s) => s.id == currentId)
        : curIdx;

    return QueueSnapshot(
      items: List.unmodifiable(items),
      currentIndex: (newCurIdx >= 0 ? newCurIdx : 0).clamp(0, items.length - 1),
      history: q.history,
      context: q.context,
      autoPlayStartIndex: boundary.clamp(0, items.length),
    );
  }

  /// Add a song to the user-intent zone (inserts at autoPlayStartIndex).
  /// Skips if already present. Increments boundary by 1.
  static QueueSnapshot addToEnd(QueueSnapshot q, Song song) {
    if (q.items.any((s) => s.id == song.id)) return q;
    final boundary = q.effectiveAutoPlayStart;
    final items = List<Song>.from(q.items);
    items.insert(boundary, song);
    return QueueSnapshot(
      items: List.unmodifiable(items),
      currentIndex: q.currentIndex,
      history: q.history,
      context: q.context,
      autoPlayStartIndex: boundary + 1,
    );
  }

  /// Add multiple songs to the user-intent zone (inserts at autoPlayStartIndex).
  /// Deduplicates against existing queue. Increments boundary by count added.
  static QueueSnapshot addAll(QueueSnapshot q, List<Song> songs) {
    final ids = q.items.map((s) => s.id).toSet();
    final newSongs = songs.where((s) => !ids.contains(s.id)).toList();
    if (newSongs.isEmpty) return q;
    final boundary = q.effectiveAutoPlayStart;
    final items = List<Song>.from(q.items);
    items.insertAll(boundary, newSongs);
    return QueueSnapshot(
      items: List.unmodifiable(items),
      currentIndex: q.currentIndex,
      history: q.history,
      context: q.context,
      autoPlayStartIndex: boundary + newSongs.length,
    );
  }

  /// Append songs to the absolute end of the queue (autoplay / discovery).
  /// Does NOT move the autoPlayStartIndex — these are algorithmic songs.
  static QueueSnapshot appendAutoPlay(QueueSnapshot q, List<Song> songs) {
    final ids = q.items.map((s) => s.id).toSet();
    final fresh = songs.where((s) => !ids.contains(s.id)).toList();
    if (fresh.isEmpty) return q;
    return QueueSnapshot(
      items: List.unmodifiable([...q.items, ...fresh]),
      currentIndex: q.currentIndex,
      history: q.history,
      context: q.context,
      autoPlayStartIndex: q.autoPlayStartIndex,
    );
  }

  /// Remove a song by ID. Adjusts currentIndex and autoPlayStartIndex.
  static QueueSnapshot remove(QueueSnapshot q, String songId) {
    if (!q.items.any((s) => s.id == songId)) return q;
    final removedIdx = q.items.indexWhere((s) => s.id == songId);
    final currentId = q.currentSong?.id;
    final items = q.items.where((s) => s.id != songId).toList();
    if (items.isEmpty) return QueueSnapshot.empty;

    int boundary = q.effectiveAutoPlayStart;
    if (removedIdx < boundary) boundary--;

    int newIdx;
    if (currentId == songId) {
      newIdx = q.currentIndex.clamp(0, items.length - 1);
    } else {
      newIdx = currentId != null
          ? items.indexWhere((s) => s.id == currentId)
          : q.currentIndex;
      if (newIdx < 0) newIdx = 0;
    }
    return QueueSnapshot(
      items: List.unmodifiable(items),
      currentIndex: newIdx,
      history: q.history,
      context: q.context,
      autoPlayStartIndex: boundary.clamp(0, items.length),
    );
  }

  // ══════════════════════════════════════════════════
  //  REORDER
  // ══════════════════════════════════════════════════

  /// Reorder a song from [oldIndex] to [newIndex].
  /// Applies Flutter's standard index shift and adjusts currentIndex
  /// and autoPlayStartIndex.
  static QueueSnapshot reorder(QueueSnapshot q, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= q.items.length) return q;
    // Flutter's standard index shift for ReorderableListView
    if (oldIndex < newIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= q.items.length) return q;
    if (oldIndex == newIndex) return q;

    final items = List<Song>.from(q.items);
    final movedSong = items.removeAt(oldIndex);
    items.insert(newIndex, movedSong);

    // Adjust currentIndex to follow the currently playing song
    int newCurIdx = q.currentIndex;
    if (q.currentIndex == oldIndex) {
      newCurIdx = newIndex;
    } else {
      if (q.currentIndex > oldIndex && q.currentIndex <= newIndex) {
        newCurIdx = q.currentIndex - 1;
      } else if (q.currentIndex < oldIndex && q.currentIndex >= newIndex) {
        newCurIdx = q.currentIndex + 1;
      }
    }

    // Adjust autoPlayStartIndex:
    // Step 1: removal at oldIndex
    int boundary = q.effectiveAutoPlayStart;
    if (oldIndex < boundary) boundary--;
    // Step 2: insertion at newIndex
    if (newIndex <= boundary) boundary++;

    return QueueSnapshot(
      items: List.unmodifiable(items),
      currentIndex: newCurIdx.clamp(0, items.length - 1),
      history: q.history,
      context: q.context,
      autoPlayStartIndex: boundary.clamp(0, items.length),
    );
  }

  /// Remove song at [index]. Adjusts currentIndex and autoPlayStartIndex.
  static QueueSnapshot removeAt(QueueSnapshot q, int index) {
    if (index < 0 || index >= q.items.length) return q;
    final items = List<Song>.from(q.items);
    items.removeAt(index);
    if (items.isEmpty) return QueueSnapshot.empty;

    int boundary = q.effectiveAutoPlayStart;
    if (index < boundary) boundary--;

    int newCurIdx = q.currentIndex;
    if (index < q.currentIndex) {
      newCurIdx = q.currentIndex - 1;
    } else if (index == q.currentIndex) {
      newCurIdx = q.currentIndex.clamp(0, items.length - 1);
    }

    return QueueSnapshot(
      items: List.unmodifiable(items),
      currentIndex: newCurIdx.clamp(0, items.length - 1),
      history: q.history,
      context: q.context,
      autoPlayStartIndex: boundary.clamp(0, items.length),
    );
  }

  // ══════════════════════════════════════════════════
  //  SHUFFLE / CLEAR
  // ══════════════════════════════════════════════════

  /// Fisher–Yates shuffle remaining items (keeps current song at front).
  /// Resets autoPlayStartIndex — shuffle merges both tiers.
  static QueueSnapshot shuffle(QueueSnapshot q) {
    if (q.items.length <= 1) return q;
    final current = q.currentSong;
    final others = List<Song>.from(q.items);
    if (current != null) others.removeWhere((s) => s.id == current.id);

    final rng = Random();
    for (int i = others.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = others[i];
      others[i] = others[j];
      others[j] = tmp;
    }

    final newItems = current != null ? [current, ...others] : others;
    return QueueSnapshot(
      items: List.unmodifiable(newItems),
      currentIndex: 0,
      history: q.history,
      context: q.context,
      // Shuffle merges tiers — reset boundary to full length
    );
  }

  // ══════════════════════════════════════════════════
  //  PRE-BUFFER WINDOW
  // ══════════════════════════════════════════════════

  /// Compute the pre-buffer window around [currentIndex].
  /// Returns a sub-list of songs that should be loaded into
  /// ConcatenatingAudioSource. Default window = 10 ahead.
  ///
  /// For small queues (≤ windowSize) returns the full queue.
  /// For large queues, returns currentIndex - 1 .. currentIndex + windowAhead.
  static List<Song> preBufferWindow(
    QueueSnapshot q, {
    int windowAhead = 10,
    int windowBehind = 1,
  }) {
    if (q.isEmpty) return [];
    if (q.items.length <= windowAhead + windowBehind + 1) {
      return List.from(q.items); // Small queue — load all
    }
    final start = (q.currentIndex - windowBehind).clamp(0, q.items.length - 1);
    final end = (q.currentIndex + windowAhead + 1).clamp(start, q.items.length);
    return q.items.sublist(start, end);
  }

  /// Clear the queue entirely.
  static QueueSnapshot clear() => QueueSnapshot.empty;
}
