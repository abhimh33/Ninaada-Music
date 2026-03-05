import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/helpers.dart';
import 'package:ninaada_music/data/models.dart';

// ════════════════════════════════════════════════════════════════
//  DYNAMIC MEDIA-THEMING ENGINE
// ════════════════════════════════════════════════════════════════
//
//  Pipeline (Spotify-grade):
//
//  Album image URL
//      │
//      ▼  (Check per-ID cache → hit? return instantly)
//  ┌─────────────────────────┐
//  │  PaletteExtractor       │   Off main thread via PaletteGenerator
//  │  Extract dominant,      │   (uses Flutter Isolate internally)
//  │  secondary, muted       │
//  └─────────┬───────────────┘
//            │
//            ▼
//  ┌─────────────────────────┐
//  │  ColorRefiner           │   Saturation reduction (–15%-25%)
//  │  Luminance clamping     │   Brightness safe range [0.08–0.22]
//  │  Accent generation      │   Contrast validation
//  └─────────┬───────────────┘
//            │
//            ▼
//  ┌─────────────────────────┐
//  │  MediaPalette           │   dominant, secondary, muted, accent
//  │  + layered gradient     │   3-stop gradient (top→mid→bottom)
//  │  + overlay blending     │   10-15% dark overlay for readability
//  └─────────┬───────────────┘
//            │
//            ▼
//  ┌───────────────────────────────────────────────┐
//  │  MediaThemeNotifier  (Riverpod)               │
//  │  Reactive state — propagates to ALL screens   │
//  │  Synchronized with AudioService callbacks     │
//  └───────────────────────────────────────────────┘
//            │
//            ▼
//  ╔═════════════════════════════════════════════════╗
//  ║  AnimatedThemeBackground                        ║
//  ║  Smooth 400ms gradient interpolation            ║
//  ║  No full widget tree rebuild                    ║
//  ║  Zero frame drops — AnimatedContainer only      ║
//  ╚═════════════════════════════════════════════════╝
//
// ════════════════════════════════════════════════════════════════

// ────────────────────────────────────────────────
//  1. MEDIA PALETTE — the refined color output
// ────────────────────────────────────────────────

class MediaPalette {
  /// Refined dominant color (top of gradient)
  final Color dominant;

  /// Refined secondary/complementary color (mid gradient)
  final Color secondary;

  /// Deep dark base tone (bottom of gradient)
  final Color muted;

  /// Vibrant accent for buttons, progress bars, highlights
  final Color accent;

  /// Pre-computed 3-stop gradient colors
  final List<Color> gradient;

  /// Overlay-blended gradient (adds 12% black for readability)
  final List<Color> overlayGradient;

  /// Adaptive text color (white or near-white with correct contrast)
  final Color textPrimary;
  final Color textSecondary;

  /// For mini-player tinted gradient
  final List<Color> miniPlayerGradient;

  const MediaPalette({
    required this.dominant,
    required this.secondary,
    required this.muted,
    required this.accent,
    required this.gradient,
    required this.overlayGradient,
    required this.textPrimary,
    required this.textSecondary,
    required this.miniPlayerGradient,
  });

  /// Default fallback palette (deep purple / dark theme)
  static const fallback = MediaPalette(
    dominant: Color(0xFF1A1A2E),
    secondary: Color(0xFF16213E),
    muted: Color(0xFF0B0F1A),
    accent: Color(0xFF8B5CF6),
    gradient: [Color(0xFF1A1A2E), Color(0xFF10141F), Color(0xFF0B0F1A)],
    overlayGradient: [Color(0xCC1A1A2E), Color(0xCC12121F), Color(0xE60A0A14)],
    textPrimary: Colors.white,
    textSecondary: Color(0xFFAAAAAA),
    miniPlayerGradient: [Color(0xEB8B5CF6), Color(0xF26D28D9)],
  );

