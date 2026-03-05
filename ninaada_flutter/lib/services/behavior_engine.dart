import 'dart:convert';
import 'dart:math' show pow, min, max;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ════════════════════════════════════════════════════════════════
//  BEHAVIOR ENGINE — Phase 9B: Behavioral Adaptation
// ════════════════════════════════════════════════════════════════
//
//  Clean, deterministic intelligence. No ML runtime. No neural nets.
//
//  Tracks three layers of behavioral signal:
//
//  ┌────────────────────────────────────────────────────────────┐
//  │  1. SONG AFFINITY   Map<songId, score>                    │
//  │     +2 full play (>80%), -3 early skip (<20%),            │
//  │     +1 replay within 24h, -1 skip <10s                    │
//  │     Clamped [-20, +20]                                    │
//  │                                                           │
//  │  2. ARTIST SCORE    Map<artistName, score>                │
//  │     += songAffinityDelta × 0.6                            │
//  │     Clamped [-50, +50]                                    │
//  │                                                           │
//  │  3. LANGUAGE SCORE  Map<language, score>                   │
//  │     += songAffinityDelta × 0.4                            │
//  │     Clamped [-30, +30]                                    │
//  │                                                           │
//  │  Daily decay: all scores × 0.98 per day since last decay  │
//  │  Session tracker: last 20 events → skip/full-play rates   │
//  │  Dynamic epsilon:                                         │
//  │    skipRate > 0.4  → ε = 0.35 (explore more)              │
//  │    fullPlay > 0.7  → ε = 0.10 (exploit groove)            │
//  │    else            → ε = 0.20 (balanced)                  │
//  └────────────────────────────────────────────────────────────┘
//
//  Persisted in Hive 'behavior_engine' box. Ring buffer of 2000
//  events for analysis. Scores persisted as JSON maps.
//
// ════════════════════════════════════════════════════════════════

/// A single listening event with play-completion signal.
class ListeningEvent {
  final String songId;
  final String artist;
  final String language;

  /// 0.0 to 1.0 — fraction of song actually listened to.
  final double playPercentage;

  /// True if user explicitly pressed skip/next.
  final bool manualSkip;

  final DateTime timestamp;

  const ListeningEvent({
    required this.songId,
    required this.artist,
    required this.language,
    required this.playPercentage,
    required this.manualSkip,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'sid': songId,
        'art': artist,
        'lng': language,
        'pp': playPercentage,
        'ms': manualSkip,
        'ts': timestamp.toIso8601String(),
      };

  factory ListeningEvent.fromJson(Map<String, dynamic> j) => ListeningEvent(
        songId: j['sid'] as String? ?? '',
        artist: j['art'] as String? ?? '',
        language: j['lng'] as String? ?? '',
        playPercentage: (j['pp'] as num?)?.toDouble() ?? 0,
        manualSkip: j['ms'] as bool? ?? false,
        timestamp: DateTime.tryParse(j['ts'] ?? '') ?? DateTime.now(),
      );

  /// Was the play "full" enough to count as positive signal?
  bool get isFullPlay => playPercentage >= 0.80;

  /// Was this an early skip (negative signal)?
  bool get isEarlySkip => playPercentage < 0.20 || (manualSkip && playPercentage < 0.30);

  /// Was this a very quick skip (< 10 seconds equivalent)?
  bool get isQuickSkip => manualSkip && playPercentage < 0.05;
}

// ════════════════════════════════════════════════════════════════
//  BEHAVIOR ENGINE SINGLETON
// ════════════════════════════════════════════════════════════════

class BehaviorEngine {
  BehaviorEngine._();
  static BehaviorEngine? _instance;

  /// Whether the engine has been initialized. Safe to call before init().
  static bool get isInitialized => _instance != null;

  static BehaviorEngine get instance {
    assert(_instance != null, 'BehaviorEngine.init() must be called first');
    return _instance!;
  }

