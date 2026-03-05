import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Placeholder for when no valid image URL is available (Ninaada logo)
const kPlaceholderImage = 'https://www.jiosaavn.com/_i/3.0/artist-default-music.png';

/// Validate and fix an image URL. Returns a valid URL or placeholder.
String safeImageUrl(String? url) {
  if (url == null || url.isEmpty) return kPlaceholderImage;
  final trimmed = url.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  // Local file path (downloaded artwork)
  if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
    return trimmed;
  }
  // Relative URL — might just be a path, try prepending https
  if (trimmed.startsWith('//')) return 'https:$trimmed';
  return kPlaceholderImage;
}

/// Safe cached image widget with built-in error handling
class SafeImage extends StatelessWidget {
  final String imageUrl;
  final double width;
  final double height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const SafeImage({
    super.key,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final url = safeImageUrl(imageUrl);
    final isLocal = url.startsWith('/') || url.startsWith('file://');

    Widget img;
    if (isLocal) {
      // Downloaded artwork — use Image.file
      final path = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
      img = Image.file(
        File(path),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: const Color(0xFF1E1E2E),
          child: const Center(
            child: Icon(Icons.broken_image, color: Color(0xFF444444), size: 20),
          ),
        ),
      );
    } else {
      img = CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => Container(
          width: width,
          height: height,
          color: const Color(0xFF1E1E2E),
          child: const Center(
            child: Icon(Icons.music_note, color: Color(0xFF444444), size: 20),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          width: width,
          height: height,
          color: const Color(0xFF1E1E2E),
          child: const Center(
            child: Icon(Icons.broken_image, color: Color(0xFF444444), size: 20),
          ),
        ),
      );
    }
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }
}

/// Format seconds to mm:ss
String fmt(num seconds) {
  final s = seconds.toInt();
  final m = s ~/ 60;
  final sec = s % 60;
  return '$m:${sec < 10 ? '0' : ''}$sec';
}

/// Deduplicate a list by id selector
List<T> dedupe<T>(List<T> items, String Function(T) getId) {
  final seen = <String>{};
  return items.where((item) {
    final id = getId(item);
    if (seen.contains(id)) return false;
    seen.add(id);
    return true;
  }).toList();
}

/// Generate gradient colors from an ID string — matches RN getGradient()
const List<List<String>> _palettes = [
  ['#141424', '#16213e', '#0f3460'],
  ['#2d132c', '#141424', '#0a0a14'],
  ['#0f4c75', '#1b262c', '#0a0a14'],
  ['#3c1642', '#086375', '#0a0a14'],
  ['#1e3a5f', '#0a0a14', '#141424'],
  ['#2c3e50', '#141424', '#0a0a14'],
  ['#4a0e4e', '#141424', '#0a0a14'],
];

List<Color> getGradientFromId(String? id) {
  final hash = (id ?? '').codeUnits.fold<int>(0, (a, c) => a + c);
  final palette = _palettes[hash % _palettes.length];
  return palette.map((hex) => _hexToColor(hex)).toList();
}

Color _hexToColor(String hex) {
  hex = hex.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return Color(int.parse(hex, radix: 16));
}

/// Dynamic color extraction from image URL hash — matches RN extractDominantColor()
Map<String, dynamic> extractDominantColor(String? imageUrl) {
  if (imageUrl == null || imageUrl.isEmpty) {
    return {
      'bg': [
        const Color(0xFF1A1A2E),
        const Color(0xFF0B0F1A),
        const Color(0xFF10141F),
      ],
      'accent': const Color(0xFF7C4DFF),
    };
  }

  // Generate hash from URL — identical algorithm to RN
  int hash = 0;
  for (int i = 0; i < imageUrl.length; i++) {
    final ch = imageUrl.codeUnitAt(i);
    hash = ((hash << 5) - hash + ch * (i + 1)) & 0xFFFFFFFF;
    // Convert to signed 32-bit
    if (hash > 0x7FFFFFFF) hash -= 0x100000000;
  }
  final abs = hash.abs();

  final hue1 = abs % 360;
  final hue2 = (hue1 + 30 + (abs % 40)) % 360;
  final sat = 40 + (abs % 30); // 40-70%
  final light1 = 12 + (abs % 10); // 12-22%
  final light2 = 6 + (abs % 6); // 6-12%

  final c1 = _hslToColor(hue1.toDouble(), sat.toDouble(), light1.toDouble());
  final c2 = _hslToColor(hue2.toDouble(), (sat - 10).toDouble(), light2.toDouble());
  const c3 = Color(0xFF0B0F1A);
  final accent = _hslToColor(hue1.toDouble(), (sat + 20).clamp(0, 80).toDouble(), 55);

  return {
    'bg': [c1, c2, c3],
    'accent': accent,
  };
}

Color _hslToColor(double h, double s, double l) {
  s /= 100;
  l /= 100;

  // Simplified HSL to RGB
  final hNorm = h / 360;
  final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  final p = 2 * l - q;

  double hueToRgb(double p, double q, double t) {
    var tt = t;
    if (tt < 0) tt += 1;
    if (tt > 1) tt -= 1;
    if (tt < 1 / 6) return p + (q - p) * 6 * tt;
    if (tt < 1 / 2) return q;
    if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
    return p;
  }

  final r = (hueToRgb(p, q, hNorm + 1 / 3) * 255).round().clamp(0, 255);
  final g = (hueToRgb(p, q, hNorm) * 255).round().clamp(0, 255);
  final b = (hueToRgb(p, q, hNorm - 1 / 3) * 255).round().clamp(0, 255);

  return Color.fromARGB(255, r, g, b);
}

/// Get time-based greeting — strict time ranges
/// Morning 5-11, Afternoon 12-16, Evening 17-20, Night 21-4
String getGreeting() {
  final h = DateTime.now().hour;
  if (h >= 5 && h <= 11) return 'Good Morning';
  if (h >= 12 && h <= 16) return 'Good Afternoon';
  if (h >= 17 && h <= 20) return 'Good Evening';
  return 'Good Night'; // 21–4
}

/// Title case a string
String titleCase(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// Parse hex color with optional alpha suffix
Color hexColor(String hex, {String alphaSuffix = ''}) {
  hex = hex.replaceFirst('#', '');
  if (alphaSuffix.isNotEmpty) hex = hex + alphaSuffix;
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length == 8) return Color(int.parse(hex, radix: 16));
  return const Color(0xFF000000);
}
