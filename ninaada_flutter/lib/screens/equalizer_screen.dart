import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/providers/equalizer_provider.dart';

// ================================================================
//  EQUALIZER SCREEN — Phase 12: Audio Intelligence Presets
// ================================================================
//
//  Layout:
//  ┌────────────────────────────────────────────────────────────┐
//  │  ≡ Equalizer                            [ON/OFF]          │
//  ├────────────────────────────────────────────────────────────┤
//  │  Premium preset pills (horizontal scroll):                │
//  │  [━ Flat] [🔊 Bass Boost] [🎤 Vocal] [💪 Gym] [Custom]  │
//  ├────────────────────────────────────────────────────────────┤
//  │  Band sliders animate to new positions on preset tap      │
//  │  Manual slider touch → reverts to "Custom" instantly      │
//  ├────────────────────────────────────────────────────────────┤
//  │  Loudness Enhancer slider                                 │
//  └────────────────────────────────────────────────────────────┘
//
//  Device-Agnostic: Presets use normalized -1.0…+1.0 gains
//  interpolated to match any hardware band count (3, 5, 9, 13…)
// ================================================================

/// Show the equalizer as a modal bottom sheet.
void showEqualizerModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: NinaadaColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const EqualizerSheet(),
  );
}

class EqualizerSheet extends ConsumerWidget {
  const EqualizerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(equalizerProvider);

    if (!eq.initialized) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(color: NinaadaColors.primaryLight),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ──
          Container(
            width: 32,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // ── Header: title + on/off toggle ──
          Row(
            children: [
              const Icon(Icons.equalizer, color: NinaadaColors.primaryLight, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Equalizer',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: eq.enabled,
                activeColor: NinaadaColors.primaryLight,
                onChanged: (v) =>
                    ref.read(equalizerProvider.notifier).setEnabled(v),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Premium preset chips ──
          _PresetChips(eq: eq),
          const SizedBox(height: 20),

          // ── Band sliders (animated) ──
          if (eq.frequencies.isNotEmpty)
            Opacity(
              opacity: eq.enabled ? 1.0 : 0.35,
              child: AbsorbPointer(
                absorbing: !eq.enabled,
                child: _BandSliders(eq: eq),
              ),
            ),

          const SizedBox(height: 16),
          const Divider(color: NinaadaColors.border, height: 1),
          const SizedBox(height: 16),

          // ── Loudness enhancer ──
          Opacity(
            opacity: eq.enabled ? 1.0 : 0.35,
            child: AbsorbPointer(
              absorbing: !eq.enabled,
              child: _LoudnessSlider(eq: eq),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════
//  PREMIUM PRESET CHIPS — horizontal scrolling pills
// ════════════════════════════════════════════════

class _PresetChips extends ConsumerWidget {
  final EqualizerState eq;
  const _PresetChips({required this.eq});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // All named presets + a "Custom" entry at the end
    final presetCount = eqPresets.length + 1;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: presetCount,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          // Last item is the "Custom" chip
          if (index == eqPresets.length) {
            final isActive = eq.isCustom;
            return _PresetPill(
              label: 'Custom',
              icon: '✎',
              isActive: isActive,
              enabled: eq.enabled,
              onTap: null, // Custom is a state, not selectable
            );
          }

          final preset = eqPresets[index];
          final isActive = eq.activePreset == preset.name;

          return _PresetPill(
            label: preset.name,
            icon: preset.icon,
            isActive: isActive,
            enabled: eq.enabled,
            onTap: eq.enabled
                ? () => ref.read(equalizerProvider.notifier).applyPreset(preset.name)
                : null,
          );
        },
      ),
    );
  }
}

/// A single premium preset pill with animated glow effect.
class _PresetPill extends StatelessWidget {
  final String label;
  final String icon;
  final bool isActive;
  final bool enabled;
  final VoidCallback? onTap;

  const _PresetPill({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? NinaadaColors.primary.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? NinaadaColors.primaryLight.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.08),
            width: isActive ? 1.5 : 1.0,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: NinaadaColors.primary.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? NinaadaColors.primaryLight
                    : Colors.white.withValues(alpha: enabled ? 0.6 : 0.3),
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════
//  BAND SLIDERS — vertical animated sliders for each frequency
// ════════════════════════════════════════════════

class _BandSliders extends ConsumerWidget {
  final EqualizerState eq;
  const _BandSliders({required this.eq});

  String _formatFreq(int hz) {
    if (hz >= 1000) {
      final khz = hz / 1000;
      return khz == khz.roundToDouble()
          ? '${khz.round()}k'
          : '${khz.toStringAsFixed(1)}k';
    }
    return '$hz';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 220,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // dB labels on the left
          SizedBox(
            width: 32,
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '+${eq.maxDecibels.round()}',
                  style: _labelStyle,
                ),
                Text('0', style: _labelStyle),
                Text(
                  '${eq.minDecibels.round()}',
                  style: _labelStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),

          // Sliders — one per hardware band
          ...List.generate(eq.frequencies.length, (i) {
            return Expanded(
              child: Column(
                children: [
                  // Vertical slider with animated thumb position
                  SizedBox(
                    height: 180,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14),
                          activeTrackColor: NinaadaColors.primaryLight,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.08),
                          thumbColor: NinaadaColors.primaryLight,
                          overlayColor:
                              NinaadaColors.primary.withValues(alpha: 0.15),
                        ),
                        child: Slider(
                          value: eq.bandGains[i],
                          min: eq.minDecibels,
                          max: eq.maxDecibels,
                          onChanged: (v) => ref
                              .read(equalizerProvider.notifier)
                              .setBandGain(i, v),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Frequency label
                  Text(
                    _formatFreq(eq.frequencies[i]),
                    style: const TextStyle(
                      color: Color(0xFF888888),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  // Current gain — animates on preset change
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      '${eq.bandGains[i] >= 0 ? "+" : ""}${eq.bandGains[i].toStringAsFixed(1)}',
                      key: ValueKey(eq.bandGains[i].toStringAsFixed(1)),
                      style: TextStyle(
                        color: eq.bandGains[i] == 0
                            ? const Color(0xFF555555)
                            : NinaadaColors.primaryLight,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  static const _labelStyle = TextStyle(
    color: Color(0xFF666666),
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );
}

// ════════════════════════════════════════════════
//  LOUDNESS ENHANCER SLIDER
// ════════════════════════════════════════════════

class _LoudnessSlider extends ConsumerWidget {
  final EqualizerState eq;
  const _LoudnessSlider({required this.eq});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.volume_up, color: Color(0xFF888888), size: 18),
            const SizedBox(width: 8),
            const Text(
              'Loudness Enhancer',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              eq.loudnessGain > 0
                  ? '+${eq.loudnessGain.toStringAsFixed(1)} dB'
                  : 'Off',
              style: TextStyle(
                color: eq.loudnessGain > 0
                    ? NinaadaColors.primaryLight
                    : const Color(0xFF666666),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape:
                const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape:
                const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: NinaadaColors.primaryLight,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            thumbColor: NinaadaColors.primaryLight,
            overlayColor: NinaadaColors.primary.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: eq.loudnessGain,
            min: 0.0,
            max: 10.0,
            onChanged: (v) =>
                ref.read(equalizerProvider.notifier).setLoudness(v),
          ),
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('0 dB', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
            Text('+10 dB', style: TextStyle(color: Color(0xFF555555), fontSize: 10)),
          ],
        ),
      ],
    );
  }
}
