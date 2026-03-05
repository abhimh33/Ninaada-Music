import 'dart:math';
import 'dart:ui' show Color;
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/data/user_taste_profile.dart';
import 'package:ninaada_music/providers/session_context_provider.dart';
import 'package:ninaada_music/services/behavior_engine.dart';

// ════════════════════════════════════════════════════════════════
//  RECOMMENDATION ENGINE — Holy Trinity Algorithm
// ════════════════════════════════════════════════════════════════
//
//  The Master Pipeline combines four mathematical components:
//
//  ┌─────────────────────────────────────────────────────────────┐
//  │  1. BASELINE HEURISTIC (Exploitation)                       │
//  │     Score_base = (0.40 × Artist_adj)                        │
//  │                + (0.35 × Genre_adj)                         │
//  │                + (0.25 × Language_adj)                      │
//  │                                                             │
//  │     *_adj = raw affinity × 0.5^(daysSince / 14.0)          │
//  │     (14-day half-life — computed by UserTasteProfile)       │
//  │                                                             │
//  │  2. SESSION MOOD MULTIPLIER (Micro-Context)                 │
//  │     If candidate matches activeSessionVibe:                 │
//  │       Score_final = Score_base × 1.5                        │
//  │     else:                                                   │
//  │       Score_final = Score_base                               │
//  │                                                             │
//  │  3. EPSILON-GREEDY SELECTION (Serendipity)                  │
//  │     ε = 0.15 (15% exploration rate)                         │
//  │     For each slot:                                          │
//  │       if random > ε → EXPLOIT: pick highest Score_final     │
//  │       if random ≤ ε → EXPLORE: pick from under-represented │
//  │                        genres/artists the user hasn't heard │
//  │                                                             │
//  │  4. CONTEXT DECAY (built into UserTasteProfile getters)     │
//  │     All affinity reads use decayed*Affinity getters which   │
//  │     apply the 14-day half-life at read time.                │
//  └─────────────────────────────────────────────────────────────┘
//
//  All scoring methods are synchronous — no I/O.
//  generateAutoPlayQueue() is the master method for auto-play.
//
// ════════════════════════════════════════════════════════════════

/// A single scored recommendation.
class ScoredSong {
  final Song song;
  final double score;
  const ScoredSong(this.song, this.score);
}

/// A "Made For You" tab definition.
class MadeForYouTab {
  final String title;
  final String subtitle;
  final String icon; // Material icon name hint
  final Color? color;
  final List<Song> songs;
  final int totalCount; // backing dataset size

  const MadeForYouTab({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.color,
    required this.songs,
    this.totalCount = 0,
  });
}

/// A "Top Picks" card = group of 6 display songs backed by up to 50.
class TopPicksCard {
  final String title;
  final List<Song> displaySongs; // exactly 6 (or fewer if not enough)
  final List<Song> backingSongs; // up to 50

  const TopPicksCard({
    required this.title,
    required this.displaySongs,
    required this.backingSongs,
  });
}

class RecommendationEngine {
  RecommendationEngine._();

  // ════════════════════════════════════════════════
  //  WEIGHTS — The Holy Trinity formula
  // ════════════════════════════════════════════════

  /// Artist affinity weight (40% of base score).
  static const double _wArtist = 0.40;

  /// Genre affinity weight (35% of base score).
  /// In Ninaada, language ≈ genre signal for Indian music.
  static const double _wGenre = 0.35;

  /// Language affinity weight (25% of base score).
  static const double _wLanguage = 0.25;

  /// Epsilon-greedy exploration rate (15%).
  static const double _epsilon = 0.15;

  /// Amplified epsilon for Discover Weekly (25%).
  static const double _discoverEpsilon = 0.25;

  static final Random _rng = Random();

  // ════════════════════════════════════════════════
  //  MANDATE 2: BASELINE HEURISTIC — scoreSong()
  // ════════════════════════════════════════════════

