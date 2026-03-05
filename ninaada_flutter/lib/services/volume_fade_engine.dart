import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:ninaada_music/services/ninaada_audio_handler.dart';

// ================================================================
//  VOLUME FADE ENGINE — Layer 2
// ================================================================
//
//  Pure service. No UI, no Riverpod, no Widget dependencies.
//  Operates directly on NinaadaAudioHandler.setVolume().
//
//  Two modes:
//  1. fadeOut()  — sleep timer: current volume → 0.0 over N seconds
//  2. fadeIn()   — alarm wake-up: startVol → targetVol over N seconds
//
//  Thread-safe: only one fade operation at a time.
//  Callers receive a Future that completes when the fade finishes
//  or is cancelled.
//
//  Math:
//    step = (endVol - startVol) / durationSeconds
//    Each tick (1s): vol += step → clamp(0.0, 1.0) → handler.setVolume
// ================================================================

class VolumeFadeEngine {
  final NinaadaAudioHandler _handler;

  Timer? _fadeTimer;
  Completer<void>? _completer;
  double _currentFadeVol = 1.0;

  /// Read-only: the volume the engine is currently targeting each tick.
  double get currentFadeVolume => _currentFadeVol;

  /// Whether a fade operation is currently in progress.
  bool get isFading => _fadeTimer?.isActive ?? false;

  VolumeFadeEngine(this._handler);

  // ────────────────────────────────────────────
  //  FADE OUT (sleep timer)
  // ────────────────────────────────────────────
  /// Gradually lower volume from [startVol] to 0.0 over [durationSeconds].
  /// Returns a Future that completes when fade finishes or is cancelled.
  Future<void> fadeOut({
    required int durationSeconds,
    double? startVol,
  }) {
    cancel(); // kill any existing fade
    final sVol = (startVol ?? _handler.volume).clamp(0.0, 1.0);
    if (durationSeconds <= 0) {
      _handler.setVolume(0.0);
      return Future.value();
    }
    return _runFade(
      startVol: sVol,
      endVol: 0.0,
      durationSeconds: durationSeconds,
    );
  }

  // ────────────────────────────────────────────
  //  FADE IN (alarm wake-up / progressive volume)
  // ────────────────────────────────────────────
  /// Ramp volume from [startVol] to [targetVol] over [durationSeconds].
  Future<void> fadeIn({
    double startVol = 0.05,
    required double targetVol,
    required int durationSeconds,
  }) {
    cancel();
    final tVol = targetVol.clamp(0.0, 1.0);
    if (durationSeconds <= 0) {
      _handler.setVolume(tVol);
      return Future.value();
    }
    return _runFade(
      startVol: startVol.clamp(0.0, 1.0),
      endVol: tVol,
      durationSeconds: durationSeconds,
    );
  }

  // ────────────────────────────────────────────
  //  CORE FADE LOOP
  // ────────────────────────────────────────────
  Future<void> _runFade({
    required double startVol,
    required double endVol,
    required int durationSeconds,
  }) {
    _completer = Completer<void>();
    _currentFadeVol = startVol;
    _handler.setVolume(startVol);

    final step = (endVol - startVol) / durationSeconds;
    int elapsed = 0;

    _fadeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      elapsed++;
      if (elapsed >= durationSeconds) {
        _currentFadeVol = endVol;
        _handler.setVolume(endVol);
        timer.cancel();
        _fadeTimer = null;
        if (!_completer!.isCompleted) _completer!.complete();
        debugPrint('=== FADE ENGINE: fade complete → vol=$endVol ===');
        return;
      }
      _currentFadeVol = (startVol + step * elapsed).clamp(0.0, 1.0);
      _handler.setVolume(_currentFadeVol);
    });

    return _completer!.future;
  }

  // ────────────────────────────────────────────
  //  CANCEL + RESTORE
  // ────────────────────────────────────────────
  /// Cancel any active fade. Does NOT reset volume.
  void cancel() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete();
    }
    _completer = null;
  }

  /// Cancel fade and restore volume to 1.0.
  void cancelAndRestore() {
    cancel();
    _currentFadeVol = 1.0;
    _handler.setVolume(1.0);
  }

  /// Teardown — call from notifier dispose.
  void dispose() {
    cancel();
  }
}