  /// Linearly interpolate between two palettes for smooth transitions
  static MediaPalette lerp(MediaPalette a, MediaPalette b, double t) {
    return MediaPalette(
      dominant: Color.lerp(a.dominant, b.dominant, t)!,
      secondary: Color.lerp(a.secondary, b.secondary, t)!,
      muted: Color.lerp(a.muted, b.muted, t)!,
      accent: Color.lerp(a.accent, b.accent, t)!,
      gradient: [
        Color.lerp(a.gradient[0], b.gradient[0], t)!,
        Color.lerp(a.gradient[1], b.gradient[1], t)!,
        Color.lerp(a.gradient[2], b.gradient[2], t)!,
      ],
      overlayGradient: [
        Color.lerp(a.overlayGradient[0], b.overlayGradient[0], t)!,
        Color.lerp(a.overlayGradient[1], b.overlayGradient[1], t)!,
        Color.lerp(a.overlayGradient[2], b.overlayGradient[2], t)!,
      ],
      textPrimary: Color.lerp(a.textPrimary, b.textPrimary, t)!,
      textSecondary: Color.lerp(a.textSecondary, b.textSecondary, t)!,
      miniPlayerGradient: [
        Color.lerp(a.miniPlayerGradient[0], b.miniPlayerGradient[0], t)!,
        Color.lerp(a.miniPlayerGradient[1], b.miniPlayerGradient[1], t)!,
      ],
    );
  }
}

// ────────────────────────────────────────────────
//  2. COLOR REFINER — Spotify-style pipeline
// ────────────────────────────────────────────────

class ColorRefiner {
  ColorRefiner._();

  /// Master refinement: raw extracted → production-quality palette
  static MediaPalette refine({
    required Color rawDominant,
    Color? rawSecondary,
    Color? rawMuted,
  }) {
    // Step 1: Light desaturation (–10% to –15%) to soften neon/harsh colors
    //          but keep them vibrant enough to be visible
    final dominant = _desaturate(rawDominant, 0.10);
    final secondary = _desaturate(rawSecondary ?? _shiftHue(rawDominant, 30), 0.15);
    final muted = _desaturate(rawMuted ?? _darken(rawDominant, 0.35), 0.20);

    // Step 2: Clamp luminance — wider range so colors are actually visible
    //   Dominant: bright enough to tint the top of the screen
    //   Secondary: mid-range for body
    //   Muted: dark base for bottom
    final domClamped = _clampLuminance(dominant, 0.15, 0.45);
    final secClamped = _clampLuminance(secondary, 0.10, 0.32);
    final mutClamped = _clampLuminance(muted, 0.04, 0.14);

    // Step 3: Generate accent (boosted saturation, mid-lightness)
    final accent = _generateAccent(rawDominant);

    // Step 4: Build layered gradient
    //   Top: dominant (vibrant, visible color from the artwork)
    //   Middle: blend of dominant + secondary
    //   Bottom: darkened muted base
    final gradMid = Color.lerp(domClamped, secClamped, 0.45)!;
    final gradBottom = _darken(mutClamped, 0.06);
    final gradient = [domClamped, gradMid, gradBottom];

    // Step 5: Apply 12% dark overlay for text readability
    final overlayGradient = gradient.map((c) {
      return Color.lerp(c, Colors.black, 0.12)!;
    }).toList();

    // Step 6: Adaptive text colors with contrast checking
    final textPrimary = _contrastSafe(domClamped, Colors.white);
    final textSecondary = _contrastSafe(
      domClamped,
      const Color(0xFFAAAAAA),
      fallback: const Color(0xFFCCCCCC),
    );

    // Step 7: Mini-player gradient (accent-tinted, semi-transparent)
    final miniGrad = [
      accent.withValues(alpha: 0.82),
      _darken(accent, 0.25).withValues(alpha: 0.88),
    ];

    return MediaPalette(
      dominant: domClamped,
      secondary: secClamped,
      muted: mutClamped,
      accent: accent,
      gradient: gradient,
      overlayGradient: overlayGradient,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      miniPlayerGradient: miniGrad,
    );
  }

  // ── Desaturate by factor (0.0=no change, 1.0=fully grey) ──
  static Color _desaturate(Color c, double factor) {
    final hsl = HSLColor.fromColor(c);
    final newSat = (hsl.saturation * (1.0 - factor)).clamp(0.0, 1.0);
    return hsl.withSaturation(newSat).toColor();
  }

  // ── Clamp lightness to [min, max] range ──
  static Color _clampLuminance(Color c, double minL, double maxL) {
    final hsl = HSLColor.fromColor(c);
    final clamped = hsl.lightness.clamp(minL, maxL);
    return hsl.withLightness(clamped).toColor();
  }

