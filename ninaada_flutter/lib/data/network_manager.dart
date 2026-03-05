import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ninaada_music/core/constants.dart';
import 'package:ninaada_music/data/performance_interceptor.dart';

// ================================================================
//  NETWORK MANAGER — single gateway for ALL API traffic
// ================================================================
//
//  Pipeline: Memory Cache → Disk Cache → Dedup → Concurrency Gate → Network
//
//  Features:
//  ● Persistent Hive cache with configurable TTL
//  ● In-memory L1 cache (up to 100 entries)
//  ● Request deduplication via fingerprinting (same URL+params = same Future)
//  ● Concurrency control (max 4 simultaneous network requests)
//  ● Cancel token management
//  ● Stale-while-revalidate for home data
// ================================================================

class NetworkManager {
  static final NetworkManager _instance = NetworkManager._internal();
  factory NetworkManager() => _instance;

  late final Dio _dio;
  Box? _cacheBox;
  bool _initialized = false;

  // ── L1 memory cache ──────────────────────────────
  final Map<String, _MemEntry> _mem = {};
  static const int _memMaxSize = 120;

  // ── Request deduplication ────────────────────────
  final Map<String, Future<dynamic>> _inFlight = {};

  // ── Concurrency gate ─────────────────────────────
  static const int _maxConcurrent = 4;
  int _activeCount = 0;
  final List<Completer<void>> _waitQueue = [];

  // ── Cancel tokens ────────────────────────────────
  final Map<String, CancelToken> _cancelTokens = {};

