import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/data/models.dart';

// ================================================================
//  ALARM SCHEDULER SERVICE — Layer 3
// ================================================================
//
//  Pure service. No UI, no Riverpod, no Widget dependencies.
//  Runs a 30-second Timer.periodic that compares DateTime.now()
//  against the configured alarm time.
//
//  Dedup guard: after trigger, suppresses re-fire for 2 minutes.
//
//  Song resolution:
//    1. Try the chosen Hive playlist (playlistId)
//    2. Fallback: HTTP GET /browse/top-songs → random song
//
//  Alarm trigger delivers a Song via [onAlarmFired] callback.
//  The controller (Layer 1) handles playback + volume ramp.
// ================================================================

/// Immutable alarm config — serialized to/from Hive.
class AlarmConfig {
  final bool enabled;
  final int hour;          // 0-23
  final int minute;        // 0-59
  final String? playlistId;
  final double volume;     // 0.0–1.0
  final bool progressiveVolume;
  final int fadeDuration;  // seconds for volume ramp
  final bool ambientDim;

  const AlarmConfig({
    this.enabled = false,
    this.hour = 7,
    this.minute = 0,
    this.playlistId,
    this.volume = 0.7,
    this.progressiveVolume = true,
    this.fadeDuration = 60,
    this.ambientDim = false,
  });

  AlarmConfig copyWith({
    bool? enabled,
    int? hour,
    int? minute,
    String? playlistId,
    double? volume,
    bool? progressiveVolume,
    int? fadeDuration,
    bool? ambientDim,
    bool clearPlaylist = false,
  }) {
    return AlarmConfig(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      playlistId: clearPlaylist ? null : (playlistId ?? this.playlistId),
      volume: volume ?? this.volume,
      progressiveVolume: progressiveVolume ?? this.progressiveVolume,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      ambientDim: ambientDim ?? this.ambientDim,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'hour': hour,
    'minute': minute,
    'playlistId': playlistId,
    'volume': volume,
    'progressiveVolume': progressiveVolume,
    'fadeDuration': fadeDuration,
    'ambientDim': ambientDim,
  };

  factory AlarmConfig.fromJson(Map<String, dynamic> json) => AlarmConfig(
    enabled: json['enabled'] as bool? ?? false,
    hour: json['hour'] as int? ?? 7,
    minute: json['minute'] as int? ?? 0,
    playlistId: json['playlistId'] as String?,
    volume: (json['volume'] as num?)?.toDouble() ?? 0.7,
    progressiveVolume: json['progressiveVolume'] as bool? ?? true,
    fadeDuration: json['fadeDuration'] as int? ?? 60,
    ambientDim: json['ambientDim'] as bool? ?? false,
  );

  String get formattedTime {
    final h = hour.toString().padLeft(2, '0');
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class AlarmSchedulerService {
  final Box _box;
  final ApiService _api = ApiService();

  Timer? _checker;
  DateTime? _lastTrigger;

  /// Fires when alarm conditions are met. Delivers (song, config).
  void Function(Song song, AlarmConfig config)? onAlarmFired;

  AlarmConfig _config = const AlarmConfig();
  AlarmConfig get config => _config;

  AlarmSchedulerService(this._box) {
    _loadConfig();
  }

  // ────────────────────────────────────────────
  //  PERSISTENCE
  // ────────────────────────────────────────────
  void _loadConfig() {
    try {
      final raw = _box.get('alarm_config');
      if (raw != null) {
        _config = AlarmConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('=== ALARM SCHEDULER: loadConfig error: $e ===');
    }
  }

  Future<void> saveConfig(AlarmConfig cfg) async {
    _config = cfg;
    await _box.put('alarm_config', jsonEncode(cfg.toJson()));
    // Restart checker if enabled changed
    if (cfg.enabled) {
      start();
    } else {
      stop();
    }
  }

  // ────────────────────────────────────────────
  //  TIME CHECKER — 30s interval
  // ────────────────────────────────────────────
  void start() {
    if (!_config.enabled) return;
    _checker?.cancel();
    _checker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    debugPrint('=== ALARM SCHEDULER: started (${_config.formattedTime}) ===');
  }

  void stop() {
    _checker?.cancel();
    _checker = null;
    debugPrint('=== ALARM SCHEDULER: stopped ===');
  }

  void _tick() {
    if (!_config.enabled) return;

    final now = DateTime.now();

    // Dedup: suppress for 2 minutes after last trigger
    if (_lastTrigger != null &&
        now.difference(_lastTrigger!).inMinutes < 2) {
      return;
    }

    if (now.hour == _config.hour && now.minute == _config.minute) {
      _lastTrigger = now;
      debugPrint('=== ALARM SCHEDULER: TRIGGERED at ${now.hour}:${now.minute} ===');
      _resolveAndFire();
    }
  }

  // ────────────────────────────────────────────
  //  SONG RESOLUTION
  // ────────────────────────────────────────────
  Future<void> _resolveAndFire() async {
    Song? song;

    // 1. Try playlist
    if (_config.playlistId != null) {
      song = _resolveFromPlaylist(_config.playlistId!);
    }

    // 2. Fallback: trending API
    if (song == null) {
      song = await _resolveFromApi();
    }

    if (song != null) {
      onAlarmFired?.call(song, _config);
    } else {
      debugPrint('=== ALARM SCHEDULER: no song resolved, alarm skipped ===');
    }
  }

  Song? _resolveFromPlaylist(String playlistId) {
    try {
      final raw = _box.get('playlists');
      if (raw == null) return null;

      // Use the library box's playlist data
      final libraryBox = Hive.box('library');
      final plRaw = libraryBox.get('playlists');
      if (plRaw == null) return null;

      final playlists = (jsonDecode(plRaw) as List)
          .map((e) => PlaylistModel.fromJson(e as Map<String, dynamic>))
          .toList();

      final match = playlists
          .where((p) => p.id == playlistId)
          .firstOrNull;

      if (match == null || match.songs.isEmpty) return null;

      // Random song from playlist
      final rng = Random();
      return match.songs[rng.nextInt(match.songs.length)];
    } catch (e) {
      debugPrint('=== ALARM SCHEDULER: playlist resolve error: $e ===');
      return null;
    }
  }

  Future<Song?> _resolveFromApi() async {
    try {
      final songs = await _api.fetchTopSongs(limit: 20);
      if (songs.isEmpty) return null;
      final rng = Random();
      return songs[rng.nextInt(songs.length)];
    } catch (e) {
      debugPrint('=== ALARM SCHEDULER: API resolve error: $e ===');
      return null;
    }
  }

  // ────────────────────────────────────────────
  //  CLEANUP
  // ────────────────────────────────────────────
  void dispose() {
    stop();
    onAlarmFired = null;
  }
}
