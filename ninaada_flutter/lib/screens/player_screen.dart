import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/media_theme_engine.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/sleep_alarm_provider.dart';
import 'package:ninaada_music/widgets/sleep_timer_modal.dart';
import 'package:ninaada_music/widgets/alarm_setup_modal.dart';
import 'package:ninaada_music/services/download_manager.dart';
import 'package:ninaada_music/widgets/media_action_sheet.dart';
import 'package:ninaada_music/widgets/queue_bottom_sheet.dart';
import 'package:ninaada_music/widgets/lyrics_view.dart';
import 'package:ninaada_music/services/ninaada_audio_handler.dart';
import 'package:ninaada_music/screens/equalizer_screen.dart';
import 'package:share_plus/share_plus.dart';

// ════════════════════════════════════════════════════════════════
//  PLAYER SCREEN — Decomposed for UI-thread efficiency
//
//  Rebuild isolation map:
//    PlayerScreen          → watch: currentSong (rebuilds on song change)
//    ├─ _PlayerBackground  → watch: palette + songImage (theme change)
//    ├─ _AlbumArt          → params only (song change via parent)
//    ├─ _TopBar            → params only (song change via parent)
//    ├─ _SongInfoRow       → watch: likedSongs (like toggle)
//    ├─ _AutoPlayToggle    → watch: autoPlay (toggle)
//    ├─ _SeekBar           → watch: progress, duration (≈200ms ticks)
//    ├─ _PlayerControls    → watch: isPlaying, shuffle, repeat
//    └─ _ActionRow         → watch: downloads, sleep, speed
//
//  Position ticks (≈5×/sec) ONLY rebuild _SeekBar — the heaviest
//  widgets (background, album art, controls) are untouched.
//
//  RepaintBoundary placements:
//    • _PlayerBackground — BackdropFilter is GPU-expensive
//    • _AlbumArt — large image, stable between songs
// ════════════════════════════════════════════════════════════════

/// Height of the mini player bar (shared with overlay).
const double kMiniHeight = 82.0;

/// Horizontal margin for the mini player.
const double kMiniHMargin = 8.0;

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final song = ref.watch(playerProvider.select((p) => p.currentSong));
    if (song == null) return const _EmptyPlayer();
    return _PlayerBody(song: song);
  }
}

// ════════════════════════════════════════════════════════════════
//  PLAYER MORPH LAYOUT — Single parametric surface
//
//  Replaces crossfade. All elements exist once and reposition
//  based on animation value `t` (0 = mini, 1 = full).
//
//  Structure: Stack with absolute-positioned elements.
//  No Row/Column axis switching. No dual artwork instances.
//
//  Opacity scheduling (no mid-point overdraw):
//    Mini controls:  1.0 → 0.0 by t=0.4
//    Progress bar:   1.0 → 0.0 by t=0.33
//    Top bar:        0.0 → 1.0 by t=0.55
//    Full controls:  0.0 → 1.0 by t=0.65
//    Song info row:  0.0 → 1.0 by t=0.65
// ════════════════════════════════════════════════════════════════

class PlayerMorphLayout extends ConsumerStatefulWidget {
  final double t;
  const PlayerMorphLayout({super.key, required this.t});

  @override
  ConsumerState<PlayerMorphLayout> createState() => _PlayerMorphLayoutState();
}

