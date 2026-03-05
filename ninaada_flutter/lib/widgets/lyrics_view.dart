import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/lrc_parser.dart';
import 'package:ninaada_music/core/media_theme_engine.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/api_service.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';

// ════════════════════════════════════════════════════════════════
//  LYRICS VIEW — Phase 7: Immersive Playback Engine
// ════════════════════════════════════════════════════════════════
//
//  Mandates 2 + 3 + 4 unified in a single widget tree.
//
//  ┌───────────────────────────────────────────────────────────┐
//  │  LyricsPanel (top-level)                                  │
//  │  ├─ Fetches lyrics for currentSong via API                │
//  │  ├─ Parses via LrcParser                                  │
//  │  └─ Renders _SyncedLyricsBody                             │
//  │       ├─ StreamBuilder<Duration> on positionStream         │
//  │       ├─ Binary search → activeIndex                      │
//  │       ├─ ScrollController.animateTo() → center active     │
//  │       ├─ GestureDetector per line → seek(startTime)       │
//  │       └─ AnimatedDefaultTextStyle for active/inactive      │
//  └───────────────────────────────────────────────────────────┘
//
//  Performance contract:
//    • StreamBuilder isolates ALL position-tick rebuilds to the
//      lyrics list — the parent widget tree is never touched.
//    • Binary search for active index: O(log n) per tick.
//    • AnimatedDefaultTextStyle handles text scale/opacity
//      transitions without triggering parent rebuilds.
//    • Background gradient reuses the existing mediaThemeProvider
//      palette — zero redundant color extraction.
//
// ════════════════════════════════════════════════════════════════

/// Height of each lyric line slot (used for scroll offset calculation).
const double _kLineHeight = 56.0;

/// Duration for smooth auto-scroll animation.
const Duration _kScrollDuration = Duration(milliseconds: 300);

/// Duration for text style transition (active ↔ inactive).
const Duration _kTextTransition = Duration(milliseconds: 250);

// ──────────────────────────────────────────────────────
//  LYRICS PROVIDER — Riverpod state for lyrics data
// ──────────────────────────────────────────────────────

/// State for the lyrics panel.
class LyricsState {
  final List<LyricLine> lines;
  final bool isLoading;
  final bool hasTimestamps;
  final String? error;
  final String? loadedForSongId;

  const LyricsState({
    this.lines = const [],
    this.isLoading = false,
    this.hasTimestamps = false,
    this.error,
    this.loadedForSongId,
  });

  LyricsState copyWith({
    List<LyricLine>? lines,
    bool? isLoading,
    bool? hasTimestamps,
    String? error,
    String? loadedForSongId,
    bool clearError = false,
  }) {
    return LyricsState(
      lines: lines ?? this.lines,
      isLoading: isLoading ?? this.isLoading,
      hasTimestamps: hasTimestamps ?? this.hasTimestamps,
      error: clearError ? null : (error ?? this.error),
      loadedForSongId: loadedForSongId ?? this.loadedForSongId,
    );
  }
}

class LyricsNotifier extends StateNotifier<LyricsState> {
  final ApiService _api = ApiService();

  LyricsNotifier() : super(const LyricsState());

  /// Fetch and parse lyrics for [song].
  /// If lyrics are already loaded for this song ID, no-op.
  Future<void> loadLyrics(Song song) async {
    if (state.loadedForSongId == song.id && state.lines.isNotEmpty) return;
    if (state.isLoading && state.loadedForSongId == song.id) return;

    state = state.copyWith(
      isLoading: true,
      clearError: true,
      loadedForSongId: song.id,
    );

    try {
      final rawLyrics = await _api.fetchLyrics(song.id);
      if (rawLyrics == null || rawLyrics.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          lines: [],
          error: 'No lyrics available',
        );
        return;
      }

      // Strip HTML tags (Ninaada often wraps lyrics in HTML)
      final cleaned = LrcParser.stripHtml(rawLyrics);
      final songDuration = Duration(seconds: song.duration);

      // Try LRC timestamp parsing first
      final lines = LrcParser.parse(cleaned, songDuration: songDuration);
      final hasTs = lines.isNotEmpty &&
          lines.first.startTime != Duration.zero ||
          (lines.length > 1 &&
              lines[1].startTime != lines[0].endTime);

      // If LRC parse returned empty but we have text, fall back to plain
      final finalLines = lines.isNotEmpty
          ? lines
          : LrcParser.parsePlainText(cleaned, songDuration: songDuration);

      state = state.copyWith(
        isLoading: false,
        lines: finalLines,
        hasTimestamps: hasTs,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load lyrics',
      );
    }
  }

  /// Clear lyrics (e.g., when navigating away).
  void clear() {
    state = const LyricsState();
  }
}

final lyricsProvider =
    StateNotifierProvider<LyricsNotifier, LyricsState>((ref) {
  return LyricsNotifier();
});

// ──────────────────────────────────────────────────────
//  LYRICS PANEL — Full-screen lyrics overlay
// ──────────────────────────────────────────────────────