  /// Score a single song against the user's taste profile.
  ///
  /// Formula (Phase 9B enhanced):
  ///   Score_base = (0.40 × Artist_adj) + (0.35 × Genre_adj) + (0.25 × Language_adj)
  ///   Score_behavior = songAffinity + (artistBehavior × 0.3) + (langBehavior × 0.2)
  ///   Score_combined = Score_base × onboardingWeight + Score_behavior
  ///
  /// All affinity lookups go through [decayed*Affinity] getters
  /// which apply the 14-day half-life.
  static double scoreSong(Song song, UserTasteProfile profile) {
    // ── Artist match (decayed) ──
    double artistScore = 0;
    final decayedArtist = profile.decayedArtistAffinity;
    final artistAff = decayedArtist[song.artist];
    if (artistAff != null) {
      artistScore = artistAff;
    } else {
      // Check individual artists in comma-separated field
      for (final part in song.artist.split(RegExp(r'[,;]'))) {
        final trimmed = part.trim();
        final aff = decayedArtist[trimmed];
        if (aff != null && aff > artistScore) artistScore = aff;
      }
    }

    // ── Genre match (decayed) — language ≈ genre in Ninaada ──
    final genreScore = profile.decayedGenreAffinity[song.language] ?? 0;

    // ── Language match (decayed) ──
    final langScore = profile.decayedLanguageAffinity[song.language] ?? 0;

    // ── Skip penalty (reduces desirability of frequently skipped songs) ──
    final skips = profile.skipCount[song.id] ?? 0;
    final skipPenalty = skips * 0.3;

    // ── Onboarding-based score (Holy Trinity) ──
    final baseScore = (artistScore * _wArtist) +
        (genreScore * _wGenre) +
        (langScore * _wLanguage) -
        skipPenalty;

    // ── Phase 9B: Behavioral layer ──
    double behaviorScore = 0;
    double onboardingW = 1.0;

    if (BehaviorEngine.isInitialized && BehaviorEngine.instance.hasMinimalData) {
      final be = BehaviorEngine.instance;

      // Song-level affinity from behavior (direct signal)
      behaviorScore += be.getSongAffinity(song.id);

      // Artist behavioral score (propagated from song plays/skips)
      behaviorScore += be.getArtistScore(song.artist) * 0.3;

      // Language behavioral score
      if (song.language.isNotEmpty) {
        behaviorScore += be.getLanguageScore(song.language) * 0.2;
      }

      // Phase 9C: Cold-start blending — onboarding weight fades as
      // behavioral data accumulates: 2.0× → 0.5×
      onboardingW = be.onboardingWeight;

      // Song rejection: if behavioral score is deeply negative,
      // heavily penalize the candidate
      if (be.getSongAffinity(song.id) < -5) {
        behaviorScore -= 5.0; // extra penalty for strongly disliked songs
      }
    }

    // Weighted sum: onboarding base × weight + behavioral layer
    return (baseScore * onboardingW) + behaviorScore;
  }

  // ════════════════════════════════════════════════
  //  MANDATE 3: SESSION MOOD MULTIPLIER — scoreSongWithSession()
  // ════════════════════════════════════════════════

  /// Score a song with the session mood multiplier applied.
  ///
  /// If the candidate matches the [sessionContext.activeSessionVibe],
  /// the base score is multiplied by 1.5×.
  static double scoreSongWithSession(
    Song song,
    UserTasteProfile profile,
    SessionContext sessionContext,
  ) {
    final baseScore = scoreSong(song, profile);

    // ── Session vibe multiplier ──
    if (sessionContext.matchesVibe(song)) {
      return baseScore * kSessionVibeMultiplier;
    }

    return baseScore;
  }

  // ════════════════════════════════════════════════
  //  MANDATE 4: EPSILON-GREEDY AUTO-PLAY QUEUE
  // ════════════════════════════════════════════════

