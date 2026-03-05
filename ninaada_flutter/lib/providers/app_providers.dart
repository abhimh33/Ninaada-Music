import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/media_theme_engine.dart';
import 'package:ninaada_music/core/queue_manager.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/data/user_taste_profile.dart';
import 'package:ninaada_music/data/user_profile.dart';
import 'package:ninaada_music/services/download_manager.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/services/ninaada_audio_handler.dart';
import 'package:ninaada_music/services/pre_buffer_engine.dart';
import 'package:ninaada_music/services/prefetch_engine.dart';
import 'package:ninaada_music/services/queue_persistence_service.dart';
import 'package:ninaada_music/services/behavior_engine.dart';
import 'package:ninaada_music/services/recommendation_engine.dart';
import 'package:ninaada_music/providers/session_context_provider.dart';
import 'package:ninaada_music/core/app_keys.dart';

/// Show a reactive toast via global ScaffoldMessenger — survives screen switches.
void _toast(String msg) {
  final messenger = scaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13)),
      backgroundColor: const Color(0xFF1A1A2E),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      duration: const Duration(seconds: 2),
    ),
  );
}

// ================================================================
//  PLAYBACK MODE — distinguishes song queue vs live radio stream
// ================================================================

enum PlaybackMode { song, radio }

// ================================================================
//  AUDIO HANDLER PROVIDER — initialized in main.dart
// ================================================================

final audioHandlerProvider = Provider<NinaadaAudioHandler>((ref) {
  throw UnimplementedError(
    'audioHandlerProvider must be overridden with ProviderScope in main.dart',
  );
});

// ================================================================
//  NAVIGATION
// ================================================================

enum AppTab { home, explore, library, radio }

class NavigationState {
  final AppTab currentTab;
  final List<AppTab> navStack;
  /// Linked-list overlay stack for sub-view navigation.
  /// Supports multi-level stacking: artist → album → credits → back.
  final List<Map<String, dynamic>> subViewStack;
  final bool showSearch;

  const NavigationState({
    this.currentTab = AppTab.home,
    this.navStack = const [AppTab.home],
    this.subViewStack = const [],
    this.showSearch = false,
  });

  /// Current (top-most) sub-view, or null if no overlay is active.
  Map<String, dynamic>? get subView =>
      subViewStack.isNotEmpty ? subViewStack.last : null;

  bool get hasSubView => subViewStack.isNotEmpty;

  NavigationState copyWith({
    AppTab? currentTab,
    List<AppTab>? navStack,
    List<Map<String, dynamic>>? subViewStack,
    bool? showSearch,
    bool clearSubView = false,
  }) {
    return NavigationState(
      currentTab: currentTab ?? this.currentTab,
      navStack: navStack ?? this.navStack,
      subViewStack: clearSubView ? const [] : (subViewStack ?? this.subViewStack),
      showSearch: showSearch ?? this.showSearch,
    );
  }
}

class NavigationNotifier extends StateNotifier<NavigationState> {
  NavigationNotifier() : super(const NavigationState());

  /// Maximum tab back-history depth. Prevents unbounded growth
  /// from rapid tab switching. Oldest entries are trimmed.
  static const _maxStackDepth = 12;

  void goTab(AppTab tab) {
    // Same tab + no overlays → no-op
    if (tab == state.currentTab && !state.hasSubView && !state.showSearch) {
      return;
    }

    // Same tab but overlays active → collapse overlays, stay on tab
    if (tab == state.currentTab) {
      state = state.copyWith(clearSubView: true, showSearch: false);
      return;
    }

    // New tab → push to back-history (avoid consecutive duplicates)
    var newStack = List<AppTab>.from(state.navStack);
    if (newStack.isEmpty || newStack.last != tab) {
      newStack.add(tab);
    }
    // Trim oldest entries if stack exceeds max depth
    if (newStack.length > _maxStackDepth) {
      newStack = newStack.sublist(newStack.length - _maxStackDepth);
    }

    state = NavigationState(
      currentTab: tab,
      navStack: newStack,
      subViewStack: const [],
      showSearch: false,
    );
  }

  /// Push a sub-view onto the overlay stack.
  /// Supports multi-level: artist → album → credits.
  void setSubView(Map<String, dynamic>? view) {
    if (view == null) {
      // Pop the top sub-view
      popSubView();
    } else {
      state = state.copyWith(
        subViewStack: [...state.subViewStack, view],
      );
    }
  }

  /// Pop the top-most sub-view from the overlay stack.
  void popSubView() {
    if (state.subViewStack.isEmpty) return;
    state = state.copyWith(
      subViewStack: state.subViewStack.sublist(0, state.subViewStack.length - 1),
    );
  }

  /// Clear all sub-views (collapse entire overlay stack).
  void clearSubViews() {
    state = state.copyWith(clearSubView: true);
  }

  void toggleSearch(bool show) {
    state = state.copyWith(showSearch: show);
  }

  /// Handle back press, returns true if handled internally.
  /// Returns false when at root (caller should handle exit).
  bool handleBack() {
    // Priority 1: Close search overlay
    if (state.showSearch) {
      state = state.copyWith(showSearch: false);
      return true;
    }
    // Priority 2: Pop top sub-view from linked-list stack
    if (state.subViewStack.isNotEmpty) {
      popSubView();
      return true;
    }
    // Priority 3: Pop to previous tab in back-history
    if (state.navStack.length > 1) {
      final ns = List<AppTab>.from(state.navStack)
        ..removeLast();
      state = NavigationState(
        currentTab: ns.last,
        navStack: ns,
      );
      return true;
    }
    // At root (Home tab, no overlays) — caller decides (exit/minimize)
    return false;
  }

  /// Whether the navigation is at the absolute root:
  /// Home tab, no sub-views, no search, single-entry navStack.
  bool get isAtRoot =>
      state.currentTab == AppTab.home &&
      !state.hasSubView &&
      !state.showSearch &&
      state.navStack.length <= 1;
}

final navigationProvider = StateNotifierProvider<NavigationNotifier, NavigationState>(
  (ref) => NavigationNotifier(),
);

// ================================================================
//  PLAYER STATE
// ================================================================

/// Controls the visual state of the global player overlay.
/// hidden → no player surface visible
/// mini   → 70px bar above bottom nav
/// full   → expanded full-screen player
enum PlayerViewState { hidden, mini, full }

class PlayerState {
  final Song? currentSong;
  final bool isPlaying;
  final double progress; // seconds
  final double duration; // seconds
  final bool shuffle;
  final String repeat; // 'off' | 'all' | 'one'
  final bool autoPlay;
  final double playbackSpeed;
  final List<Song> queue;
  final QueueSnapshot queueSnapshot;
  final String? queueContext;
  final bool miniPlayerVisible;
  final PlayerViewState viewState;
  final Map<String, dynamic> dynamicColors;

  /// Shuffle playback order indices from just_audio.
  /// null when shuffle is off; list of source indices when on.
  final List<int>? shuffleIndices;

  /// True when the audio engine is buffering (loading / rebuffering).
  final bool isBuffering;

  // ── Radio state ──
  final PlaybackMode playbackMode;
  final RadioStation? activeRadioStation;
  final bool radioLoading;

  const PlayerState({
    this.currentSong,
    this.isPlaying = false,
    this.progress = 0,
    this.duration = 0,
    this.shuffle = false,
    this.repeat = 'off',
    this.autoPlay = true,
    this.playbackSpeed = 1.0,
    this.queue = const [],
    this.queueSnapshot = QueueSnapshot.empty,
    this.queueContext,
    this.miniPlayerVisible = false,
    this.viewState = PlayerViewState.hidden,
    this.shuffleIndices,
    this.dynamicColors = const {
      'bg': [Color(0xFF1A1A2E), Color(0xFF0B0F1A), Color(0xFF10141F)],
      'accent': Color(0xFF8B5CF6),
    },
    this.isBuffering = false,
    this.playbackMode = PlaybackMode.song,
    this.activeRadioStation,
    this.radioLoading = false,
  });

  /// Convenience: true when a radio stream is the active audio source.
  bool get isRadioMode => playbackMode == PlaybackMode.radio;

