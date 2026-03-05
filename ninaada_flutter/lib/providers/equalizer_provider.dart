import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ninaada_music/providers/app_providers.dart';

// ================================================================
//  EQUALIZER PROVIDER — Phase 12: Audio Intelligence Presets
// ================================================================
//
//  Architecture:
//  ┌────────────────────────────────────────────────────────────┐
//  │  Device-Agnostic Preset Engine                             │
//  │                                                            │
//  │  Presets store NORMALIZED gains (-1.0 … +1.0) in a        │
//  │  canonical 5-point curve. On apply, the interpolation      │
//  │  helper resamples that curve onto however many bands the   │
//  │  hardware exposes (3, 5, 9, 13…) and scales by the        │
//  │  device's maxDecibels. Safe on any Android SoC.            │
//  │                                                            │
//  │  State interceptor: touching any band slider while a       │
//  │  preset is active instantly reverts to "Custom".           │
//  │                                                            │
//  │  Hive persistence: enabled, bandGains, loudnessGain,       │
//  │  activePreset, and normalizedGains are all persisted.      │
//  └────────────────────────────────────────────────────────────┘
// ================================================================

// ────────────────────────────────────────────────
//  EQ PRESET MODEL
// ────────────────────────────────────────────────

/// A device-agnostic equalizer preset.
///
/// [normalizedGains] are values between -1.0 and +1.0 representing
/// the EQ curve at canonical control points. These are interpolated
/// to match whatever band count the hardware reports, then scaled
/// by the device's max dB range.
class EqPreset {
  final String name;
  final String icon;
  final List<double> normalizedGains;

  const EqPreset({
    required this.name,
    required this.icon,
    required this.normalizedGains,
  });
}

/// Built-in presets with normalized gains (-1.0 … +1.0).
/// 5-point canonical curves.
const List<EqPreset> eqPresets = [
  EqPreset(name: 'Flat',          icon: '━',  normalizedGains: [0.0,  0.0,  0.0,  0.0,  0.0]),
  EqPreset(name: 'Bass Boost',    icon: '🔊', normalizedGains: [0.8,  0.5,  0.0, -0.2, -0.2]),
  EqPreset(name: 'Vocal Clarity', icon: '🎤', normalizedGains: [-0.3, -0.1, 0.6,  0.5,  0.1]),
  EqPreset(name: 'Acoustic',      icon: '🎸', normalizedGains: [0.3,  0.1,  0.4,  0.3,  0.2]),
  EqPreset(name: 'Gym Mode',      icon: '💪', normalizedGains: [0.8,  0.4, -0.2,  0.5,  0.7]),
  EqPreset(name: 'Classical',     icon: '🎻', normalizedGains: [0.2,  0.2,  0.2,  0.4,  0.5]),
  EqPreset(name: 'Rock',          icon: '🎸', normalizedGains: [0.6,  0.3, -0.1,  0.3,  0.6]),
  EqPreset(name: 'Pop',           icon: '🎵', normalizedGains: [-0.1, 0.2,  0.5,  0.2, -0.1]),
  EqPreset(name: 'Jazz',          icon: '🎷', normalizedGains: [0.3,  0.0,  0.1,  0.3,  0.4]),
  EqPreset(name: 'Electronic',    icon: '🎧', normalizedGains: [0.7,  0.3,  0.0,  0.3,  0.5]),
  EqPreset(name: 'Hip-Hop',       icon: '🎤', normalizedGains: [0.7,  0.5,  0.0,  0.1,  0.3]),
];

// ────────────────────────────────────────────────
//  INTERPOLATION HELPER — the heart of device-agnostic mapping
// ────────────────────────────────────────────────

/// Resamples a [source] list of N values onto [targetLength] points
/// using linear interpolation, then scales each value by [maxDb].
///
/// Example: 5 normalized preset values → 9 hardware bands.
///
/// The algorithm places source points at evenly-spaced positions
/// across [0 … targetLength-1], then for each target index finds
/// the two nearest source neighbours and lerps between them.
List<double> interpolatePreset(
  List<double> source,
  int targetLength,
  double maxDb,
) {
  if (source.isEmpty || targetLength <= 0) return List.filled(targetLength, 0.0);
  if (source.length == 1) return List.filled(targetLength, source[0] * maxDb);
  if (targetLength == 1) {
    // Average the entire source curve
    final avg = source.reduce((a, b) => a + b) / source.length;
    return [avg * maxDb];
  }

  final result = List<double>.filled(targetLength, 0.0);
  final srcLen = source.length;

  for (int i = 0; i < targetLength; i++) {
    // Map target index [0 … targetLength-1] onto source range [0 … srcLen-1]
    final srcPos = i * (srcLen - 1) / (targetLength - 1);
    final lo = srcPos.floor();
    final hi = (lo + 1).clamp(0, srcLen - 1);
    final frac = srcPos - lo;

    // Linear interpolation between neighbouring source points
    final normalized = source[lo] * (1.0 - frac) + source[hi] * frac;

    // Scale from [-1.0 … +1.0] to [-maxDb … +maxDb]
    result[i] = (normalized * maxDb).clamp(-maxDb, maxDb);
  }

  return result;
}