  // ── Darken a color by factor ──
  static Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    final newL = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(newL).toColor();
  }

  // ── Shift hue by degrees ──
  static Color _shiftHue(Color c, double degrees) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withHue((hsl.hue + degrees) % 360).toColor();
  }

  // ── Generate accent (moderate saturation, balanced lightness) ──
  // Toned down from hyper-vibrant to elegant-visible.
  static Color _generateAccent(Color raw) {
    final hsl = HSLColor.fromColor(raw);
    // Saturation 40-60% (was 55-80%), lightness 45-55% (was 50-62%)
    final sat = hsl.saturation.clamp(0.40, 0.60);
    final light = hsl.lightness.clamp(0.45, 0.55);
    return hsl.withSaturation(sat).withLightness(light).toColor();
  }

  // ── Ensure text color has sufficient contrast against bg ──
  static Color _contrastSafe(Color bg, Color text, {Color? fallback}) {
    final ratio = _contrastRatio(bg, text);
    if (ratio >= 4.5) return text;
    // If contrast is poor, lighten the text
    if (fallback != null) return fallback;
    return Colors.white;
  }

  // ── WCAG contrast ratio ──
  static double _contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }

  static double _relativeLuminance(Color c) {
    double linearize(double v) {
      return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055).clamp(0, 1);
    }
    // pow(x, 2.4) approximation
    double srgbToLinear(double v) {
      if (v <= 0.03928) return v / 12.92;
      final base = (v + 0.055) / 1.055;
      // x^2.4 ≈ x^2 * x^0.4
      return base * base * _pow04(base);
    }

    final r = srgbToLinear(c.r);
    final g = srgbToLinear(c.g);
    final b = srgbToLinear(c.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// Approximate x^0.4 without dart:math pow
  static double _pow04(double x) {
    // x^0.4 = x^(2/5) ≈ sqrt(x) * sqrt(sqrt(x)) / sqrt(sqrt(sqrt(x)))
    // Simpler: use repeated sqrt. x^0.5 = sqrt(x), x^0.25 = sqrt(sqrt(x))
    // x^0.4 ≈ x^0.5 * x^(-0.1) ≈ sqrt(x) / x^0.1
    // Even simpler approximation good enough for contrast:
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    // Newton's method for x^0.4: use 3 iterations starting from x
    double result = x;
    // f(y) = y^2.5 - x, f'(y) = 2.5*y^1.5
    // We want y = x^0.4, so y^2.5 = x
    for (int i = 0; i < 4; i++) {
      final y25 = result * result * _sqrt(result); // y^2.5
      final dy = 2.5 * result * _sqrt(result);      // 2.5*y^1.5
      if (dy.abs() < 1e-10) break;
      result = result - (y25 - x) / dy;
      if (result < 0) result = 0;
    }
    return result.clamp(0.0, 1.0);
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    // Babylonian method
    double guess = x * 0.5;
    for (int i = 0; i < 8; i++) {
      guess = (guess + x / guess) * 0.5;
    }
    return guess;
  }
}

// ────────────────────────────────────────────────
//  3. ISOLATE COLOR QUANTIZER — Off-main-thread
// ────────────────────────────────────────────────
//
//  Why: PaletteGenerator runs color quantization on the UI thread,
//  causing jank during track transitions. This module moves the heavy
//  pixel-processing into a background isolate via compute().
//
//  Pipeline:
//    Main thread:  resolve image → resize to 80×80 → extract RGBA bytes
//    Isolate:      median-cut quantization → score buckets → top 3 colors
//    Main thread:  ColorRefiner.refine() → cache → emit
//

/// Fallback RGB triples for [dominant, secondary, muted]
const _kFallbackRgb = [26, 26, 46, 22, 33, 62, 10, 10, 20];

