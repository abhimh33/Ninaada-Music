import 'dart:convert';
import 'dart:math' show pow;
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ════════════════════════════════════════════════════════════════
//  USER TASTE PROFILE — Local device-level user preferences
// ════════════════════════════════════════════════════════════════
//
//  1 Device = 1 User = 1 Profile.
//  No auth, no JWT, no cloud sync — everything is local Hive.
//
//  Stored as a single JSON blob in the 'user_taste' Hive box.
//
//  ┌───────────────────────────────────────────────────────────────┐
//  │  artistAffinity      Map<artistName, score>                  │
//  │  genreAffinity       Map<language, score>                    │
//  │  languageAffinity    Map<language, score>                    │
//  │  albumAffinity       Map<albumName, score>                   │
//  │  affinityTimestamps  Map<dimension:key, ISO8601>             │
//  │  lastPlayedAt        Map<songId, ISO8601 timestamp>          │
//  │  skipCount           Map<songId, count>                      │
//  │  listeningHistory    List<songId> (last 200)                 │
//  │  weeklyDigest        {generatedAt, songIds}                  │
//  └───────────────────────────────────────────────────────────────┘
//
//  ── Exponential Time Decay (14-day half-life) ──
//
//    Affinity_adjusted = Affinity_raw × 0.5^(DaysSinceLastInteraction / 14.0)
//
//    Applied at READ time via decayed*Affinity getters, preserving
//    the raw accumulated data for lossless recalculation.
//
//  ── Scoring Weights ──
//    Full play    → +2.0
//    Repeat play  → +3.0 (play count > 3)
//    Liked song   → +4.0
//    Skip         → -1.0
//
// ════════════════════════════════════════════════════════════════

/// Half-life in days for affinity score decay.
/// After 14 days of no interaction, a score drops to 50%.
const double kAffinityHalfLifeDays = 14.0;

class UserTasteProfile {
  /// Artist name → accumulated affinity score (raw, un-decayed)
  Map<String, double> artistAffinity;

  /// Language/genre → accumulated affinity score
  /// (Ninaada uses language as the primary genre signal)
  Map<String, double> genreAffinity;

  /// Language → accumulated affinity score (distinct from genre for scoring)
  Map<String, double> languageAffinity;

  /// Album name → accumulated affinity score
  Map<String, double> albumAffinity;

  /// Phase 6 — Per-entry decay clock.
  /// Key format: "artist:ArtistName", "genre:Hindi", "language:Hindi",
  /// "album:AlbumName". Value = DateTime of last interaction with that key.
  /// Used by [getDecayedScore] to apply 14-day half-life at read time.
  Map<String, DateTime> affinityTimestamps;

  /// Song ID → last played timestamp (ISO 8601)
  Map<String, DateTime> lastPlayedAt;

  /// Song ID → skip count
  Map<String, int> skipCount;

  /// Recent song IDs in play order (most recent first, max 200)
  List<String> listeningHistory;

  /// Weekly digest metadata for Discover Weekly caching
  DateTime? weeklyDigestGeneratedAt;
  List<String> weeklyDigestSongIds;

  UserTasteProfile({
    required this.artistAffinity,
    required this.genreAffinity,
    required this.languageAffinity,
    required this.albumAffinity,
    required this.affinityTimestamps,
    required this.lastPlayedAt,
    required this.skipCount,
    required this.listeningHistory,
    this.weeklyDigestGeneratedAt,
    this.weeklyDigestSongIds = const [],
  });

  /// Brand new empty profile (first app install)
  factory UserTasteProfile.initial() {
    return UserTasteProfile(
      artistAffinity: {},
      genreAffinity: {},
      languageAffinity: {},
      albumAffinity: {},
      affinityTimestamps: {},
      lastPlayedAt: {},
      skipCount: {},
      listeningHistory: [],
      weeklyDigestSongIds: [],
    );
  }

