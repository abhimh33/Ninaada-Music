import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/screens/player_screen.dart';

// ════════════════════════════════════════════════════════════════
//  PLAYER OVERLAY — Single surface for mini + full player
//
//  Lives in the global Stack. Animates height from 70px (mini bar)
//  to full screen (player). One AnimationController, no Navigator,
//  no separate Scaffold. Vertical drag physics for natural feel.
//
//  Phase 3 — True morph layout:
//    • Single PlayerMorphLayout driven by animation value t
//    • No crossfade, no dual-tree, no opacity swap
//    • All elements exist once and reposition via lerp
//    • AnimatedBuilder drives geometry only (GPU-driven)
// ════════════════════════════════════════════════════════════════

/// Bottom offset for the mini player (sits above the 70px bottom nav).
const double _kBottomNavHeight = 70.0;

class PlayerOverlay extends ConsumerStatefulWidget {
  const PlayerOverlay({super.key});

  @override
  ConsumerState<PlayerOverlay> createState() => _PlayerOverlayState();
}

class _PlayerOverlayState extends ConsumerState<PlayerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Critically damped spring — no overshoot, fast settle.
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 600,
    damping: 50,
  );

  /// Track the last viewState we reacted to, to avoid redundant forward/reverse.
  PlayerViewState _lastViewState = PlayerViewState.hidden;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300), // fallback, spring overrides
    );
  }

  /// Animate to target using critically damped spring.
  void _springTo(double target) {
    final simulation = SpringSimulation(
      _spring,
      _controller.value,           // from current position
      target,                       // to 0 or 1
      _controller.velocity * 0.001, // velocity in controller units
    );
    _controller.animateWith(simulation);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewState = ref.watch(
      playerProvider.select((p) => p.viewState),
    );

    // Hidden → nothing to render
    if (viewState == PlayerViewState.hidden) {
      // If we were animating, snap shut
      if (_controller.value > 0) _controller.value = 0;
      _lastViewState = viewState;
      return const SizedBox.shrink();
    }

    // React to viewState transitions (mini ↔ full)
    if (viewState != _lastViewState) {
      _lastViewState = viewState;
      if (viewState == PlayerViewState.full) {
        _springTo(1.0);
      } else if (viewState == PlayerViewState.mini) {
        _springTo(0.0);
      }
    }

    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value; // 0 = mini, 1 = full

        // ── Geometry interpolation ──
        // Mini: sits above bottom nav with horizontal margins
        // Full: fills entire screen edge-to-edge
        final height = lerpDouble(kMiniHeight, size.height, t)!;
        final bottom = lerpDouble(_kBottomNavHeight, 0, t)!;
        final hMargin = lerpDouble(kMiniHMargin, 0, t)!;
        final borderRadius = lerpDouble(14, 0, t)!;

        return Positioned(
          left: hMargin,
          right: hMargin,
          bottom: bottom,
          height: height,
          child: GestureDetector(
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(borderRadius),
              clipBehavior: Clip.antiAlias,
              elevation: lerpDouble(4, 12, t)!,
              shadowColor: Colors.black.withOpacity(0.4),
              child: PlayerMorphLayout(t: t),
            ),
          ),
        );
      },
    );
  }

  // ══════════════════════════════════════════════════
  //  DRAG GESTURE HANDLERS
  // ══════════════════════════════════════════════════

  void _onDragUpdate(DragUpdateDetails details) {
    // ── Gesture conflict guard: ignore if horizontal > vertical ──
    if (details.delta.dx.abs() > details.delta.dy.abs()) return;

    final delta = details.primaryDelta! / MediaQuery.of(context).size.height;
    _controller.value -= delta; // drag up → increase, drag down → decrease
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    // ── Velocity-priority logic (400 px/s threshold) ──
    if (velocity < -400) {
      // Fast swipe up → expand
      HapticFeedback.lightImpact();
      _springTo(1.0);
      ref.read(playerProvider.notifier).expandPlayer();
      return;
    }
    if (velocity > 400) {
      // Fast swipe down → collapse
      HapticFeedback.lightImpact();
      _springTo(0.0);
      ref.read(playerProvider.notifier).collapsePlayer();
      return;
    }

    // ── Tight position threshold (no ambiguity between 0.4–0.6) ──
    if (_controller.value > 0.6) {
      HapticFeedback.lightImpact();
      _springTo(1.0);
      ref.read(playerProvider.notifier).expandPlayer();
    } else if (_controller.value < 0.4) {
      HapticFeedback.lightImpact();
      _springTo(0.0);
      ref.read(playerProvider.notifier).collapsePlayer();
    } else {
      // Dead zone 0.4–0.6: snap to nearest edge
      final target = _controller.value >= 0.5 ? 1.0 : 0.0;
      HapticFeedback.lightImpact();
      _springTo(target);
      if (target == 1.0) {
        ref.read(playerProvider.notifier).expandPlayer();
      } else {
        ref.read(playerProvider.notifier).collapsePlayer();
      }
    }
  }

  // ══════════════════════════════════════════════════
  //  SURFACE — now handled by PlayerMorphLayout
  //  (no _buildSurface, no _MiniLayout, no crossfade)
  // ══════════════════════════════════════════════════
}