/// Top-level function for compute() — MUST be top-level.
/// Input:  RGBA pixel bytes (80×80 = 25 600 bytes).
/// Output: [domR,domG,domB, secR,secG,secB, mutR,mutG,mutB]
List<int> _quantizePixels(Uint8List rgbaBytes) {
  final pixelCount = rgbaBytes.length ~/ 4;
  if (pixelCount == 0) return _kFallbackRgb;

  // ── Step 1: Collect valid pixels, skip transparent / near-black / near-white
  final pixels = <int>[]; // packed 0xRRGGBB
  for (int i = 0; i < pixelCount; i++) {
    final off = i * 4;
    final r = rgbaBytes[off];
    final g = rgbaBytes[off + 1];
    final b = rgbaBytes[off + 2];
    final a = rgbaBytes[off + 3];
    if (a < 128) continue;
    final brightness = (r * 299 + g * 587 + b * 114) ~/ 1000;
    if (brightness < 15 || brightness > 240) continue;
    pixels.add((r << 16) | (g << 8) | b);
  }
  if (pixels.isEmpty) return _kFallbackRgb;

  // ── Step 2: Median-cut into 16 buckets
  final buckets = _medianCutSplit(pixels, 16);

  // ── Step 3: Score each bucket
  //    score = population_ratio × (1 + saturation×2) × (0.5 + brightness_fit)
  final scored = <({double score, int r, int g, int b, double sat, double light})>[];
  final totalPx = pixels.length;

  for (final bucket in buckets) {
    if (bucket.isEmpty) continue;
    int rSum = 0, gSum = 0, bSum = 0;
    for (final px in bucket) {
      rSum += (px >> 16) & 0xFF;
      gSum += (px >> 8) & 0xFF;
      bSum += px & 0xFF;
    }
    final n = bucket.length;
    final avgR = rSum ~/ n, avgG = gSum ~/ n, avgB = bSum ~/ n;

    // HSL-like properties
    int maxC = avgR, minC = avgR;
    if (avgG > maxC) maxC = avgG;
    if (avgB > maxC) maxC = avgB;
    if (avgG < minC) minC = avgG;
    if (avgB < minC) minC = avgB;

    final light = (maxC + minC) / 510.0;
    final chroma = (maxC - minC) / 255.0;
    final denom = 1.0 - (2.0 * light - 1.0).abs();
    final sat = denom > 0.01 ? (chroma / denom).clamp(0.0, 1.0) : 0.0;

    final popFactor = n / totalPx;
    final brightFit = 1.0 - (light - 0.4).abs();
    final score = popFactor * (1.0 + sat * 2.0) * (0.5 + brightFit);

    scored.add((score: score, r: avgR, g: avgG, b: avgB, sat: sat, light: light));
  }

  if (scored.isEmpty) return _kFallbackRgb;

  // Sort by score descending
  scored.sort((a, b) => b.score.compareTo(a.score));

  // Dominant: highest-scored
  final dom = scored[0];

  // Secondary: next sufficiently different color
  var sec = scored.length > 1 ? scored[1] : dom;
  for (int i = 1; i < scored.length; i++) {
    final dr = (scored[i].r - dom.r).abs();
    final dg = (scored[i].g - dom.g).abs();
    final db = (scored[i].b - dom.b).abs();
    if (dr + dg + db > 60) {
      sec = scored[i];
      break;
    }
  }

  // Muted: darkest bucket with some saturation
  var mut = scored.last;
  for (final s in scored.reversed) {
    if (s.light < 0.25 && s.sat > 0.05) {
      mut = s;
      break;
    }
  }

  return [dom.r, dom.g, dom.b, sec.r, sec.g, sec.b, mut.r, mut.g, mut.b];
}

/// Median-cut: recursively split the pixel list into [target] boxes.
List<List<int>> _medianCutSplit(List<int> pixels, int target) {
  final boxes = <List<int>>[List<int>.from(pixels)];

  while (boxes.length < target) {
    int bestIdx = 0, bestScore = 0, bestAxis = 0;

    for (int i = 0; i < boxes.length; i++) {
      if (boxes[i].length < 2) continue;
      int rMin = 255, rMax = 0, gMin = 255, gMax = 0, bMin = 255, bMax = 0;
      for (final px in boxes[i]) {
        final r = (px >> 16) & 0xFF, g = (px >> 8) & 0xFF, b = px & 0xFF;
        if (r < rMin) rMin = r;
        if (r > rMax) rMax = r;
        if (g < gMin) gMin = g;
        if (g > gMax) gMax = g;
        if (b < bMin) bMin = b;
        if (b > bMax) bMax = b;
      }
      final rR = rMax - rMin, gR = gMax - gMin, bR = bMax - bMin;
      int range, axis;
      if (rR >= gR && rR >= bR) {
        range = rR; axis = 0;
      } else if (gR >= rR && gR >= bR) {
        range = gR; axis = 1;
      } else {
        range = bR; axis = 2;
      }
      final score = range * boxes[i].length;
      if (score > bestScore) {
        bestScore = score; bestIdx = i; bestAxis = axis;
      }
    }

    if (bestScore == 0) break;

    final box = boxes[bestIdx];
    final shift = 16 - bestAxis * 8;
    box.sort((a, b) => ((a >> shift) & 0xFF).compareTo((b >> shift) & 0xFF));

    final mid = box.length ~/ 2;
    boxes[bestIdx] = box.sublist(0, mid);
    boxes.add(box.sublist(mid));
  }

  return boxes;
}