  PlayerState copyWith({
    Song? currentSong,
    bool? isPlaying,
    double? progress,
    double? duration,
    bool? shuffle,
    String? repeat,
    bool? autoPlay,
    double? playbackSpeed,
    List<Song>? queue,
    QueueSnapshot? queueSnapshot,
    String? queueContext,
    bool? miniPlayerVisible,
    PlayerViewState? viewState,
    List<int>? shuffleIndices,
    Map<String, dynamic>? dynamicColors,
    bool? isBuffering,
    PlaybackMode? playbackMode,
    RadioStation? activeRadioStation,
    bool? radioLoading,
    bool clearSong = false,
    bool clearRadio = false,
  }) {
    return PlayerState(
      currentSong: clearSong ? null : (currentSong ?? this.currentSong),
      isPlaying: isPlaying ?? this.isPlaying,
      progress: progress ?? this.progress,
      duration: duration ?? this.duration,
      shuffle: shuffle ?? this.shuffle,
      repeat: repeat ?? this.repeat,
      autoPlay: autoPlay ?? this.autoPlay,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      queue: queue ?? this.queue,
      queueSnapshot: queueSnapshot ?? this.queueSnapshot,
      queueContext: queueContext ?? this.queueContext,
      miniPlayerVisible: miniPlayerVisible ?? this.miniPlayerVisible,
      viewState: viewState ?? this.viewState,
      shuffleIndices: shuffleIndices ?? this.shuffleIndices,
      dynamicColors: dynamicColors ?? this.dynamicColors,
      isBuffering: isBuffering ?? this.isBuffering,
      playbackMode: playbackMode ?? this.playbackMode,
      activeRadioStation: clearRadio ? null : (activeRadioStation ?? this.activeRadioStation),
      radioLoading: radioLoading ?? this.radioLoading,
    );
  }
}

class PlayerNotifier extends StateNotifier<PlayerState> {
  final NinaadaAudioHandler _handler;
  final ApiService _api;
  final Ref _ref;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _processingSub;
  StreamSubscription? _downloadSub;
  ProviderSubscription? _networkSub;
  bool _queueDirty = false; // set by setQueue(), consumed by playSong()
  bool _streamsAttached = false; // guard against duplicate wiring

  // ══════════════════════════════════════════════════
  //  PLAYER VIEW STATE — overlay expand/collapse
  // ══════════════════════════════════════════════════

