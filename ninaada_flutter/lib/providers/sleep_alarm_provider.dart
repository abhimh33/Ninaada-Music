import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/services/alarm_scheduler_service.dart';
import 'package:ninaada_music/services/volume_fade_engine.dart';

// ================================================================
//  SLEEP & ALARM PROVIDER — Layer 1 (Controller)
// ================================================================
//
//  Replaces the old SleepTimerState / SleepTimerNotifier.
//
//  Responsibilities:
//    1. Sleep countdown timer (1-second tick)
//    2. End-of-song mode (StreamSubscription on processingState)
//    3. Fade-out delegation → VolumeFadeEngine.fadeOut()
//    4. Alarm delegation → AlarmSchedulerService
//    5. Ambient dim value (ValueNotifier for overlay)
//    6. Hive persistence for all settings
//
//  Architecture rules:
//    - NO UI code. No BuildContext. No Widget references.
//    - Services (VolumeFadeEngine, AlarmSchedulerService) are pure.
//    - State is immutable. All mutations go through copyWith.
// ================================================================

// ────────────────────────────────────────────────
//  STATE
// ────────────────────────────────────────────────

class SleepAlarmState {
  // ── Sleep Timer ──
  final bool sleepActive;
  final int sleepRemaining;       // seconds
  final bool endOfSong;           // stop after current song finishes
  final bool fadeOutEnabled;
  final int fadeOutDuration;      // 15, 30, or 60 seconds
  final bool ambientDimEnabled;
  final double ambientDimValue;   // 0.0 (off) → 0.8 (max dim)

  // ── Alarm ──
  final bool alarmEnabled;
  final int alarmHour;            // 0-23
  final int alarmMinute;          // 0-59
  final String? alarmPlaylistId;
  final double alarmVolume;       // 0.0–1.0
  final bool progressiveVolume;   // ramp-up instead of instant
  final int alarmFadeDuration;    // seconds for progressive ramp

  // ── UI Transient ──
  final bool fadeInProgress;      // true while VolumeFadeEngine is fading

  const SleepAlarmState({
    this.sleepActive = false,
    this.sleepRemaining = 0,
    this.endOfSong = false,
    this.fadeOutEnabled = true,
    this.fadeOutDuration = 30,
    this.ambientDimEnabled = false,
    this.ambientDimValue = 0.0,
    this.alarmEnabled = false,
    this.alarmHour = 7,
    this.alarmMinute = 0,
    this.alarmPlaylistId,
    this.alarmVolume = 0.7,
    this.progressiveVolume = true,
    this.alarmFadeDuration = 60,
    this.fadeInProgress = false,
  });

  SleepAlarmState copyWith({
    bool? sleepActive,
    int? sleepRemaining,
    bool? endOfSong,
    bool? fadeOutEnabled,
    int? fadeOutDuration,
    bool? ambientDimEnabled,
    double? ambientDimValue,
    bool? alarmEnabled,
    int? alarmHour,
    int? alarmMinute,
    String? alarmPlaylistId,
    bool clearAlarmPlaylist = false,
    double? alarmVolume,
    bool? progressiveVolume,
    int? alarmFadeDuration,
    bool? fadeInProgress,
  }) {
    return SleepAlarmState(
      sleepActive: sleepActive ?? this.sleepActive,
      sleepRemaining: sleepRemaining ?? this.sleepRemaining,
      endOfSong: endOfSong ?? this.endOfSong,
      fadeOutEnabled: fadeOutEnabled ?? this.fadeOutEnabled,
      fadeOutDuration: fadeOutDuration ?? this.fadeOutDuration,
      ambientDimEnabled: ambientDimEnabled ?? this.ambientDimEnabled,
      ambientDimValue: ambientDimValue ?? this.ambientDimValue,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      alarmHour: alarmHour ?? this.alarmHour,
      alarmMinute: alarmMinute ?? this.alarmMinute,
      alarmPlaylistId: clearAlarmPlaylist
          ? null
          : (alarmPlaylistId ?? this.alarmPlaylistId),
      alarmVolume: alarmVolume ?? this.alarmVolume,
      progressiveVolume: progressiveVolume ?? this.progressiveVolume,
      alarmFadeDuration: alarmFadeDuration ?? this.alarmFadeDuration,
      fadeInProgress: fadeInProgress ?? this.fadeInProgress,
    );
  }