  /// Whether the user has ANY signal at all — listening history OR
  /// onboarding-seeded affinities. If either exists, scoring is valid.
  bool get isEmpty =>
      lastPlayedAt.isEmpty &&
      listeningHistory.isEmpty &&
      artistAffinity.isEmpty &&
      languageAffinity.isEmpty;

  // ════════════════════════════════════════════════
  //  EXPONENTIAL TIME DECAY (Phase 6)
  // ════════════════════════════════════════════════

  /// Apply 14-day half-life decay to a single entry.
  /// [dimension] — "artist", "genre", "language", "album"
  /// [key]       — the key within that dimension (e.g. artist name)
  /// [rawScore]  — the un-decayed accumulated score
  ///
  /// Returns: rawScore × pow(0.5, daysSinceLastInteraction / 14.0)
  /// If no timestamp exists, returns rawScore unmodified (cold-start grace).
  double getDecayedScore(String dimension, String key, double rawScore) {
    final ts = affinityTimestamps['$dimension:$key'];
    if (ts == null) return rawScore;
    final daysSince = DateTime.now().difference(ts).inHours / 24.0;
    if (daysSince <= 0) return rawScore;
    return rawScore * pow(0.5, daysSince / kAffinityHalfLifeDays);
  }

  /// Decayed view of the entire artist affinity map.
  Map<String, double> get decayedArtistAffinity => artistAffinity.map(
        (k, v) => MapEntry(k, getDecayedScore('artist', k, v)),
      );

  /// Decayed view of the entire genre affinity map.
  Map<String, double> get decayedGenreAffinity => genreAffinity.map(
        (k, v) => MapEntry(k, getDecayedScore('genre', k, v)),
      );

  /// Decayed view of the entire language affinity map.
  Map<String, double> get decayedLanguageAffinity => languageAffinity.map(
        (k, v) => MapEntry(k, getDecayedScore('language', k, v)),
      );

  /// Decayed view of the entire album affinity map.
  Map<String, double> get decayedAlbumAffinity => albumAffinity.map(
        (k, v) => MapEntry(k, getDecayedScore('album', k, v)),
      );

  /// Record the "last touched" timestamp for an affinity key.
  void touchAffinity(String dimension, String key) {
    affinityTimestamps['$dimension:$key'] = DateTime.now();
  }