// ────────────────────────────────────────────────
//  STATE
// ────────────────────────────────────────────────

class EqualizerState {
  /// Whether the equalizer is enabled.
  final bool enabled;

  /// Band center frequencies in Hz (e.g., [60, 230, 910, 3600, 14000]).
  final List<int> frequencies;

  /// Current gain per band in dB (same length as [frequencies]).
  final List<double> bandGains;

  /// Min decibel value the hardware supports (e.g., -15.0).
  final double minDecibels;

  /// Max decibel value the hardware supports (e.g., +15.0).
  final double maxDecibels;

  /// Loudness enhancer target gain in dB (0.0 = off, max ~1000 mB).
  final double loudnessGain;

  /// Name of the active preset (null = "Custom" / manual).
  final String? activePreset;

  /// Whether parameters have been loaded from hardware yet.
  final bool initialized;

  const EqualizerState({
    this.enabled = true,
    this.frequencies = const [],
    this.bandGains = const [],
    this.minDecibels = -15.0,
    this.maxDecibels = 15.0,
    this.loudnessGain = 0.0,
    this.activePreset,
    this.initialized = false,
  });

  /// Whether the user is in manual (custom) mode — no preset active.
  bool get isCustom => activePreset == null;

  EqualizerState copyWith({
    bool? enabled,
    List<int>? frequencies,
    List<double>? bandGains,
    double? minDecibels,
    double? maxDecibels,
    double? loudnessGain,
    String? activePreset,
    bool clearPreset = false,
    bool? initialized,
  }) {
    return EqualizerState(
      enabled: enabled ?? this.enabled,
      frequencies: frequencies ?? this.frequencies,
      bandGains: bandGains ?? this.bandGains,
      minDecibels: minDecibels ?? this.minDecibels,
      maxDecibels: maxDecibels ?? this.maxDecibels,
      loudnessGain: loudnessGain ?? this.loudnessGain,
      activePreset: clearPreset ? null : (activePreset ?? this.activePreset),
      initialized: initialized ?? this.initialized,
    );
  }

