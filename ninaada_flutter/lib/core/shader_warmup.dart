import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════
//  SHADER / PIPELINE WARMUP — Phase 7, Step 3
// ════════════════════════════════════════════════════════════════
//
//  Pre-exercises the GPU pipeline paths used by the player:
//    • LinearGradient rendering
//    • BackdropFilter blur (sigma 20)
//    • Rounded rect clipping
//    • Box shadow
//
//  On Impeller (default since Flutter 3.10), this warms up
//  the Metal/Vulkan PSO cache. On Skia, it compiles the GL shaders.
//
//  Called once during app startup — draws to an offscreen canvas
//  so there is zero visual artifact. Typically completes in <10ms.
// ════════════════════════════════════════════════════════════════

class NinaadaShaderWarmup {
  static bool _warmedUp = false;

  /// Run warmup once. Safe to call multiple times (no-op after first).
  static Future<void> execute() async {
    if (_warmedUp) return;
    _warmedUp = true;

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 100, 100));

      // 1. Gradient paint (exercises gradient shader compilation)
      final gradientPaint = Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF7C4DFF), Color(0xFF0B0F1A)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
      canvas.drawRect(const Rect.fromLTWH(0, 0, 100, 100), gradientPaint);

      // 2. Rounded rect clip (exercises clip path pipeline)
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(
        const Rect.fromLTWH(10, 10, 80, 80),
        const Radius.circular(18),
      ));
      canvas.drawRect(
        const Rect.fromLTWH(10, 10, 80, 80),
        Paint()..color = const Color(0xFF333333),
      );
      canvas.restore();

      // 3. Box shadow (exercises shadow paint)
      final shadowPaint = Paint()
        ..color = const Color(0x4D000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(20, 20, 60, 60),
          const Radius.circular(18),
        ),
        shadowPaint,
      );

      // 4. Image filter blur (exercises BackdropFilter pipeline)
      canvas.saveLayer(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      );
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 100, 100),
        Paint()..color = const Color(0x80000000),
      );
      canvas.restore();

      // Finalize — this forces GPU pipeline compilation
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      image.dispose();
      picture.dispose();

      debugPrint('=== NINAADA: shader warmup complete ===');
    } catch (e) {
      debugPrint('=== NINAADA: shader warmup failed (non-fatal): $e ===');
    }
  }
}