  // ── Constants ──
  static const int _maxEvents = 2000;
  static const int _sessionWindow = 20; // last N events for session behavior
  static const double _dailyDecay = 0.98;
  static const double _songClampMin = -20.0;
  static const double _songClampMax = 20.0;
  static const double _artistClampMin = -50.0;
  static const double _artistClampMax = 50.0;
  static const double _langClampMin = -30.0;
  static const double _langClampMax = 30.0;

  // ── Scoring deltas ──
  static const double _fullPlayDelta = 2.0;
  static const double _earlySkipDelta = -3.0;
  static const double _quickSkipDelta = -1.0; // stacks with earlySkip
  static const double _replayBonusDelta = 1.0;
  static const double _artistPropagation = 0.6;
  static const double _languagePropagation = 0.4;

  // ── Dynamic epsilon thresholds ──
  static const double _highSkipThreshold = 0.40;
  static const double _highFullPlayThreshold = 0.70;
  static const double _epsilonExplore = 0.35; // high skip → explore more
  static const double _epsilonBalanced = 0.20; // default
  static const double _epsilonExploit = 0.10; // high full play → exploit

  // ── State ──
  late Box _box;
  final List<ListeningEvent> _events = [];

  /// Song-level affinity: songId → score [-20, +20]
  final Map<String, double> songAffinity = {};

  /// Artist behavioral score: artistName → score [-50, +50]
  final Map<String, double> behavioralArtistScore = {};

  /// Language behavioral score: language → score [-30, +30]
  final Map<String, double> behavioralLanguageScore = {};

  /// Last time daily decay was applied.
  DateTime _lastDecayDate = DateTime.now();

  /// Total events ever processed (persisted, never resets).
  int _totalEventsProcessed = 0;

  int get totalEvents => _totalEventsProcessed;

  /// Unmodifiable view of the event buffer.
  List<ListeningEvent> get events => List.unmodifiable(_events);

  // ════════════════════════════════════════════════
  //  INIT
  // ════════════════════════════════════════════════

  static Future<void> init() async {
    if (_instance != null) return;
    final engine = BehaviorEngine._();
    engine._box = await Hive.openBox('behavior_engine');
    engine._load();
    engine._applyPendingDecay();
    _instance = engine;
    debugPrint('=== BEHAVIOR ENGINE: initialized — '
        '${engine._events.length} events, '
        '${engine.songAffinity.length} song affinities, '
        'ε=${engine.currentEpsilon.toStringAsFixed(2)} ===');
  }

  // ════════════════════════════════════════════════
  //  PERSISTENCE
  // ════════════════════════════════════════════════

  void _load() {
    // Events ring buffer
    final rawEvents = _box.get('events');
    if (rawEvents != null) {
      try {
        final list = (jsonDecode(rawEvents) as List)
            .map((e) => ListeningEvent.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _events.addAll(list);
      } catch (e) {
        debugPrint('=== BEHAVIOR ENGINE: events parse error: $e ===');
      }
    }

    // Song affinity
    final rawSong = _box.get('songAffinity');
    if (rawSong != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(rawSong));
        songAffinity.addAll(
          map.map((k, v) => MapEntry(k, (v as num).toDouble())),
        );
      } catch (e) {
        debugPrint('=== BEHAVIOR ENGINE: songAffinity parse error: $e ===');
      }
    }