  // ── Serialization ──

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'bandGains': bandGains,
        'loudnessGain': loudnessGain,
        'activePreset': activePreset,
      };

  factory EqualizerState.fromJson(Map<String, dynamic> json) {
    return EqualizerState(
      enabled: json['enabled'] as bool? ?? true,
      bandGains: (json['bandGains'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      loudnessGain: (json['loudnessGain'] as num?)?.toDouble() ?? 0.0,
      activePreset: json['activePreset'] as String?,
    );
  }
}

// ────────────────────────────────────────────────
//  NOTIFIER
// ────────────────────────────────────────────────

class EqualizerNotifier extends StateNotifier<EqualizerState> {
  final Ref _ref;

  EqualizerNotifier(this._ref) : super(const EqualizerState()) {
    _init();
  }

  // ════════════════════════════════════════════════
  //  INITIALIZATION
  // ════════════════════════════════════════════════

  Future<void> _init() async {
    try {
      final handler = _ref.read(audioHandlerProvider);
      final eq = handler.equalizer;

      // Fetch hardware-reported parameters
      final params = await eq.parameters;
      final bands = params.bands;
      final minDb = params.minDecibels;
      final maxDb = params.maxDecibels;

      final frequencies = bands.map((b) => b.centerFrequency.round()).toList();
      final gains = bands.map((b) => b.gain).toList();

      state = state.copyWith(
        frequencies: frequencies,
        bandGains: gains,
        minDecibels: minDb,
        maxDecibels: maxDb,
        initialized: true,
      );

      // Restore saved profile from Hive
      _restoreFromHive();

      debugPrint(
        '=== EQ: initialized (${bands.length} bands, '
        '${minDb.toStringAsFixed(1)}dB – ${maxDb.toStringAsFixed(1)}dB) ===',
      );
    } catch (e) {
      debugPrint('=== EQ: init failed: $e ===');
      // Even if hardware query fails, mark as initialized with defaults
      state = state.copyWith(initialized: true);
    }
  }

  void _restoreFromHive() {
    try {
      final box = Hive.box('settings');
      final raw = box.get('eq_profile');
      if (raw == null) return;

      final saved = EqualizerState.fromJson(
        jsonDecode(raw as String) as Map<String, dynamic>,
      );

      // Apply enabled state
      final handler = _ref.read(audioHandlerProvider);
      handler.equalizer.setEnabled(saved.enabled);
      state = state.copyWith(enabled: saved.enabled);

      // If a preset was saved, re-apply it through interpolation
      // (handles device changes / band count differences gracefully)
      if (saved.activePreset != null) {
        final preset = eqPresets.cast<EqPreset?>().firstWhere(
          (p) => p!.name == saved.activePreset,
          orElse: () => null,
        );
        if (preset != null) {
          final gains = interpolatePreset(
            preset.normalizedGains,
            state.frequencies.length,
            state.maxDecibels,
          );
          _applyAllBandGains(gains);
          state = state.copyWith(
            bandGains: gains,
            activePreset: saved.activePreset,
          );
        } else {
          // Preset name no longer exists — fall back to saved band gains
          _restoreSavedBandGains(saved);
        }
      } else {
        // Custom mode — restore raw band gains
        _restoreSavedBandGains(saved);
      }

      // Apply loudness
      if (saved.loudnessGain != 0.0) {
        _applyLoudness(saved.loudnessGain);
        state = state.copyWith(loudnessGain: saved.loudnessGain);
      }

      debugPrint('=== EQ: restored profile (preset=${saved.activePreset}) ===');
    } catch (e) {
      debugPrint('=== EQ: restore failed: $e ===');
    }
  }

  void _restoreSavedBandGains(EqualizerState saved) {
    if (saved.bandGains.length == state.frequencies.length) {
      _applyAllBandGains(saved.bandGains);
      state = state.copyWith(bandGains: saved.bandGains);
    }
  }

  Future<void> _persist() async {
    try {
      final box = Hive.box('settings');
      await box.put('eq_profile', jsonEncode(state.toJson()));
    } catch (e) {
      debugPrint('=== EQ: persist failed: $e ===');
    }
  }

  // ════════════════════════════════════════════════
  //  PUBLIC API
  // ════════════════════════════════════════════════

  /// Toggle the entire equalizer on/off.
  void setEnabled(bool enabled) {
    final handler = _ref.read(audioHandlerProvider);
    handler.equalizer.setEnabled(enabled);
    state = state.copyWith(enabled: enabled);
    _persist();
  }

  /// Set a specific band's gain in dB.
  ///
  /// **Custom Fallback Trigger**: If a preset is active, touching
  /// any individual slider instantly reverts to "Custom" mode.
  void setBandGain(int bandIndex, double gain) {
    if (bandIndex < 0 || bandIndex >= state.bandGains.length) return;

    final clamped = gain.clamp(state.minDecibels, state.maxDecibels);
    _setBandGainHardware(bandIndex, clamped);

    final updated = List<double>.from(state.bandGains);
    updated[bandIndex] = clamped;
    // ── STATE INTERCEPTOR: revert to Custom on manual touch ──
    state = state.copyWith(bandGains: updated, clearPreset: true);
    _persist();
  }

  /// Apply a named preset using the device-agnostic interpolation engine.
  ///
  /// The preset's 5 normalized control points are resampled onto the
  /// hardware's actual band count and scaled by maxDecibels.
  void applyPreset(String name) {
    final preset = eqPresets.cast<EqPreset?>().firstWhere(
      (p) => p!.name == name,
      orElse: () => null,
    );
    if (preset == null) return;

    final gains = interpolatePreset(
      preset.normalizedGains,
      state.frequencies.length,
      state.maxDecibels,
    );

    _applyAllBandGains(gains);
    state = state.copyWith(bandGains: gains, activePreset: name);
    _persist();
  }

  /// Reset all bands to 0 dB (flat).
  void resetFlat() {
    applyPreset('Flat');
  }

  /// Set the loudness enhancer target gain in dB (0.0 = off).
  /// Range typically 0 to ~10 dB (mapped to 0–1000 mB internally).
  void setLoudness(double gainDb) {
    final clamped = gainDb.clamp(0.0, 10.0);
    _applyLoudness(clamped);
    state = state.copyWith(loudnessGain: clamped);
    _persist();
  }

  // ════════════════════════════════════════════════
  //  HARDWARE WRITE HELPERS
  // ════════════════════════════════════════════════

  void _setBandGainHardware(int index, double gain) {
    try {
      final handler = _ref.read(audioHandlerProvider);
      handler.equalizer.parameters.then((params) {
        if (index < params.bands.length) {
          params.bands[index].setGain(gain);
        }
      });
    } catch (e) {
      debugPrint('=== EQ: setBandGain($index, $gain) failed: $e ===');
    }
  }

  void _applyAllBandGains(List<double> gains) {
    try {
      final handler = _ref.read(audioHandlerProvider);
      handler.equalizer.parameters.then((params) {
        for (int i = 0; i < gains.length && i < params.bands.length; i++) {
          params.bands[i].setGain(gains[i]);
        }
      });
    } catch (e) {
      debugPrint('=== EQ: applyAllBandGains failed: $e ===');
    }
  }

  void _applyLoudness(double gainDb) {
    try {
      final handler = _ref.read(audioHandlerProvider);
      // AndroidLoudnessEnhancer.setTargetGain expects millibels (mB)
      // 1 dB = 100 mB → multiply by 100
      handler.loudnessEnhancer.setTargetGain(gainDb * 100);
    } catch (e) {
      debugPrint('=== EQ: setLoudness($gainDb) failed: $e ===');
    }
  }
}

// ────────────────────────────────────────────────
//  PROVIDER
// ────────────────────────────────────────────────

final equalizerProvider =
    StateNotifierProvider<EqualizerNotifier, EqualizerState>(
  (ref) => EqualizerNotifier(ref),
);