// ────────────────────────────────────────────────
//  3b. PALETTE EXTRACTOR — isolate pipeline + cache
// ────────────────────────────────────────────────

class PaletteExtractor {
  PaletteExtractor._();

  static final Map<String, MediaPalette> _cache = {};
  static const int _maxCacheSize = 200;
  static String? _pendingId;

  /// Extract palette from image URL.
  ///
  /// 1. Resolve image (cached by CachedNetworkImage — fast).
  /// 2. Resize to 80×80, extract RGBA pixel bytes (sub-ms).
  /// 3. Run median-cut quantization in a background isolate via compute().
  /// 4. Feed raw colors into ColorRefiner on the main thread.
  static Future<MediaPalette> extract({
    required String mediaId,
    required String imageUrl,
  }) async {
    // Cache hit — instant return
    if (_cache.containsKey(mediaId)) return _cache[mediaId]!;

    // Prevent duplicate work on rapid skip
    if (_pendingId == mediaId) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (_cache.containsKey(mediaId)) return _cache[mediaId]!;
    }
    _pendingId = mediaId;

    try {
      final url = safeImageUrl(imageUrl);

      // ── Main thread: resolve + resize + get bytes (fast, cached) ──
      final rgbaBytes = await _resolveImagePixels(url);

      // ── Background isolate: heavy color quantization ──
      final rawColors = await compute(_quantizePixels, rgbaBytes);

      final rawDominant = Color.fromARGB(
        255, rawColors[0], rawColors[1], rawColors[2],
      );
      final rawSecondary = Color.fromARGB(
        255, rawColors[3], rawColors[4], rawColors[5],
      );
      final rawMuted = Color.fromARGB(
        255, rawColors[6], rawColors[7], rawColors[8],
      );

      debugPrint('=== NINAADA PALETTE [isolate]: song=$mediaId '
          'dom=${rawDominant.value.toRadixString(16)} ===');

      // ── Main thread: lightweight refinement ──
      final palette = ColorRefiner.refine(
        rawDominant: rawDominant,
        rawSecondary: rawSecondary,
        rawMuted: rawMuted,
      );

      debugPrint('=== NINAADA PALETTE: refined '
          'dom=${palette.dominant.value.toRadixString(16)} '
          'sec=${palette.secondary.value.toRadixString(16)} '
          'acc=${palette.accent.value.toRadixString(16)} ===');

      _evictIfNeeded();
      _cache[mediaId] = palette;
      _pendingId = null;
      return palette;
    } catch (e) {
      debugPrint('=== NINAADA: PaletteExtractor failed for $mediaId: $e ===');
      _pendingId = null;
      return _hashFallback(imageUrl);
    }
  }

  /// Resolve image from cache/network → resize to 80×80 → RGBA bytes.
  /// Runs on the main thread but is fast:
  ///   - CachedNetworkImageProvider hits disk/memory cache
  ///   - Engine decodes on a separate thread
  ///   - Canvas resize + toByteData for 80×80 is sub-millisecond
  static Future<Uint8List> _resolveImagePixels(String url) async {
    const targetSize = 80;

    // 1. Resolve image from cache / network
    final completer = Completer<ui.Image>();
    final provider = CachedNetworkImageProvider(url);
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (error, _) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);

    final image = await completer.future.timeout(
      const Duration(seconds: 6),
    );

    // 2. Resize to 80×80 for minimal pixel data
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final src = Rect.fromLTWH(
      0, 0, image.width.toDouble(), image.height.toDouble(),
    );
    const dst = Rect.fromLTWH(0, 0, targetSize * 1.0, targetSize * 1.0);
    canvas.drawImageRect(
      image, src, dst, Paint()..filterQuality = FilterQuality.low,
    );
    final picture = recorder.endRecording();
    final resized = await picture.toImage(targetSize, targetSize);

    // 3. Extract raw RGBA bytes (25 600 bytes for 80×80)
    final byteData = await resized.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );

    // Clean up GPU-backed resources
    image.dispose();
    resized.dispose();
    picture.dispose();

    return byteData!.buffer.asUint8List();
  }

  /// Quick synchronous check if a palette is cached
  static MediaPalette? getCached(String mediaId) => _cache[mediaId];

  /// Pre-warm cache for upcoming queue items (call with next 2-3 songs)
  static Future<void> preWarm(List<Song> upcoming) async {
    for (final song in upcoming.take(3)) {
      if (!_cache.containsKey(song.id)) {
        extract(mediaId: song.id, imageUrl: song.image)
            .catchError((_) => MediaPalette.fallback);
      }
    }
  }

  static void clearCache() => _cache.clear();

  static void _evictIfNeeded() {
    while (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Hash-based fallback when image can't be loaded
  static MediaPalette _hashFallback(String imageUrl) {
    int hash = 0;
    for (int i = 0; i < imageUrl.length; i++) {
      final ch = imageUrl.codeUnitAt(i);
      hash = ((hash << 5) - hash + ch * (i + 1)) & 0xFFFFFFFF;
      if (hash > 0x7FFFFFFF) hash -= 0x100000000;
    }
    final abs = hash.abs();
    final hue = (abs % 360).toDouble();

    final rawDominant = HSLColor.fromAHSL(1, hue, 0.5, 0.18).toColor();
    final rawSecondary = HSLColor.fromAHSL(
      1, (hue + 30) % 360, 0.4, 0.12,
    ).toColor();

    return ColorRefiner.refine(
      rawDominant: rawDominant,
      rawSecondary: rawSecondary,
    );
  }
}

// ────────────────────────────────────────────────
//  4. MEDIA THEME STATE + NOTIFIER (Riverpod)
// ────────────────────────────────────────────────

class MediaThemeState {
  final MediaPalette palette;
  final String? activeSongId;
  final bool isTransitioning;

  const MediaThemeState({
    this.palette = MediaPalette.fallback,
    this.activeSongId,
    this.isTransitioning = false,
  });

  MediaThemeState copyWith({
    MediaPalette? palette,
    String? activeSongId,
    bool? isTransitioning,
  }) {
    return MediaThemeState(
      palette: palette ?? this.palette,
      activeSongId: activeSongId ?? this.activeSongId,
      isTransitioning: isTransitioning ?? this.isTransitioning,
    );
  }
}

class MediaThemeNotifier extends StateNotifier<MediaThemeState> {
  MediaThemeNotifier() : super(const MediaThemeState());
  bool _backgrounded = false; // Phase 7: skip palette extraction when backgrounded
  String? _pendingSongId;     // Phase 7: queue song change for when resumed
  Song? _pendingSong;

  /// Phase 7: Suspend/resume palette extraction.
  void setBackgrounded(bool value) {
    _backgrounded = value;
    // On resume, process any pending song change that arrived while backgrounded
    if (!value && _pendingSong != null) {
      final song = _pendingSong!;
      _pendingSong = null;
      _pendingSongId = null;
      onSongChanged(song);
    }
  }

  /// Called by PlayerNotifier when a new song starts playing.
  /// This is the single integration point.
  Future<void> onSongChanged(Song song) async {
    // Skip if already showing this song's theme
    if (state.activeSongId == song.id) return;

    // Phase 7: Defer extraction while in background
    if (_backgrounded) {
      _pendingSongId = song.id;
      _pendingSong = song;
      return;
    }

    debugPrint('=== NINAADA THEME: onSongChanged → ${song.id} (${song.name}) ===');

    // Mark transitioning
    state = state.copyWith(activeSongId: song.id, isTransitioning: true);

    try {
      final palette = await PaletteExtractor.extract(
        mediaId: song.id,
        imageUrl: song.image,
      );

      // Only apply if this is still the active song (handles rapid skip)
      if (state.activeSongId == song.id) {
        state = state.copyWith(palette: palette, isTransitioning: false);
      }
    } catch (_) {
      if (state.activeSongId == song.id) {
        state = state.copyWith(isTransitioning: false);
      }
    }
  }

  /// Pre-warm palettes for upcoming queue items
  Future<void> preWarmQueue(List<Song> queue, String? currentId) async {
    if (currentId == null) return;
    final idx = queue.indexWhere((s) => s.id == currentId);
    if (idx < 0) return;
    final upcoming = queue.skip(idx + 1).take(3).toList();
    await PaletteExtractor.preWarm(upcoming);
  }

  /// Reset to default theme
  void reset() {
    state = const MediaThemeState();
  }
}

final mediaThemeProvider = StateNotifierProvider<MediaThemeNotifier, MediaThemeState>(
  (ref) => MediaThemeNotifier(),
);

// ────────────────────────────────────────────────
//  5. ANIMATED GRADIENT BACKGROUND WIDGETS
// ────────────────────────────────────────────────

/// Full-screen animated gradient background that reacts to the current media theme.
/// Uses AnimatedContainer for smooth 400ms transitions — no full rebuild.
class AnimatedThemeBackground extends ConsumerWidget {
  final Widget child;
  final bool useOverlay;
  final Duration duration;

  const AnimatedThemeBackground({
    super.key,
    required this.child,
    this.useOverlay = true,
    this.duration = const Duration(milliseconds: 400),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(mediaThemeProvider.select((s) => s.palette));
    final colors = useOverlay ? palette.overlayGradient : palette.gradient;

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Player-screen specific background with album art blur + dynamic color tint.
/// This replaces the old static gradient overlay in player_screen.dart.
class PlayerDynamicBackground extends ConsumerWidget {
  final String imageUrl;
  final Widget child;

  const PlayerDynamicBackground({
    super.key,
    required this.imageUrl,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(mediaThemeProvider.select((s) => s.palette));

    return Stack(
      children: [
        // Layer 1: Blurred album art
        Positioned.fill(
          child: CachedNetworkImage(
            imageUrl: safeImageUrl(imageUrl),
            fit: BoxFit.cover,
            color: Colors.black.withValues(alpha: 0.6),
            colorBlendMode: BlendMode.darken,
            errorWidget: (_, __, ___) => Container(color: palette.dominant),
          ),
        ),
        // Layer 2: Heavy blur — reduced sigma for softer ambient feel
        Positioned.fill(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 45, sigmaY: 45),
            child: const SizedBox.expand(),
          ),
        ),
        // Layer 3: Cinematic dark overlay
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.65),
                  const Color(0xFF0B0F1A).withValues(alpha: 0.92),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),
        ),
        // Layer 4: Dynamic color tint — animated 400ms easeOut
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  palette.dominant.withValues(alpha: 0.50),
                  palette.secondary.withValues(alpha: 0.35),
                  palette.muted.withValues(alpha: 0.70),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Layer 5: Content
        Positioned.fill(child: child),
      ],
    );
  }
}

