import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/data/user_taste_profile.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/services/recommendation_engine.dart';

// ════════════════════════════════════════════════════════════════
//  MADE FOR YOU — Isolated provider with TTL cache + Isolate
// ════════════════════════════════════════════════════════════════
//
//  Architecture:
//  ┌────────────────────────────────────────────────────────────┐
//  │  1. Listens to homeProvider for candidate song pool        │
//  │  2. Pools candidates from topSongs + liked + recent +      │
//  │     downloaded for richer recommendations                  │
//  │  3. Runs RecommendationEngine.getMadeForYouTabs() with     │
//  │     time-aware mood (localHour) on compute() isolate       │
//  │     when candidate pool > 100 items                        │
//  │  4. Caches 6 MadeForYouCard objects with 30-min TTL        │
//  │  5. No songs rendered inline — cards are navigation        │
//  │     entry points only                                      │
//  └────────────────────────────────────────────────────────────┘
//
// ════════════════════════════════════════════════════════════════

/// A single glassmorphic card in the 2×3 Made For You grid.
class MadeForYouCard {
  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final Color color;
  final List<Song> songs;
  final int songCount;

  const MadeForYouCard({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.color,
    required this.songs,
    required this.songCount,
  });
}

class MadeForYouState {
  final List<MadeForYouCard> cards;
  final bool loading;
  final DateTime? generatedAt;

  const MadeForYouState({
    this.cards = const [],
    this.loading = false,
    this.generatedAt,
  });

  bool get isReady => cards.isNotEmpty;

  /// 30-minute TTL — skip recomputation if still fresh.
  bool get isStale {
    if (generatedAt == null) return true;
    return DateTime.now().difference(generatedAt!).inMinutes > 30;
  }

  MadeForYouState copyWith({
    List<MadeForYouCard>? cards,
    bool? loading,
    DateTime? generatedAt,
  }) {
    return MadeForYouState(
      cards: cards ?? this.cards,
      loading: loading ?? this.loading,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }
}

// ── Isolate payload (plain data — no closures) ──
class _MfyPayload {
  final UserTasteProfile profile;
  final List<Song> candidates;
  final int hour;

  const _MfyPayload(this.profile, this.candidates, this.hour);
}

// ── Top-level function for compute() — runs on background isolate ──
List<MadeForYouCard> _computeInIsolate(_MfyPayload payload) {
  final tabs = RecommendationEngine.getMadeForYouTabs(
    profile: payload.profile,
    candidates: payload.candidates,
    localHour: payload.hour,
  );

  return List.generate(tabs.length, (i) {
    final tab = tabs[i];
    return MadeForYouCard(
      id: 'mfy_$i',
      title: tab.title,
      subtitle: tab.subtitle,
      iconName: tab.icon,
      color: tab.color ?? const Color(0xFF8B5CF6),
      songs: tab.songs,
      songCount: tab.totalCount,
    );
  });
}

// ════════════════════════════════════════════════════════════════
//  MadeForYouNotifier — StateNotifier with auto-listen + TTL
// ════════════════════════════════════════════════════════════════
class MadeForYouNotifier extends StateNotifier<MadeForYouState> {
  final Ref _ref;

  MadeForYouNotifier(this._ref) : super(const MadeForYouState()) {
    // Auto-trigger when home data finishes loading
    _ref.listen<HomeState>(homeProvider, (prev, next) {
      if (!next.loading && next.hasData) {
        generate();
      }
    });

    // Also check immediately if home data already exists
    Future.microtask(() {
      final home = _ref.read(homeProvider);
      if (!home.loading && home.hasData) {
        generate();
      }
    });
  }

  /// Generate 6 Made For You cards.
  /// TTL guard: skips if cache is fresh and non-empty.
  Future<void> generate() async {
    if (state.isReady && !state.isStale) return;
    if (state.loading) return;

    state = state.copyWith(loading: true);

    try {
      final profile = TasteProfileManager.instance.profile;
      if (profile == null || profile.isEmpty) {
        state = state.copyWith(loading: false);
        return;
      }

      // ── Pool candidates from ALL available song sources ──
      // Richer pool = better affinity matching = higher engagement
      final home = _ref.read(homeProvider);
      final library = _ref.read(libraryProvider);

      final candidateMap = <String, Song>{};
      for (final s in home.topSongs) {
        candidateMap[s.id] = s;
      }
      for (final s in library.recentlyPlayed) {
        candidateMap[s.id] = s;
      }
      for (final s in library.likedSongs) {
        candidateMap[s.id] = s;
      }
      for (final s in library.downloadedSongs) {
        candidateMap[s.id] = s;
      }

      final candidates = candidateMap.values.toList();
      if (candidates.isEmpty) {
        state = state.copyWith(loading: false);
        return;
      }

      final hour = DateTime.now().hour;

      List<MadeForYouCard> cards;
      if (candidates.length > 100) {
        // Offload to isolate — preserves 60fps scroll during scoring
        cards = await compute(
          _computeInIsolate,
          _MfyPayload(profile, candidates, hour),
        );
      } else {
        // Small dataset — inline is fine, avoid isolate overhead
        cards = _computeInIsolate(
          _MfyPayload(profile, candidates, hour),
        );
      }

      state = MadeForYouState(
        cards: cards,
        loading: false,
        generatedAt: DateTime.now(),
      );

      debugPrint(
        '=== NINAADA: MadeForYou generated ${cards.length} cards '
        'from ${candidates.length} candidates ===',
      );
    } catch (e) {
      debugPrint('=== NINAADA: MadeForYou generate() error: $e ===');
      state = state.copyWith(loading: false);
    }
  }

  /// Force refresh — ignores TTL. Used for pull-to-refresh.
  Future<void> refresh() async {
    state = const MadeForYouState(); // clear cache
    await generate();
  }
}

// ════════════════════════════════════════════════════════════════
//  PROVIDER DECLARATION
// ════════════════════════════════════════════════════════════════

final madeForYouProvider =
    StateNotifierProvider<MadeForYouNotifier, MadeForYouState>(
  (ref) => MadeForYouNotifier(ref),
);