class _PlayerMorphLayoutState extends ConsumerState<PlayerMorphLayout>
    with SingleTickerProviderStateMixin {
  double _dragDistance = 0;
  DateTime _lastSkip = DateTime(2000);

  // ── Skip nudge animation (12px, 100ms) ──
  late final AnimationController _nudgeController;
  double _nudgeDirection = 0; // -1 = left (next), +1 = right (prev)

  @override
  void initState() {
    super.initState();
    _nudgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    _nudgeController.dispose();
    super.dispose();
  }

  void _fireSkipNudge(double direction) {
    _nudgeDirection = direction;
    _nudgeController.forward(from: 0).then((_) {
      _nudgeController.value = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final song = ref.watch(playerProvider.select((p) => p.currentSong));
    final isPlaying = ref.watch(playerProvider.select((p) => p.isPlaying));
    final isBuffering = ref.watch(playerProvider.select((p) => p.isBuffering));
    final isRadio = ref.watch(playerProvider.select((p) => p.isRadioMode));
    final radioStation = ref.watch(playerProvider.select((p) => p.activeRadioStation));

    if (song == null && radioStation == null) return const SizedBox.shrink();

    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final screenH = mq.size.height;
    final safeTop = mq.padding.top;

    // ── Container dimensions (change with t) ──
    final containerW = screenW - 2 * lerpDouble(kMiniHMargin, 0, t)!;

    // ── Opacity scheduling ──
    final miniCtrlOp = (1.0 - t * 2.5).clamp(0.0, 1.0);    // gone by t=0.4
    final progressOp = (1.0 - t * 3.0).clamp(0.0, 1.0);     // gone by t=0.33
    final topBarOp   = ((t - 0.25) / 0.30).clamp(0.0, 1.0);  // visible by t=0.55
    final fullCtrlOp = ((t - 0.35) / 0.30).clamp(0.0, 1.0);  // visible by t=0.65
    final bgMorphOp  = ((t - 0.05) / 0.40).clamp(0.0, 1.0);  // bg crossfade 0.05→0.45

    // ── Artwork morph ──
    final fullArtSize = screenW - 56.0;
    final artSize = lerpDouble(48.0, fullArtSize, t)!;
    final artRadius = lerpDouble(8.0, 18.0, t)!;

    // Mini: left-aligned, vertically centered in 70px bar (below 2px progress bar)
    final miniArtLeft = 12.0;
    final miniArtTop = (kMiniHeight - 48.0) / 2;

    // Full: centered, below top bar + spacer
    final topBarH = 56.0;
    // Compute spacer for full layout distribution
    final belowArtFixed = 50.0 + 6 + 24 + 12 + 48 + 8 + 56 + 32 + 40; // ≈276
    final flexTotal = (screenH - safeTop - topBarH - fullArtSize - belowArtFixed);
    final spacerUnit = (flexTotal / 5).clamp(8.0, double.infinity);
    final spacer2 = spacerUnit * 2;

    final fullArtLeft = (containerW - fullArtSize) / 2;
    final fullArtTop = safeTop + topBarH + spacer2;

    final artLeft = lerpDouble(miniArtLeft, fullArtLeft, t)!;
    final artTop = lerpDouble(miniArtTop, fullArtTop, t)!;

    // ── Title morph ──
    final titleFs = lerpDouble(14.0, 22.0, t)!;
    final artistFs = lerpDouble(11.0, 15.0, t)!;

    // Mini: beside artwork, centered vertically in 70px
    final miniTitleLeft = miniArtLeft + 42 + 8; // 62
    final miniTitleTop = (kMiniHeight - 32) / 2; // ≈19, for ~32px of title+artist
    final miniTitleWidth = containerW - miniTitleLeft - 150; // space for controls

    // Full: below artwork, full width with padding
    final fullTitleLeft = 20.0;
    final fullTitleTop = fullArtTop + fullArtSize + spacer2;
    final fullTitleWidth = containerW - 40.0;

    final titleLeft = lerpDouble(miniTitleLeft, fullTitleLeft, t)!;
    final titleTop = lerpDouble(miniTitleTop, fullTitleTop, t)!;
    final titleWidth = lerpDouble(miniTitleWidth, fullTitleWidth, t)!;

    // ── Full controls position (below title block) ──
    final fullControlsTop = fullTitleTop + 52 + 6; // title block ~52px + gap

    // Display name / artist
    final displayName = isRadio
        ? (radioStation?.name ?? 'Radio')
        : (song?.name ?? '');
    final displayArtist = isRadio ? '' : (song?.artist ?? '');

    return GestureDetector(
      // Tap to expand when in mini state (t < 0.3)
      onTap: t < 0.3
          ? () {
              HapticFeedback.lightImpact();
              ref.read(playerProvider.notifier).expandPlayer();
            }
          : null,
      behavior: t < 0.3 ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
      child: Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // ── Layer 0: Background ──
        // Mini gradient fades out, full background fades in
        Positioned.fill(child: _MorphMiniGradient(opacity: 1.0 - bgMorphOp)),
        if (bgMorphOp > 0)
          Positioned.fill(
            child: Opacity(
              opacity: bgMorphOp,
              child: const RepaintBoundary(child: _PlayerBackground()),
            ),
          ),

        // ── Layer 1: Mini progress bar (own widget to avoid parent rebuild on ticks) ──
        if (progressOp > 0.01)
          Positioned(
            top: 0, left: 0, right: 0, height: 2,
            child: Opacity(
              opacity: progressOp,
              child: const _MiniProgressBar(),
            ),
          ),

        // ── Layer 2: Top bar (full only) ──
        if (topBarOp > 0.01 && song != null)
          Positioned(
            top: safeTop + 8, left: 20, right: 20,
            child: Opacity(
              opacity: topBarOp,
              child: _TopBar(song: song),
            ),
          ),

        // ── Layer 3: Artwork (single instance, morphs) ──
        Positioned(
          left: artLeft,
          top: artTop,
          width: artSize,
          height: artSize,
          child: GestureDetector(
            onHorizontalDragStart: (_) => _dragDistance = 0,
            onHorizontalDragUpdate: (d) => _dragDistance += d.primaryDelta ?? 0,
            onHorizontalDragEnd: (details) {
              if (isRadio) { _dragDistance = 0; return; }
              final viewState = ref.read(playerProvider).viewState;
              if (viewState != PlayerViewState.full) { _dragDistance = 0; return; }
              // Skip debounce guard (250ms)
              final now = DateTime.now();
              if (now.difference(_lastSkip).inMilliseconds < 250) { _dragDistance = 0; return; }
              final velocity = details.primaryVelocity ?? 0;
              final distance = _dragDistance.abs();
              if (distance > 60 || velocity.abs() > 300) {
                HapticFeedback.lightImpact();
                _lastSkip = now;
                final goNext = _dragDistance < 0 || velocity < -300;
                // Subtle 12px nudge in swipe direction, then skip
                _fireSkipNudge(goNext ? -1 : 1);
                if (goNext) {
                  ref.read(playerProvider.notifier).playNext();
                } else {
                  ref.read(playerProvider.notifier).playPrev();
                }
              }
              _dragDistance = 0;
            },
            onLongPress: () {
              if (song != null && t > 0.9) {
                HapticFeedback.mediumImpact();
                showSongActionSheet(context, ref, song);
              }
            },
            child: AnimatedBuilder(
              animation: _nudgeController,
              builder: (context, child) {
                // 12px nudge: ease out, then snap back (controller resets to 0)
                final nudge = _nudgeDirection * 12 *
                    Curves.easeOut.transform(_nudgeController.value);
                return Transform.translate(
                  offset: Offset(nudge, 0),
                  child: child,
                );
              },
              child: _MorphArtwork(
                isRadio: isRadio,
                radioEmoji: radioStation?.emoji,
                imageUrl: song != null ? safeImageUrl(song.image) : null,
                size: artSize,
                radius: artRadius,
                songId: song?.id ?? '',
              ),
            ),
          ),
        ),

        // ── Layer 4: Title / Artist (morphs position + font size) ──
        Positioned(
          left: titleLeft,
          top: titleTop,
          width: titleWidth,
          child: SizedBox(
            width: titleWidth, // Fixed width prevents line-wrap jitter
            child: Column(
              crossAxisAlignment: t < 0.5
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: titleFs,
                    fontWeight: FontWeight.lerp(
                      FontWeight.w600, FontWeight.w800, t,
                    ),
                    letterSpacing: lerpDouble(0, -0.5, t),
                  ),
                ),
                if (isRadio && t < 0.5) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6, height: 6,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF4D6D),
                        ),
                      ),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ] else if (displayArtist.isNotEmpty) ...[
                  SizedBox(height: lerpDouble(0, 2, t)),
                  Text(
                    displayArtist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t < 0.5
                          ? Colors.white.withOpacity(0.7)
                          : const Color(0xFFAAAAAA),
                      fontSize: artistFs,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // ── Layer 5: Mini controls (fade out) ──
        if (miniCtrlOp > 0.01)
          Positioned(
            right: 4,
            top: 2, // below progress bar
            height: kMiniHeight - 2,
            child: Opacity(
              opacity: miniCtrlOp,
              child: _MorphMiniControls(
                isPlaying: isPlaying,
                isRadio: isRadio,
                isBuffering: isBuffering,
              ),
            ),
          ),

        // ── Layer 6: Song info row — like button (full only) ──
        if (fullCtrlOp > 0.01 && song != null)
          Positioned(
            left: 20, right: 20,
            top: fullTitleTop,
            child: Opacity(
              opacity: fullCtrlOp,
              child: _SongInfoRow(song: song),
            ),
          ),

        // ── Layer 7: Full controls (fade in) ──
        if (fullCtrlOp > 0.01 && song != null)
          Positioned(
            left: 20, right: 20,
            top: fullControlsTop,
            child: Opacity(
              opacity: fullCtrlOp,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _AutoPlayToggle(),
                  const SizedBox(height: 12),
                  _SeekBar(screenWidth: screenW),
                  const SizedBox(height: 8),
                  const _PlayerControls(),
                  const SizedBox(height: 32),
                  _ActionRow(song: song),
                ],
              ),
            ),
          ),
      ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Morph Artwork — single instance, morphs size/radius
// ──────────────────────────────────────────────

class _MorphArtwork extends StatelessWidget {
  final bool isRadio;
  final String? radioEmoji;
  final String? imageUrl;
  final double size;
  final double radius;
  final String songId;

  const _MorphArtwork({
    required this.isRadio,
    this.radioEmoji,
    this.imageUrl,
    required this.size,
    required this.radius,
    required this.songId,
  });

  @override
  Widget build(BuildContext context) {
    if (isRadio) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: NinaadaColors.surface,
        ),
        alignment: Alignment.center,
        child: Text(radioEmoji ?? '📻',
            style: TextStyle(fontSize: size * 0.5)),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: Container(
        key: ValueKey(songId),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: size > 100 ? 18 : 6,
              offset: Offset(0, size > 100 ? 8 : 2),
            ),
          ],
        ),
        child: SafeImage(
          imageUrl: imageUrl ?? '',
          width: size,
          height: size,
          fit: BoxFit.cover,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Morph Mini Gradient — dynamic gradient background for mini state
// ──────────────────────────────────────────────

// ──────────────────────────────────────────────
//  Mini progress bar — Phase 7 rebuild isolation
//  Only this tiny 2px widget rebuilds on position ticks.
//  Prevents the entire PlayerMorphLayout from rebuilding ~5×/sec.
// ──────────────────────────────────────────────

class _MiniProgressBar extends ConsumerWidget {
  const _MiniProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playerProvider.select((p) => p.progress));
    final duration = ref.watch(playerProvider.select((p) => p.duration));
    final isRadio = ref.watch(playerProvider.select((p) => p.isRadioMode));
    final pct = (!isRadio && duration > 0) ? (progress / duration).clamp(0.0, 1.0) : 0.0;

    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: pct,
          child: Container(height: 2, color: Colors.white),
        ),
      ),
    );
  }
}