  void expandPlayer() {
    state = state.copyWith(viewState: PlayerViewState.full);
    // Fullscreen immersive — hide status bar + navigation bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void collapsePlayer() {
    state = state.copyWith(viewState: PlayerViewState.mini);
    // Restore system UI when leaving full player
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void hidePlayer() {
    state = state.copyWith(viewState: PlayerViewState.hidden);
  }

  /// Tick counter for periodic position persist (every ~30 position ticks ≈ 30s)
  int _persistTickCounter = 0;

  /// Phase 9B: Flag to prevent double-logging when playNext/playPrev
  /// triggers onTrackChanged after we already logged the event.
  bool _behaviorSkipLogged = false;

  PlayerNotifier(this._ref)
      : _handler = _ref.read(audioHandlerProvider),
        _api = ApiService(),
        super(const PlayerState()) {
    _wireStreams();
  }

  // ══════════════════════════════════════════════════
  //  PHASE 9B: BEHAVIOR EVENT LOGGING
  // ══════════════════════════════════════════════════

  /// Log a behavior event for the PREVIOUS song (the one currently in state)
  /// before transitioning to the next song.
  ///
  /// Called from:
  ///   • playNext() / playPrev() → manualSkip = true
  ///   • onTrackChanged (natural advance) → manualSkip = false
  ///   • playSong() (user picks a new song) → manualSkip = false
  void _logBehaviorForPreviousSong(bool manualSkip) {
    if (!BehaviorEngine.isInitialized) return;
    final song = state.currentSong;
    if (song == null) return;
    if (state.duration <= 0) return; // no duration data → can't compute percentage

    final playPercentage = (state.progress / state.duration).clamp(0.0, 1.0);

    // Don't log if barely started (< 1 second) — likely a queue setup artifact
    if (state.progress < 1.0 && !manualSkip) return;

    final event = ListeningEvent(
      songId: song.id,
      artist: song.artist,
      language: song.language,
      playPercentage: playPercentage,
      manualSkip: manualSkip,
      timestamp: DateTime.now(),
    );

    // Fire-and-forget — BehaviorEngine handles persistence internally
    BehaviorEngine.instance.logEvent(event);
  }

  // ══════════════════════════════════════════════════
  //  QUEUE PERSISTENCE — Phase 8
  // ══════════════════════════════════════════════════

  /// Schedule a debounced persist of the current playback state.
  /// Called on track changes, queue mutations, and periodic position updates.
  void _schedulePersist() {
    if (state.isRadioMode || state.queueSnapshot.isEmpty) return;
    QueuePersistenceService.instance.scheduleWrite(
      snapshot: state.queueSnapshot,
      positionMs: (state.progress * 1000).toInt(),
      shuffle: state.shuffle,
      repeat: state.repeat,
      autoPlay: state.autoPlay,
      playbackSpeed: state.playbackSpeed,
    );
  }

  /// Cold boot restoration — loads saved queue state into the audio engine
  /// without playing. The player is paused and ready at the saved position.
  /// Returns true if a state was successfully restored.
  Future<bool> restoreFromSavedState() async {
    try {
      final saved = QueuePersistenceService.instance.loadSavedState();
      if (saved == null) return false;

      final songs = saved.snapshot.items;
      if (songs.isEmpty) return false;

      final idx = saved.snapshot.currentIndex.clamp(0, songs.length - 1);
      final currentSong = songs[idx];

      // 1. Load queue into audio engine without playing
      await _handler.loadQueueSilent(
        songs,
        initialIndex: idx,
        initialPosition: Duration(milliseconds: saved.positionMs),
      );

      // 2. Sync playback settings
      if (saved.playbackSpeed != 1.0) {
        await _handler.setRate(saved.playbackSpeed);
      }
      if (saved.shuffle) {
        await _handler.setShuffleEnabled(true);
      }

      // 3. Update Riverpod state — player is paused at saved position
      state = state.copyWith(
        currentSong: currentSong,
        isPlaying: false,
        progress: saved.positionMs / 1000.0,
        duration: currentSong.duration > 0
            ? currentSong.duration.toDouble()
            : 240,
        queue: songs,
        queueSnapshot: saved.snapshot,
        queueContext: saved.snapshot.context,
        miniPlayerVisible: true,
        viewState: PlayerViewState.mini,
        shuffle: saved.shuffle,
        repeat: saved.repeat,
        autoPlay: saved.autoPlay,
        playbackSpeed: saved.playbackSpeed,
        dynamicColors: extractDominantColor(currentSong.image),
      );

      // 4. Sync loop mode
      _syncLoopMode();

      // 5. Update media theme
      _ref.read(mediaThemeProvider.notifier).onSongChanged(currentSong);

      debugPrint(
        '=== NINAADA: restored queue (${songs.length} songs, '
        'idx=$idx, pos=${saved.positionMs}ms) ===',
      );
      return true;
    } catch (e) {
      debugPrint('=== NINAADA: restoreFromSavedState FAILED: $e ===');
      return false;
    }
  }

  void _wireStreams() {
    // ── Guard: prevent duplicate subscriptions ──
    if (_streamsAttached) return;
    _streamsAttached = true;

    // ── Position updates ──
    _positionSub = _handler.positionStream.listen((pos) {
      if (!mounted) return;
      // ── Seek suspension: suppress jitter while seeking ──
      if (_handler.isSeeking) return;
      final secs = pos.inMilliseconds / 1000.0;
      state = state.copyWith(progress: secs);

      // ── Periodic position persist (every ~30 ticks ≈ 30s) ──
      _persistTickCounter++;
      if (_persistTickCounter >= 30) {
        _persistTickCounter = 0;
        _schedulePersist();
      }

      // ── Predictive pre-fetch at 80% ──
      final cur = state.currentSong;
      if (cur != null && state.duration > 0) {
        PrefetchEngine.onPositionTick(
          progress: secs,
          duration: state.duration,
          queue: state.queue,
          currentIndex: _handler.currentIndex,
          currentSongId: cur.id,
          autoPlay: state.autoPlay,
        );
      }
    });

    // ── Duration updates ──
    _durationSub = _handler.durationStream.listen((dur) {
      if (!mounted || dur == null) return;
      state = state.copyWith(duration: dur.inMilliseconds / 1000.0);
    });

    // ── Player state (playing/paused) ──
    _stateSub = _handler.playerStateStream.listen((playerState) {
      if (!mounted) return;
      state = state.copyWith(isPlaying: playerState.playing);
      // Auto-clear radio loading when the stream actually starts playing.
      // Belt-and-suspenders: even if playRadio()'s post-await update is
      // stale-guarded (newer station tapped), the spinner still clears.
      if (playerState.playing && state.radioLoading && state.isRadioMode) {
        state = state.copyWith(radioLoading: false);
      }
      // ── Persist on pause (Phase 8) ──
      // When the user pauses, immediately schedule a persist so the exact
      // pause position is captured. Without this, the saved position could
      // drift up to ~6 seconds behind (periodic tick interval).
      if (!playerState.playing && state.currentSong != null) {
        _schedulePersist();
      }
    });

    // ── Processing state (buffering indicator) ──
    _processingSub = _handler.processingStateStream.listen((procState) {
      if (!mounted) return;
      final buffering = procState == ProcessingState.loading ||
          procState == ProcessingState.buffering;
      if (buffering != state.isBuffering) {
        state = state.copyWith(isBuffering: buffering);
      }

      // ── Phase 6, Step 8: Buffer loop prevention ──
      // If we're buffering while offline with no local file,
      // pause immediately to avoid infinite spinner.
      if (buffering) {
        final network = _ref.read(networkProvider);
        final cur = state.currentSong;
        if (network == NetworkStatus.offline && cur != null && !_hasLocalFile(cur.id)) {
          _handler.pause();
          _toast('Connection lost.');
          debugPrint('=== NINAADA: buffer loop prevented (offline, no local) ===');
        }
      }
    });

    // ── Track changed callback (gapless advance) ──
    _handler.onTrackChanged = (index, song) {
      if (!mounted) return;
      // Skip if we already set this song (from playSong direct call)
      if (state.currentSong?.id == song.id) return;

      // ── Phase 9B: Log behavior for the OUTGOING song ──
      if (_behaviorSkipLogged) {
        _behaviorSkipLogged = false; // Already logged in playNext/playPrev
      } else {
        _logBehaviorForPreviousSong(false); // Natural gapless advance
      }

      state = state.copyWith(
        currentSong: song,
        progress: 0,
        miniPlayerVisible: true,
        queue: _handler.songQueue,
        shuffleIndices: state.shuffle ? _handler.shuffleIndices : null,
        dynamicColors: extractDominantColor(song.image),
      );
      // Reset prefetch tracker for new song
      PrefetchEngine.onSongChanged(song.id);
      // Update media theme
      _ref.read(mediaThemeProvider.notifier).onSongChanged(song);
      // Record play
      _ref.read(libraryProvider.notifier).addRecent(song);
      _ref.read(libraryProvider.notifier).incPlayCount(song);
      // Update session context for mood-aware recommendations
      _ref.read(sessionContextProvider.notifier).onSongPlayed(song);
      // Trigger rolling pre-buffer replenishment (fire-and-forget)
      PreBufferEngine.onTrackAdvanced(
        handler: _handler,
        autoPlay: state.autoPlay,
      );
      // ── Persist queue state on track change ──
      _schedulePersist();
    };

    // ── Queue completed callback ──
    _handler.onQueueEnd = () {
      if (!mounted) return;
      _onQueueEnd();
    };

    // ── App killed callback (Phase 8) ──
    // Fires from onTaskRemoved when user swipes app from recents.
    // Flush the pending queue persist BEFORE the process dies.
    _handler.onAppKilled = () {
      _schedulePersist();
      QueuePersistenceService.instance.flushNow();
    };

    // ── Download completion bridge (Phase 5) ──
    // One-way event: DownloadManager → PlayerNotifier hot-swap.
    // No circular provider dependency.
    _downloadSub = DownloadManager().downloadCompletedStream.listen(
      _handleDownloadCompleted,
    );

    // ── Phase 6, Step 6+7: Mid-playback network drop/recovery ──
    _networkSub = _ref.listen<NetworkStatus>(networkProvider, (prev, next) {
      if (!mounted) return;
      if (next == NetworkStatus.offline) {
        _handleNetworkDrop();
      }
      // Step 7: On recovery, we do NOT auto-switch current local playback
      // back to remote. The banner disappears, future plays may stream
      // normally, but current playback is never silently mutated.
    });
  }

  // ══════════════════════════════════════════════════
  //  NETWORK DROP HANDLER — Phase 6, Step 6
  // ══════════════════════════════════════════════════

  /// Called when network transitions to offline mid-playback.
  /// If current song has a local copy → hot-swap silently.
  /// If no local copy → pause with message. No endless spinner.
  void _handleNetworkDrop() {
    final cur = state.currentSong;
    if (cur == null) return;

    if (_hasLocalFile(cur.id)) {
      // Hot-swap to local file (Phase 5 infrastructure)
      final index = _handler.songQueue.indexWhere((s) => s.id == cur.id);
      if (index != -1) {
        _handler.hotSwapSource(index);
        debugPrint('=== NINAADA: network drop → hot-swapped to local ===');
      }
    } else if (state.isPlaying) {
      // No local file — pause to avoid infinite buffering
      _handler.pause();
      _toast('Connection lost.');
      debugPrint('=== NINAADA: network drop → paused (no local) ===');
    }
  }

  // ══════════════════════════════════════════════════
  //  DOWNLOAD HOT-SWAP — Phase 5
  // ══════════════════════════════════════════════════

  /// Called when a download completes. Hot-swaps the audio source
  /// in-place from remote → local file without interrupting playback.
  Future<void> _handleDownloadCompleted(String songId) async {
    if (!mounted) return;
    // Guard: don't swap during active seeking, buffering, or queue reload
    if (_handler.isSeeking || state.isBuffering || _handler.isReloadingQueue) return;

    // Re-evaluate index fresh (never cache across awaits)
    final index = _handler.songQueue.indexWhere((s) => s.id == songId);
    if (index == -1) return;

    // Validate the download is truly complete with file on disk
    final record = DownloadManager().getRecord(songId);
    if (record == null || record.status != DownloadStatus.completed) return;
    if (record.localFilePath == null || !File(record.localFilePath!).existsSync()) return;

    // Pure source mutation — no state change, no rebuild, no UI flicker
    await _handler.hotSwapSource(index);
    debugPrint('=== NINAADA: hot-swapped ${songId} to local file ===');
  }

  /// Called when a download is deleted. Hot-swaps the audio source
  /// back from local file → remote stream without interrupting playback.
  Future<void> handleDownloadDeleted(String songId) async {
    if (!mounted) return;
    if (_handler.isReloadingQueue) return;

    final index = _handler.songQueue.indexWhere((s) => s.id == songId);
    if (index == -1) return;

    await _handler.hotSwapSource(index);
    debugPrint('=== NINAADA: hot-swapped ${songId} back to remote ===');
  }

  /// Check if a song has a playable local file on disk.
  bool _hasLocalFile(String songId) {
    final record = DownloadManager().getRecord(songId);
    if (record == null || record.status != DownloadStatus.completed) return false;
    return record.localFilePath != null &&
        File(record.localFilePath!).existsSync();
  }

  Future<void> playSong(Song song, {String? context, bool autoAdvance = false}) async {
    // ── Phase 9B: Log behavior for the song we're leaving ──
    if (state.currentSong != null && state.currentSong!.id != song.id) {
      _logBehaviorForPreviousSong(false);
    }

    // ── Phase 6: Strict Offline Guard ──
    // If offline and no local copy → hard stop. No fallback. No attempt.
    final network = _ref.read(networkProvider);
    final hasLocal = _hasLocalFile(song.id);

    if (network == NetworkStatus.offline && !hasLocal) {
      _toast('Download to play offline.');
      return;
    }

    // ── Snapshot for rollback on error ──
    final prevState = state;
    try {
      // 1. Immediate state update for responsive UI (optimistic)
      state = state.copyWith(
        currentSong: song,
        isPlaying: false,
        progress: 0,
        miniPlayerVisible: true,
        viewState: state.viewState == PlayerViewState.hidden
            ? PlayerViewState.mini
            : state.viewState,
        dynamicColors: extractDominantColor(song.image),
        playbackMode: PlaybackMode.song,
        clearRadio: true,
        radioLoading: false,
      );

      // Trigger dynamic media-theming engine
      _ref.read(mediaThemeProvider.notifier).onSongChanged(song);

      if (context != null) {
        state = state.copyWith(queueContext: context);
      }

      // 2. Sync queue to handler if dirty (setQueue was called before this)
      //    Uses replaceContextAndPlay for atomic stop→clear→load→play.
      if (_queueDirty) {
        _queueDirty = false;
        final idx = state.queue.indexWhere((s) => s.id == song.id);
        PreBufferEngine.reset(); // new context → reset pre-buffer tracker
        await _handler.replaceContextAndPlay(state.queue, idx >= 0 ? idx : 0);
      } else {
        // 3. Play via handler — seek-based for queue mode.
        await _handler.playSong(song);
      }

      // 4. Sync playback speed and loop mode
      if (state.playbackSpeed != 1.0) {
        await _handler.setRate(state.playbackSpeed);
      }
      _syncLoopMode();

      // 5. Final state
      state = state.copyWith(
        isPlaying: true,
        duration: song.duration > 0 ? song.duration.toDouble() : 240,
        queue: _handler.songQueue,
      );

      // Record play
      _ref.read(libraryProvider.notifier).addRecent(song);
      _ref.read(libraryProvider.notifier).incPlayCount(song);
      // Update session context for mood-aware recommendations
      _ref.read(sessionContextProvider.notifier).onSongPlayed(song);

      // Trigger rolling pre-buffer replenishment
      PreBufferEngine.onTrackAdvanced(
        handler: _handler,
        autoPlay: state.autoPlay,
      );

      // ── Persist queue state after playSong ──
      _schedulePersist();
    } catch (e) {
      debugPrint('=== NINAADA: playSong error: $e ===');
      // ── Rollback to previous state on failure ──
      state = prevState;
      _toast('Try other song.');
    }
  }

  Future<void> togglePlay() async {
    await _handler.togglePlayback();
  }

  // ── Skip debounce (250ms) — prevents rapid double-fire ──
  DateTime _lastSkipTime = DateTime(2000);

  Future<void> playNext() async {
    final now = DateTime.now();
    if (now.difference(_lastSkipTime).inMilliseconds < 250) return;
    // ── Buffering guard: don't skip while engine is still loading ──
    if (state.isBuffering) return;
    _lastSkipTime = now;

    // ── Phase 9B: Log behavior for current song as manual skip ──
    _logBehaviorForPreviousSong(true);
    _behaviorSkipLogged = true;

    final q = _handler.songQueue;
    if (q.isEmpty) return;

    final curIdx = _handler.currentIndex;

    // At end of queue with no loop/shuffle? → try auto-play similar
    if (curIdx >= q.length - 1 && state.repeat == 'off' && !state.shuffle) {
      if (state.autoPlay && state.currentSong != null) {
        await _fetchSimilarAndPlay(state.currentSong!);
      }
      return;
    }

    // Let the handler advance (ConcatenatingAudioSource handles gapless)
    await _handler.skipToNext();
  }

  Future<void> playPrev() async {
    final now = DateTime.now();
    if (now.difference(_lastSkipTime).inMilliseconds < 250) return;
    // ── Buffering guard: don't skip while engine is still loading ──
    if (state.isBuffering) return;
    _lastSkipTime = now;

    // ── Phase 9B: Log behavior for current song as manual skip ──
    _logBehaviorForPreviousSong(true);
    _behaviorSkipLogged = true;

    await _handler.skipToPrevious();
  }

  Future<void> seekTo(double fraction) async {
    if (state.duration <= 0) return;
    final pos = fraction * state.duration;
    await _handler.seekTo(pos);
    state = state.copyWith(progress: pos);
  }

  void toggleShuffle() {
    final newShuffle = !state.shuffle;
    state = state.copyWith(shuffle: newShuffle);
    _handler.setShuffleEnabled(newShuffle);
    // Sync shuffle indices after engine processes the change
    Future.microtask(() {
      if (!mounted) return;
      state = state.copyWith(
        shuffleIndices: newShuffle ? _handler.shuffleIndices : null,
      );
    });
  }

  void cycleRepeat() {
    const modes = ['off', 'all', 'one'];
    final idx = modes.indexOf(state.repeat);
    state = state.copyWith(repeat: modes[(idx + 1) % 3]);
    _syncLoopMode();
  }

  /// Sync Riverpod repeat state → just_audio LoopMode
  void _syncLoopMode() {
    switch (state.repeat) {
      case 'one':
        _handler.setLoopMode(LoopMode.one);
      case 'all':
        _handler.setLoopMode(LoopMode.all);
      default:
        _handler.setLoopMode(LoopMode.off);
    }
  }

  void toggleAutoPlay() => state = state.copyWith(autoPlay: !state.autoPlay);

  Future<void> changeSpeed(double speed) async {
    final rounded = (speed * 100).round() / 100.0;
    state = state.copyWith(playbackSpeed: rounded);
    await _handler.setRate(rounded);
  }

  /// Set the queue data. Marks dirty so next playSong() syncs to handler.
  /// Also creates a QueueSnapshot for immutable queue tracking.
  void setQueue(List<Song> songs) {
    final snapshot = QueueManager.create(songs, context: state.queueContext);
    state = state.copyWith(queue: songs, queueSnapshot: snapshot);
    _queueDirty = true;
  }

  /// Insert [song] immediately after the currently playing track.
  /// Syncs both state, QueueSnapshot, and ConcatenatingAudioSource.
  void insertNext(Song song) {
    _handler.insertNext(song);
    final newQueue = _handler.songQueue;
    final snapshot = QueueManager.insertNext(state.queueSnapshot, song);
    state = state.copyWith(queue: newQueue, queueSnapshot: snapshot);
    _schedulePersist();
  }

  /// Add [song] to the user-intent zone (inserts at the autoplay boundary).
  /// Ensures user-added songs always play before algorithmic songs.
  Future<void> addToQueue(Song song) async {
    final boundary = state.queueSnapshot.effectiveAutoPlayStart;
    await _handler.insertAt(boundary, song);
    final newQueue = _handler.songQueue;
    final snapshot = QueueManager.addToEnd(state.queueSnapshot, song);
    state = state.copyWith(queue: newQueue, queueSnapshot: snapshot);
    _schedulePersist();
  }

  /// Add multiple [songs] to the user-intent zone (inserts at boundary).
  /// Ensures user-added songs always play before algorithmic songs.
  Future<void> addAllToQueue(List<Song> songs) async {
    if (songs.isEmpty) return;
    final boundary = state.queueSnapshot.effectiveAutoPlayStart;
    await _handler.insertAllAt(boundary, songs);
    final newQueue = _handler.songQueue;
    final snapshot = QueueManager.addAll(state.queueSnapshot, songs);
    state = state.copyWith(queue: newQueue, queueSnapshot: snapshot);
    _schedulePersist();
  }

  /// Insert multiple [songs] immediately after current track (with dedup).
  Future<void> insertAllNext(List<Song> songs) async {
    if (songs.isEmpty) return;
    await _handler.insertAllNext(songs);
    final newQueue = _handler.songQueue;
    final snapshot = QueueManager.insertAllNext(state.queueSnapshot, songs);
    state = state.copyWith(queue: newQueue, queueSnapshot: snapshot);
    _schedulePersist();
  }

  /// Reorder a song in the queue.
  /// Syncs QueueSnapshot (immutable state), handler _songs list,
  /// AND ConcatenatingAudioSource simultaneously via mutex lock.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    // Apply Flutter's standard index shift at the Riverpod layer
    // so the handler receives already-adjusted indices.
    int adjustedNew = newIndex;
    if (oldIndex < newIndex) adjustedNew -= 1;
    if (adjustedNew < 0 || adjustedNew >= state.queue.length) return;
    if (oldIndex == adjustedNew) return;

    // 1. Sync the audio engine (mutates _songs + _playlist under mutex)
    await _handler.reorderQueue(oldIndex, adjustedNew);

    // 2. Produce new immutable QueueSnapshot
    //    (pass raw oldIndex/newIndex — QueueManager.reorder applies the
    //    same shift internally for QueueSnapshot consistency)
    final snapshot = QueueManager.reorder(state.queueSnapshot, oldIndex, newIndex);

    // 3. Update Riverpod state
    state = state.copyWith(
      queue: _handler.songQueue,
      queueSnapshot: snapshot,
    );
    _schedulePersist();
  }

