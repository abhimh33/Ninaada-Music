import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ninaada_music/core/constants.dart';
import 'package:ninaada_music/services/download_manager.dart';

// ════════════════════════════════════════════════════════════════
//  NETWORK INTELLIGENCE PROVIDER — Phase 6, Single Authority
// ════════════════════════════════════════════════════════════════
//
//  One source of truth for network availability. All offline
//  decisions reference this provider — no scattered checks.
//
//  Features:
//  ● Reactive Riverpod StateNotifier
//  ● 500ms debounce to absorb flapping (elevators, basements)
//  ● Defaults to offline until first check completes
//  ● Lightweight ping verification on each state change
//  ● Startup detection before any play attempt
// ════════════════════════════════════════════════════════════════

enum NetworkStatus { online, offline }

class NetworkNotifier extends StateNotifier<NetworkStatus> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounce;
  final Connectivity _connectivity = Connectivity();
  bool _backgrounded = false; // Phase 7: skip pings when app is backgrounded

  NetworkNotifier() : super(NetworkStatus.offline) {
    _init();
  }

  /// Phase 7, Step 7: Suspend/resume connectivity processing.
  /// When backgrounded, we skip expensive ping checks — the
  /// connectivity listener still fires but debounce is no-op'd.
  void setBackgrounded(bool value) {
    _backgrounded = value;
    // When resuming, do a fresh check to catch changes that happened
    // while backgrounded.
    if (!value) {
      _connectivity.checkConnectivity().then(_onConnectivityChanged);
    }
  }

  Future<void> _init() async {
    // ── Step 10: Startup detection — check before first play ──
    try {
      final results = await _connectivity.checkConnectivity();
      final hasTransport = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);
      if (hasTransport) {
        final reachable = await _pingCheck();
        state = reachable ? NetworkStatus.online : NetworkStatus.offline;
      } else {
        state = NetworkStatus.offline;
      }
    } catch (e) {
      debugPrint('=== NETWORK: startup check failed: $e ===');
      state = NetworkStatus.offline;
    }
    debugPrint('=== NETWORK: initial status = $state ===');

    // ── Listen for changes ──
    _sub = _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
  }

  // ── Step 9: Debounce — 500ms stable before emitting ──
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _debounce?.cancel();
    // Phase 7: Skip expensive ping when app is in background
    if (_backgrounded) return;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final hasTransport = results.any((r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet);

      if (!hasTransport) {
        if (state != NetworkStatus.offline) {
          state = NetworkStatus.offline;
          debugPrint('=== NETWORK: offline (no transport) ===');
        }
        return;
      }

      // ── Step 11: Airplane edge case — one ping per state change ──
      final reachable = await _pingCheck();
      final newStatus = reachable ? NetworkStatus.online : NetworkStatus.offline;
      if (newStatus != state) {
        state = newStatus;
        debugPrint('=== NETWORK: ${state.name} (ping=${reachable}) ===');
      }
    });
  }

  /// Lightweight reachability check — one DNS lookup per state change.
  /// Uses the app's own API base to verify actual internet access,
  /// falling back to a public DNS if the primary fails.
  Future<bool> _pingCheck() async {
    try {
      // Try resolving the API host first (proves our backend is reachable)
      final uri = Uri.parse(apiBase);
      final results = await InternetAddress.lookup(uri.host)
          .timeout(const Duration(seconds: 3));
      return results.isNotEmpty && results[0].rawAddress.isNotEmpty;
    } catch (_) {
      // Fallback: try a well-known public host
      try {
        final results = await InternetAddress.lookup('dns.google')
            .timeout(const Duration(seconds: 3));
        return results.isNotEmpty && results[0].rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}

/// Single authority for network status across the entire app.
final networkProvider = StateNotifierProvider<NetworkNotifier, NetworkStatus>(
  (ref) => NetworkNotifier(),
);

/// Quick check: is this song playable right now?
/// Online → always true. Offline → only if downloaded.
bool isSongAvailable(NetworkStatus network, String songId) {
  if (network != NetworkStatus.offline) return true;
  return DownloadManager().isDownloaded(songId);
}