class _MorphMiniGradient extends ConsumerWidget {
  final double opacity;
  const _MorphMiniGradient({required this.opacity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (opacity < 0.01) return const SizedBox.expand();

    final miniGrad = ref.watch(
      mediaThemeProvider.select((s) => s.palette.miniPlayerGradient),
    );

    return Opacity(
      opacity: opacity,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: miniGrad.map((c) => c.withOpacity(0.82)).toList(),
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Morph Mini Controls — play/prev/next/close for mini state
// ──────────────────────────────────────────────

class _MorphMiniControls extends ConsumerWidget {
  final bool isPlaying;
  final bool isRadio;
  final bool isBuffering;

  const _MorphMiniControls({
    required this.isPlaying,
    required this.isRadio,
    this.isBuffering = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isRadio)
          _MiniBtn(
            icon: Icons.skip_previous_rounded,
            size: 16,
            opacity: 0.6,
            onTap: () => ref.read(playerProvider.notifier).playPrev(),
          ),
        if (isBuffering)
          const SizedBox(
            width: 20, height: 20,
            child: Padding(
              padding: EdgeInsets.all(2),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
          )
        else
          _MiniBtn(
            icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 20,
            opacity: 0.6,
            onTap: () => ref.read(playerProvider.notifier).togglePlay(),
          ),
        if (!isRadio)
          _MiniBtn(
            icon: Icons.skip_next_rounded,
            size: 16,
            opacity: 0.6,
            onTap: () => ref.read(playerProvider.notifier).playNext(),
          ),
        _MiniBtn(
          icon: isRadio ? Icons.stop_rounded : Icons.close_rounded,
          size: 16,
          opacity: 0.4,
          onTap: () => isRadio
              ? ref.read(playerProvider.notifier).stopRadio()
              : ref.read(playerProvider.notifier).stopAndClear(),
        ),
      ],
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final double opacity;
  final VoidCallback onTap;

  const _MiniBtn({
    required this.icon,
    required this.size,
    required this.opacity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, size: size, color: Colors.white.withOpacity(opacity)),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Empty state — shown when nothing is playing
// ──────────────────────────────────────────────

class _EmptyPlayer extends StatelessWidget {
  const _EmptyPlayer();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note, size: 80, color: Color(0xFF333333)),
          SizedBox(height: 16),
          Text('Nothing Playing',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text('Search and play a song',
              style: TextStyle(color: Color(0xFF888888))),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Player body — layout shell, rebuilds on song change only
// ──────────────────────────────────────────────

class _PlayerBody extends StatelessWidget {
  final Song song;
  const _PlayerBody({required this.song});

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Stack(
      children: [
        // Background layers — isolated in RepaintBoundary
        const RepaintBoundary(child: _PlayerBackground()),

        // Main content — full-screen immersive layout
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _TopBar(song: song),
                ),
                const Spacer(flex: 2),
                _SwipeableAlbumArt(
                  song: song,
                  size: sw - 56,
                ),
                const Spacer(flex: 2),
                _SongInfoRow(song: song),
                const SizedBox(height: 6),
                const _AutoPlayToggle(),
                const SizedBox(height: 12),
                _SeekBar(screenWidth: sw),
                const SizedBox(height: 8),
                const _PlayerControls(),
                const SizedBox(height: 32),
                _ActionRow(song: song),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  Background — blur + gradient + dynamic color tint
//  Watches: mediaThemeProvider.palette, currentSong.image
//  RepaintBoundary: BackdropFilter is very GPU-expensive
// ──────────────────────────────────────────────

class _PlayerBackground extends ConsumerWidget {
  const _PlayerBackground();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(mediaThemeProvider.select((s) => s.palette));
    final songImage = ref.watch(
      playerProvider.select((p) => p.currentSong?.image),
    );

    return Stack(
      children: [
        // Blurred album art
        if (songImage != null)
          Positioned.fill(
            child: CachedNetworkImage(
              imageUrl: safeImageUrl(songImage),
              fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.6),
              colorBlendMode: BlendMode.darken,
              errorWidget: (_, __, ___) =>
                  Container(color: palette.dominant),
            ),
          ),
        // Blur overlay — capped at sigma 20 for frame budget (Phase 7: lowered from 25)
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: const SizedBox.expand(),
          ),
        ),
        // Dark cinematic overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.40),
                  Colors.black.withValues(alpha: 0.55),
                  const Color(0xFF0B0F1A).withValues(alpha: 0.90),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.45, 1],
              ),
            ),
          ),
        ),
        // Dynamic color tint — animated 400ms easeOut
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.dominant.withValues(alpha: 0.45),
                  palette.secondary.withValues(alpha: 0.30),
                  palette.muted.withValues(alpha: 0.65),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  Album art — pure StatelessWidget, no provider watch
// ──────────────────────────────────────────────

class _AlbumArt extends StatelessWidget {
  final String imageUrl;
  final double size;
  final String songId;
  const _AlbumArt({super.key, required this.imageUrl, required this.size, required this.songId});

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'album_art_$songId',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              width: size,
              height: size,
              color: NinaadaColors.surfaceLight,
              child: const Icon(Icons.music_note,
                  color: Color(0xFF666666), size: 48),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Swipeable album art — swipe to skip + long press + AnimatedSwitcher
//  ConsumerStatefulWidget to track drag distance without provider
// ──────────────────────────────────────────────

class _SwipeableAlbumArt extends ConsumerStatefulWidget {
  final Song song;
  final double size;
  const _SwipeableAlbumArt({required this.song, required this.size});

  @override
  ConsumerState<_SwipeableAlbumArt> createState() => _SwipeableAlbumArtState();
}

class _SwipeableAlbumArtState extends ConsumerState<_SwipeableAlbumArt> {
  double _dragDistance = 0;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onHorizontalDragStart: (_) => _dragDistance = 0,
        onHorizontalDragUpdate: (details) {
          _dragDistance += details.primaryDelta ?? 0;
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          final distance = _dragDistance.abs();

          // Guard: only skip when overlay is fully expanded
          final viewState = ref.read(playerProvider).viewState;
          if (viewState != PlayerViewState.full) {
            _dragDistance = 0;
            return;
          }

          // Skip only if meaningful drag (>60px) OR fast swipe (>300px/s)
          if (distance > 60 || velocity.abs() > 300) {
            HapticFeedback.lightImpact();
            if (_dragDistance < 0 || velocity < -300) {
              ref.read(playerProvider.notifier).playNext();
            } else {
              ref.read(playerProvider.notifier).playPrev();
            }
          }
          _dragDistance = 0;
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          showSongActionSheet(context, ref, widget.song);
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.15, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOut,
                )),
                child: child,
              ),
            );
          },
          child: _AlbumArt(
            key: ValueKey(widget.song.id),
            imageUrl: safeImageUrl(widget.song.image),
            size: widget.size,
            songId: widget.song.id,
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Top bar — down arrow, title, more button
// ──────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  final Song song;
  const _TopBar({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () {
            // Collapse the player overlay back to mini bar
            ref.read(playerProvider.notifier).collapsePlayer();
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.keyboard_arrow_down,
                size: 26, color: Colors.white.withOpacity(0.7)),
          ),
        ),
        Text(
          'NOW PLAYING',
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 11,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        GestureDetector(
          onTap: () => showSongActionSheet(context, ref, song),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.more_vert,
                size: 22, color: Colors.white.withOpacity(0.7)),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  Song info + like button
//  Watches: libraryProvider.likedSongs (like toggle only)
// ──────────────────────────────────────────────

class _SongInfoRow extends ConsumerWidget {
  final Song song;
  const _SongInfoRow({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLiked = ref.watch(
      libraryProvider.select(
        (lib) => lib.likedSongs.any((s) => s.id == song.id),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5),
              ),
              const SizedBox(height: 2),
              Text(
                song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Color(0xFFAAAAAA), fontSize: 15),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => ref.read(libraryProvider.notifier).toggleLike(song),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: isLiked
              ? Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                        colors: [Color(0xFFFF4D6D), Color(0xFFFF1744)]),
                    boxShadow: [
                      BoxShadow(
                          color: const Color(0xFFFF4D6D).withOpacity(0.25),
                          blurRadius: 6),
                    ],
                  ),
                  child: const Icon(Icons.favorite,
                      size: 18, color: Colors.white),
                )
              : Icon(Icons.favorite_border,
                  size: 26, color: Colors.white.withOpacity(0.5)),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  Auto-play toggle
//  Watches: playerProvider.autoPlay only
// ──────────────────────────────────────────────

class _AutoPlayToggle extends ConsumerWidget {
  const _AutoPlayToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoPlay = ref.watch(playerProvider.select((p) => p.autoPlay));

    return Row(
      children: [
        Icon(Icons.radio,
            size: 14,
            color: autoPlay
                ? NinaadaColors.primaryLight
                : const Color(0xFF555555)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Auto-play similar',
              style: TextStyle(color: Color(0xFF666666), fontSize: 11)),
        ),
        GestureDetector(
          onTap: () => ref.read(playerProvider.notifier).toggleAutoPlay(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 34,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color: autoPlay
                    ? NinaadaColors.primary
                    : const Color(0xFF333333),
                boxShadow: autoPlay
                    ? [
                        BoxShadow(
                            color: NinaadaColors.primary.withOpacity(0.35),
                            blurRadius: 5)
                      ]
                    : null,
              ),
              alignment:
                  autoPlay ? Alignment.centerRight : Alignment.centerLeft,
              padding: const EdgeInsets.all(2),
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  Seek bar + time labels
//  Watches: playerProvider.progress, .duration ONLY
//  This is the widget that rebuilds ≈5×/sec — fully isolated
// ──────────────────────────────────────────────

class _SeekBar extends ConsumerStatefulWidget {
  final double screenWidth;
  const _SeekBar({required this.screenWidth});

  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  bool _isDragging = false;
  double _dragValue = 0.0; // 0.0 – 1.0

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(playerProvider.select((p) => p.progress));
    final duration = ref.watch(playerProvider.select((p) => p.duration));
    final streamPct = duration > 0 ? progress / duration : 0.0;
    final displayPct = (_isDragging ? _dragValue : streamPct).clamp(0.0, 1.0);
    final sw = widget.screenWidth;
    final trackWidth = sw - 40; // account for horizontal padding

    // Display time: while dragging show drag position, else stream position
    final displayProgress = _isDragging ? _dragValue * duration : progress;

    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
              _dragValue = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragUpdate: (details) {
            setState(() {
              _dragValue = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
            });
          },
          onHorizontalDragEnd: (details) {
            final seekPct = _dragValue;
            setState(() => _isDragging = false);
            HapticFeedback.lightImpact();
            ref.read(playerProvider.notifier).seekTo(seekPct);
          },
          onTapDown: (details) {
            final pct = (details.localPosition.dx / trackWidth).clamp(0.0, 1.0);
            ref.read(playerProvider.notifier).seekTo(pct);
          },
          child: SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                // Background track
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Filled portion
                FractionallySizedBox(
                  widthFactor: displayPct,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: NinaadaColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Thumb — grows slightly while dragging
                Positioned(
                  left: (trackWidth - 14) * displayPct,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: _isDragging ? 18 : 14,
                    height: _isDragging ? 18 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(_isDragging ? 0.5 : 0.3),
                            blurRadius: _isDragging ? 8 : 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(fmt(displayProgress),
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 12)),
            Text(fmt(duration),
                style: const TextStyle(
                    color: Color(0xFF888888), fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  Playback controls — shuffle, prev, play, next, repeat
//  Watches: isPlaying, shuffle, repeat ONLY
// ──────────────────────────────────────────────

class _PlayerControls extends ConsumerWidget {
  const _PlayerControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying =
        ref.watch(playerProvider.select((p) => p.isPlaying));
    final isBuffering =
        ref.watch(playerProvider.select((p) => p.isBuffering));
    final shuffle =
        ref.watch(playerProvider.select((p) => p.shuffle));
    final repeat =
        ref.watch(playerProvider.select((p) => p.repeat));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _PressableIcon(
          onTap: () => ref.read(playerProvider.notifier).toggleShuffle(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(Icons.shuffle,
                size: 22,
                color: shuffle
                    ? NinaadaColors.primary
                    : const Color(0xFF888888)),
          ),
        ),
        _PressableIcon(
          onTap: () => ref.read(playerProvider.notifier).playPrev(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.skip_previous,
                size: 32, color: Colors.white.withOpacity(0.7)),
          ),
        ),
        _PressableIcon(
          onTap: () => ref.read(playerProvider.notifier).togglePlay(),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [NinaadaColors.primary, NinaadaColors.primaryLight],
              ),
              boxShadow: [
                BoxShadow(
                  color: NinaadaColors.primary.withOpacity(0.25),
                  blurRadius: 12,
                ),
              ],
            ),
            child: isBuffering
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 28,
                    color: Colors.white,
                  ),
          ),
        ),
        _PressableIcon(
          onTap: () => ref.read(playerProvider.notifier).playNext(),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(Icons.skip_next,
                size: 32, color: Colors.white.withOpacity(0.7)),
          ),
        ),
        _PressableIcon(
          onTap: () => ref.read(playerProvider.notifier).cycleRepeat(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  repeat == 'one' ? Icons.repeat_one : Icons.repeat,
                  size: 22,
                  color: repeat == 'off'
                      ? const Color(0xFF888888)
                      : NinaadaColors.primary,
                ),
                if (repeat == 'all')
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: NinaadaColors.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
//  Action row — playlist, download, speed, share, timer
//  Watches: downloadedSongs, sleepTimer, playbackSpeed
// ──────────────────────────────────────────────

class _ActionRow extends ConsumerWidget {
  final Song song;
  const _ActionRow({required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDled = ref.watch(
      libraryProvider
          .select((lib) => lib.downloadedSongs.any((s) => s.id == song.id)),
    );
    final sleep = ref.watch(sleepAlarmProvider);
    final speed =
        ref.watch(playerProvider.select((p) => p.playbackSpeed));

    return Row(
      children: [
        Expanded(
          child: Center(
            child: _ActionBtn(
              icon: Icons.lyrics_outlined,
              label: 'Lyrics',
              color: NinaadaColors.primary,
              onTap: () => _showLyricsPanel(context),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _ActionBtn(
              icon: Icons.playlist_add_rounded,
              label: 'Save',
              color: NinaadaColors.primary,
              onTap: () => showPlaylistPicker(ref, song),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _ActionBtn(
              icon: Icons.queue_music_rounded,
              label: 'Queue',
              color: NinaadaColors.primary,
              onTap: () => showQueueBottomSheet(context),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _ActionBtn(
              icon: isDled
                  ? Icons.check_circle
                  : Icons.arrow_circle_down_outlined,
              label: isDled ? 'Saved' : 'Download',
              color: isDled
                  ? NinaadaColors.primaryLight
                  : NinaadaColors.primary,
              onTap: () {
                if (!isDled) {
                  DownloadManager().download(song).then((_) {
                    ref.read(libraryProvider.notifier).loadAll();
                  });
                }
              },
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _ActionBtn(
              icon: Icons.equalizer_rounded,
              label: 'EQ',
              color: NinaadaColors.primary,
              onTap: () => showEqualizerModal(context),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: _ActionBtn(
              icon: Icons.timer_outlined,
              label: sleep.sleepActive ? fmt(sleep.sleepRemaining) : 'Sleep',
              color: sleep.sleepActive
                  ? NinaadaColors.primaryLight
                  : NinaadaColors.primary,
              onTap: () => showSleepTimerModal(context),
            ),
          ),
        ),
      ],
    );
  }

  void _showSpeedModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _SpeedSheet(),
    );
  }

  void _showLyricsPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: const LyricsPanel(),
        ),
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const _ClearCacheSheet(),
    );
  }


}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _PressableIcon(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Color(0xFF888888), fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _OverflowItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OverflowItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: NinaadaColors.primary),
            const SizedBox(width: 14),
            Text(label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Pressable icon — 120ms scale 0.95 on press, easeOut
//  No bounce, no scaling above 1.0
// ──────────────────────────────────────────────

class _PressableIcon extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _PressableIcon({required this.child, required this.onTap});

  @override
  State<_PressableIcon> createState() => _PressableIconState();
}

class _PressableIconState extends State<_PressableIcon> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _pressed = true);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Speed control bottom sheet — matches RN Premium Speed Control
class _SpeedSheet extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playerProvider).playbackSpeed;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag indicator handle
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${speed.toStringAsFixed(2)}x',
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300, letterSpacing: -1),
          ),
          Text(
            'Playback Speed',
            style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10),
          ),
          const SizedBox(height: 14),
          // ── Continuous slider with reference marks ──
          Stack(
            alignment: Alignment.center,
            children: [
              // Reference line at 1.0x (normal speed)
              Positioned(
                // 1.0x is at (1.0 - 0.5) / (2.0 - 0.5) = 0.333 along the slider
                left: 0,
                right: 0,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final trackWidth = constraints.maxWidth - 32; // slider padding
                    final normalPos = 16 + trackWidth * ((1.0 - 0.5) / (2.0 - 0.5));
                    return Stack(
                      children: [
                        Positioned(
                          left: normalPos - 0.5,
                          top: 0,
                          child: Container(
                            width: 1,
                            height: 26,
                            color: Colors.white.withOpacity(0.15),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: NinaadaColors.primary.withOpacity(0.5),
                  inactiveTrackColor: Colors.white.withOpacity(0.08),
                  thumbColor: NinaadaColors.primary,
                  overlayColor: NinaadaColors.primary.withOpacity(0.12),
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: speed.clamp(0.5, 2.0),
                  min: 0.5,
                  max: 2.0,
                  onChanged: (v) {
                    final rounded = (v * 20).round() / 20; // snap to 0.05
                    ref.read(playerProvider.notifier).changeSpeed(rounded);
                  },
                ),
              ),
            ],
          ),
          // Slider labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final label in ['0.5x', '1.0x', '1.5x', '2.0x'])
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Quick select pills
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final s in [
                (0.75, '0.75x'),
                (1.0, 'Normal'),
                (1.25, '1.25x'),
                (1.5, '1.5x'),
                (2.0, '2x'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => ref.read(playerProvider.notifier).changeSpeed(s.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: speed == s.$1
                              ? NinaadaColors.primary.withOpacity(0.15)
                              : Colors.white.withOpacity(0.05),
                          border: Border.all(
                            color: speed == s.$1
                                ? NinaadaColors.primary.withOpacity(0.4)
                                : Colors.white.withOpacity(0.08),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          s.$2,
                          style: TextStyle(
                            color: speed == s.$1 ? NinaadaColors.primaryLight : Colors.white.withOpacity(0.6),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────
//  Clear Audio Cache sheet — Phase 8
//  Shows cache size and allows clearing cached audio files.
// ──────────────────────────────────────────────

class _ClearCacheSheet extends StatefulWidget {
  const _ClearCacheSheet();

  @override
  State<_ClearCacheSheet> createState() => _ClearCacheSheetState();
}

class _ClearCacheSheetState extends State<_ClearCacheSheet> {
  int _cacheSize = -1; // -1 = loading
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final size = await NinaadaAudioHandler.getAudioCacheSize();
    if (mounted) setState(() => _cacheSize = size);
  }

  Future<void> _clearCache() async {
    setState(() => _clearing = true);
    final freed = await NinaadaAudioHandler.clearAudioCache();
    if (mounted) {
      setState(() {
        _cacheSize = 0;
        _clearing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Freed ${_formatBytes(freed)}',
            style: const TextStyle(color: Colors.white),
          ),
          backgroundColor: const Color(0xFF1A1A2E),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'Audio Cache',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cached audio streams are stored locally for zero-data replays.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          // Cache size display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.storage_rounded,
                  color: NinaadaColors.primary,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cache Size',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _cacheSize < 0
                            ? 'Calculating...'
                            : _formatBytes(_cacheSize),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Clear button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _clearing || _cacheSize <= 0 ? null : _clearCache,
              style: ElevatedButton.styleFrom(
                backgroundColor: NinaadaColors.primary.withOpacity(0.15),
                foregroundColor: NinaadaColors.primaryLight,
                disabledBackgroundColor: Colors.white.withOpacity(0.03),
                disabledForegroundColor: Colors.white.withOpacity(0.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _clearing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded, size: 18),
              label: Text(
                _clearing ? 'Clearing...' : 'Clear Audio Cache',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
