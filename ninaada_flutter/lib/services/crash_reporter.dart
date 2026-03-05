import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ninaada_music/core/app_version.dart';

// ════════════════════════════════════════════════════════════════
//  CRASH REPORTER — Phase 8, Step 1
// ════════════════════════════════════════════════════════════════
//
//  Lightweight, self-hosted crash telemetry. No bloated SDKs.
//
//  Captures:
//    • Fatal exceptions (FlutterError.onError)
//    • Uncaught async errors (PlatformDispatcher.onError)
//    • Player state at crash (viewState, shuffle, queue length)
//    • Network state at crash
//    • Device info (OS, model, app version)
//
//  Storage:
//    • Persists crash reports to Hive box (survives process death)
//    • Uploads on next app launch (fire-and-forget)
//    • Max 50 stored reports (ring buffer)
//
//  Privacy:
//    • No user PII
//    • No song names or content
//    • Only structural state (indices, counts, enums)
// ════════════════════════════════════════════════════════════════

/// Immutable crash report — serialized to/from JSON for Hive storage.
class CrashReport {
  final String id;
  final DateTime timestamp;
  final String errorType;    // 'flutter_error' | 'async_error' | 'anr'
  final String message;
  final String? stackTrace;
  final Map<String, dynamic> appState;
  final Map<String, dynamic> deviceInfo;

  const CrashReport({
    required this.id,
    required this.timestamp,
    required this.errorType,
    required this.message,
    this.stackTrace,
    this.appState = const {},
    this.deviceInfo = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'errorType': errorType,
    'message': message,
    'stackTrace': stackTrace,
    'appState': appState,
    'deviceInfo': deviceInfo,
  };

  factory CrashReport.fromJson(Map<String, dynamic> json) => CrashReport(
    id: json['id'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    errorType: json['errorType'] as String,
    message: json['message'] as String,
    stackTrace: json['stackTrace'] as String?,
    appState: Map<String, dynamic>.from(json['appState'] ?? {}),
    deviceInfo: Map<String, dynamic>.from(json['deviceInfo'] ?? {}),
  );
}

/// Singleton crash reporter — initialized once during app startup.
class CrashReporter {
  CrashReporter._();
  static final CrashReporter instance = CrashReporter._();

  Box? _box;
  bool _initialized = false;
  static const int _maxReports = 50;
  static const String _boxName = 'crash_reports';

  // ── Snapshot providers — set by app after init ──
  Map<String, dynamic> Function()? snapshotProvider;

  /// Initialize the crash reporter. Opens its own Hive box.
  Future<void> init() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox(_boxName);
      _initialized = true;
      debugPrint('=== CRASH REPORTER: initialized (${_box!.length} pending) ===');
    } catch (e) {
      debugPrint('=== CRASH REPORTER: init FAILED: $e ===');
    }
  }

  /// Record a crash. Call from FlutterError.onError or PlatformDispatcher.
  void recordCrash({
    required String errorType,
    required String message,
    String? stackTrace,
  }) {
    if (!_initialized || _box == null) return;

    final report = CrashReport(
      id: '${DateTime.now().millisecondsSinceEpoch}_${errorType.hashCode.abs()}',
      timestamp: DateTime.now(),
      errorType: errorType,
      message: _truncate(message, 500) ?? '',
      stackTrace: _truncate(stackTrace, 2000),
      appState: _captureAppState(),
      deviceInfo: _captureDeviceInfo(),
    );

    try {
      // Ring buffer: drop oldest if at capacity
      if (_box!.length >= _maxReports) {
        _box!.deleteAt(0);
      }
      _box!.add(jsonEncode(report.toJson()));
    } catch (e) {
      // Silent — can't crash inside crash handler
    }
  }

  /// Get all pending crash reports.
  List<CrashReport> getPendingReports() {
    if (!_initialized || _box == null) return [];
    final reports = <CrashReport>[];
    for (var i = 0; i < _box!.length; i++) {
      try {
        final json = jsonDecode(_box!.getAt(i) as String);
        reports.add(CrashReport.fromJson(json));
      } catch (_) {
        // Skip corrupted entries
      }
    }
    return reports;
  }

  /// Clear all pending reports (call after successful upload).
  Future<void> clearReports() async {
    if (!_initialized || _box == null) return;
    await _box!.clear();
  }

  /// Get report count.
  int get pendingCount => _box?.length ?? 0;

  // ── Internal helpers ──

  Map<String, dynamic> _captureAppState() {
    if (snapshotProvider != null) {
      try {
        return snapshotProvider!();
      } catch (_) {
        return {'snapshot_error': true};
      }
    }
    return {};
  }

  Map<String, dynamic> _captureDeviceInfo() {
    return {
      'platform': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'dartVersion': Platform.version.split(' ').first,
      'locale': Platform.localeName,
      'appVersion': appVersionFull,
    };
  }

  String? _truncate(String? s, int maxLen) {
    if (s == null) return null;
    return s.length > maxLen ? '${s.substring(0, maxLen)}…' : s;
  }
}
