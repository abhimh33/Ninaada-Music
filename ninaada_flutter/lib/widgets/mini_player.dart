import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/core/media_theme_engine.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/screens/player_screen.dart';

/// Mini player bar — positioned above bottom nav
/// Gradient purple, progress bar, song info, prev/play/next/close controls
/// Now radio-aware: shows station info + LIVE badge when in radio mode
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use select to avoid rebuilding on every position tick
    final song = ref.watch(playerProvider.select((p) => p.currentSong));
    final isPlaying = ref.watch(playerProvider.select((p) => p.isPlaying));
    final progress = ref.watch(playerProvider.select((p) => p.progress));
    final duration = ref.watch(playerProvider.select((p) => p.duration));

    final isRadio = ref.watch(playerProvider.select((p) => p.isRadioMode));
    final radioStation = ref.watch(playerProvider.select((p) => p.activeRadioStation));

    // Hide mini player when radio is active
    if (isRadio) return const SizedBox.shrink();
    // Need a song to show
    if (song == null) return const SizedBox.shrink();

    final progressPct = (!isRadio && duration > 0) ? progress / duration : 0.0;

    // ── Swipe-down dismissal via Dismissible ──
    // Phase 7: RepaintBoundary isolates position-tick repaints
    return RepaintBoundary(
      child: Dismissible(
      key: const ValueKey('mini_player_dismiss'),
      direction: DismissDirection.down,
      onDismissed: (_) => ref.read(playerProvider.notifier).stopAndClear(),
      background: const SizedBox.shrink(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: GestureDetector(
          // Tap → open full-screen player via route push (enables Hero animation)
          onTap: () {
            Navigator.of(context).push(
              PageRouteBuilder(
                opaque: true,
                transitionDuration: const Duration(milliseconds: 400),
                reverseTransitionDuration: const Duration(milliseconds: 350),
                pageBuilder: (_, __, ___) => const _HeroPlayerRoute(),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOut,
                    ),
                    child: child,
                  );
                },
              ),
            );
          },
          // ── Horizontal swipe to skip ──
          onHorizontalDragEnd: (details) {
            if (isRadio) return; // no skip in radio mode
            final velocity = details.primaryVelocity ?? 0;
            if (velocity > 300) {
              // Swiped left→right → previous
              ref.read(playerProvider.notifier).playPrev();
            } else if (velocity < -300) {
              // Swiped right→left → next
              ref.read(playerProvider.notifier).playNext();
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 10,
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _DynamicMiniGradient(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress bar
                  Container(
                    height: 2,
                    color: Colors.black.withOpacity(0.3),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: progressPct.clamp(0.0, 1.0),
                        child: Container(height: 2, color: Colors.white),
                      ),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        // Artwork / radio icon
                        if (isRadio && radioStation != null) ...[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: NinaadaColors.surface,
                            ),
                            alignment: Alignment.center,
                            child: Text(radioStation.emoji, style: const TextStyle(fontSize: 24)),
                          ),
                        ] else if (song != null) ...[
                          // ── Hero-wrapped album art ──
                          Hero(
                            tag: 'album_art_${song.id}',
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: safeImageUrl(song.image),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                placeholder: (_, __) => Container(
                                  width: 48,
                                  height: 48,
                                  color: NinaadaColors.surface,
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  width: 48,
                                  height: 48,
                                  color: NinaadaColors.surface,
                                  child: const Icon(Icons.music_note, size: 16, color: Color(0xFF666666)),
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        // Song / station info — AnimatedSwitcher for smooth text transition
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.4),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Column(
                              key: ValueKey(isRadio ? 'radio' : song?.id ?? ''),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isRadio ? (radioStation?.name ?? 'Radio') : (song?.name ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                Row(
                                  children: [
                                    if (isRadio) ...[
                                      Container(
                                        width: 6,
                                        height: 6,
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
                                    ] else ...[
                                      Expanded(
                                        child: Text(
                                          song?.artist ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.7),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Controls — radio mode hides prev/next
                        if (!isRadio)
                          _MiniBtn(
                            icon: Icons.skip_previous_rounded,
                            size: 26,
                            opacity: 0.7,
                            onTap: () => ref.read(playerProvider.notifier).playPrev(),
                          ),
                        _MiniBtn(
                          icon: isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 28,
                          opacity: 0.7,
                          onTap: () => ref.read(playerProvider.notifier).togglePlay(),
                        ),
                        if (!isRadio)
                          _MiniBtn(
                            icon: Icons.skip_next_rounded,
                            size: 26,
                            opacity: 0.7,
                            onTap: () => ref.read(playerProvider.notifier).playNext(),
                          ),
                        _MiniBtn(
                          icon: isRadio ? Icons.stop_rounded : Icons.close_rounded,
                          size: 24,
                          opacity: 0.5,
                          onTap: () => isRadio
                              ? ref.read(playerProvider.notifier).stopRadio()
                              : ref.read(playerProvider.notifier).stopAndClear(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
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
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        child: Icon(icon, size: size, color: Colors.white.withOpacity(opacity)),
      ),
    );
  }
}

/// Dynamic gradient for the mini player — reads from MediaThemeEngine
class _DynamicMiniGradient extends ConsumerWidget {
  final Widget child;
  const _DynamicMiniGradient({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miniGrad = ref.watch(
      mediaThemeProvider.select((s) => s.palette.miniPlayerGradient),
    );

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: miniGrad.map((c) => c.withOpacity(0.88)).toList(),
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: child,
    ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  _HeroPlayerRoute — Full-screen player pushed as a route
//  (enables Hero animation for album art flying from mini → full)
// ════════════════════════════════════════════════════════════════

class _HeroPlayerRoute extends StatelessWidget {
  const _HeroPlayerRoute();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: NinaadaColors.background,
      body: PlayerScreen(),
    );
  }
}
