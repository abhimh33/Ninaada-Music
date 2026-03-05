import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/services/download_manager.dart';

// ================================================================
//  NINAADA AUDIO HANDLER — Production-grade audio engine
// ================================================================
//
//  Integrates three pillars:
//
//  ┌────────────────────────────────────────────────────────────┐
//  │  1. audio_service (BaseAudioHandler)                       │
//  │     → Lock screen controls (play/pause/prev/next)          │
//  │     → Notification media player with album art             │
//  │     → Audio focus (auto-pause on call, duck for nav)       │
//  │     → Background execution (survives app backgrounding)    │
//  ├────────────────────────────────────────────────────────────┤
//  │  2. just_audio (AudioPlayer)                               │
//  │     → High-quality streaming audio playback                │
//  │     → Position/duration/state streams                      │
//  │     → Speed control, volume, seek                          │
//  ├────────────────────────────────────────────────────────────┤
//  │  3. ConcatenatingAudioSource (Gapless Engine)              │
//  │     → Pre-buffers next track while current plays           │
//  │     → Zero-latency seamless track transitions              │
//  │     → Dynamic add/remove/reorder without stopping          │
//  │     → Lazy preparation to minimize memory                  │
//  └────────────────────────────────────────────────────────────┘
//
//  Data Flow:
//    PlayerNotifier → NinaadaAudioHandler → ConcatenatingAudioSource
//                                         → AudioPlayer → OS audio
//                                         → playbackState → notification
//
//  Queue Mode vs Stream Mode:
//    Queue mode: ConcatenatingAudioSource manages ordered playback
//    Stream mode: Direct URL for live radio (bypasses queue)
//
// ================================================================

class NinaadaAudioHandler extends BaseAudioHandler with SeekHandler {
  // ── DSP Audio Effects Pipeline (Phase 11) ──
  final AndroidEqualizer equalizer = AndroidEqualizer();
  final AndroidLoudnessEnhancer loudnessEnhancer = AndroidLoudnessEnhancer();

  late final AudioPlayer _player;
  final ConcatenatingAudioSource _playlist = ConcatenatingAudioSource(
    children: [],
    useLazyPreparation: true, // Only prepare current + adjacent tracks
  );

  /// Parallel song metadata list (indexed identically to _playlist.children)
  final List<Song> _songs = [];

  /// Whether the player is in radio/stream mode vs queue mode
  bool _streamMode = false;

  /// Guard to prevent duplicate stream subscriptions
  bool _streamsAttached = false;

  /// True while a seek-to-index operation is in-flight.
  /// Exposed so the notifier can suppress position jitter.
  bool get isSeeking => _isSeeking;
  bool _isSeeking = false;

  /// True during loadQueue / replaceAndPlay — suppresses hot-swap.
  bool get isReloadingQueue => _isReloadingQueue;
  bool _isReloadingQueue = false;

  /// Mutex serializes all queue mutations (load, insert, append, clear,
  /// replace, stream-switch). Prevents interleaved async corrupting
  /// the _songs ↔ _playlist synchronization.
  final _queueMutex = _SimpleMutex();

  // ── Audio focus / interruption state ──
  bool _wasPlayingBeforeInterrupt = false;
  double _preDuckVolume = 1.0;
  StreamSubscription? _interruptSub;
  StreamSubscription? _noisySub;

  /// Expose for callers that need to check lock state.
  _SimpleMutex get queueMutex => _queueMutex;

  // ════════════════════════════════════════════════
  //  CALLBACKS — wired by PlayerNotifier
  // ════════════════════════════════════════════════

  /// Fires when the active track changes (gapless advance or seek).
  /// Parameters: (index in queue, song metadata)
  void Function(int index, Song song)? onTrackChanged;

  /// Fires when the entire queue has finished playing.
  /// Only fires with LoopMode.off when the last source completes.
  void Function()? onQueueEnd;

  /// Fires on onTaskRemoved (app swiped from recents) so the provider
  /// layer can flush pending queue persistence before the process dies.
  void Function()? onAppKilled;

  /// Resolved audio cache directory path (set during _init).
  /// Used by _toAudioSource for LockCachingAudioSource cacheFile.
  String? _audioCacheDirPath;

  // ════════════════════════════════════════════════
  //  STREAMS — forwarded from AudioPlayer
  // ════════════════════════════════════════════════

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<bool> get playingStream => _player.playingStream;
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  // ════════════════════════════════════════════════
  //  STATE ACCESSORS
  // ════════════════════════════════════════════════

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration get bufferedPosition => _player.bufferedPosition;
  Duration get playerDuration => _player.duration ?? Duration.zero;
  double get volume => _player.volume;
  double get speed => _player.speed;
  int get currentIndex => _player.currentIndex ?? -1;
  List<int>? get shuffleIndices => _player.effectiveIndices;
  bool get inStreamMode => _streamMode;
  List<Song> get songQueue => List.unmodifiable(_songs);