  /// Remove a song from the queue by index.
  /// Syncs QueueSnapshot, handler _songs list,
  /// AND ConcatenatingAudioSource simultaneously via mutex lock.
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= state.queue.length) return;

    final wasCurrentSong = _handler.currentIndex == index;

    // 1. Sync the audio engine (mutates _songs + _playlist under mutex)
    await _handler.removeFromQueue(index);

    // 2. Produce new immutable QueueSnapshot
    final snapshot = QueueManager.removeAt(state.queueSnapshot, index);

    // 3. Read fresh queue from handler (source of truth post-mutation)
    final newQueue = _handler.songQueue;

    if (newQueue.isEmpty) {
      state = state.copyWith(
        queue: [],
        queueSnapshot: QueueSnapshot.empty,
        clearSong: true,
        isPlaying: false,
        miniPlayerVisible: false,
        viewState: PlayerViewState.hidden,
      );
      return;
    }

    // 4. If the removed song was playing, update currentSong from handler
    final updatedSong = wasCurrentSong ? _handler.currentSong : state.currentSong;

    state = state.copyWith(
      queue: newQueue,
      queueSnapshot: snapshot,
      currentSong: updatedSong,
    );
    _schedulePersist();
  }

  /// Fisher–Yates shuffle and start playback from index 0.
  Future<void> shufflePlay(List<Song> songs) async {
    if (songs.isEmpty) return;
    final shuffled = List<Song>.from(songs);
    final rng = Random();
    for (int i = shuffled.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    state = state.copyWith(shuffle: true);
    await _handler.replaceAndPlay(shuffled, startIndex: 0);
    state = state.copyWith(queue: _handler.songQueue);
  }

  /// Generate a mix from a seed song — DESTRUCTIVE PIVOT.
  ///
  /// 1. Stops all current playback and clears the queue.
  /// 2. Loads [seed, ...similar] as a fresh queue.
  /// 3. Sets autoPlayStartIndex to 1 (seed is explicit, rest is discovery).
  /// 4. Starts playback from the seed.
  Future<void> startMix(Song seed) async {
    try {
      // 1. Stop + clear atomically
      await _handler.clearQueue();

      // 2. Fetch similar songs
      final similar = await _api.fetchSimilarSongs(seed.id);
      final filtered = similar.where((s) => s.id != seed.id).toList();
      final queue = [seed, ...filtered];

      // 3. Create snapshot with boundary: seed is at index 0 (user intent),
      //    everything from index 1 onward is algorithmic discovery.
      final snapshot = QueueManager.create(
        queue,
        startIndex: 0,
        context: 'Mix: ${seed.name}',
        autoPlayStartIndex: 1,
      );

      // 4. Load into handler and play
      await _handler.loadQueue(queue, initialIndex: 0);
      await _handler.play();

      state = state.copyWith(
        currentSong: seed,
        queue: queue,
        queueSnapshot: snapshot,
        queueContext: 'Mix: ${seed.name}',
        isPlaying: true,
        miniPlayerVisible: true,
        viewState: state.viewState == PlayerViewState.hidden
            ? PlayerViewState.mini
            : state.viewState,
        playbackMode: PlaybackMode.song,
        clearRadio: true,
      );

      _queueDirty = false;
      _ref.read(libraryProvider.notifier).addRecent(seed);
    } catch (_) {
      // Fallback: just play the seed song normally
      await playSong(seed, autoAdvance: true);
    }
  }

  /// Dismiss (clear) the queue without disposing the player instance.
  void dismissQueue() {
    _handler.clearQueue();
    state = state.copyWith(queue: [], queueContext: null);
    // Clear persisted state — queue is explicitly dismissed
    QueuePersistenceService.instance.clearSavedState();
  }

  Future<void> stopAndClear() async {
    await _handler.clearQueue();
    state = state.copyWith(
      clearSong: true,
      isPlaying: false,
      miniPlayerVisible: false,
      viewState: PlayerViewState.hidden,
      queue: [],
      playbackMode: PlaybackMode.song,
      clearRadio: true,
      radioLoading: false,
    );
  }

  // ════════════════════════════════════════════════
  //  RADIO PLAYBACK — unified through PlayerState
  // ════════════════════════════════════════════════

  /// Play a radio station. Atomically stops current audio (song or radio),
  /// switches to stream mode, and updates state for all listeners.
  /// Tapping the same station toggles pause/resume.
  Future<void> playRadio(RadioStation station) async {
    // ── Toggle: same station → pause/resume ──
    if (state.isRadioMode && state.activeRadioStation?.id == station.id) {
      await _handler.togglePlayback();
      return;
    }

    // ── EAGER UI: instantly mark station as active + loading ──
    // The _stateSub listener syncs isPlaying from the actual player
    // state automatically — do NOT set isPlaying here to avoid
    // flicker fights with the listener.
    state = state.copyWith(
      playbackMode: PlaybackMode.radio,
      activeRadioStation: station,
      radioLoading: true,
      miniPlayerVisible: false,
      viewState: PlayerViewState.hidden,
    );

    _toast('Connecting to radio...');

    try {
      debugPrint('=== NINAADA: playRadio starting stream for ${station.name} ===');
      await _handler.playStream(
        station.url,
        title: station.name,
        artist: 'Live Radio',
      ).timeout(const Duration(seconds: 25));
      debugPrint('=== NINAADA: playRadio stream started OK ===');

      if (state.activeRadioStation?.id == station.id) {
        state = state.copyWith(
          radioLoading: false,
          isPlaying: true,
        );
        _toast('Radio started.');
      }
    } catch (e) {
      debugPrint('=== NINAADA: playRadio attempt 1 failed: $e, retrying... ===');
      // ── Retry once before giving up ──
      try {
        await _handler.playStream(
          station.url,
          title: station.name,
          artist: 'Live Radio',
        ).timeout(const Duration(seconds: 25));
        debugPrint('=== NINAADA: playRadio retry OK ===');

        if (state.activeRadioStation?.id == station.id) {
          state = state.copyWith(
            radioLoading: false,
            isPlaying: true,
          );
          _toast('Radio started.');
        }
      } catch (e2) {
        debugPrint('=== NINAADA: playRadio RETRY FAILED: $e2 ===');
        _toast('Try other station or song.');
        if (state.activeRadioStation?.id == station.id) {
          state = state.copyWith(
            playbackMode: PlaybackMode.song,
            clearRadio: true,
            radioLoading: false,
            isPlaying: false,
          );
        }
      }
    }
  }

  /// Stop the active radio stream. Optionally resumes the song queue
  /// if there was one loaded previously.
  Future<void> stopRadio() async {
    debugPrint('=== NINAADA: stopRadio called ===');
    // Use pause (not handler.stop) to avoid foreground service teardown.
    // resumeQueueMode below will re-set the audio source cleanly.
    await _handler.pause();
    state = state.copyWith(
      playbackMode: PlaybackMode.song,
      clearRadio: true,
      radioLoading: false,
      isPlaying: false,
      // Keep miniPlayerVisible if there's a song queue to return to
      miniPlayerVisible: state.currentSong != null,
      viewState: state.currentSong != null ? PlayerViewState.mini : PlayerViewState.hidden,
    );

    // Resume queue mode so next playSong() works cleanly
    if (_handler.songQueue.isNotEmpty) {
      await _handler.resumeQueueMode(atIndex: _handler.currentIndex >= 0 ? _handler.currentIndex : 0);
    }
  }

  /// Called when the entire ConcatenatingAudioSource queue completes.
  /// LoopMode.one and .all are handled by just_audio internally.
  void _onQueueEnd() {
    if (state.repeat != 'off') return; // Loop modes handled by player
    if (state.autoPlay && state.currentSong != null) {
      _fetchSimilarAndPlay(state.currentSong!);
    }
  }

  Future<void> _fetchSimilarAndPlay(Song song) async {
    try {
      // Try L3 prefetch cache first — avoids redundant API call
      List<Song>? similar = PrefetchEngine.getSimilar(song.id);
      similar ??= await _api.fetchSimilarSongs(song.id);

      if (similar.isNotEmpty) {
        final candidates = similar.where((s) => s.id != song.id).toList();

        if (candidates.isNotEmpty) {
          // ── Holy Trinity: session-aware recommendation queue ──
          final profile = TasteProfileManager.instance.profile;
          final session = _ref.read(sessionContextProvider);
          final existingIds = _handler.songQueue.map((s) => s.id).toSet();

          final ranked = RecommendationEngine.generateAutoPlayQueue(
            profile: profile,
            candidates: candidates,
            sessionContext: session,
            count: candidates.length,
            excludeIds: existingIds,
          );

          final toAppend = ranked.isNotEmpty ? ranked : candidates;

          final prevCount = _handler.songQueue.length;
          await _handler.appendToQueue(toAppend);
          await _handler.seekToIndex(prevCount);
          await _handler.play();
          // Use appendAutoPlay — these are algorithmic, don't shift boundary
          final snapshot = QueueManager.appendAutoPlay(
            state.queueSnapshot,
            toAppend,
          );
          state = state.copyWith(
            queue: _handler.songQueue,
            queueSnapshot: snapshot,
          );
          return; // Success — done
        }
      }

      // Phase 9A: Fallback — if no similar songs, fetch top songs from the 
      // current song's language (or user's preferred language) so autoplay
      // doesn't stall. Language-aware candidate pool.
      final fallbackLang = song.language.isNotEmpty
          ? song.language.toLowerCase()
          : _ref.read(userProfileProvider).primaryLanguage;
      final fallbackSongs = await _api.fetchTopSongs(language: fallbackLang, limit: 20);
      final existingIds = _handler.songQueue.map((s) => s.id).toSet();
      final fallbackCandidates = fallbackSongs
          .where((s) => s.id != song.id && !existingIds.contains(s.id))
          .toList();

      if (fallbackCandidates.isNotEmpty) {
        final profile = TasteProfileManager.instance.profile;
        final session = _ref.read(sessionContextProvider);
        final ranked = RecommendationEngine.generateAutoPlayQueue(
          profile: profile,
          candidates: fallbackCandidates,
          sessionContext: session,
          count: fallbackCandidates.length.clamp(1, 10),
          excludeIds: existingIds,
        );
        final toAppend = ranked.isNotEmpty ? ranked : fallbackCandidates.take(10).toList();
        final prevCount = _handler.songQueue.length;
        await _handler.appendToQueue(toAppend);
        await _handler.seekToIndex(prevCount);
        await _handler.play();
        final snapshot = QueueManager.appendAutoPlay(
          state.queueSnapshot,
          toAppend,
        );
        state = state.copyWith(
          queue: _handler.songQueue,
          queueSnapshot: snapshot,
        );
      }
    } catch (e) {
      debugPrint('=== NINAADA: _fetchSimilarAndPlay error: $e ===');
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _processingSub?.cancel();
    _downloadSub?.cancel();
    _networkSub?.close();
    _handler.onTrackChanged = null;
    _handler.onQueueEnd = null;
    _handler.onAppKilled = null;
    super.dispose();
  }
}

final playerProvider = StateNotifierProvider<PlayerNotifier, PlayerState>(
  (ref) => PlayerNotifier(ref),
);

// ================================================================
//  LIBRARY STATE (Liked, Playlists, Downloads, Recent, PlayCounts)
// ================================================================

class LibraryState {
  final List<Song> likedSongs;
  final List<PlaylistModel> playlists;
  final List<Song> downloadedSongs;
  final List<Song> recentlyPlayed;
  final Map<String, PlayCount> playCounts;
  final String libraryTab; // 'playlists' | 'downloads' | 'liked' | 'smart'
  final PlaylistModel? selectedPlaylist;

  const LibraryState({
    this.likedSongs = const [],
    this.playlists = const [],
    this.downloadedSongs = const [],
    this.recentlyPlayed = const [],
    this.playCounts = const {},
    this.libraryTab = 'playlists',
    this.selectedPlaylist,
  });

  LibraryState copyWith({
    List<Song>? likedSongs,
    List<PlaylistModel>? playlists,
    List<Song>? downloadedSongs,
    List<Song>? recentlyPlayed,
    Map<String, PlayCount>? playCounts,
    String? libraryTab,
    PlaylistModel? selectedPlaylist,
    bool clearPlaylist = false,
  }) {
    return LibraryState(
      likedSongs: likedSongs ?? this.likedSongs,
      playlists: playlists ?? this.playlists,
      downloadedSongs: downloadedSongs ?? this.downloadedSongs,
      recentlyPlayed: recentlyPlayed ?? this.recentlyPlayed,
      playCounts: playCounts ?? this.playCounts,
      libraryTab: libraryTab ?? this.libraryTab,
      selectedPlaylist: clearPlaylist ? null : (selectedPlaylist ?? this.selectedPlaylist),
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  Box? _box;
  bool _initialized = false;

  LibraryNotifier() : super(const LibraryState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      _box = Hive.box('library');
      _initialized = true;
      await loadAll();
    } catch (e) {
      debugPrint('=== NINAADA: LibraryNotifier._init error: $e ===');
    }
  }

  Future<void> loadAll() async {
    if (!_initialized || _box == null) {
      debugPrint('=== NINAADA: loadAll skipped - box not ready ===');
      return;
    }
    try {
      final box = _box!;
      final liked = box.get('likedSongs');
      final playlists = box.get('playlists');
      final downloads = box.get('downloadedSongs');
      final recent = box.get('recentlyPlayed');
      final counts = box.get('playCounts');

      state = state.copyWith(
        likedSongs: liked != null
            ? (jsonDecode(liked) as List).map((e) => Song.fromJson(e)).toList()
            : [],
        playlists: playlists != null
            ? (jsonDecode(playlists) as List).map((e) => PlaylistModel.fromJson(e)).toList()
            : [],
        downloadedSongs: downloads != null
            ? (jsonDecode(downloads) as List).map((e) => Song.fromJson(e)).toList()
            : [],
        recentlyPlayed: recent != null
            ? (jsonDecode(recent) as List).map((e) => Song.fromJson(e)).toList()
            : [],
        playCounts: counts != null
            ? (jsonDecode(counts) as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, PlayCount.fromJson(v)),
              )
            : {},
      );
    } catch (e) {
      // Load error
    }
  }

  // === LIKES ===
  bool isLiked(String songId) => state.likedSongs.any((s) => s.id == songId);

  Future<void> toggleLike(Song song) async {
    final exists = state.likedSongs.any((s) => s.id == song.id);
    final updated = exists
        ? state.likedSongs.where((s) => s.id != song.id).toList()
        : [...state.likedSongs, song];
    state = state.copyWith(likedSongs: updated);
    await _box?.put('likedSongs', jsonEncode(updated.map((s) => s.toJson()).toList()));

    // Update taste profile — like = +4.0, unlike = -4.0
    try {
      await TasteProfileManager.instance.onSongLiked(
        artist: song.artist,
        language: song.language,
        isLiked: !exists,
      );
    } catch (_) {}
  }

  // === PLAYLISTS ===
  Future<void> createPlaylist(String name) async {
    final pl = PlaylistModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      songs: [],
    );
    final updated = [...state.playlists, pl];
    state = state.copyWith(playlists: updated);
    await _savePlaylists(updated);
  }

  Future<void> addToPlaylist(Song song, String playlistId) async {
    final updated = state.playlists.map((p) {
      if (p.id == playlistId) {
        return PlaylistModel(id: p.id, name: p.name, songs: [...p.songs, song]);
      }
      return p;
    }).toList();
    state = state.copyWith(playlists: updated);
    await _savePlaylists(updated);
  }

  Future<void> removeFromPlaylist(String songId, String playlistId) async {
    final updated = state.playlists.map((p) {
      if (p.id == playlistId) {
        return PlaylistModel(
          id: p.id,
          name: p.name,
          songs: p.songs.where((s) => s.id != songId).toList(),
        );
      }
      return p;
    }).toList();
    state = state.copyWith(playlists: updated);
    if (state.selectedPlaylist?.id == playlistId) {
      state = state.copyWith(selectedPlaylist: updated.firstWhere((p) => p.id == playlistId));
    }
    await _savePlaylists(updated);
  }

  Future<void> deletePlaylist(String playlistId) async {
    final updated = state.playlists.where((p) => p.id != playlistId).toList();
    state = state.copyWith(playlists: updated, clearPlaylist: true);
    await _savePlaylists(updated);
  }

  Future<void> _savePlaylists(List<PlaylistModel> pl) async {
    await _box?.put('playlists', jsonEncode(pl.map((p) => p.toJson()).toList()));
  }

  void selectPlaylist(PlaylistModel? pl) {
    state = state.copyWith(selectedPlaylist: pl, clearPlaylist: pl == null);
  }

  void setLibraryTab(String tab) {
    state = state.copyWith(libraryTab: tab, clearPlaylist: true);
  }

  // === RECENTLY PLAYED ===
  Future<void> addRecent(Song song) async {
    final updated = [song, ...state.recentlyPlayed.where((s) => s.id != song.id)].take(20).toList();
    state = state.copyWith(recentlyPlayed: updated);
    await _box?.put('recentlyPlayed', jsonEncode(updated.map((s) => s.toJson()).toList()));
  }

  Future<void> clearRecent() async {
    state = state.copyWith(recentlyPlayed: []);
    await _box?.delete('recentlyPlayed');
  }

  // === PLAY COUNTS ===
  Future<void> incPlayCount(Song song) async {
    final updated = Map<String, PlayCount>.from(state.playCounts);
    final existing = updated[song.id];
    final newCount = (existing?.count ?? 0) + 1;
    updated[song.id] = PlayCount(
      count: newCount,
      song: song,
    );
    state = state.copyWith(playCounts: updated);
    await _box?.put('playCounts', jsonEncode(updated.map((k, v) => MapEntry(k, v.toJson()))));

    // Update taste profile for recommendation engine
    try {
      await TasteProfileManager.instance.onSongPlayed(
        songId: song.id,
        artist: song.artist,
        language: song.language,
        album: song.album,
        playCount: newCount,
      );
    } catch (_) {}
  }

  List<Song> getMostPlayed() {
    final sorted = state.playCounts.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return sorted
        .take(10)
        .map((pc) => pc.song)
        .whereType<Song>()
        .toList();
  }

  // === DOWNLOADS ===
  Future<void> deleteDownload(String songId) async {
    final updated = state.downloadedSongs.where((s) => s.id != songId).toList();
    state = state.copyWith(downloadedSongs: updated);
    await _box?.put('downloadedSongs', jsonEncode(updated.map((s) => s.toJson()).toList()));
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>(
  (ref) => LibraryNotifier(),
);

// ================================================================
//  HOME / BROWSE STATE
// ================================================================

class HomeState {
  final List<BrowseItem> trending;
  final List<BrowseItem> featured;
  final List<BrowseItem> newReleases;
  final List<Song> topSongs;
  final List<Song> quickPicks;
  final bool loading;
  final String? error;

  // ── Recommendation fields (session-cached) ──
  final List<MadeForYouTab> madeForYouTabs;
  final List<List<Song>> dailyMix;
  final List<Song> discoverWeekly;
  final List<TopPicksCard> topPicks;
  final bool recommendationsReady;
  final int selectedMfyTab;

  const HomeState({
    this.trending = const [],
    this.featured = const [],
    this.newReleases = const [],
    this.topSongs = const [],
    this.quickPicks = const [],
    this.loading = true,
    this.error,
    this.madeForYouTabs = const [],
    this.dailyMix = const [],
    this.discoverWeekly = const [],
    this.topPicks = const [],
    this.recommendationsReady = false,
    this.selectedMfyTab = 0,
  });

  bool get hasData => trending.isNotEmpty || featured.isNotEmpty || newReleases.isNotEmpty || topSongs.isNotEmpty;

  HomeState copyWith({
    List<BrowseItem>? trending,
    List<BrowseItem>? featured,
    List<BrowseItem>? newReleases,
    List<Song>? topSongs,
    List<Song>? quickPicks,
    bool? loading,
    String? error,
    bool clearError = false,
    List<MadeForYouTab>? madeForYouTabs,
    List<List<Song>>? dailyMix,
    List<Song>? discoverWeekly,
    List<TopPicksCard>? topPicks,
    bool? recommendationsReady,
    int? selectedMfyTab,
  }) {
    return HomeState(
      trending: trending ?? this.trending,
      featured: featured ?? this.featured,
      newReleases: newReleases ?? this.newReleases,
      topSongs: topSongs ?? this.topSongs,
      quickPicks: quickPicks ?? this.quickPicks,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      madeForYouTabs: madeForYouTabs ?? this.madeForYouTabs,
      dailyMix: dailyMix ?? this.dailyMix,
      discoverWeekly: discoverWeekly ?? this.discoverWeekly,
      topPicks: topPicks ?? this.topPicks,
      recommendationsReady: recommendationsReady ?? this.recommendationsReady,
      selectedMfyTab: selectedMfyTab ?? this.selectedMfyTab,
    );
  }
}

class HomeNotifier extends StateNotifier<HomeState> {
  final ApiService _api;
  final Ref _ref;

  HomeNotifier(Ref ref)
      : _api = ApiService(),
        _ref = ref,
        super(const HomeState()) {
    // Defer to avoid state changes during widget mount
    Future.microtask(() => fetchHome());
  }

  Future<void> fetchHome() async {
    debugPrint('=== NINAADA: fetchHome() called ===');
    state = state.copyWith(loading: true, clearError: true);
    try {
      // Phase 9A: Read user profile for language-personalized content
      final profile = _ref.read(userProfileProvider);
      final primaryLang = profile.primaryLanguage;
      final allLangs = profile.preferredLanguages;

      debugPrint('=== NINAADA: fetching API data (lang=$primaryLang, all=${allLangs.join(",")}) ===');

      // Fetch trending + featured + new releases with primary language
      // + top songs for ALL preferred languages
      final baseFutures = <Future>[
        _api.fetchTrending(language: primaryLang),
        _api.fetchFeatured(language: primaryLang),
        _api.fetchNewReleases(),
      ];

      // Fetch top songs for each preferred language (max 3 to limit API calls)
      final langFutures = allLangs.take(3).map(
        (lang) => _api.fetchTopSongs(language: lang, limit: 20),
      );

      final results = await Future.wait([...baseFutures, ...langFutures]);

      final trending = results[0] as List<BrowseItem>;
      final featured = results[1] as List<BrowseItem>;
      final newReleases = results[2] as List<BrowseItem>;

      // Merge top songs from all languages, deduped by song ID
      final seen = <String>{};
      final topSongs = <Song>[];
      for (int i = 3; i < results.length; i++) {
        for (final song in results[i] as List<Song>) {
          if (seen.add(song.id)) topSongs.add(song);
        }
      }

      debugPrint('=== NINAADA: API returned. trending=${trending.length}, '
          'featured=${featured.length}, newReleases=${newReleases.length}, '
          'topSongs=${ topSongs.length} (${allLangs.take(3).join("+")}) ===');

      final hasData = trending.isNotEmpty || featured.isNotEmpty || newReleases.isNotEmpty || topSongs.isNotEmpty;
      state = state.copyWith(
        trending: trending,
        featured: featured,
        newReleases: newReleases,
        topSongs: topSongs,
        loading: false,
        error: hasData ? null : 'No data returned. Is the API server running?',
        clearError: hasData,
      );

      // Generate personalized recommendations from pooled songs
      if (hasData) _generateRecommendations();
    } catch (e) {
      debugPrint('=== NINAADA: fetchHome() EXCEPTION: $e ===');
      state = state.copyWith(
        loading: false,
        error: 'Failed to connect to server.\n$e',
      );
    }
  }

  void setQuickPicks(List<Song> picks) {
    state = state.copyWith(quickPicks: picks);
  }

  /// Switch the selected Made For You tab (no playback, UI-only).
  void selectMfyTab(int index) {
    if (index >= 0 && index < state.madeForYouTabs.length) {
      state = state.copyWith(selectedMfyTab: index);
    }
  }

  // ── RECOMMENDATION GENERATION ──
  // Called once after fetchHome() succeeds. Results are session-cached
  // in HomeState; they only regenerate on next fetchHome() or app restart.

  void _generateRecommendations() {
    try {
      final profile = TasteProfileManager.instance.profile;
      if (profile == null) {
        debugPrint('=== NINAADA: No taste profile, skipping recommendations ===');
        return;
      }

      // Pool all available songs as candidates
      final candidates = <Song>{...state.topSongs};
      // Add any additional songs we can gather from trending/featured
      // (BrowseItems don't have mediaUrl, but we use topSongs as the main pool)

      final candidateList = candidates.toList();
      debugPrint('=== NINAADA: Generating recommendations from ${candidateList.length} candidates ===');

      if (candidateList.isEmpty) return;

      // Made For You tabs
      final mfyTabs = RecommendationEngine.getMadeForYouTabs(
        profile: profile,
        candidates: candidateList,
      );

      // Daily Mix
      final dailyMix = RecommendationEngine.getDailyMix(
        profile: profile,
        candidates: candidateList,
      );

      // Discover Weekly (check 7-day cache)
      List<Song> discoverWeekly;
      final mgr = TasteProfileManager.instance;
      if (mgr.isWeeklyDigestValid()) {
        // Use cached song IDs to reconstruct list
        final cachedIds = profile.weeklyDigestSongIds;
        discoverWeekly = candidateList
            .where((s) => cachedIds.contains(s.id))
            .toList();
        // If cache is stale (songs removed from API), regenerate
        if (discoverWeekly.length < 5) {
          discoverWeekly = RecommendationEngine.getDiscoverWeekly(
            profile: profile,
            candidates: candidateList,
          );
          mgr.saveWeeklyDigest(discoverWeekly.map((s) => s.id).toList());
        }
      } else {
        discoverWeekly = RecommendationEngine.getDiscoverWeekly(
          profile: profile,
          candidates: candidateList,
        );
        mgr.saveWeeklyDigest(discoverWeekly.map((s) => s.id).toList());
      }

      // Top Picks
      final topPicks = RecommendationEngine.getTopPicks(
        profile: profile,
        candidates: candidateList,
      );

      // Quick Picks (personalized)
      final quickPicks = RecommendationEngine.getQuickPicks(
        profile: profile,
        candidates: candidateList,
        limit: 6,
      );

      state = state.copyWith(
        madeForYouTabs: mfyTabs,
        dailyMix: dailyMix,
        discoverWeekly: discoverWeekly,
        topPicks: topPicks,
        quickPicks: quickPicks.isNotEmpty ? quickPicks : state.quickPicks,
        recommendationsReady: true,
      );

      debugPrint('=== NINAADA: Recommendations ready — '
          'mfy=${mfyTabs.length}, daily=${dailyMix.length}, '
          'discover=${discoverWeekly.length}, topPicks=${topPicks.length} ===');
    } catch (e) {
      debugPrint('=== NINAADA: _generateRecommendations error: $e ===');
    }
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>(
  (ref) => HomeNotifier(ref),
);

// ================================================================
//  SEARCH STATE
// ================================================================

class SearchState {
  final String query;
  final String filter; // songs | albums | artists
  final Map<String, List<dynamic>> results; // songs, albums, artists
  final bool searching;
  final List<String> recentSearches;

  const SearchState({
    this.query = '',
    this.filter = 'songs',
    this.results = const {'songs': [], 'albums': [], 'artists': []},
    this.searching = false,
    this.recentSearches = const [],
  });

  SearchState copyWith({
    String? query,
    String? filter,
    Map<String, List<dynamic>>? results,
    bool? searching,
    List<String>? recentSearches,
  }) {
    return SearchState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      results: results ?? this.results,
      searching: searching ?? this.searching,
      recentSearches: recentSearches ?? this.recentSearches,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final ApiService _api;
  Box? _box;
  Timer? _debounce;
  /// Track last successfully executed query to prevent identical re-fires.
  String _lastExecutedQuery = '';
  /// Generation counter — incremented on every new search dispatch.
  /// When a result arrives, if its generation doesn't match the current
  /// generation, it's a stale/cancelled result and is silently discarded.
  int _searchGeneration = 0;
  /// Minimum query length to trigger API call.
  static const int _minQueryLength = 3;
  /// Debounce duration — 500ms balances responsiveness with minimal backend load.
  static const Duration _debounceDuration = Duration(milliseconds: 500);

  SearchNotifier()
      : _api = ApiService(),
        super(const SearchState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      _box = Hive.box('search');
      final recent = _box?.get('recentSearches');
      if (recent != null) {
        state = state.copyWith(
          recentSearches: (jsonDecode(recent) as List).cast<String>(),
        );
      }
    } catch (e) {
      debugPrint('=== NINAADA: SearchNotifier._init error: $e ===');
    }
  }

  void setQuery(String q) => state = state.copyWith(query: q);
  void setFilter(String f) => state = state.copyWith(filter: f);

  /// Debounced search — waits 500ms after the last keystroke.
  /// Enforces: trim, min-length, cancels previous in-flight, dedup.
  void debouncedSearch(String q) {
    _debounce?.cancel();
    final trimmed = q.trim();
    // Block empty / whitespace-only
    if (trimmed.isEmpty) {
      state = state.copyWith(query: q, searching: false);
      return;
    }
    // Block sub-minimum-length
    if (trimmed.length < _minQueryLength) {
      state = state.copyWith(query: q, searching: false);
      return;
    }
    state = state.copyWith(query: q, searching: true);
    _debounce = Timer(_debounceDuration, () {
      _executeSearch(trimmed);
    });
  }

  /// Direct search — for submit, recent tap, suggestion tap.
  /// Still validates + deduplicates.
  Future<void> doSearch(String q) async {
    final trimmed = q.trim();
    if (trimmed.isEmpty || trimmed.length < _minQueryLength) return;
    _debounce?.cancel(); // cancel any pending debounce
    await _executeSearch(trimmed);
  }

  /// Central search executor — single point of API dispatch.
  /// Enforces: dedup identical queries, cancel previous in-flight.
  ///
  /// Uses a generation counter to guarantee that only the LATEST
  /// search result is committed to state. Cancelled/stale results
  /// from superseded searches are silently discarded.
  Future<void> _executeSearch(String q) async {
    // Dedup: don't re-fire if identical to last successful query
    final r = state.results;
    final hasAnyResults = (r['songs']?.isNotEmpty ?? false) ||
        (r['albums']?.isNotEmpty ?? false) ||
        (r['artists']?.isNotEmpty ?? false);
    if (q == _lastExecutedQuery && hasAnyResults) {
      state = state.copyWith(searching: false);
      return;
    }
    // Cancel any previous in-flight search request
    _api.cancelSearch();
    // Increment generation — any in-flight result from a previous search
    // will see a mismatched generation and bail out silently.
    final gen = ++_searchGeneration;
    // CRITICAL: Always set query here — doSearch() and suggestion taps
    // bypass debouncedSearch(), so query would stay empty and the UI
    // condition `hasQuery` would be false, hiding results entirely.
    state = state.copyWith(query: q, searching: true);
    debugPrint('=== EXEC_SEARCH: gen=$gen q="$q" ===');
    try {
      final results = await _api.search(q);
      if (!mounted) {
        debugPrint('=== EXEC_SEARCH: gen=$gen NOT MOUNTED, discarding ===');
        return;
      }
      // Stale guard: a newer search was dispatched while we were waiting.
      // Discard this result silently — the newer search will commit its own.
      if (gen != _searchGeneration) {
        debugPrint('=== EXEC_SEARCH: gen=$gen STALE (current=$_searchGeneration), discarding ===');
        return;
      }
      final songCount = (results['songs'] as List?)?.length ?? 0;
      final albumCount = (results['albums'] as List?)?.length ?? 0;
      final artistCount = (results['artists'] as List?)?.length ?? 0;
      debugPrint('=== EXEC_SEARCH: gen=$gen COMMITTING songs=$songCount albums=$albumCount artists=$artistCount ===');
      _lastExecutedQuery = q;
      state = state.copyWith(
        results: {
          'songs': results['songs'] as List? ?? [],
          'albums': results['albums'] as List? ?? [],
          'artists': results['artists'] as List? ?? [],
        },
        searching: false,
      );

      // Save recent
      final updated = [q, ...state.recentSearches.where((s) => s != q)].take(10).toList();
      state = state.copyWith(recentSearches: updated);
      await _box?.put('recentSearches', jsonEncode(updated));
    } catch (e) {
      debugPrint('=== EXEC_SEARCH: gen=$gen EXCEPTION: $e ===');
      // Only update state if this is still the active search generation
      if (mounted && gen == _searchGeneration) {
        state = state.copyWith(searching: false);
      }
    }
  }

  Future<void> clearRecentSearches() async {
    state = state.copyWith(recentSearches: []);
    await _box?.delete('recentSearches');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _api.cancelSearch();
    super.dispose();
  }

  /// Full reset — clears query, results, cancels debounce + in-flight requests.
  /// Called when search overlay is closed or X button is tapped.
  void clearResults() {
    _debounce?.cancel();
    _api.cancelSearch();
    _lastExecutedQuery = '';
    state = state.copyWith(
      query: '',
      results: {'songs': [], 'albums': [], 'artists': []},
      searching: false,
    );
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>(
  (ref) => SearchNotifier(),
);

// ================================================================
//  EXPLORE STATE
// ================================================================

class ExploreState {
  final String? selectedGenre;
  final List<Song> genreSongs;
  final bool genreLoading;
  final Color genreColor;

  const ExploreState({
    this.selectedGenre,
    this.genreSongs = const [],
    this.genreLoading = false,
    this.genreColor = const Color(0xFF8B5CF6),
  });

  ExploreState copyWith({
    String? selectedGenre,
    List<Song>? genreSongs,
    bool? genreLoading,
    Color? genreColor,
    bool clearGenre = false,
  }) {
    return ExploreState(
      selectedGenre: clearGenre ? null : (selectedGenre ?? this.selectedGenre),
      genreSongs: genreSongs ?? this.genreSongs,
      genreLoading: genreLoading ?? this.genreLoading,
      genreColor: genreColor ?? this.genreColor,
    );
  }
}

class ExploreNotifier extends StateNotifier<ExploreState> {
  final ApiService _api;

  ExploreNotifier()
      : _api = ApiService(),
        super(const ExploreState());

  Future<void> loadGenre(String langId, Color color) async {
    state = state.copyWith(selectedGenre: langId, genreLoading: true, genreColor: color);
    try {
      final topSongs = await _api.fetchTopSongs(language: langId, limit: 30);
      final querySongs = await _api.searchSongs('$langId songs', limit: 30);
      final seen = <String>{};
      final merged = <Song>[];
      for (final s in topSongs) {
        if (seen.add(s.id)) merged.add(s);
      }
      for (final s in querySongs) {
        if (seen.add(s.id)) merged.add(s);
      }
      state = state.copyWith(genreSongs: merged.take(50).toList(), genreLoading: false);
    } catch (e) {
      state = state.copyWith(genreSongs: [], genreLoading: false);
    }
  }

  Future<void> loadMood(String name, String query, Color color) async {
    state = state.copyWith(selectedGenre: name, genreLoading: true, genreColor: color);
    try {
      final res1 = await _api.searchSongs(query, limit: 30);
      final res2 = await _api.searchSongs('$name songs', limit: 20);
      final seen = <String>{};
      final merged = <Song>[];
      for (final s in res1) {
        if (seen.add(s.id)) merged.add(s);
      }
      for (final s in res2) {
        if (seen.add(s.id)) merged.add(s);
      }
      state = state.copyWith(genreSongs: merged.take(50).toList(), genreLoading: false);
    } catch (e) {
      state = state.copyWith(genreSongs: [], genreLoading: false);
    }
  }

  void clearGenre() {
    state = state.copyWith(clearGenre: true, genreSongs: []);
  }
}

final exploreProvider = StateNotifierProvider<ExploreNotifier, ExploreState>(
  (ref) => ExploreNotifier(),
);

// ================================================================
//  SLEEP TIMER — MIGRATED to sleep_alarm_provider.dart
// ================================================================
//
//  The old SleepTimerState / SleepTimerNotifier / sleepTimerProvider
//  have been replaced by the 4-layer Sleep & Alarm subsystem.
//
//  Import: package:ninaada_music/providers/sleep_alarm_provider.dart
//  Provider: sleepAlarmProvider (SleepAlarmNotifier, SleepAlarmState)
//
//  Backward-compat alias (will be removed after full UI migration):
// ================================================================
// ================================================================
//  MISC SETTINGS PROVIDERS (Phase 12 Polish)
// ================================================================

/// Reactive EQ toggle state.
/// Toggled by radio screen; affects EQ icon color.
final eqProvider = StateProvider<bool>((ref) => false);

/// Reactive download quality state.
/// Selected in downloads tab; persistent preference.
final downloadQualityProvider = StateProvider<String>((ref) => 'High');
