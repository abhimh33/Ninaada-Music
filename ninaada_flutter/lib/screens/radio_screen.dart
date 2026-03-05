import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/data/models.dart';
import 'package:ninaada_music/data/radio_data.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/sleep_alarm_provider.dart';

import 'package:ninaada_music/widgets/sleep_timer_modal.dart';
import 'package:ninaada_music/screens/equalizer_screen.dart';

/// Radio screen — header with radio-tower icon + LIVE badge,
/// NowPlaying banner, Quick Play horizontal list, expandable category cards
/// Matches RN radio tab pixel-perfect

// ─── State ─────────────────────────────────────────
// Active station + loading now live in PlayerState (playbackMode / activeRadioStation / radioLoading).
// Only the expanded-category toggle remains local.
final _expandedCategoryProvider = StateProvider<String?>((ref) => null);

class RadioScreen extends ConsumerWidget {
  const RadioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = ref.watch(playerProvider);
    final active = ps.isRadioMode ? ps.activeRadioStation : null;
    final loading = ps.radioLoading;

    return CustomScrollView(
      slivers: [
        // Header gradient — scrolls with content
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 18, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1C1336), Color(0xFF1A1333), Color(0xFF0B0F1A)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, 0.55, 1],
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.cell_tower, size: 22, color: Colors.white),
                          const SizedBox(width: 8),
                          const Text('Radio Stations', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Live streaming · ${radioCategories.length} categories',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Now Playing Banner
        if (active != null)
          SliverToBoxAdapter(
            child: _NowPlayingBanner(station: active, loading: loading),
          ),

        // Quick Play
        const SliverToBoxAdapter(child: _QuickPlaySection()),

        // All Categories
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _CategoryCard(category: radioCategories[i]),
            childCount: radioCategories.length,
          ),
        ),

        // Footer
        SliverToBoxAdapter(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 30, bottom: 160),
              child: Column(
                children: [
                  const Icon(Icons.cell_tower, size: 28, color: Color(0xFF333333)),
                  const SizedBox(height: 8),
                  const Text(
                    'All streams are sourced from public internet radio stations',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF444444), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Hero Now Playing Card ─────────────────────────
class _NowPlayingBanner extends ConsumerWidget {
  final RadioStation station;
  final bool loading;
  const _NowPlayingBanner({required this.station, required this.loading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(playerProvider.select((p) => p.isPlaying));

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: const Color(0xFF1A1228),
              border: Border.all(
                color: Colors.white.withOpacity(0.06),
                width: 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ── Top row: "Now Playing" label + LIVE badge ──
                  Row(
                    children: [
                      Icon(Icons.cell_tower, size: 14, color: Colors.white.withOpacity(0.6)),
                      const SizedBox(width: 6),
                      Text(
                        'NOW PLAYING',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                      const Spacer(),
                      if (!loading) const _PulsingLiveBadge(compact: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // ── Main content row ──
                  Row(
                    children: [
                      // Large emoji with glow backdrop
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: NinaadaColors.primary.withOpacity(0.10),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.06),
                            width: 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(station.emoji, style: const TextStyle(fontSize: 28)),
                      ),
                      const SizedBox(width: 14),
                      // Station name + status
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              station.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                            ),
                            const SizedBox(height: 4),
                            if (loading)
                              Row(
                                children: [
                                  SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white.withOpacity(0.6),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Connecting...',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              )
                            else
                              // Waveform + EQ + Sleep — constrained to fit
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  children: [
                                    const _WaveformBars(),
                                    const SizedBox(width: 4),
                                    _RadioEQButton(),
                                    const SizedBox(width: 3),
                                    _RadioSleepButton(),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Controls
                      const SizedBox(width: 8),
                      // Play/Pause
                      GestureDetector(
                        onTap: () => ref.read(playerProvider.notifier).playRadio(station),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.12),
                            border: Border.all(color: Colors.white.withOpacity(0.15)),
                          ),
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Stop
                      GestureDetector(
                        onTap: () => ref.read(playerProvider.notifier).stopRadio(),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFC94A4A).withOpacity(0.12),
                            border: Border.all(color: const Color(0xFFC94A4A).withOpacity(0.20)),
                          ),
                          child: const Icon(Icons.stop_rounded, color: Color(0xFFC94A4A), size: 22),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Quick Play Section ────────────────────────────
class _QuickPlaySection extends ConsumerWidget {
  const _QuickPlaySection();

  /// Category label lookup for quick play picks.
  static const _defaultCatLabels = ['AIR', 'Kannada', 'Hindi', 'English', 'Kannada', 'Tamil', 'Malayalam', 'Hindi'];

  /// Build the ordered station list — pin active station to index 0.
  static List<RadioStation> _orderedPicks(RadioStation? active) {
    final base = quickPlayStations;
    if (active == null) return base;
    // If active is already in the list, move it to front
    final idx = base.indexWhere((s) => s.id == active.id);
    if (idx > 0) {
      return [base[idx], ...base.sublist(0, idx), ...base.sublist(idx + 1)];
    }
    // If active is NOT in the default list (came from a category), prepend it
    if (idx < 0) {
      return [active, ...base];
    }
    return base; // idx == 0, already first
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ps = ref.watch(playerProvider);
    final active = ps.isRadioMode ? ps.activeRadioStation : null;
    final picks = _orderedPicks(active);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Text('Quick Play', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: picks.length,
            itemBuilder: (context, index) {
              final s = picks[index];
              final isActive = active?.id == s.id;
              // Find original index for cat label (best-effort)
              final origIdx = quickPlayStations.indexWhere((qs) => qs.id == s.id);
              final catLabel = origIdx >= 0 && origIdx < _defaultCatLabels.length
                  ? _defaultCatLabels[origIdx]
                  : '';
              return GestureDetector(
                onTap: () => ref.read(playerProvider.notifier).playRadio(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  width: 100,
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF1A1228) : NinaadaColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isActive ? NinaadaColors.primary.withOpacity(0.35) : NinaadaColors.border,
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(s.emoji, style: const TextStyle(fontSize: 28)),
                          const SizedBox(height: 6),
                          Text(
                            s.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive ? NinaadaColors.primary : const Color(0xFFCCCCCC),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            catLabel,
                            style: const TextStyle(color: Color(0xFF666666), fontSize: 9),
                          ),
                        ],
                      ),
                      if (isActive)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC94A4A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Category Card ─────────────────────────────────
class _CategoryCard extends ConsumerWidget {
  final RadioCategory category;
  const _CategoryCard({required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(_expandedCategoryProvider) == category.id;
    final ps = ref.watch(playerProvider);
    final active = ps.isRadioMode ? ps.activeRadioStation : null;
    final loading = ps.radioLoading;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NinaadaColors.surfaceLight),
      ),
      child: Column(
        children: [
          // Category header
          GestureDetector(
            onTap: () {
              final cur = ref.read(_expandedCategoryProvider);
              ref.read(_expandedCategoryProvider.notifier).state = cur == category.id ? null : category.id;
            },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: [category.color.withOpacity(0.19), category.color.withOpacity(0.03)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: category.color.withOpacity(0.15),
                    ),
                    child: Icon(category.icon, size: 22, color: category.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(category.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(
                          '${category.stations.length} stations · ${category.subtitle}',
                          style: const TextStyle(color: Color(0xFF888888), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.keyboard_arrow_down, size: 20, color: Color(0xFF888888)),
                  ),
                ],
              ),
            ),
          ),

          // Station list (expanded)
          if (expanded) ...[
            for (final station in category.stations)
              _StationRow(station: station, isActive: active?.id == station.id, loading: loading && active?.id == station.id),
          ],
        ],
      ),
    );
  }
}

// ─── Station Row ───────────────────────────────────
class _StationRow extends ConsumerWidget {
  final RadioStation station;
  final bool isActive;
  final bool loading;
  const _StationRow({required this.station, required this.isActive, required this.loading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => ref.read(playerProvider.notifier).playRadio(station),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isActive ? NinaadaColors.primary.withOpacity(0.08) : Colors.transparent,
          border: const Border(top: BorderSide(color: NinaadaColors.surfaceLight)),
        ),
        child: Row(
          children: [
            // Station icon — glow when active
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isActive ? NinaadaColors.primary.withOpacity(0.12) : NinaadaColors.surfaceLight,
              ),
              alignment: Alignment.center,
              child: Text(station.emoji, style: const TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                station.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isActive ? NinaadaColors.primary : const Color(0xFFCCCCCC),
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            if (isActive)
              loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: NinaadaColors.primary))
                  : const _EqualizerBars()
            else
              const Icon(Icons.play_circle, size: 28, color: Color(0xFF555555)),
          ],
        ),
      ),
    );
  }
}

// ─── Equalizer Animation (station rows) ────────────
class _EqualizerBars extends StatefulWidget {
  const _EqualizerBars();

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return SizedBox(
          width: 28,
          height: 18,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              // Phase-offset sinusoidal for organic movement
              final phase = i * 0.8;
              final h = 0.35 + 0.65 * ((math.sin((_ctrl.value * 2 * math.pi) + phase) + 1) / 2);
              return Container(
                width: 3,
                height: 18 * h,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: NinaadaColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

// ─── Waveform Bars (hero card) ─────────────────────
class _WaveformBars extends StatefulWidget {
  const _WaveformBars();

  @override
  State<_WaveformBars> createState() => _WaveformBarsState();
}

class _WaveformBarsState extends State<_WaveformBars> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return SizedBox(
          height: 20,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(5, (i) {
              final phase = i * 1.1;
              final h = 0.25 + 0.75 * ((math.sin((_ctrl.value * 2 * math.pi) + phase) + 1) / 2);
              return Container(
                width: 3,
                height: 20 * h,
                margin: const EdgeInsets.only(right: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  gradient: LinearGradient(
                    colors: [NinaadaColors.primary, NinaadaColors.primaryLight],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

// ─── Radio EQ Button ─────────────────────────────
class _RadioEQButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eqOn = ref.watch(eqProvider);
    final accent = eqOn ? NinaadaColors.primary : const Color(0xFF666666);

    return GestureDetector(
      onTap: () {
        ref.read(eqProvider.notifier).state = !eqOn;
        showEqualizerModal(context);
      },
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: eqOn ? NinaadaColors.primary.withOpacity(0.12) : Colors.white.withOpacity(0.06),
          border: Border.all(
            color: eqOn ? NinaadaColors.primary.withOpacity(0.3) : Colors.white.withOpacity(0.1),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.equalizer_rounded,
              size: 13,
              color: accent,
            ),
            const SizedBox(width: 4),
            Text(
              'EQ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Radio Sleep Button (matches hero card theme) ──
class _RadioSleepButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(sleepAlarmProvider);
    final isActive = sleep.sleepActive;

    return GestureDetector(
      onTap: () => showSleepTimerModal(context),
      child: Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(11),
          color: isActive
              ? NinaadaColors.primary.withOpacity(0.20)
              : Colors.white.withOpacity(0.08),
          border: Border.all(
            color: isActive
                ? NinaadaColors.primary.withOpacity(0.40)
                : Colors.white.withOpacity(0.12),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 12,
              color: isActive ? NinaadaColors.primaryLight : Colors.white.withOpacity(0.5),
            ),
            if (isActive) ...[
              const SizedBox(width: 4),
              Text(
                fmt(sleep.sleepRemaining),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: NinaadaColors.primaryLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Pulsing LIVE Badge ────────────────────────────
class _PulsingLiveBadge extends StatefulWidget {
  final bool compact;
  const _PulsingLiveBadge({this.compact = false});

  @override
  State<_PulsingLiveBadge> createState() => _PulsingLiveBadgeState();
}

class _PulsingLiveBadgeState extends State<_PulsingLiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 6 : 8,
            vertical: widget.compact ? 2 : 3,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFC94A4A).withOpacity(0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFC94A4A).withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(
                    const Color(0xFFC94A4A).withOpacity(0.4),
                    const Color(0xFFC94A4A),
                    _pulse.value,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: widget.compact ? 8 : 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Helper functions ──────────────────────────────
// All radio playback goes through PlayerNotifier.playRadio() / stopRadio().