/// The top-level lyrics panel. Manages data fetching and renders
/// the synced scrolling view inside a dynamic palette background.
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({super.key});

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  @override
  void initState() {
    super.initState();
    _loadIfNeeded();
  }

  void _loadIfNeeded() {
    final song = ref.read(playerProvider).currentSong;
    if (song != null) {
      ref.read(lyricsProvider.notifier).loadLyrics(song);
    }
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((p) => p.currentSong));
    final lyricsState = ref.watch(lyricsProvider);
    final palette = ref.watch(mediaThemeProvider.select((s) => s.palette));

    // Auto-fetch when song changes
    ref.listen<Song?>(
      playerProvider.select((p) => p.currentSong),
      (prev, next) {
        if (next != null && next.id != prev?.id) {
          ref.read(lyricsProvider.notifier).loadLyrics(next);
        }
      },
    );

    if (song == null) return const SizedBox.shrink();

    return _LyricsBackground(
      palette: palette,
      child: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            _LyricsHeader(song: song),

            // ── Body ──
            Expanded(
              child: _buildBody(lyricsState, song),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LyricsState lyricsState, Song song) {
    if (lyricsState.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Colors.white54),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Loading lyrics…',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (lyricsState.error != null || lyricsState.lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lyrics_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              lyricsState.error ?? 'No lyrics available',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              song.name,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return _SyncedLyricsBody(
      lines: lyricsState.lines,
      hasTimestamps: lyricsState.hasTimestamps,
    );
  }
}

// ──────────────────────────────────────────────────────
//  DYNAMIC BACKGROUND (Mandate 4)
// ──────────────────────────────────────────────────────

class _LyricsBackground extends StatelessWidget {
  final MediaPalette palette;
  final Widget child;

  const _LyricsBackground({
    required this.palette,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.dominant.withValues(alpha: 0.85),
            Color.lerp(palette.secondary, Colors.black, 0.3)!,
            Colors.black.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
      child: child,
    );
  }
}

// ──────────────────────────────────────────────────────
//  LYRICS HEADER
// ──────────────────────────────────────────────────────

class _LyricsHeader extends StatelessWidget {
  final Song song;
  const _LyricsHeader({required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Icon(Icons.keyboard_arrow_down,
                color: Colors.white70, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  song.artist,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.lyrics, color: Colors.white38, size: 20),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
//  SYNCED LYRICS BODY (Mandates 2 + 3)
//
//  StreamBuilder<Duration> listens to positionStream.
//  Binary search finds activeIndex → ScrollController.animateTo()
//  centers the active line. GestureDetector on each line → seek.
//
//  Rebuild scope: ONLY this subtree rebuilds on position ticks.
//  Parent (LyricsPanel, _LyricsBackground) untouched.
// ──────────────────────────────────────────────────────

class _SyncedLyricsBody extends ConsumerStatefulWidget {
  final List<LyricLine> lines;
  final bool hasTimestamps;

  const _SyncedLyricsBody({
    required this.lines,
    required this.hasTimestamps,
  });

  @override
  ConsumerState<_SyncedLyricsBody> createState() => _SyncedLyricsBodyState();
}

class _SyncedLyricsBodyState extends ConsumerState<_SyncedLyricsBody> {
  final ScrollController _scrollController = ScrollController();
  int _lastActiveIndex = -1;
  bool _userScrolling = false;
  Timer? _userScrollTimer;

  @override
  void dispose() {
    _scrollController.dispose();
    _userScrollTimer?.cancel();
    super.dispose();
  }

  /// Scroll so that [index] is centered vertically.
  void _scrollToIndex(int index) {
    if (!_scrollController.hasClients) return;
    if (_userScrolling) return; // Don't fight user's manual scroll

    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset =
        (index * _kLineHeight) - (viewportHeight / 2) + (_kLineHeight / 2);
    final clampedOffset = targetOffset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    _scrollController.animateTo(
      clampedOffset,
      duration: _kScrollDuration,
      curve: Curves.easeOutCubic,
    );
  }

  /// Seek audio to the tapped [LyricLine]'s startTime (Mandate 3).
  void _onLineTap(LyricLine line) {
    final handler = ref.read(audioHandlerProvider);
    handler.seek(line.startTime);

    // Also update the progress in PlayerState immediately for snappy UI
    final secs = line.startTime.inMilliseconds / 1000.0;
    ref.read(playerProvider.notifier).seekTo(
          ref.read(playerProvider).duration > 0
              ? secs / ref.read(playerProvider).duration
              : 0,
        );
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          // User is manually scrolling — pause auto-scroll for 3 seconds
          _userScrolling = true;
          _userScrollTimer?.cancel();
          _userScrollTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _userScrolling = false);
          });
        }
        return false;
      },
      child: StreamBuilder<Duration>(
        stream: handler.positionStream,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final activeIndex =
              LrcParser.findActiveIndex(widget.lines, position);

          // Auto-scroll when active line changes
          if (activeIndex != _lastActiveIndex && activeIndex >= 0) {
            _lastActiveIndex = activeIndex;
            // Post-frame to avoid scrolling during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToIndex(activeIndex);
            });
          }

          return ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).size.height * 0.35,
              bottom: MediaQuery.of(context).size.height * 0.45,
            ),
            itemCount: widget.lines.length,
            itemExtent: _kLineHeight,
            itemBuilder: (context, index) {
              final line = widget.lines[index];
              final isActive = index == activeIndex;

              return _LyricLineWidget(
                line: line,
                isActive: isActive,
                hasTimestamps: widget.hasTimestamps,
                onTap: () => _onLineTap(line),
              );
            },
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────
//  SINGLE LYRIC LINE WIDGET
//
//  AnimatedDefaultTextStyle handles the scale/opacity
//  transition for active ↔ inactive without rebuilding
//  the parent list. Each line is a lightweight widget.
// ──────────────────────────────────────────────────────

class _LyricLineWidget extends StatelessWidget {
  final LyricLine line;
  final bool isActive;
  final bool hasTimestamps;
  final VoidCallback onTap;

  const _LyricLineWidget({
    required this.line,
    required this.isActive,
    required this.hasTimestamps,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: hasTimestamps ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _kLineHeight,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AnimatedDefaultTextStyle(
          duration: _kTextTransition,
          curve: Curves.easeOut,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white24,
            fontSize: isActive ? 22 : 18,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            height: 1.3,
          ),
          child: Text(
            line.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