  NetworkManager._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: apiBase,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'NinaadaMusic/1.0',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      },
    ));
    // Network APM — measures true round-trip latency before any cache layer
    _dio.interceptors.add(PerformanceInterceptor());
  }

  /// Must be called once at app startup (after Hive.initFlutter).
  Future<void> init() async {
    if (_initialized) return;
    try {
      _cacheBox = await Hive.openBox('apiCache');
      _initialized = true;
      debugPrint('=== NINAADA: NetworkManager initialized (${_cacheBox!.length} cached entries) ===');
    } catch (e) {
      debugPrint('=== NINAADA: NetworkManager init failed: $e ===');
    }
  }

  // ================================================================
  //  PUBLIC API
  // ================================================================

  /// Primary GET with full pipeline.
  ///
  /// [cacheKey] — explicit cache key (auto-generated from path+params if null).
  /// [cacheTtl] — how long a cache entry is considered fresh.
  /// [cancelKey] — if set, any previous request with the same key is cancelled.
  /// [skipCache] — bypass cache entirely (force network).
  /// [staleOk] — if true, return stale cache immediately and refresh in background.
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? params,
    String? cacheKey,
    Duration cacheTtl = const Duration(minutes: 15),
    String? cancelKey,
    bool skipCache = false,
    bool staleOk = false,
  }) async {
    final key = cacheKey ?? _fingerprint(path, params);

    // ── 1. Memory cache ──
    if (!skipCache) {
      final mem = _readMem(key, cacheTtl);
      if (mem != null) return mem;

      // ── 2. Disk cache ──
      final disk = _readDisk(key, cacheTtl, staleOk: staleOk);
      if (disk != null) {
        if (staleOk) {
          // Return stale immediately, refresh in background
          _backgroundRefresh(path, params: params, cacheKey: key, cancelKey: cancelKey);
        }
        return disk;
      }
    }

    // ── 3. Dedup — if identical request is already in-flight, piggy-back ──
    //
    //  IMPORTANT: Skip dedup for cancelable requests (cancelKey != null).
    //  Cancelable requests have explicit lifecycle management — if we dedup,
    //  a new search can piggyback on a CANCELLED future and receive null,
    //  causing blank results.
    final fp = _fingerprint(path, params);
    if (cancelKey == null && _inFlight.containsKey(fp)) {
      return _inFlight[fp];
    }

    // ── 4. Network with concurrency gate ──
    final future = _networkGet(path, params: params, cancelKey: cancelKey, cacheKey: key);
    if (cancelKey == null) _inFlight[fp] = future;

    try {
      return await future;
    } finally {
      if (cancelKey == null) _inFlight.remove(fp);
    }
  }

  /// Cancel a specific in-flight request.
  void cancelRequest(String key) {
    _cancelTokens[key]?.cancel('Cancelled');
    _cancelTokens.remove(key);
  }

  /// Cancel all in-flight requests.
  void cancelAll() {
    for (final t in _cancelTokens.values) {
      t.cancel('Cancelled all');
    }
    _cancelTokens.clear();
  }

  /// Wipe all caches (memory + disk).
  Future<void> clearCache() async {
    _mem.clear();
    if (_initialized) await _cacheBox?.clear();
  }

  /// Wipe memory cache only.
  void clearMemoryCache() => _mem.clear();

  /// Remove a single cache entry.
  Future<void> invalidate(String cacheKey) async {
    _mem.remove(cacheKey);
    if (_initialized) await _cacheBox?.delete(cacheKey);
  }

  /// Check how many entries are cached on disk.
  int get diskCacheCount => _cacheBox?.length ?? 0;

  /// Fire-and-forget warm-up ping to wake Render from cold sleep.
  /// Call once during app startup — no await needed.
  void warmUp() {
    _dio.get('/ping').catchError((_) => null);
    debugPrint('=== NINAADA: warm-up ping sent ===');
  }

  // ================================================================
  //  INTERNALS
  // ================================================================

  // ── Fingerprint: deterministic key from path + sorted params ──
  String _fingerprint(String path, Map<String, dynamic>? params) {
    final buf = StringBuffer(path);
    if (params != null && params.isNotEmpty) {
      final sorted = params.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
      for (final e in sorted) {
        buf.write('|${e.key}=${e.value}');
      }
    }
    return buf.toString();
  }

  // ── Memory cache read ──
  dynamic _readMem(String key, Duration ttl) {
    final entry = _mem[key];
    if (entry != null && DateTime.now().difference(entry.ts) < ttl) {
      return entry.data;
    }
    if (entry != null) _mem.remove(key); // expired
    return null;
  }

  // ── Disk cache read ──
  dynamic _readDisk(String key, Duration ttl, {bool staleOk = false}) {
    if (!_initialized || _cacheBox == null) return null;
    final raw = _cacheBox!.get(key);
    if (raw == null) return null;

    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final ts = DateTime.parse(map['t'] as String);
      final age = DateTime.now().difference(ts);

      if (age < ttl || staleOk) {
        final data = map['d'];
        // Promote to memory cache
        _writeMem(key, data);
        return data;
      }
      // Expired — delete
      _cacheBox!.delete(key);
    } catch (_) {
      _cacheBox!.delete(key);
    }
    return null;
  }

  // ── Memory cache write ──
  void _writeMem(String key, dynamic data) {
    // Evict oldest entries if at capacity
    while (_mem.length >= _memMaxSize) {
      _mem.remove(_mem.keys.first);
    }
    _mem[key] = _MemEntry(data: data, ts: DateTime.now());
  }

  // ── Disk cache write ──
  Future<void> _writeDisk(String key, dynamic data) async {
    if (!_initialized || _cacheBox == null) return;
    try {
      final payload = jsonEncode({
        'd': data,
        't': DateTime.now().toIso8601String(),
      });
      await _cacheBox!.put(key, payload);
    } catch (e) {
      debugPrint('=== NINAADA: disk cache write failed for $key: $e ===');
    }
  }

  // ── Concurrency gate ──
  Future<void> _acquireSlot() async {
    if (_activeCount < _maxConcurrent) {
      _activeCount++;
      return;
    }
    final c = Completer<void>();
    _waitQueue.add(c);
    await c.future;
    _activeCount++;
  }

  void _releaseSlot() {
    _activeCount--;
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeAt(0).complete();
    }
  }

  // ── The actual network call with auto-retry ──
  Future<dynamic> _networkGet(
    String path, {
    Map<String, dynamic>? params,
    String? cancelKey,
    required String cacheKey,
    int retryCount = 0,
  }) async {
    await _acquireSlot();

    CancelToken? cancelToken;
    if (cancelKey != null) {
      _cancelTokens[cancelKey]?.cancel('Superseded');
      cancelToken = CancelToken();
      _cancelTokens[cancelKey] = cancelToken;
    }

    try {
      final response = await _dio.get(
        path,
        queryParameters: params,
        cancelToken: cancelToken,
      );
      final data = response.data;

      // Write to both caches
      _writeMem(cacheKey, data);
      _writeDisk(cacheKey, data); // fire-and-forget

      if (cancelKey != null) _cancelTokens.remove(cancelKey);
      return data;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) return null;
      // Auto-retry up to 2 times on timeout or connection error (Render cold start)
      if (retryCount < 2 &&
          (e.type == DioExceptionType.connectionTimeout ||
           e.type == DioExceptionType.receiveTimeout ||
           e.type == DioExceptionType.connectionError)) {
        debugPrint('=== NINAADA: retry #${retryCount + 1} $path after ${e.type} ===');
        // Release slot BEFORE retry — the recursive call acquires its own.
        // Mark that we already released so `finally` doesn't double-release.
        _releaseSlot();
        await Future.delayed(Duration(seconds: 2 + retryCount));
        // The recursive call handles its own slot acquire/release.
        // We must NOT let `finally` release again, so we return directly
        // from within a try that has already released.
        final result = await _networkGet(path, params: params, cancelKey: cancelKey,
            cacheKey: cacheKey, retryCount: retryCount + 1);
        // Re-acquire a slot just so the `finally` block's _releaseSlot
        // doesn't corrupt the counter. This is a no-op pattern.
        _activeCount++;
        return result;
      }
      rethrow;
    } finally {
      _releaseSlot();
    }
  }

  // ── Background refresh (stale-while-revalidate) ──
  void _backgroundRefresh(
    String path, {
    Map<String, dynamic>? params,
    required String cacheKey,
    String? cancelKey,
  }) {
    // Don't await — just fire and forget
    _networkGet(path, params: params, cancelKey: cancelKey, cacheKey: cacheKey).catchError((_) {
      // Ignore background refresh errors — stale data is already served
      return null;
    });
  }
}

// ── Internal data classes ──

class _MemEntry {
  final dynamic data;
  final DateTime ts;
  _MemEntry({required this.data, required this.ts});
}
