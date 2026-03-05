import 'package:flutter/foundation.dart';

/// Lightweight structured logger for Ninaada Music.
///
/// - [debug]   → truly stripped in release builds (kDebugMode guard)
/// - [warning] → survives in release builds (uses print)
/// - [error]   → survives in release builds (uses print)
class AppLogger {
  AppLogger._();

  /// Debug-level log — only visible in debug/profile mode.
  /// Completely no-op in release builds (guarded by kDebugMode).
  static void debug(String message) {
    if (kDebugMode) {
      debugPrint('[NINAADA] $message');
    }
  }

  /// Warning-level log — always visible, even in release builds.
  static void warning(String message) {
    if (kReleaseMode) {
      // ignore: avoid_print
      print('[NINAADA WARN] $message');
    } else {
      debugPrint('[NINAADA WARN] $message');
    }
  }

  /// Error-level log — always visible, even in release builds.
  static void error(String message, [Object? error, StackTrace? stack]) {
    if (kReleaseMode) {
      // ignore: avoid_print
      print('[NINAADA ERROR] $message${error != null ? ' | $error' : ''}');
    } else {
      debugPrint('[NINAADA ERROR] $message${error != null ? ' | $error' : ''}');
      if (stack != null) debugPrint(stack.toString());
    }
  }
}