/// Mini-player dynamic gradient bar
class MiniPlayerDynamicGradient extends ConsumerWidget {
  final Widget child;

  const MiniPlayerDynamicGradient({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final miniGrad = ref.watch(
      mediaThemeProvider.select((s) => s.palette.miniPlayerGradient),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: miniGrad,
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: child,
    );
  }
}

/// Section header gradient that adapts to the current media theme
/// Used for album detail, artist detail, playlist detail headers
class AdaptiveHeaderGradient extends ConsumerWidget {
  final Widget child;
  final List<Color>? overrideColors;

  const AdaptiveHeaderGradient({
    super.key,
    required this.child,
    this.overrideColors,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(mediaThemeProvider.select((s) => s.palette));
    final colors = overrideColors ?? [
      palette.dominant,
      Color.lerp(palette.dominant, const Color(0xFF0B0F1A), 0.7)!,
      const Color(0xFF0B0F1A),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: child,
    );
  }
}

/// Helper: Get accent color from the current theme (for seek bars, icons, etc.)
Color getThemeAccent(WidgetRef ref) {
  return ref.watch(mediaThemeProvider.select((s) => s.palette.accent));
}

/// Helper: Get the full palette
MediaPalette getThemePalette(WidgetRef ref) {
  return ref.watch(mediaThemeProvider.select((s) => s.palette));
}