  Song? get currentSong {
    final idx = _player.currentIndex;
    if (idx == null || idx < 0 || idx >= _songs.length) return null;
    return _songs[idx];
  }

  // ════════════════════════════════════════════════
  //  INITIALIZATION
  // ════════════════════════════════════════════════

  NinaadaAudioHandler() {
    // Construct AudioPlayer with DSP pipeline (Phase 11).
    // AndroidEqualizer + AndroidLoudnessEnhancer are piped through
    // the hardware audio effects engine for zero-latency processing.
    _player = AudioPlayer(
      audioPipeline: AudioPipeline(
        androidAudioEffects: [equalizer, loudnessEnhancer],
      ),
    );

    // Seed initial PlaybackState immediately so the OS media session
    // knows which controls exist BEFORE any audio loads.
    // Android 13+ will not render clickable buttons without this.
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
    _init();
  }

  Future<void> _init() async {
    // ── Enable DSP audio effects (Phase 11) ──
    try {
      await equalizer.setEnabled(true);
      await loudnessEnhancer.setEnabled(true);
      debugPrint('=== NINAADA HANDLER: DSP effects enabled ===');
    } catch (e) {
      debugPrint('=== NINAADA HANDLER: DSP effects init failed: $e ===');
    }

    // ── Configure audio session for music playback ──
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      // ── Audio focus interruption handling ──
      // Phone calls → pause + smart resume.
      // Nav voice / brief sounds → duck volume to 20%.
      _interruptSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              if (_player.playing) {
                _preDuckVolume = _player.volume;
                _player.setVolume((_preDuckVolume * 0.2).clamp(0.0, 1.0));
              }
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_player.playing) {
                _wasPlayingBeforeInterrupt = true;
                _player.pause();
              }
          }
        } else {
          // Interruption ended — restore
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(_preDuckVolume);
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              if (_wasPlayingBeforeInterrupt) {
                _wasPlayingBeforeInterrupt = false;
                _player.play();
              }
          }
        }
      });

      // ── Becoming noisy (headphone unplug → auto-pause) ──
      // Standard media-app UX: audio should not suddenly blare from speaker.
      _noisySub = session.becomingNoisyEventStream.listen((_) {
        if (_player.playing) _player.pause();
      });
    } catch (e) {
      debugPrint('=== NINAADA HANDLER: audio session config failed: $e ===');
    }

    // ── Forward playback events → audio_service playbackState ──
    // Guard: prevent duplicate subscriptions if _init is called twice.
    if (_streamsAttached) return;
    _streamsAttached = true;

    // This powers the notification, lock screen controls, and media session.
    // Using listen() instead of pipe() so an error doesn't silently kill
    // the subscription, and we also listen to playingStream so the
    // notification play/pause icon updates immediately on toggle.
    _player.playbackEventStream.listen(
      (event) => playbackState.add(_transformEvent(event)),
      onError: (e) => debugPrint('=== NINAADA HANDLER: playbackEvent error: $e ==='),
    );
    // playingStream fires on every play/pause toggle — re-emit PlaybackState
    // so the notification updates its play/pause icon immediately.
    _player.playingStream.listen((_) {
      playbackState.add(_transformEvent(_player.playbackEvent));
    });

    // ── Track index changes → update mediaItem + notify provider ──
    _player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < _songs.length && !_streamMode) {
        final song = _songs[index];
        mediaItem.add(_toMediaItem(song));
        onTrackChanged?.call(index, song);
      }
    });

    // ── Queue end detection ──
    // With ConcatenatingAudioSource + LoopMode.off, completed means ALL done
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_streamMode) {
        debugPrint('=== NINAADA HANDLER: queue completed ===');
        onQueueEnd?.call();
      }
    });

    // ── Set initial empty playlist (will be populated on first play) ──
    try {
      await _player.setAudioSource(_playlist, initialIndex: 0);
    } catch (_) {
      // Expected to fail with empty playlist — safe to ignore
    }

    // ── Resolve audio cache directory for LockCachingAudioSource ──
    try {
      final tempDir = await getTemporaryDirectory();
      final cacheDir = Directory('${tempDir.path}/ninaada_audio_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      _audioCacheDirPath = cacheDir.path;
      debugPrint('=== NINAADA HANDLER: audio cache dir: ${cacheDir.path} ===');
    } catch (e) {
      debugPrint('=== NINAADA HANDLER: cache dir init failed: $e ===');
    }

    debugPrint('=== NINAADA HANDLER: initialized ===');
  }

  // ════════════════════════════════════════════════
  //  QUEUE MANAGEMENT — MUTEX-SERIALIZED
  // ════════════════════════════════════════════════
  //
  //  All public queue mutations acquire [_queueMutex] to guarantee:
  //  1. _songs list and _playlist.children stay perfectly in sync
  //  2. No interleaved async corrupts indices or offsets
  //  3. Rapid button mashing is serialized in FIFO order
  //
  //  Private _xxxImpl methods contain the logic — they are called
  //  INSIDE the mutex by the public wrapper and by composite
  //  operations like replaceContextAndPlay.

  // ── INTERNAL IMPLEMENTATIONS (no mutex) ──────────────────────

  Future<void> _loadQueueImpl(List<Song> songs, {int initialIndex = 0}) async {
    _isReloadingQueue = true;
    _streamMode = false;
    await _playlist.clear();
    _songs.clear();

    if (songs.isEmpty) {
      queue.add([]);
      mediaItem.add(null);
      _isReloadingQueue = false;
      return;
    }

    final sources = songs.map(_toAudioSource).toList();
    await _playlist.addAll(sources);
    _songs.addAll(songs);
    queue.add(_songs.map(_toMediaItem).toList());

    final idx = initialIndex.clamp(0, songs.length - 1);
    try {
      await _player.setAudioSource(_playlist, initialIndex: idx);
      mediaItem.add(_toMediaItem(songs[idx]));
    } catch (e) {
      debugPrint('=== NINAADA HANDLER: loadQueue error: $e ===');
    }
    _isReloadingQueue = false;
    debugPrint('=== NINAADA HANDLER: loadQueue ${songs.length} songs, start=$idx ===');
  }

  Future<void> _playSongImpl(Song song) async {
  final wasStream = _streamMode;
  _streamMode = false;

  try {
    // ── STEP 1: Resolve target index (insert if absent) ──
    int targetIdx = _songs.indexWhere((s) => s.id == song.id);
    if (targetIdx < 0) {
      // Song not in queue → append it
      _songs.add(song);
      await _playlist.add(_toAudioSource(song));
      queue.add(_songs.map(_toMediaItem).toList());
      targetIdx = _songs.length - 1;
    }

    // ── STEP 2: Always stop current audio first ──
    // This guarantees radio stream is killed before song loads.
    await _player.stop();

    // ── STEP 3: Navigate to the target track ──
    if (wasStream || _playlist.length > 0) {
      // Re-attach the ConcatenatingAudioSource (required after stream
      // mode, and safe to do in queue mode as well).
      await _player.setAudioSource(_playlist,
          initialIndex: targetIdx, initialPosition: Duration.zero);
    }

    mediaItem.add(_toMediaItem(song));

    // ── STEP 4: Force play ──
    _player.play();
  } on PlayerInterruptedException {
    // Another song was tapped before this one finished loading.
    // just_audio killed this load automatically. Silently swallow.
    debugPrint('=== NINAADA HANDLER: playSong interrupted (rapid switch) ===');
  } on PlatformException catch (e) {
    if (e.code == 'abort') {
      debugPrint('=== NINAADA HANDLER: playSong aborted (rapid switch) ===');
    } else {
      debugPrint('=== NINAADA HANDLER: playSong platform error: $e ===');
    }
  } catch (e) {
    debugPrint('=== NINAADA HANDLER: playSong error: $e ===');
  }
}

  Future<void> _insertNextImpl(Song song) async {
    final existIdx = _songs.indexWhere((s) => s.id == song.id);
    if (existIdx >= 0) {
      _songs.removeAt(existIdx);
      await _playlist.removeAt(existIdx);
    }
    final curIdx = _player.currentIndex ?? 0;
    final insertAt = (curIdx + 1).clamp(0, _songs.length);
    _songs.insert(insertAt, song);
    await _playlist.insert(insertAt, _toAudioSource(song));
    queue.add(_songs.map(_toMediaItem).toList());
  }

  Future<void> _addToQueueImpl(Song song) async {
    if (_songs.any((s) => s.id == song.id)) return;
    _songs.add(song);
    await _playlist.add(_toAudioSource(song));
    queue.add(_songs.map(_toMediaItem).toList());
  }

  /// Insert a single song at a specific [index] (with dedup).
  /// Used for boundary-aware "Add to Queue" (user intent).
  Future<void> _insertAtImpl(int index, Song song) async {
    if (_songs.any((s) => s.id == song.id)) return;
    final clampedIdx = index.clamp(0, _songs.length);
    _songs.insert(clampedIdx, song);
    await _playlist.insert(clampedIdx, _toAudioSource(song));
    queue.add(_songs.map(_toMediaItem).toList());
  }

  /// Insert multiple songs at a specific [index] (with dedup).
  /// Used for boundary-aware bulk "Add to Queue" (user intent).
  Future<void> _insertAllAtImpl(int index, List<Song> songs) async {
    final existingIds = _songs.map((s) => s.id).toSet();
    final fresh = songs.where((s) => !existingIds.contains(s.id)).toList();
    if (fresh.isEmpty) return;
    final clampedIdx = index.clamp(0, _songs.length);
    _songs.insertAll(clampedIdx, fresh);
    for (int i = 0; i < fresh.length; i++) {
      await _playlist.insert(clampedIdx + i, _toAudioSource(fresh[i]));
    }
    queue.add(_songs.map(_toMediaItem).toList());
  }

  Future<void> _appendToQueueImpl(List<Song> songs) async {
    final existingIds = _songs.map((s) => s.id).toSet();
    final fresh = songs.where((s) => !existingIds.contains(s.id)).toList();
    if (fresh.isEmpty) return;
    _songs.addAll(fresh);
    await _playlist.addAll(fresh.map(_toAudioSource).toList());
    queue.add(_songs.map(_toMediaItem).toList());
  }

  Future<void> _insertAllNextImpl(List<Song> songs) async {
    if (songs.isEmpty) return;
    final incomingIds = songs.map((s) => s.id).toSet();
    final currentIdx = _player.currentIndex ?? 0;
    final currentId = currentIdx < _songs.length ? _songs[currentIdx].id : null;

    // Remove existing duplicates of the incoming batch (preserve current)
    for (int i = _songs.length - 1; i >= 0; i--) {
      if (incomingIds.contains(_songs[i].id) && _songs[i].id != currentId) {
        _songs.removeAt(i);
        await _playlist.removeAt(i);
      }
    }

    // Re-locate current after removals
    final curIdx = _player.currentIndex ?? 0;
    final insertAt = (curIdx + 1).clamp(0, _songs.length);

    // Filter out currently-playing song from batch
    final filtered = currentId != null
        ? songs.where((s) => s.id != currentId).toList()
        : songs;
    if (filtered.isEmpty) return;

    // Bulk insert into both structures
    _songs.insertAll(insertAt, filtered);
    for (int i = 0; i < filtered.length; i++) {
      await _playlist.insert(insertAt + i, _toAudioSource(filtered[i]));
    }
    queue.add(_songs.map(_toMediaItem).toList());
  }

  Future<void> _clearQueueImpl() async {
    await _player.stop();
    await _playlist.clear();
    _songs.clear();
    queue.add([]);
    mediaItem.add(null);
  }

  Future<void> _reorderQueueImpl(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _songs.length) return;
    // Flutter's standard index shift (already applied by caller at
    // the Riverpod layer, but the handler operates on raw indices
    // so we accept the ALREADY-SHIFTED newIndex here).
    if (newIndex < 0 || newIndex >= _songs.length) return;
    if (oldIndex == newIndex) return;

    // 1. Mutate the Dart metadata list
    final song = _songs.removeAt(oldIndex);
    _songs.insert(newIndex, song);

    // 2. Mirror in ConcatenatingAudioSource — this is the critical
    //    sync point. move() is an atomic operation on the native
    //    player pipeline; gapless playback is preserved.
    await _playlist.move(oldIndex, newIndex);

    // 3. Broadcast updated queue to audio_service (notification)
    queue.add(_songs.map(_toMediaItem).toList());
    debugPrint('=== NINAADA HANDLER: reorderQueue $oldIndex → $newIndex ===');
  }

  Future<void> _removeFromQueueImpl(int index) async {
    if (index < 0 || index >= _songs.length) return;

    final curIdx = _player.currentIndex ?? -1;
    final isCurrentSong = index == curIdx;

    // 1. Mutate the Dart metadata list
    _songs.removeAt(index);

    // 2. Mirror in ConcatenatingAudioSource
    await _playlist.removeAt(index);

    if (_songs.isEmpty) {
      // Queue is now empty — stop playback
      await _player.stop();
      queue.add([]);
      mediaItem.add(null);
      debugPrint('=== NINAADA HANDLER: removeFromQueue — queue now empty ===');
      return;
    }

    // 3. If we removed the currently playing song, just_audio will
    //    auto-advance to the next source at the same index. Update
    //    mediaItem to reflect the new current song.
    if (isCurrentSong) {
      final newIdx = (_player.currentIndex ?? 0).clamp(0, _songs.length - 1);
      mediaItem.add(_toMediaItem(_songs[newIdx]));
      onTrackChanged?.call(newIdx, _songs[newIdx]);
    }

    // 4. Broadcast updated queue
    queue.add(_songs.map(_toMediaItem).toList());
    debugPrint('=== NINAADA HANDLER: removeFromQueue index=$index, remaining=${_songs.length} ===');
  }

  Future<void> _playStreamImpl(String url, {String? title, String? artist}) async {
    _streamMode = true;

    // ── EAGER NOTIFICATION: push MediaItem BEFORE stop() so the
    //    foreground service has metadata to display during the
    //    stop→load transition gap.
    mediaItem.add(MediaItem(
      id: url,
      title: title ?? 'Radio Stream',
      artist: 'Connecting...',
    ));

    try {
      // ── STEP 1: Kill current audio instantly.
      await _player.stop();

      // ── STEP 2: Load the stream URL.
      //    PlayerInterruptedException fires if user taps another
      //    station/song before buffering completes.
      await _player.setUrl(url);

      // ── STEP 3: Force play.
      _player.play();

      // Update notification with actual artist
      mediaItem.add(MediaItem(
        id: url,
        title: title ?? 'Radio Stream',
        artist: artist ?? 'Live',
      ));
    } on PlayerInterruptedException {
      debugPrint('=== NINAADA HANDLER: playStream interrupted (rapid switch) ===');
    } on PlatformException catch (e) {
      if (e.code == 'abort') {
        debugPrint('=== NINAADA HANDLER: playStream aborted (rapid switch) ===');
      } else {
        _streamMode = false;
        debugPrint('=== NINAADA HANDLER: playStream platform error: $e ===');
        rethrow;
      }
    } catch (e) {
      _streamMode = false;
      debugPrint('=== NINAADA HANDLER: playStream FAILED: $e ===');
      rethrow;
    }
  }

  Future<void> _resumeQueueModeImpl({int? atIndex}) async {
    if (_songs.isEmpty) return;
    _streamMode = false;
    final idx = (atIndex ?? 0).clamp(0, _songs.length - 1);
    try {
      await _player.setAudioSource(_playlist, initialIndex: idx);
      mediaItem.add(_toMediaItem(_songs[idx]));
    } catch (e) {
      debugPrint('=== NINAADA HANDLER: resumeQueueMode error: $e ===');
    }
  }

  // ── PUBLIC MUTEX-PROTECTED API ───────────────────────────────

  /// Load a complete queue. Does NOT start playback.
  Future<void> loadQueue(List<Song> songs, {int initialIndex = 0}) =>
      _queueMutex.protect(() => _loadQueueImpl(songs, initialIndex: initialIndex));

  /// Load a queue and seek to a specific position without playing.
  /// Used for cold boot restoration — populates ConcatenatingAudioSource
  /// and seeks to the saved position so the player is ready to resume.
  Future<void> loadQueueSilent(
    List<Song> songs, {
    int initialIndex = 0,
    Duration initialPosition = Duration.zero,
  }) =>
      _queueMutex.protect(() async {
        await _loadQueueImpl(songs, initialIndex: initialIndex);
        try {
          await _player.seek(initialPosition, index: initialIndex);
          // Do NOT call _player.play() — user taps play to resume.
        } catch (e) {
          debugPrint('=== NINAADA HANDLER: loadQueueSilent seek error: $e ===');
        }
        debugPrint(
          '=== NINAADA HANDLER: loadQueueSilent ${songs.length} songs, '
          'index=$initialIndex, pos=${initialPosition.inMilliseconds}ms ===',
        );
      });

  /// Play a song. Atomic stop→setSource→play pipeline.
  /// Rapid taps are handled natively by PlayerInterruptedException.
  Future<void> playSong(Song song) =>
      _queueMutex.protect(() => _playSongImpl(song));

  /// Replace entire queue and start playing from [startIndex].
  Future<void> replaceAndPlay(List<Song> songs, {int startIndex = 0}) =>
      _queueMutex.protect(() async {
        try {
          await _player.stop();
          await _loadQueueImpl(songs, initialIndex: startIndex);
          // setAudioSource already called inside _loadQueueImpl;
          // just_audio handles interruption if another call arrives.
          _player.play();
        } on PlayerInterruptedException {
          debugPrint('=== NINAADA HANDLER: replaceAndPlay interrupted ===');
        } on PlatformException catch (e) {
          if (e.code != 'abort') rethrow;
        }
      });

  /// Atomic context switch: stop → clear → load → play.
  /// Used when the user taps a song from a completely new context
  /// (different playlist, album, or browse section).
  Future<void> replaceContextAndPlay(List<Song> songs, int startIndex) =>
      _queueMutex.protect(() async {
        _streamMode = false;
        try {
          await _player.stop();
          await _loadQueueImpl(songs, initialIndex: startIndex);
          _player.play();
        } on PlayerInterruptedException {
          debugPrint('=== NINAADA HANDLER: replaceContextAndPlay interrupted ===');
        } on PlatformException catch (e) {
          if (e.code != 'abort') rethrow;
        }
      });

  /// Insert song immediately after the current track (with dedup).
  Future<void> insertNext(Song song) =>
      _queueMutex.protect(() => _insertNextImpl(song));

  /// Append song to end of queue (no-op if already present).
  Future<void> addToQueue(Song song) =>
      _queueMutex.protect(() => _addToQueueImpl(song));

  /// Append multiple songs to end (with dedup).
  Future<void> appendToQueue(List<Song> songs) =>
      _queueMutex.protect(() => _appendToQueueImpl(songs));

  /// Insert multiple songs immediately after current track (with dedup).
  Future<void> insertAllNext(List<Song> songs) =>
      _queueMutex.protect(() => _insertAllNextImpl(songs));

  /// Insert a single song at a specific index (boundary-aware, with dedup).
  Future<void> insertAt(int index, Song song) =>
      _queueMutex.protect(() => _insertAtImpl(index, song));

  /// Insert multiple songs at a specific index (boundary-aware, with dedup).
  Future<void> insertAllAt(int index, List<Song> songs) =>
      _queueMutex.protect(() => _insertAllAtImpl(index, songs));

  /// Seek to a specific index in the queue (no mutex needed — atomic).
  /// Sets [_isSeeking] during the operation so the notifier can
  /// suppress position jitter from the stream.
  Future<void> seekToIndex(int index) async {
    if (index >= 0 && index < _songs.length) {
      _isSeeking = true;
      try {
        await _player.seek(Duration.zero, index: index);
      } finally {
        _isSeeking = false;
      }
    }
  }

  /// Hot-swap an audio source at [index] without interrupting playback.
  /// Used when a download completes (remote→local) or is deleted (local→remote).
  /// If the song is currently playing, preserves position via seek.
  /// Mutex-serialized to prevent collision with other queue mutations.
  Future<void> hotSwapSource(int index) =>
      _queueMutex.protect(() => _hotSwapSourceImpl(index));

  Future<void> _hotSwapSourceImpl(int index) async {
    if (index < 0 || index >= _songs.length) return;
    if (_isReloadingQueue || _streamMode) return;

    final song = _songs[index];
    final curIdx = _player.currentIndex ?? -1;
    final wasPlaying = curIdx == index;
    final position = wasPlaying ? _player.position : Duration.zero;

    // 1. Remove old source
    await _playlist.removeAt(index);

    // 2. Insert fresh source (will resolve to local or remote via _toAudioSource)
    await _playlist.insert(index, _toAudioSource(song));

    // 3. If currently playing, seek back to saved position
    if (wasPlaying) {
      _isSeeking = true;
      try {
        await _player.seek(position, index: index);
      } finally {
        _isSeeking = false;
      }
      // Resume if was playing
      if (_player.playing) {
        // Already playing, no action needed
      }
    }

    debugPrint('=== NINAADA HANDLER: hotSwapSource index=$index, song=${song.id}, wasPlaying=$wasPlaying ===');
  }

  /// Clear the queue and stop playback.
  Future<void> clearQueue() =>
      _queueMutex.protect(() => _clearQueueImpl());

  /// Reorder a song in the queue. Syncs _songs AND _playlist atomically.
  /// Accepts already-shifted indices (caller applies Flutter's standard
  /// `if (oldIndex < newIndex) newIndex -= 1` before calling).
  Future<void> reorderQueue(int oldIndex, int newIndex) =>
      _queueMutex.protect(() => _reorderQueueImpl(oldIndex, newIndex));

  /// Remove a song from the queue by index. Syncs _songs AND _playlist.
  Future<void> removeFromQueue(int index) =>
      _queueMutex.protect(() => _removeFromQueueImpl(index));

  // ════════════════════════════════════════════════
  //  RADIO / STREAM MODE — MUTEX-SERIALIZED
  // ════════════════════════════════════════════════

  /// Play a live radio stream (exits queue mode).
  /// Atomic stop→setUrl→play with PlayerInterruptedException safety.
  Future<void> playStream(String url, {String? title, String? artist}) =>
      _queueMutex.protect(
        () => _playStreamImpl(url, title: title, artist: artist),
      );

  /// Return to queue mode after streaming.
  Future<void> resumeQueueMode({int? atIndex}) =>
      _queueMutex.protect(() => _resumeQueueModeImpl(atIndex: atIndex));

  // ════════════════════════════════════════════════
  //  STANDARD BaseAudioHandler OVERRIDES
  //  (Called by OS: lock screen, notification, headset buttons)
  // ════════════════════════════════════════════════

  /// Handle media button clicks from notification / headset / lock screen.
  /// On Android, the native audio_service routes KEYCODE_MEDIA_NEXT and
  /// KEYCODE_MEDIA_PREVIOUS through onClick → click() → skipToNext/Previous.
  /// We override click() to add logging and direct dispatch instead of
  /// relying on BaseAudioHandler's default routing.
  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    debugPrint('=== NINAADA HANDLER: click() CALLED, button=$button ===');
    try {
      switch (button) {
        case MediaButton.media:
          if (_player.playing) {
            await pause();
          } else {
            await play();
          }
        case MediaButton.next:
          debugPrint('=== NINAADA HANDLER: click() dispatching skipToNext ===');
          await skipToNext();
          debugPrint('=== NINAADA HANDLER: click() skipToNext DONE ===');
        case MediaButton.previous:
          debugPrint('=== NINAADA HANDLER: click() dispatching skipToPrevious ===');
          await skipToPrevious();
          debugPrint('=== NINAADA HANDLER: click() skipToPrevious DONE ===');
      }
    } catch (e, st) {
      debugPrint('=== NINAADA HANDLER: click() ERROR: $e\n$st ===');
    }
  }

  @override
  Future<void> play() async {
    debugPrint('=== NINAADA HANDLER: play() CALLED ===');
    // MUST NOT await — AudioPlayer.play() blocks until playback completes
    // (it awaits an internal Completer). Awaiting here would block the
    // serial platform channel and prevent ALL subsequent OS commands
    // (pause, next, prev) from being dispatched.
    // The playingStream listener in _init() handles PlaybackState broadcast.
    _player.play();
  }

  @override
  Future<void> pause() async {
    debugPrint('=== NINAADA HANDLER: pause() CALLED ===');
    // Fire-and-forget for consistency with play().
    // playingStream listener handles PlaybackState broadcast.
    _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    playbackState.add(_transformEvent(_player.playbackEvent));
  }

  @override
  Future<void> skipToNext() async {
    debugPrint('=== NINAADA HANDLER: skipToNext() CALLED, streamMode=$_streamMode, queueLen=${_songs.length}, curIdx=${_player.currentIndex} ===');
    if (_streamMode) return;
    if (_songs.isEmpty) return;
    final curIdx = _player.currentIndex ?? 0;
    final nextIdx = curIdx + 1;
    if (nextIdx >= _songs.length) {
      debugPrint('=== NINAADA HANDLER: skipToNext — already at last track ===');
      return;
    }
    await _player.seek(Duration.zero, index: nextIdx);
    debugPrint('=== NINAADA HANDLER: skipToNext — seeked to index $nextIdx ===');
    if (nextIdx >= 0 && nextIdx < _songs.length) {
      mediaItem.add(_toMediaItem(_songs[nextIdx]));
      onTrackChanged?.call(nextIdx, _songs[nextIdx]);
    }
    // Ensure playback starts after skip (matches skipToPrevious behavior).
    _player.play();
    playbackState.add(_transformEvent(_player.playbackEvent));
  }

  @override
  Future<void> skipToPrevious() async {
    debugPrint('=== NINAADA HANDLER: skipToPrevious() CALLED, streamMode=$_streamMode, curIdx=${_player.currentIndex} ===');
    if (_streamMode) return;
    if (_songs.isEmpty) return;
    final curIdx = _player.currentIndex ?? 0;

    // Always jump to previous track (no 3-second restart rule).
    // If at first track, restart it from 0:00.
    if (curIdx > 0) {
      final prevIdx = curIdx - 1;
      debugPrint('=== NINAADA HANDLER: skipToPrevious — jumping to index $prevIdx ===');
      await _player.seek(Duration.zero, index: prevIdx);
      if (prevIdx >= 0 && prevIdx < _songs.length) {
        mediaItem.add(_toMediaItem(_songs[prevIdx]));
        onTrackChanged?.call(prevIdx, _songs[prevIdx]);
      }
    } else {
      debugPrint('=== NINAADA HANDLER: skipToPrevious — at first track, restarting ===');
      await _player.seek(Duration.zero);
    }
    _player.play();
    playbackState.add(_transformEvent(_player.playbackEvent));
  }

  @override
  Future<void> stop() async {
    debugPrint('=== NINAADA HANDLER: stop() CALLED ===');
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    // App killed (swiped from recents).
    // 1. Flush pending queue persistence BEFORE stopping playback,
    //    so the saved position reflects the last heard moment.
    onAppKilled?.call();
    // 2. Stop everything + dismiss notification.
    await stop();
  }

  // ════════════════════════════════════════════════
  //  EXTENDED CONTROLS
  // ════════════════════════════════════════════════

  /// Toggle play/pause.
  /// Routes through BaseAudioHandler overrides (play/pause) to guarantee
  /// OS notification, lock screen, and Bluetooth all stay in sync.
  Future<void> togglePlayback() async {
    if (_player.playing) {
      await pause();
    } else {
      await play();
    }
  }

  /// Seek to a position in seconds.
  Future<void> seekTo(double seconds) async {
    await _player.seek(Duration(milliseconds: (seconds * 1000).toInt()));
  }

  /// Set playback rate (clamped 0.5–2.0).
  Future<void> setRate(double rate) async {
    await _player.setSpeed(rate.clamp(0.5, 2.0));
  }

  /// Set volume (clamped 0.0–1.0).
  Future<void> setVolume(double vol) async {
    await _player.setVolume(vol.clamp(0.0, 1.0));
  }

  /// Set loop mode: LoopMode.off / .all / .one
  Future<void> setLoopMode(LoopMode mode) async {
    await _player.setLoopMode(mode);
  }

  /// Enable/disable just_audio's built-in shuffle order.
  Future<void> setShuffleEnabled(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
  }

  // ════════════════════════════════════════════════
  //  AUDIO CACHE MANAGEMENT — Phase 8
  // ════════════════════════════════════════════════

  /// Clear all cached audio files created by [LockCachingAudioSource].
  /// just_audio stores cached files in the temporary directory.
  /// Returns the number of bytes freed (approximate).
  static Future<int> clearAudioCache() async {
    try {
      final dir = await _getAudioCacheDir();
      if (dir == null || !await dir.exists()) return 0;

      int totalBytes = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          totalBytes += await entity.length();
          await entity.delete();
        }
      }
      debugPrint('=== NINAADA HANDLER: cleared audio cache (${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB) ===');
      return totalBytes;
    } catch (e) {
      debugPrint('=== NINAADA HANDLER: clearAudioCache error: $e ===');
      return 0;
    }
  }

  /// Get the approximate size of the audio cache in bytes.
  static Future<int> getAudioCacheSize() async {
    try {
      final dir = await _getAudioCacheDir();
      if (dir == null || !await dir.exists()) return 0;

      int totalBytes = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
      return totalBytes;
    } catch (_) {
      return 0;
    }
  }

  static Future<Directory?> _getAudioCacheDir() async {
    try {
      final tempDir = await getTemporaryDirectory();
      return Directory('${tempDir.path}/ninaada_audio_cache');
    } catch (_) {
      return null;
    }
  }

  // ════════════════════════════════════════════════
  //  INTERNAL HELPERS
  // ════════════════════════════════════════════════

  /// Convert Song → AudioSource for ConcatenatingAudioSource.
  ///
  /// Priority chain (Phase 9 routing):
  ///   1. Explicit download (DownloadManager) → AudioSource.file
  ///   2. Song.localUri field                  → AudioSource.file
  ///   3. LockCachingAudioSource (Phase 8)     → cached network stream
  ///   4. Plain network fallback               → AudioSource.uri
  AudioSource _toAudioSource(Song song) {
    // ── Priority 1: Check DownloadManager for completed download ──
    final dlPath = DownloadManager().getLocalPath(song.id);
    if (dlPath != null && File(dlPath).existsSync()) {
      debugPrint('=== AUDIO: routing ${song.id} → DOWNLOADED file ===');
      return AudioSource.file(
        dlPath,
        tag: _toMediaItem(song),
      );
    }

    // ── Priority 2: Song already has a localUri (legacy path) ──
    if (song.localUri != null && song.localUri!.isNotEmpty) {
      final f = File(song.localUri!);
      if (f.existsSync()) {
        debugPrint('=== AUDIO: routing ${song.id} → localUri ===');
        return AudioSource.file(
          song.localUri!,
          tag: _toMediaItem(song),
        );
      }
    }

    // ── Priority 3: LockCachingAudioSource (Phase 8 stream cache) ──
    if (_audioCacheDirPath != null) {
      return LockCachingAudioSource(
        Uri.parse(song.mediaUrl),
        cacheFile: File('$_audioCacheDirPath/${song.id}.cached'),
        tag: _toMediaItem(song),
      );
    }

    // ── Priority 4: Fallback plain network ──
    return AudioSource.uri(
      Uri.parse(song.mediaUrl),
      tag: _toMediaItem(song),
    );
  }

  /// Convert Song → MediaItem for audio_service (notification metadata).
  /// Uses local album art when available (offline lock screen support).
  MediaItem _toMediaItem(Song song) {
    // Check for locally-downloaded album art so lock screen works offline
    Uri? artUri;
    final localArt = DownloadManager().getLocalArtPath(song.id);
    if (localArt != null && File(localArt).existsSync()) {
      artUri = Uri.file(localArt);
    } else {
      artUri = Uri.tryParse(song.image);
    }

    return MediaItem(
      id: song.id,
      title: song.name,
      artist: song.artist,
      album: song.album,
      artUri: artUri,
      duration: Duration(seconds: song.duration),
    );
  }

  /// Transform just_audio PlaybackEvent → audio_service PlaybackState.
  /// This is what powers the notification and lock screen.
  /// Song mode: [Prev] [Play/Pause] [Next] — all 3 in compact view.
  /// Radio mode: [Play/Pause] only — skip is meaningless for streams.
  PlaybackState _transformEvent(PlaybackEvent event) {
    final isStream = _streamMode;
    final playing = _player.playing;
    return PlaybackState(
      controls: [
        if (!isStream) MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        if (!isStream) MediaControl.skipToNext,
      ],
      systemActions: {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        if (!isStream) MediaAction.skipToNext,
        if (!isStream) MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: isStream ? const [0] : const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }

  /// Release all resources.
  Future<void> dispose() async {
    onTrackChanged = null;
    onQueueEnd = null;
    onAppKilled = null;
    _interruptSub?.cancel();
    _noisySub?.cancel();
    await _player.dispose();
  }
}

// ================================================================
//  SIMPLE MUTEX — FIFO async lock for queue mutations
// ================================================================
//
//  Serializes queue mutations (_songs + _playlist) so interleaved
//  async operations don't corrupt index synchronization.
//  NOT used for playback versioning — that's handled natively by
//  just_audio's PlayerInterruptedException.
// ================================================================

class _SimpleMutex {
  Future<void> _chain = Future.value();

  Future<T> protect<T>(Future<T> Function() action) async {
    final prev = _chain;
    final completer = Completer<void>();
    _chain = completer.future;

    try {
      await prev;
    } catch (_) {}

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}