  /// Generate an auto-play queue using the complete Holy Trinity algorithm.
  ///
  /// Phase 9B/9C enhanced:
  ///   • Dynamic epsilon replaces static 0.15 — adapts to session behavior
  ///   • Diversity guard prevents same-artist streaks (3+ in a row)
  ///   • Song rejection filters out strongly negative-affinity songs
  ///
  /// For each slot in [count]:
  ///   • With probability (1 − ε): **EXPLOIT**
  ///   • With probability ε:       **EXPLORE**
  ///
  /// [candidates] — the full pool of songs to choose from.
  /// [sessionContext] — current session mood for the 1.5× multiplier.
  /// [excludeIds] — song IDs already in the queue (avoid duplicates).
  static List<Song> generateAutoPlayQueue({
    required UserTasteProfile profile,
    required List<Song> candidates,
    required SessionContext sessionContext,
    int count = 10,
    Set<String>? excludeIds,
  }) {
    if (candidates.isEmpty) return [];

    final exclude = excludeIds ?? {};
    final filtered = candidates.where((s) => !exclude.contains(s.id)).toList();
    if (filtered.isEmpty) return [];

    // Score all candidates with session multiplier
    final scored = filtered
        .map((s) => ScoredSong(s, scoreSongWithSession(s, profile, sessionContext)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.length <= count) {
      return scored.map((s) => s.song).toList();
    }

    // ── Phase 9B: Dynamic epsilon from BehaviorEngine ──
    final epsilon = BehaviorEngine.isInitialized
        ? BehaviorEngine.instance.currentEpsilon
        : _epsilon;

    // ── Build explore pool: bottom 50% by score, excluding heavily skipped ──
    final midIdx = scored.length ~/ 2;
    final explorePool = scored.sublist(midIdx).where((s) {
      final skips = profile.skipCount[s.song.id] ?? 0;
      return skips < 3;
    }).toList();

    final result = <Song>[];
    final usedIds = <String>{};
    // ── Phase 9C: Diversity guard — track recent artists in this queue ──
    final recentArtists = <String>[];
    int exploitIdx = 0;

    for (int i = 0; i < count && exploitIdx < scored.length; i++) {
      final roll = _rng.nextDouble();

      if (explorePool.isNotEmpty && roll <= epsilon) {
        // ── EXPLORE: random pick from under-represented pool ──
        final pick = explorePool.removeAt(_rng.nextInt(explorePool.length));
        if (!usedIds.contains(pick.song.id)) {
          // Diversity check before adding
          if (_passesDiversityGuard(pick.song, recentArtists)) {
            result.add(pick.song);
            usedIds.add(pick.song.id);
            recentArtists.insert(0, pick.song.artist);
            continue;
          }
        }
      }

      // ── EXPLOIT: next highest-scored song not yet used ──
      while (exploitIdx < scored.length &&
          usedIds.contains(scored[exploitIdx].song.id)) {
        exploitIdx++;
      }
      if (exploitIdx < scored.length) {
        final candidate = scored[exploitIdx].song;
        // Diversity guard: if this would be 3rd same-artist in a row,
        // skip to the next candidate
        if (!_passesDiversityGuard(candidate, recentArtists)) {
          exploitIdx++;
          i--; // retry this slot
          continue;
        }
        result.add(candidate);
        usedIds.add(candidate.id);
        recentArtists.insert(0, candidate.artist);
        exploitIdx++;
      }
    }

    return result;
  }

  /// Phase 9C: Diversity guard — prevents 3+ songs from same artist in a row.
  static bool _passesDiversityGuard(Song song, List<String> recentArtists) {
    if (recentArtists.length < 2) return true;

    final primary = song.artist.split(RegExp(r'[,;]')).first.trim().toLowerCase();
    final last2 = recentArtists.take(2).map(
      (a) => a.split(RegExp(r'[,;]')).first.trim().toLowerCase(),
    );

    // Block if both of the last 2 songs share this primary artist
    return !last2.every((a) => a == primary);
  }

  // ════════════════════════════════════════════════
  //  STANDARD RECOMMENDATIONS (session-aware)
  // ════════════════════════════════════════════════

  /// Rank candidates with epsilon-greedy exploration + session multiplier.
  /// Used by Made For You, Top Picks, Quick Picks.
  static List<Song> getRecommendations({
    required UserTasteProfile profile,
    required List<Song> candidates,
    int limit = 20,
    Set<String>? excludeIds,
    bool enableExploration = true,
    SessionContext sessionContext = const SessionContext(),
  }) {
    if (profile.isEmpty || candidates.isEmpty) {
      return candidates.take(limit).toList();
    }

    return generateAutoPlayQueue(
      profile: profile,
      candidates: candidates,
      sessionContext: sessionContext,
      count: limit,
      excludeIds: excludeIds,
    );
  }

  // ════════════════════════════════════════════════
  //  MADE FOR YOU — 6 thematic tabs
  // ════════════════════════════════════════════════

  /// Generate the "Made For You" tabs from candidates + profile.
  ///
  /// Tabs:
  ///   1. "Because you love [Top Artist]"
  ///   2. "Your [Top Language] Mix"
  ///   3. Time-aware mood (Morning Vibes / Afternoon Boost / Evening Relax / Night Chill)
  ///   4. "Chill & Focus"
  ///   5. "High Energy"
  ///   6. "Feel Good"
  static List<MadeForYouTab> getMadeForYouTabs({
    required UserTasteProfile profile,
    required List<Song> candidates,
    int? localHour,
  }) {
    final tabs = <MadeForYouTab>[];

    // ── Tab 1: "Because you love [Top Artist]" ──
    final topArtists = profile.topArtists(1);
    if (topArtists.isNotEmpty) {
      final artistName = topArtists.first.key;
      final artistSongs = candidates
          .where((s) => s.artist.toLowerCase().contains(artistName.toLowerCase()))
          .toList();
      if (artistSongs.length < 5) {
        final extras = getRecommendations(
          profile: profile,
          candidates: candidates,
          limit: 15,
          excludeIds: artistSongs.map((s) => s.id).toSet(),
        );
        artistSongs.addAll(extras.take(15 - artistSongs.length));
      }
      tabs.add(MadeForYouTab(
        title: 'Because you love\n$artistName',
        subtitle: 'More from artists like ${_truncate(artistName, 16)}...',
        icon: 'person',
        color: const Color(0xFF6D28D9),
        songs: _dedup(artistSongs).take(15).toList(),
        totalCount: artistSongs.length,
      ));
    }

    // ── Tab 2: "Your [Language] Mix" ──
    final topLangs = profile.topLanguages(1);
    if (topLangs.isNotEmpty) {
      final lang = topLangs.first.key;
      final langSongs = candidates
          .where((s) => s.language.toLowerCase() == lang.toLowerCase())
          .toList();
      if (langSongs.length < 5) {
        langSongs.addAll(getRecommendations(
          profile: profile,
          candidates: candidates,
          limit: 22,
          excludeIds: langSongs.map((s) => s.id).toSet(),
        ));
      }
      final displayLang = lang.isNotEmpty
          ? '${lang[0].toUpperCase()}${lang.substring(1).toLowerCase()}'
          : 'Your';
      tabs.add(MadeForYouTab(
        title: 'Your $displayLang Mix',
        subtitle: 'Hits in $displayLang',
        icon: 'language',
        color: const Color(0xFFD97706),
        songs: _dedup(langSongs).take(22).toList(),
        totalCount: langSongs.length,
      ));
    }

    // ── Tab 3: Time-aware mood card ──
    final hour = localHour ?? DateTime.now().hour;
    final mood = _getTimeMood(hour);
    final moodSongs = _filterByKeywords(candidates, mood.keywords);
    if (moodSongs.length < 5) {
      moodSongs.addAll(getRecommendations(
        profile: profile,
        candidates: candidates,
        limit: 15,
        excludeIds: moodSongs.map((s) => s.id).toSet(),
      ));
    }
    tabs.add(MadeForYouTab(
      title: mood.title,
      subtitle: mood.subtitle,
      icon: mood.icon,
      color: mood.color,
      songs: _dedup(moodSongs).take(15).toList(),
      totalCount: moodSongs.length,
    ));

    // ── Tab 4: "Chill & Focus" ──
    final chillSongs = _filterByKeywords(candidates, [
      'lofi', 'chill', 'relax', 'focus', 'study', 'sleep',
      'instrumental', 'ambient', 'piano',
    ]);
    if (chillSongs.length < 5) {
      chillSongs.addAll(getRecommendations(
        profile: profile,
        candidates: candidates,
        limit: 15,
        excludeIds: chillSongs.map((s) => s.id).toSet(),
      ));
    }
    tabs.add(MadeForYouTab(
      title: 'Chill & Focus',
      subtitle: 'Relax and concentrate',
      icon: 'headphones',
      color: const Color(0xFF0D9488),
      songs: _dedup(chillSongs).take(15).toList(),
      totalCount: chillSongs.length,
    ));

    // ── Tab 5: "High Energy" ──
    final energySongs = _filterByKeywords(candidates, [
      'party', 'dance', 'energy', 'pump', 'workout', 'bass',
      'beat', 'dj', 'remix', 'club',
    ]);
    if (energySongs.length < 5) {
      energySongs.addAll(getRecommendations(
        profile: profile,
        candidates: candidates,
        limit: 15,
        excludeIds: energySongs.map((s) => s.id).toSet(),
      ));
    }
    tabs.add(MadeForYouTab(
      title: 'High Energy',
      subtitle: 'Get pumped up',
      icon: 'flash_on',
      color: const Color(0xFFBE185D),
      songs: _dedup(energySongs).take(15).toList(),
      totalCount: energySongs.length,
    ));

    // ── Tab 6: "Feel Good" ──
    final feelGoodSongs = _filterByKeywords(candidates, [
      'happy', 'feel good', 'joyful', 'fun', 'sunshine',
      'smile', 'positive', 'upbeat',
    ]);
    if (feelGoodSongs.length < 5) {
      feelGoodSongs.addAll(getRecommendations(
        profile: profile,
        candidates: candidates,
        limit: 15,
        excludeIds: feelGoodSongs.map((s) => s.id).toSet(),
      ));
    }
    tabs.add(MadeForYouTab(
      title: 'Feel Good',
      subtitle: 'Songs to lift your mood',
      icon: 'wb_sunny',
      color: const Color(0xFFA16207),
      songs: _dedup(feelGoodSongs).take(15).toList(),
      totalCount: feelGoodSongs.length,
    ));

    return tabs;
  }

  // ════════════════════════════════════════════════
  //  DAILY MIX — affinity cluster grouping
  // ════════════════════════════════════════════════

  static List<List<Song>> getDailyMix({
    required UserTasteProfile profile,
    required List<Song> candidates,
    int mixCount = 5,
    int songsPerMix = 15,
  }) {
    if (candidates.isEmpty) return [];

    final mixes = <List<Song>>[];
    final usedIds = <String>{};

    // Cluster 1: Top artist
    final topArtists = profile.topArtists(mixCount);
    for (final entry in topArtists) {
      final artistSongs = candidates
          .where((s) =>
              !usedIds.contains(s.id) &&
              s.artist.toLowerCase().contains(entry.key.toLowerCase()))
          .take(songsPerMix)
          .toList();
      if (artistSongs.length >= 3) {
        mixes.add(artistSongs);
        usedIds.addAll(artistSongs.map((s) => s.id));
      }
      if (mixes.length >= mixCount) break;
    }

    // Cluster 2: Top languages
    if (mixes.length < mixCount) {
      final topLangs = profile.topLanguages(mixCount - mixes.length);
      for (final entry in topLangs) {
        final langSongs = candidates
            .where((s) =>
                !usedIds.contains(s.id) &&
                s.language.toLowerCase() == entry.key.toLowerCase())
            .take(songsPerMix)
            .toList();
        if (langSongs.length >= 3) {
          mixes.add(langSongs);
          usedIds.addAll(langSongs.map((s) => s.id));
        }
        if (mixes.length >= mixCount) break;
      }
    }

    // Cluster 3: Fill remaining with general recommendations
    if (mixes.length < mixCount) {
      final remaining = getRecommendations(
        profile: profile,
        candidates: candidates,
        limit: songsPerMix,
        excludeIds: usedIds,
      );
      if (remaining.length >= 3) {
        mixes.add(remaining);
      }
    }

    return mixes;
  }

  // ════════════════════════════════════════════════
  //  DISCOVER WEEKLY — amplified exploration (ε = 0.25)
  // ════════════════════════════════════════════════

  static List<Song> getDiscoverWeekly({
    required UserTasteProfile profile,
    required List<Song> candidates,
    int limit = 20,
  }) {
    if (profile.isEmpty || candidates.isEmpty) {
      return candidates.take(limit).toList();
    }

    // Prioritize songs NOT in recent history
    final recentIds = profile.listeningHistory.take(50).toSet();

    final scored = candidates
        .map((s) {
          double score = scoreSong(s, profile);

          // Novelty bonus: songs not in recent history get boosted
          if (!recentIds.contains(s.id)) {
            score += 2.0;
          }

          // Skip penalty amplified for discover weekly
          final skips = profile.skipCount[s.id] ?? 0;
          if (skips >= 2) score -= skips * 1.0;

          return ScoredSong(s, score);
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    if (scored.length <= limit) {
      return scored.map((s) => s.song).toList();
    }

    // ── Amplified epsilon-greedy for discovery ──
    // Phase 9B: Use dynamic epsilon + discovery amplification
    final baseEpsilon = BehaviorEngine.isInitialized
        ? BehaviorEngine.instance.currentEpsilon
        : _epsilon;
    final discoverEps = min(baseEpsilon + 0.10, 0.40); // discovery always pushes harder
    final result = <Song>[];
    final usedIds = <String>{};

    final exploreStart = (scored.length * 0.4).toInt();
    final explorePool = scored.sublist(exploreStart).where((s) {
      final skips = profile.skipCount[s.song.id] ?? 0;
      return skips < 3;
    }).toList();

    int exploitIdx = 0;
    for (int i = 0; i < limit && exploitIdx < scored.length; i++) {
      if (explorePool.isNotEmpty && _rng.nextDouble() < discoverEps) {
        final pick = explorePool.removeAt(_rng.nextInt(explorePool.length));
        if (!usedIds.contains(pick.song.id)) {
          result.add(pick.song);
          usedIds.add(pick.song.id);
          continue;
        }
      }
      while (exploitIdx < scored.length &&
          usedIds.contains(scored[exploitIdx].song.id)) {
        exploitIdx++;
      }
      if (exploitIdx < scored.length) {
        result.add(scored[exploitIdx].song);
        usedIds.add(scored[exploitIdx].song.id);
        exploitIdx++;
      }
    }

    return result;
  }

  // ════════════════════════════════════════════════
  //  TOP PICKS — "Based on your listening"
  // ════════════════════════════════════════════════

  static List<TopPicksCard> getTopPicks({
    required UserTasteProfile profile,
    required List<Song> candidates,
    int cardCount = 8,
    int displayPerCard = 6,
    int backingPerCard = 50,
  }) {
    if (candidates.isEmpty) return [];

    final scored = candidates
        .map((s) => ScoredSong(s, scoreSong(s, profile)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final allSongs = scored.map((s) => s.song).toList();
    final cards = <TopPicksCard>[];

    for (int i = 0; i < cardCount && i * displayPerCard < allSongs.length; i++) {
      final start = i * displayPerCard;
      final backingEnd = min(start + backingPerCard, allSongs.length);
      final displayEnd = min(start + displayPerCard, allSongs.length);

      final display = allSongs.sublist(start, displayEnd);
      final backing = allSongs.sublist(start, backingEnd);

      final artistCounts = <String, int>{};
      for (final s in display) {
        artistCounts[s.artist] = (artistCounts[s.artist] ?? 0) + 1;
      }
      String title;
      if (artistCounts.isNotEmpty) {
        final topArtist = artistCounts.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
        title = _truncate(topArtist, 20);
      } else {
        title = 'Mix ${i + 1}';
      }

      cards.add(TopPicksCard(
        title: title,
        displaySongs: display,
        backingSongs: backing,
      ));
    }

    return cards;
  }

  // ════════════════════════════════════════════════
  //  QUICK PICKS
  // ════════════════════════════════════════════════

  static List<Song> getQuickPicks({
    required UserTasteProfile profile,
    required List<Song> candidates,
    int limit = 6,
  }) {
    return getRecommendations(
      profile: profile,
      candidates: candidates,
      limit: limit,
    );
  }

  // ════════════════════════════════════════════════
  //  HELPERS
  // ════════════════════════════════════════════════

  static _TimeMood _getTimeMood(int hour) {
    if (hour >= 5 && hour < 12) {
      return const _TimeMood(
        title: 'Morning Vibes',
        subtitle: 'Perfect for this time of day',
        icon: 'wb_sunny',
        color: Color(0xFFA16207),
        keywords: [
          'acoustic', 'chill', 'morning', 'calm', 'soothing',
          'peaceful', 'love', 'soft', 'gentle',
        ],
      );
    } else if (hour >= 12 && hour < 17) {
      return const _TimeMood(
        title: 'Afternoon Boost',
        subtitle: 'Keep your energy flowing',
        icon: 'wb_cloudy',
        color: Color(0xFFEA580C),
        keywords: [
          'upbeat', 'energy', 'pop', 'rock', 'dance', 'fun',
          'groove', 'beat', 'party', 'happy',
        ],
      );
    } else if (hour >= 17 && hour < 21) {
      return const _TimeMood(
        title: 'Evening Relax',
        subtitle: 'Wind down your evening',
        icon: 'nights_stay',
        color: Color(0xFF7C3AED),
        keywords: [
          'relax', 'evening', 'smooth', 'jazz', 'soul', 'mellow',
          'slow', 'romantic', 'lofi', 'sunset',
        ],
      );
    } else {
      return const _TimeMood(
        title: 'Night Chill',
        subtitle: 'Late night listening',
        icon: 'dark_mode',
        color: Color(0xFF1E40AF),
        keywords: [
          'night', 'chill', 'sleep', 'ambient', 'lofi', 'calm',
          'dream', 'quiet', 'soft', 'lullaby',
        ],
      );
    }
  }

  static List<Song> _filterByKeywords(
      List<Song> candidates, List<String> keywords) {
    return candidates.where((s) {
      final text =
          '${s.name} ${s.artist} ${s.album} ${s.subtitle ?? ''}'.toLowerCase();
      return keywords.any((kw) => text.contains(kw.toLowerCase()));
    }).toList();
  }

  static List<Song> _dedup(List<Song> songs) {
    final seen = <String>{};
    return songs.where((s) => seen.add(s.id)).toList();
  }

  static String _truncate(String s, int maxLen) {
    if (s.length <= maxLen) return s;
    return '${s.substring(0, maxLen)}...';
  }
}

// ════════════════════════════════════════════════════════════════
//  _TimeMood — Internal value object for time-aware mood card
// ════════════════════════════════════════════════════════════════
class _TimeMood {
  final String title;
  final String subtitle;
  final String icon;
  final Color color;
  final List<String> keywords;

  const _TimeMood({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.keywords,
  });
}