  /// Formatted timer display  e.g. "12:45"
  String get sleepDisplay {
    final m = (sleepRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (sleepRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Formatted alarm time  e.g. "07:00"
  String get alarmDisplay {
    final h = alarmHour.toString().padLeft(2, '0');
    final m = alarmMinute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ── SERIALIZATION (for Hive persistence) ──

  Map<String, dynamic> toJson() => {
    'fadeOutEnabled': fadeOutEnabled,
    'fadeOutDuration': fadeOutDuration,
    'ambientDimEnabled': ambientDimEnabled,
    'alarmEnabled': alarmEnabled,
    'alarmHour': alarmHour,
    'alarmMinute': alarmMinute,
    'alarmPlaylistId': alarmPlaylistId,
    'alarmVolume': alarmVolume,
    'progressiveVolume': progressiveVolume,
    'alarmFadeDuration': alarmFadeDuration,
  };

  factory SleepAlarmState.fromJson(Map<String, dynamic> json) {
    return SleepAlarmState(
      fadeOutEnabled: json['fadeOutEnabled'] as bool? ?? true,
      fadeOutDuration: json['fadeOutDuration'] as int? ?? 30,
      ambientDimEnabled: json['ambientDimEnabled'] as bool? ?? false,
      alarmEnabled: json['alarmEnabled'] as bool? ?? false,
      alarmHour: json['alarmHour'] as int? ?? 7,
      alarmMinute: json['alarmMinute'] as int? ?? 0,
      alarmPlaylistId: json['alarmPlaylistId'] as String?,
      alarmVolume: (json['alarmVolume'] as num?)?.toDouble() ?? 0.7,
      progressiveVolume: json['progressiveVolume'] as bool? ?? true,
      alarmFadeDuration: json['alarmFadeDuration'] as int? ?? 60,
    );
  }
}

// ────────────────────────────────────────────────
//  NOTIFIER
// ────────────────────────────────────────────────

class SleepAlarmNotifier extends StateNotifier<SleepAlarmState> {
  final Ref _ref;
  final Box _box;

  late final VolumeFadeEngine _fadeEngine;
  late final AlarmSchedulerService _alarmScheduler;

  Timer? _sleepTimer;
  StreamSubscription? _endOfSongSub;

  /// Drives the AmbientDimOverlay widget without full state rebuilds.
  final ValueNotifier<double> ambientDimNotifier = ValueNotifier(0.0);

  SleepAlarmNotifier(this._ref, this._box)
      : super(const SleepAlarmState()) {
    _init();
  }

  // ════════════════════════════════════════════════
  //  INITIALIZATION
  // ════════════════════════════════════════════════

  void _init() {
    // 1. Instantiate services
    final handler = _ref.read(audioHandlerProvider);
    _fadeEngine = VolumeFadeEngine(handler);
    _alarmScheduler = AlarmSchedulerService(_box);

    // 2. Wire alarm trigger callback
    _alarmScheduler.onAlarmFired = _onAlarmFired;

    // 3. Restore persisted settings from Hive
    _loadFromHive();

    // 4. If alarm was previously enabled, start the checker
    if (state.alarmEnabled) {
      _alarmScheduler.start();
    }

    debugPrint('=== SLEEP ALARM: initialized ===');
  }

  void _loadFromHive() {
    try {
      final raw = _box.get('sleep_alarm_settings');
      if (raw != null) {
        final saved = SleepAlarmState.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        state = saved;
        // Also sync alarm scheduler config
        _alarmScheduler.saveConfig(AlarmConfig(
          enabled: saved.alarmEnabled,
          hour: saved.alarmHour,
          minute: saved.alarmMinute,
          playlistId: saved.alarmPlaylistId,
          volume: saved.alarmVolume,
          progressiveVolume: saved.progressiveVolume,
          fadeDuration: saved.alarmFadeDuration,
        ));
      }
    } catch (e) {
      debugPrint('=== SLEEP ALARM: loadFromHive error: $e ===');
    }
  }

  Future<void> _persist() async {
    try {
      await _box.put('sleep_alarm_settings', jsonEncode(state.toJson()));
    } catch (e) {
      debugPrint('=== SLEEP ALARM: persist error: $e ===');
    }
  }

  // ════════════════════════════════════════════════
  //  SLEEP TIMER — CORE
  // ════════════════════════════════════════════════

  /// Start sleep timer.
  ///   minutes > 0  → countdown mode
  ///   minutes == -1 → end-of-song mode
  ///   minutes == 0  → cancel
  void startSleep(int minutes) {
    _cancelSleepInternal();
    _fadeEngine.cancelAndRestore();

    if (minutes == 0) {
      // Cancel
      state = state.copyWith(
        sleepActive: false,
        sleepRemaining: 0,
        endOfSong: false,
        ambientDimValue: 0.0,
      );
      ambientDimNotifier.value = 0.0;
      return;
    }

    if (minutes == -1) {
      // End of song mode
      state = state.copyWith(sleepActive: true, endOfSong: true, sleepRemaining: 0);
      _listenForEndOfSong();
      return;
    }

    // Countdown mode
    final totalSeconds = minutes * 60;
    state = state.copyWith(
      sleepActive: true,
      endOfSong: false,
      sleepRemaining: totalSeconds,
    );
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (_) => _sleepTick());
    debugPrint('=== SLEEP ALARM: sleep started (${minutes}m) ===');
  }

  void _sleepTick() {
    if (!mounted) {
      _sleepTimer?.cancel();
      return;
    }

    final remaining = state.sleepRemaining - 1;

    // ── Ambient dim ramp ──
    if (state.ambientDimEnabled && state.sleepRemaining > 0) {
      // Base dim: 0.0 → 0.8 over the full timer duration
      // But only start dimming in the last 5 minutes (300s) to avoid
      // dimming for 90-minute timers from the start.
      final dimWindow = 300; // seconds
      if (remaining <= dimWindow) {
        final dimFraction = 1.0 - (remaining / dimWindow);
        final dimVal = (dimFraction * 0.8).clamp(0.0, 0.8);
        ambientDimNotifier.value = dimVal;
        state = state.copyWith(ambientDimValue: dimVal);
      }
    }

    // ── Fade-out trigger ──
    // Start the fade exactly when remaining == fadeOutDuration (once).
    if (state.fadeOutEnabled &&
        remaining == state.fadeOutDuration &&
        !_fadeEngine.isFading) {
      debugPrint('=== SLEEP ALARM: fade-out started (${state.fadeOutDuration}s) ===');
      _fadeEngine.fadeOut(durationSeconds: state.fadeOutDuration);
      state = state.copyWith(fadeInProgress: true);
    }

    if (remaining <= 0) {
      _onSleepComplete();
      return;
    }

    state = state.copyWith(sleepRemaining: remaining);
  }

  void _onSleepComplete() {
    debugPrint('=== SLEEP ALARM: sleep complete — stopping ===');
    _sleepTimer?.cancel();
    _sleepTimer = null;

    // Stop playback (not just pause) — full shutdown so the foreground
    // service is released and battery drain is eliminated overnight.
    final handler = _ref.read(audioHandlerProvider);
    handler.stop();

    // Reset volume to 1.0 (clean for next play)
    _fadeEngine.cancelAndRestore();

    // Reset state
    state = state.copyWith(
      sleepActive: false,
      sleepRemaining: 0,
      endOfSong: false,
      ambientDimValue: 0.0,
      fadeInProgress: false,
    );
    ambientDimNotifier.value = 0.0;
  }

  // ════════════════════════════════════════════════
  //  END-OF-SONG MODE
  // ════════════════════════════════════════════════

  void _listenForEndOfSong() {
    _endOfSongSub?.cancel();
    final handler = _ref.read(audioHandlerProvider);

    _endOfSongSub = handler.playerStateStream.listen((playerState) {
      if (!mounted) {
        _endOfSongSub?.cancel();
        return;
      }

      // When the current track finishes processing (completed state)
      if (playerState.processingState == ProcessingState.completed) {
        debugPrint('=== SLEEP ALARM: end-of-song triggered ===');
        _endOfSongSub?.cancel();
        _endOfSongSub = null;
        _onSleepComplete();
      }
    });

    debugPrint('=== SLEEP ALARM: listening for end-of-song ===');
  }

  void _cancelSleepInternal() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _endOfSongSub?.cancel();
    _endOfSongSub = null;
  }

  // ════════════════════════════════════════════════
  //  SLEEP SETTINGS
  // ════════════════════════════════════════════════

  void setFadeOutEnabled(bool v) {
    state = state.copyWith(fadeOutEnabled: v);
    _persist();
  }

  void setFadeOutDuration(int seconds) {
    state = state.copyWith(fadeOutDuration: seconds);
    _persist();
  }

  void setAmbientDimEnabled(bool v) {
    state = state.copyWith(ambientDimEnabled: v);
    if (!v) {
      ambientDimNotifier.value = 0.0;
      state = state.copyWith(ambientDimValue: 0.0);
    }
    _persist();
  }

  // ════════════════════════════════════════════════
  //  ALARM SETTINGS
  // ════════════════════════════════════════════════

  void setAlarmEnabled(bool v) {
    state = state.copyWith(alarmEnabled: v);
    _syncAlarmConfig();
    _persist();
  }

  void setAlarmTime(int hour, int minute) {
    state = state.copyWith(alarmHour: hour, alarmMinute: minute);
    _syncAlarmConfig();
    _persist();
  }

  void setAlarmPlaylist(String? playlistId) {
    if (playlistId == null) {
      state = state.copyWith(clearAlarmPlaylist: true);
    } else {
      state = state.copyWith(alarmPlaylistId: playlistId);
    }
    _syncAlarmConfig();
    _persist();
  }

  void setAlarmVolume(double v) {
    state = state.copyWith(alarmVolume: v.clamp(0.0, 1.0));
    _syncAlarmConfig();
    _persist();
  }

  void setProgressiveVolume(bool v) {
    state = state.copyWith(progressiveVolume: v);
    _syncAlarmConfig();
    _persist();
  }

  void setAlarmFadeDuration(int seconds) {
    state = state.copyWith(alarmFadeDuration: seconds);
    _syncAlarmConfig();
    _persist();
  }

  void _syncAlarmConfig() {
    _alarmScheduler.saveConfig(AlarmConfig(
      enabled: state.alarmEnabled,
      hour: state.alarmHour,
      minute: state.alarmMinute,
      playlistId: state.alarmPlaylistId,
      volume: state.alarmVolume,
      progressiveVolume: state.progressiveVolume,
      fadeDuration: state.alarmFadeDuration,
    ));
  }

  // ════════════════════════════════════════════════
  //  ALARM TRIGGER (callback from AlarmSchedulerService)
  // ════════════════════════════════════════════════

  void _onAlarmFired(Song song, AlarmConfig config) {
    debugPrint('=== SLEEP ALARM: alarm fired → ${song.name} ===');

    // Reset ambient dim
    ambientDimNotifier.value = 0.0;
    state = state.copyWith(ambientDimValue: 0.0);

    // Play the alarm song
    _ref.read(playerProvider.notifier).playSong(song, context: 'Alarm');

    // Volume handling
    final handler = _ref.read(audioHandlerProvider);
    if (config.progressiveVolume) {
      // Start at near-silent, ramp up to alarm volume
      handler.setVolume(0.05);
      _fadeEngine.fadeIn(
        startVol: 0.05,
        targetVol: config.volume,
        durationSeconds: config.fadeDuration,
      );
      state = state.copyWith(fadeInProgress: true);
    } else {
      handler.setVolume(config.volume);
    }
  }

  /// Dismiss alarm (stop ramp, keep playing at alarm volume).
  void dismissAlarm() {
    _fadeEngine.cancel();
    final handler = _ref.read(audioHandlerProvider);
    handler.setVolume(state.alarmVolume);
    state = state.copyWith(fadeInProgress: false);
  }

  /// Snooze alarm — pause playback, re-arm in 5 minutes.
  void snoozeAlarm({int minutes = 5}) {
    _fadeEngine.cancel();
    final handler = _ref.read(audioHandlerProvider);
    handler.pause();
    handler.setVolume(1.0);
    state = state.copyWith(fadeInProgress: false);

    // Re-arm: shift alarm time forward by snooze duration
    final now = DateTime.now();
    final snoozeTime = now.add(Duration(minutes: minutes));
    setAlarmTime(snoozeTime.hour, snoozeTime.minute);
    debugPrint('=== SLEEP ALARM: snoozed → ${snoozeTime.hour}:${snoozeTime.minute} ===');
  }

  // ════════════════════════════════════════════════
  //  CLEANUP
  // ════════════════════════════════════════════════

  @override
  void dispose() {
    _cancelSleepInternal();
    _fadeEngine.dispose();
    _alarmScheduler.dispose();
    ambientDimNotifier.dispose();
    super.dispose();
  }
}

// ════════════════════════════════════════════════
//  PROVIDERS
// ════════════════════════════════════════════════

/// The Hive box must be opened in main.dart before runApp.
final sleepAlarmBoxProvider = Provider<Box>((ref) {
  return Hive.box('sleep_alarm');
});

final sleepAlarmProvider =
    StateNotifierProvider<SleepAlarmNotifier, SleepAlarmState>((ref) {
  final box = ref.read(sleepAlarmBoxProvider);
  return SleepAlarmNotifier(ref, box);
});

/// Expose the ambient dim ValueNotifier for the overlay widget.
/// This avoids rebuilding the entire widget tree on every dim change.
final ambientDimProvider = Provider<ValueNotifier<double>>((ref) {
  return ref.read(sleepAlarmProvider.notifier).ambientDimNotifier;
});