    // Artist behavioral score
    final rawArtist = _box.get('artistScore');
    if (rawArtist != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(rawArtist));
        behavioralArtistScore.addAll(
          map.map((k, v) => MapEntry(k, (v as num).toDouble())),
        );
      } catch (e) {
        debugPrint('=== BEHAVIOR ENGINE: artistScore parse error: $e ===');
      }
    }

    // Language behavioral score
    final rawLang = _box.get('languageScore');
    if (rawLang != null) {
      try {
        final map = Map<String, dynamic>.from(jsonDecode(rawLang));
        behavioralLanguageScore.addAll(
          map.map((k, v) => MapEntry(k, (v as num).toDouble())),
        );
      } catch (e) {
        debugPrint('=== BEHAVIOR ENGINE: languageScore parse error: $e ===');
      }
    }

    // Last decay date
    final rawDecay = _box.get('lastDecayDate');
    if (rawDecay != null) {
      _lastDecayDate = DateTime.tryParse(rawDecay) ?? DateTime.now();
    }

    // Total events counter
    _totalEventsProcessed = _box.get('totalEvents', defaultValue: 0) as int;
  }

  Future<void> _save() async {
    // Persist events (ring buffer — only keep last _maxEvents)
    final eventJson = _events.map((e) => e.toJson()).toList();
    await _box.put('events', jsonEncode(eventJson));

    // Persist affinity maps
    await _box.put('songAffinity', jsonEncode(songAffinity));
    await _box.put('artistScore', jsonEncode(behavioralArtistScore));
    await _box.put('languageScore', jsonEncode(behavioralLanguageScore));

    // Persist decay date
    await _box.put('lastDecayDate', _lastDecayDate.toIso8601String());

    // Persist total events
    await _box.put('totalEvents', _totalEventsProcessed);
  }

  // ════════════════════════════════════════════════
  //  DAILY DECAY — 0.98 per day
  // ════════════════════════════════════════════════

  void _applyPendingDecay() {
    final now = DateTime.now();
    final daysPassed = now.difference(_lastDecayDate).inDays;
    if (daysPassed <= 0) return;

    final factor = pow(_dailyDecay, daysPassed).toDouble();
    debugPrint('=== BEHAVIOR ENGINE: applying $daysPassed day(s) decay '
        '(factor=${factor.toStringAsFixed(4)}) ===');

    // Decay all maps
    for (final key in songAffinity.keys.toList()) {
      songAffinity[key] = songAffinity[key]! * factor;
      // Prune near-zero entries to keep maps small
      if (songAffinity[key]!.abs() < 0.01) songAffinity.remove(key);
    }

    for (final key in behavioralArtistScore.keys.toList()) {
      behavioralArtistScore[key] = behavioralArtistScore[key]! * factor;
      if (behavioralArtistScore[key]!.abs() < 0.01) {
        behavioralArtistScore.remove(key);
      }
    }

    for (final key in behavioralLanguageScore.keys.toList()) {
      behavioralLanguageScore[key] = behavioralLanguageScore[key]! * factor;
      if (behavioralLanguageScore[key]!.abs() < 0.01) {
        behavioralLanguageScore.remove(key);
      }
    }

    _lastDecayDate = DateTime(now.year, now.month, now.day);
    _save(); // fire-and-forget
  }

  // ════════════════════════════════════════════════
  //  EVENT LOGGING — The core behavioral signal
  // ════════════════════════════════════════════════

  /// Log a listening event and update all affinity scores.
  ///
  /// Called from PlayerNotifier when:
  ///   • A track changes (previous song gets logged)
  ///   • User manually skips (with playPercentage at skip time)
  Future<void> logEvent(ListeningEvent event) async {
    // ── 1. Ring buffer: append + trim ──
    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
    _totalEventsProcessed++;

    // ── 2. Compute song affinity delta ──
    double delta = 0;

    if (event.isFullPlay) {
      delta += _fullPlayDelta;
    }

    if (event.isEarlySkip) {
      delta += _earlySkipDelta;
    }

    if (event.isQuickSkip) {
      delta += _quickSkipDelta; // stacks: -3 + -1 = -4 for instant skips
    }

    // Replay bonus: played same song within last 24h
    if (delta > 0) {
      final lastPlay = _findLastPlayTime(event.songId);
      if (lastPlay != null) {
        final hoursSince = event.timestamp.difference(lastPlay).inHours;
        if (hoursSince > 0 && hoursSince <= 24) {
          delta += _replayBonusDelta;
        }
      }
    }

    // ── 3. Update song affinity ──
    if (delta != 0) {
      final current = songAffinity[event.songId] ?? 0;
      songAffinity[event.songId] =
          (current + delta).clamp(_songClampMin, _songClampMax);

      // ── 4. Propagate to artist score ──
      if (event.artist.isNotEmpty) {
        final primaryArtist =
            event.artist.split(RegExp(r'[,;]')).first.trim();
        if (primaryArtist.isNotEmpty) {
          final artistDelta = delta * _artistPropagation;
          final currentArtist =
              behavioralArtistScore[primaryArtist] ?? 0;
          behavioralArtistScore[primaryArtist] = (currentArtist + artistDelta)
              .clamp(_artistClampMin, _artistClampMax);
        }
      }

      // ── 5. Propagate to language score ──
      if (event.language.isNotEmpty) {
        final lang = event.language.toLowerCase();
        final langDelta = delta * _languagePropagation;
        final currentLang = behavioralLanguageScore[lang] ?? 0;
        behavioralLanguageScore[lang] =
            (currentLang + langDelta).clamp(_langClampMin, _langClampMax);
      }
    }

    // ── 6. Persist (fire-and-forget, debounced by Hive) ──
    await _save();

    debugPrint('=== BEHAVIOR ENGINE: logged ${event.songId} — '
        'pp=${event.playPercentage.toStringAsFixed(2)}, '
        'skip=${event.manualSkip}, delta=$delta, '
        'songAff=${songAffinity[event.songId]?.toStringAsFixed(1)} ===');
  }

  /// Find the timestamp of the most recent play of this song
  /// (before the current event, i.e., second-to-last occurrence).
  DateTime? _findLastPlayTime(String songId) {
    // Search backwards through events, skip the one we just added
    for (int i = _events.length - 2; i >= 0; i--) {
      if (_events[i].songId == songId) return _events[i].timestamp;
    }
    return null;
  }

  // ════════════════════════════════════════════════
  //  SESSION BEHAVIOR — last N events analysis
  // ════════════════════════════════════════════════

  /// Recent skip rate (0.0 to 1.0) from last [_sessionWindow] events.
  double get recentSkipRate {
    if (_events.isEmpty) return 0;
    final window =
        _events.sublist(max(0, _events.length - _sessionWindow));
    final skips = window.where((e) => e.isEarlySkip).length;
    return skips / window.length;
  }

  /// Recent full-play rate (0.0 to 1.0) from last [_sessionWindow] events.
  double get recentFullPlayRate {
    if (_events.isEmpty) return 0;
    final window =
        _events.sublist(max(0, _events.length - _sessionWindow));
    final full = window.where((e) => e.isFullPlay).length;
    return full / window.length;
  }

  // ════════════════════════════════════════════════
  //  DYNAMIC EPSILON — adapts exploration rate
  // ════════════════════════════════════════════════

  /// Compute the current epsilon based on session behavior.
  ///
  /// Logic:
  ///   • User skipping a lot (>40%) → ε = 0.35 (explore more, current picks are bad)
  ///   • User listening fully (>70%) → ε = 0.10 (exploit the groove)
  ///   • Otherwise → ε = 0.20 (balanced discovery)
  double get currentEpsilon {
    // Not enough data → use balanced default
    if (_events.length < 5) return _epsilonBalanced;

    final skipRate = recentSkipRate;
    final fullRate = recentFullPlayRate;

    if (skipRate > _highSkipThreshold) return _epsilonExplore;
    if (fullRate > _highFullPlayThreshold) return _epsilonExploit;
    return _epsilonBalanced;
  }

  // ════════════════════════════════════════════════
  //  QUERY HELPERS — used by RecommendationEngine
  // ════════════════════════════════════════════════

  /// Get the song-level affinity score (0 if unknown).
  double getSongAffinity(String songId) => songAffinity[songId] ?? 0;

  /// Get the behavioral artist score (0 if unknown).
  double getArtistScore(String artist) {
    // Check exact match first
    final exact = behavioralArtistScore[artist];
    if (exact != null) return exact;
    // Check primary artist (first in comma-separated list)
    final primary = artist.split(RegExp(r'[,;]')).first.trim();
    return behavioralArtistScore[primary] ?? 0;
  }

  /// Get the behavioral language score (0 if unknown).
  double getLanguageScore(String language) =>
      behavioralLanguageScore[language.toLowerCase()] ?? 0;

  /// Whether the engine has enough data to provide meaningful signals.
  bool get hasMinimalData => _totalEventsProcessed >= 5;

  /// Cold-start weight multiplier for onboarding profile.
  ///
  /// < 20 events → 2.0× (trust onboarding heavily)
  /// 20–100 events → linear ramp from 2.0× to 0.5×
  /// > 100 events → 0.5× (behavior dominates)
  double get onboardingWeight {
    if (_totalEventsProcessed < 20) return 2.0;
    if (_totalEventsProcessed > 100) return 0.5;
    // Linear interpolation: 20→2.0, 100→0.5
    final t = (_totalEventsProcessed - 20) / 80.0;
    return 2.0 - (1.5 * t);
  }

  // ════════════════════════════════════════════════
  //  DIVERSITY GUARD — prevent artist repetition
  // ════════════════════════════════════════════════

  /// Check if the last N autoplay songs were from the same artist.
  /// Returns a penalty multiplier (1.0 = no penalty, 0.0 = full block).
  double diversityPenalty(String artist, List<String> recentAutoplayArtists) {
    if (recentAutoplayArtists.isEmpty) return 1.0;
    final primary = artist.split(RegExp(r'[,;]')).first.trim().toLowerCase();

    // Count how many of the last 3 autoplay songs share this artist
    final last3 = recentAutoplayArtists
        .take(3)
        .map((a) => a.split(RegExp(r'[,;]')).first.trim().toLowerCase())
        .toList();

    final sameArtistCount = last3.where((a) => a == primary).length;

    if (sameArtistCount >= 2) return 0.2; // Heavy penalty: 3rd in a row
    if (sameArtistCount >= 1) return 0.7; // Light penalty: 2nd in a row
    return 1.0; // No penalty
  }

  // ════════════════════════════════════════════════
  //  DEBUG — dev overlay data
  // ════════════════════════════════════════════════

  /// Summary for debug overlay (only in debug mode).
  Map<String, dynamic> get debugSummary => {
        'totalEvents': _totalEventsProcessed,
        'bufferedEvents': _events.length,
        'epsilon': currentEpsilon,
        'skipRate': recentSkipRate,
        'fullPlayRate': recentFullPlayRate,
        'songAffinities': songAffinity.length,
        'artistScores': behavioralArtistScore.length,
        'languageScores': behavioralLanguageScore.length,
        'onboardingWeight': onboardingWeight,
        'topArtists': _topEntries(behavioralArtistScore, 5),
        'topLanguages': _topEntries(behavioralLanguageScore, 3),
        'recentEvents': _events
            .reversed
            .take(5)
            .map((e) => '${e.songId.substring(0, min(8, e.songId.length))}:'
                '${(e.playPercentage * 100).toInt()}%'
                '${e.manualSkip ? "⏭" : ""}')
            .toList(),
      };

  List<MapEntry<String, double>> _topEntries(Map<String, double> map, int n) {
    final sorted = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(n).toList();
  }

  /// Reset all behavioral data (for testing).
  Future<void> reset() async {
    _events.clear();
    songAffinity.clear();
    behavioralArtistScore.clear();
    behavioralLanguageScore.clear();
    _totalEventsProcessed = 0;
    _lastDecayDate = DateTime.now();
    await _save();
    debugPrint('=== BEHAVIOR ENGINE: RESET ===');
  }
}