  /// Top N artists sorted by DECAYED affinity score (descending)
  List<MapEntry<String, double>> topArtists([int n = 5]) {
    final entries = decayedArtistAffinity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  /// Top N languages/genres sorted by DECAYED affinity (descending)
  List<MapEntry<String, double>> topGenres([int n = 3]) {
    final entries = decayedGenreAffinity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  /// Top N languages sorted by DECAYED affinity (descending)
  List<MapEntry<String, double>> topLanguages([int n = 3]) {
    final entries = decayedLanguageAffinity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(n).toList();
  }

  // ════════════════════════════════════════════════
  //  SERIALIZATION — JSON round-trip for Hive
  // ════════════════════════════════════════════════

  Map<String, dynamic> toJson() {
    return {
      'artistAffinity': artistAffinity,
      'genreAffinity': genreAffinity,
      'languageAffinity': languageAffinity,
      'albumAffinity': albumAffinity,
      'affinityTimestamps': affinityTimestamps.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ),
      'lastPlayedAt': lastPlayedAt.map(
        (k, v) => MapEntry(k, v.toIso8601String()),
      ),
      'skipCount': skipCount,
      'listeningHistory': listeningHistory,
      'weeklyDigestGeneratedAt': weeklyDigestGeneratedAt?.toIso8601String(),
      'weeklyDigestSongIds': weeklyDigestSongIds,
    };
  }

  factory UserTasteProfile.fromJson(Map<String, dynamic> json) {
    return UserTasteProfile(
      artistAffinity: _toDoubleMap(json['artistAffinity']),
      genreAffinity: _toDoubleMap(json['genreAffinity']),
      languageAffinity: _toDoubleMap(json['languageAffinity']),
      albumAffinity: _toDoubleMap(json['albumAffinity']),
      affinityTimestamps: _toDateTimeMap(json['affinityTimestamps']),
      lastPlayedAt: _toDateTimeMap(json['lastPlayedAt']),
      skipCount: _toIntMap(json['skipCount']),
      listeningHistory: (json['listeningHistory'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      weeklyDigestGeneratedAt: json['weeklyDigestGeneratedAt'] != null
          ? DateTime.tryParse(json['weeklyDigestGeneratedAt'])
          : null,
      weeklyDigestSongIds: (json['weeklyDigestSongIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  static Map<String, double> _toDoubleMap(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
  }

  static Map<String, int> _toIntMap(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    return raw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }

  static Map<String, DateTime> _toDateTimeMap(dynamic raw) {
    if (raw == null || raw is! Map) return {};
    final result = <String, DateTime>{};
    for (final entry in raw.entries) {
      final dt = DateTime.tryParse(entry.value.toString());
      if (dt != null) result[entry.key.toString()] = dt;
    }
    return result;
  }
}

// ════════════════════════════════════════════════════════════════
//  TASTE PROFILE MANAGER — Singleton access + Hive persistence
// ════════════════════════════════════════════════════════════════
//
//  Usage:
//    await TasteProfileManager.init();           // in main.dart
//    TasteProfileManager.instance.profile;       // read
//    TasteProfileManager.instance.onSongPlayed(song);  // write
//
// ════════════════════════════════════════════════════════════════

class TasteProfileManager {
  TasteProfileManager._();

  static TasteProfileManager? _instance;
  static TasteProfileManager get instance {
    assert(_instance != null, 'TasteProfileManager.init() must be called first');
    return _instance!;
  }

  late Box _box;
  late UserTasteProfile _profile;

  UserTasteProfile get profile => _profile;

  /// Initialize once in main.dart after Hive.initFlutter()
  static Future<void> init() async {
    if (_instance != null) return;
    final mgr = TasteProfileManager._();
    mgr._box = await Hive.openBox('user_taste');
    mgr._load();
    _instance = mgr;
    debugPrint('=== NINAADA: TasteProfileManager initialized '
        '(${mgr._profile.listeningHistory.length} history entries) ===');
  }

  void _load() {
    final raw = _box.get('profile');
    if (raw != null) {
      try {
        _profile = UserTasteProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw)),
        );
        return;
      } catch (e) {
        debugPrint('=== NINAADA: taste profile parse error: $e ===');
      }
    }
    _profile = UserTasteProfile.initial();
  }

  Future<void> _save() async {
    await _box.put('profile', jsonEncode(_profile.toJson()));
  }

  // ════════════════════════════════════════════════
  //  SIGNAL METHODS — called from LibraryNotifier / PlayerNotifier
  // ════════════════════════════════════════════════

  /// Called when a song is played (not skipped).
  /// Updates all affinity maps + listening history.
  Future<void> onSongPlayed({
    required String songId,
    required String artist,
    required String language,
    required String album,
    int playCount = 1,
  }) async {
    // Artist affinity: +2.0, bonus +1.0 if repeated (playCount > 3)
    final artistScore = playCount > 3 ? 3.0 : 2.0;
    _profile.artistAffinity[artist] =
        (_profile.artistAffinity[artist] ?? 0) + artistScore;
    _profile.touchAffinity('artist', artist);

    // Split primary artists (comma/semicolon separated) for secondary credit
    final parts = artist.split(RegExp(r'[,;]'));
    if (parts.length > 1) {
      for (int i = 1; i < parts.length; i++) {
        final secondary = parts[i].trim();
        if (secondary.isNotEmpty) {
          _profile.artistAffinity[secondary] =
              (_profile.artistAffinity[secondary] ?? 0) + 1.0;
          _profile.touchAffinity('artist', secondary);
        }
      }
    }

    // Language/genre affinity: +2.0
    if (language.isNotEmpty) {
      _profile.genreAffinity[language] =
          (_profile.genreAffinity[language] ?? 0) + 2.0;
      _profile.languageAffinity[language] =
          (_profile.languageAffinity[language] ?? 0) + 2.0;
      _profile.touchAffinity('genre', language);
      _profile.touchAffinity('language', language);
    }

    // Album affinity: +1.5
    if (album.isNotEmpty) {
      _profile.albumAffinity[album] =
          (_profile.albumAffinity[album] ?? 0) + 1.5;
      _profile.touchAffinity('album', album);
    }

    // Last played at
    _profile.lastPlayedAt[songId] = DateTime.now();

    // Listening history (max 200, most recent first)
    _profile.listeningHistory.remove(songId);
    _profile.listeningHistory.insert(0, songId);
    if (_profile.listeningHistory.length > 200) {
      _profile.listeningHistory = _profile.listeningHistory.sublist(0, 200);
    }

    await _save();
  }

  /// Called when a song is liked/unliked.
  /// Like → +4.0, unlike → -4.0 (but floor at 0).
  Future<void> onSongLiked({
    required String artist,
    required String language,
    required bool isLiked,
  }) async {
    final delta = isLiked ? 4.0 : -4.0;

    _profile.artistAffinity[artist] =
        ((_profile.artistAffinity[artist] ?? 0) + delta).clamp(0, double.infinity);
    _profile.touchAffinity('artist', artist);

    if (language.isNotEmpty) {
      _profile.genreAffinity[language] =
          ((_profile.genreAffinity[language] ?? 0) + delta).clamp(0, double.infinity);
      _profile.touchAffinity('genre', language);
    }

    await _save();
  }

  /// Called when a song is skipped (< 30% listened).
  Future<void> onSongSkipped(String songId) async {
    _profile.skipCount[songId] = (_profile.skipCount[songId] ?? 0) + 1;

    // Heavy skip penalty after 3+ skips
    final count = _profile.skipCount[songId]!;
    if (count >= 3) {
      // Reduce artist affinity slightly
      // (we don't know the artist here; callers should include it if needed)
    }

    await _save();
  }

  /// Save the weekly digest cache.
  Future<void> saveWeeklyDigest(List<String> songIds) async {
    _profile.weeklyDigestGeneratedAt = DateTime.now();
    _profile.weeklyDigestSongIds = songIds;
    await _save();
  }

  /// Check if the weekly digest is still valid (< 7 days old).
  bool isWeeklyDigestValid() {
    if (_profile.weeklyDigestGeneratedAt == null) return false;
    final age = DateTime.now().difference(_profile.weeklyDigestGeneratedAt!);
    return age.inDays < 7;
  }

  // ════════════════════════════════════════════════
  //  ONBOARDING — Cold Start Taste Seed
  // ════════════════════════════════════════════════
  //
  //  Injects explicit user preferences from the onboarding screen.
  //  Language score = 15.0 (safe ceiling — 1.5× session multiplier → 22.5)
  //  Artist  score = 18.0 (not 20.0 — 1.5× would spike to 30.0,
  //                         strangling epsilon-greedy discovery)
  //
  //  We also call touchAffinity() so the 14-day decay starts ticking.
  // ════════════════════════════════════════════════

  Future<void> seedFromOnboarding({
    required List<String> languages,
    required List<String> artists,
    double languageScore = 15.0,
    double artistScore = 18.0,
  }) async {
    for (final lang in languages) {
      _profile.genreAffinity[lang] =
          (_profile.genreAffinity[lang] ?? 0) + languageScore;
      _profile.languageAffinity[lang] =
          (_profile.languageAffinity[lang] ?? 0) + languageScore;
      _profile.touchAffinity('genre', lang);
      _profile.touchAffinity('language', lang);
    }

    for (final artist in artists) {
      _profile.artistAffinity[artist] =
          (_profile.artistAffinity[artist] ?? 0) + artistScore;
      _profile.touchAffinity('artist', artist);
    }

    await _save();
    debugPrint('=== NINAADA: onboarding seed injected — '
        '${languages.length} languages, ${artists.length} artists ===');
  }

  /// Reset the profile (for testing or user request).
  Future<void> reset() async {
    _profile = UserTasteProfile.initial();
    await _save();
  }
}
