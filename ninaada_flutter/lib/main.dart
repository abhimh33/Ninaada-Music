import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:audio_service/audio_service.dart' as svc;
import 'package:ninaada_music/core/app_keys.dart';
import 'package:ninaada_music/core/theme.dart';
import 'package:ninaada_music/data/network_manager.dart';
import 'package:ninaada_music/data/user_taste_profile.dart';
import 'package:ninaada_music/providers/app_providers.dart';
import 'package:ninaada_music/providers/sleep_alarm_provider.dart';
import 'package:ninaada_music/screens/explore_screen.dart';
import 'package:ninaada_music/screens/home_screen.dart';
import 'package:ninaada_music/screens/library_screen.dart';
import 'package:ninaada_music/screens/radio_screen.dart';
import 'package:ninaada_music/screens/search_overlay.dart';
import 'package:ninaada_music/screens/sub_views.dart';
import 'package:ninaada_music/services/ninaada_audio_handler.dart';
import 'package:ninaada_music/services/queue_persistence_service.dart';
import 'package:ninaada_music/services/download_manager.dart';
import 'package:ninaada_music/services/crash_reporter.dart';
import 'package:ninaada_music/services/anr_watchdog.dart';
import 'package:ninaada_music/services/behavior_engine.dart';
import 'package:ninaada_music/widgets/bottom_nav.dart';
import 'package:ninaada_music/widgets/player_overlay.dart';
import 'package:ninaada_music/widgets/behavior_debug_overlay.dart';
import 'package:ninaada_music/providers/onboarding_provider.dart';
import 'package:ninaada_music/providers/network_provider.dart';
import 'package:ninaada_music/screens/onboarding_screen.dart';
import 'package:ninaada_music/core/media_theme_engine.dart';
import 'package:ninaada_music/core/shader_warmup.dart';

bool _mainCalled = false;

void main() async {
  // Guard against double execution (Impeller creates two GL contexts)
  if (_mainCalled) {
    debugPrint('=== NINAADA: main() SKIPPED (already called) ===');
    return;
  }
  _mainCalled = true;

  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('=== NINAADA: main() started ===');

  // ── Phase 7, Step 10: Release mode log discipline ──
  // Override debugPrint to a complete no-op in release mode.
  // This eliminates ALL string interpolation, allocation, and I/O
  // from ~100+ debugPrint calls across the codebase. Zero CPU cost.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Global error handler — makes widget errors visible instead of red screen
  FlutterError.onError = (details) {
    debugPrint('=== FLUTTER ERROR: ${details.exception} ===');
    debugPrint('${details.stack}');
    // Phase 8: Record to crash reporter
    CrashReporter.instance.recordCrash(
      errorType: 'flutter_error',
      message: details.exception.toString(),
      stackTrace: details.stack?.toString(),
    );
  };

  // Phase 8: Catch uncaught async errors (Futures, Isolates)
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('=== ASYNC ERROR: $error ===');
    debugPrint('$stack');
    CrashReporter.instance.recordCrash(
      errorType: 'async_error',
      message: error.toString(),
      stackTrace: stack.toString(),
    );
    return true; // Handled — prevent crash
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Container(
      color: Colors.red.withOpacity(0.15),
      padding: const EdgeInsets.all(8),
      child: Text(
        'WIDGET ERROR:\n${details.exception}',
        style: const TextStyle(color: Colors.red, fontSize: 11, decoration: TextDecoration.none),
      ),
    );
  };

  // Init Hive
  await Hive.initFlutter();
  await Hive.openBox('library');
  await Hive.openBox('search');
  await Hive.openBox('settings');
  await Hive.openBox('sleep_alarm');
  debugPrint('=== NINAADA: Hive initialized ===');

  // Phase 8: Init crash reporter (uses Hive — must come after Hive.initFlutter)
  await CrashReporter.instance.init();
  final pending = CrashReporter.instance.pendingCount;
  if (pending > 0) {
    debugPrint('=== CRASH REPORTER: $pending pending reports from previous session ===');
  }

  // Phase 8: Start ANR watchdog
  AnrWatchdog.instance.start();

  // Init queue persistence service (uses Hive for queue state snapshots)
  try {
    await QueuePersistenceService.instance.init();
    debugPrint('=== NINAADA: QueuePersistenceService initialized ===');
  } catch (e) {
    debugPrint('=== NINAADA: QueuePersistenceService init FAILED: $e ===');
  }

  // Init download manager (opens its own Hive box, resolves download dir)
  try {
    await DownloadManager().init();
    debugPrint('=== NINAADA: DownloadManager initialized ===');
  } catch (e) {
    debugPrint('=== NINAADA: DownloadManager init FAILED: $e ===');
  }

  // Init audio handler with OS integration (lock screen, notification, background)
  late final NinaadaAudioHandler audioHandler;
  try {
    audioHandler = await svc.AudioService.init<NinaadaAudioHandler>(
      builder: () => NinaadaAudioHandler(),
      config: const svc.AudioServiceConfig(
        androidNotificationChannelId: 'com.pramodbelagali.ninaada_music.audio',
        androidNotificationChannelName: 'Ninaada Music',
        androidShowNotificationBadge: true,
        // Keep foreground service + notification alive when paused so
        // the user can resume from lock screen / notification shade.
        // androidNotificationOngoing is redundant here — the foreground
        // service already keeps the notification non-dismissible.
        androidStopForegroundOnPause: false,
      ),
    );
    debugPrint('=== NINAADA: AudioHandler initialized (OS-integrated) ===');
  } catch (e) {
    debugPrint('=== NINAADA: AudioService.init FAILED: $e — using fallback ===');
    // Fallback: handler without OS integration (still plays audio)
    audioHandler = NinaadaAudioHandler();
  }

  // Init taste profile manager (local device profile for recommendations)
  try {
    await TasteProfileManager.init();
  } catch (e) {
    debugPrint('=== NINAADA: TasteProfileManager init FAILED: $e ===');
  }

  // Phase 9B: Init behavior engine (behavioral adaptation — uses Hive)
  try {
    await BehaviorEngine.init();
  } catch (e) {
    debugPrint('=== NINAADA: BehaviorEngine init FAILED: $e ===');
  }

  // Init network manager (persistent API cache)
  try {
    await NetworkManager().init();
    // Wake Render from cold sleep immediately (fire-and-forget)
    NetworkManager().warmUp();
    debugPrint('=== NINAADA: NetworkManager initialized ===');
  } catch (e) {
    debugPrint('=== NINAADA: NetworkManager init FAILED: $e ===');
  }

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF0B0F1A),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF101528),
    ),
  );

  // Phase 7: Pre-warm GPU pipeline (gradients, blurs, shadows)
  await NinaadaShaderWarmup.execute();

  debugPrint('=== NINAADA: calling runApp ===');
  // Phase 8: runZonedGuarded catches errors that bypass FlutterError.onError
  // and PlatformDispatcher.onError (e.g. microtask zone errors).
  runZonedGuarded(
    () => runApp(ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const NinaadaApp(),
    )),
    (error, stack) {
      debugPrint('=== ZONE ERROR: $error ===');
      CrashReporter.instance.recordCrash(
        errorType: 'zone_error',
        message: error.toString(),
        stackTrace: stack.toString(),
      );
    },
  );
}

class NinaadaApp extends ConsumerWidget {
  const NinaadaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingProvider);
    return MaterialApp(
      title: 'Ninaada Music',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: NinaadaTheme.darkTheme,
      home: onboarding.hasCompletedOnboarding
          ? const _AppShell()
          : const OnboardingScreen(),
    );
  }
}

/// Root shell — switches screens based on navigation state,
/// overlays MiniPlayer + BottomNav + ContextMenu
class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> with WidgetsBindingObserver {
  /// Timestamp of the last "press back again to exit" toast.
  /// If the user presses back within 2 seconds, the app exits.
  DateTime? _lastBackPress;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Phase 8: Wire crash reporter snapshot provider — captures player state
    // at the moment of any crash for diagnostics.
    CrashReporter.instance.snapshotProvider = () {
      try {
        final player = ref.read(playerProvider);
        final network = ref.read(networkProvider);
        return {
          'viewState': player.viewState.name,
          'isPlaying': player.isPlaying,
          'isBuffering': player.isBuffering,
          'shuffle': player.shuffle,
          'repeat': player.repeat,
          'queueLength': player.queue.length,
          'playbackSpeed': player.playbackSpeed,
          'playbackMode': player.playbackMode.name,
          'autoPlay': player.autoPlay,
          'networkStatus': network.name,
          'hasSong': player.currentSong != null,
        };
      } catch (_) {
        return {'snapshot_error': true};
      }
    };

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.read(libraryProvider.notifier).loadAll();
      } catch (e) {
        debugPrint('=== APPSHELL: loadAll ERROR: $e ===');
      }
      // ── Cold Boot Restoration (Phase 8) ──
      // Restore saved queue state without playing. The player appears
      // paused at the last known position with the full queue loaded.
      _restoreSavedState();
    });
  }

  /// Attempt to restore the playback queue from a previous session.
  Future<void> _restoreSavedState() async {
    try {
      final restored = await ref.read(playerProvider.notifier).restoreFromSavedState();
      if (restored) {
        debugPrint('=== APPSHELL: queue restored from saved state ===');
      }
    } catch (e) {
      debugPrint('=== APPSHELL: restoreState ERROR: $e ===');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Phase 7: Resume background-paused subsystems
      ref.read(networkProvider.notifier).setBackgrounded(false);
      ref.read(mediaThemeProvider.notifier).setBackgrounded(false);
      // Force rebuild so getGreeting() and getVibes() pick up the current hour.
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.detached) {
      // Phase 7: Pause expensive subsystems when app not visible
      ref.read(networkProvider.notifier).setBackgrounded(true);
      ref.read(mediaThemeProvider.notifier).setBackgrounded(true);
      // ── Flush pending queue state on background / kill (Phase 8) ──
      QueuePersistenceService.instance.flushNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navigationProvider);
    final isFullPlayer = ref.watch(
      playerProvider.select((p) => p.viewState == PlayerViewState.full),
    );

    const bottomNavHeight = 70.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        // Priority 0: If player overlay is in full-screen, collapse it
        final playerView = ref.read(playerProvider).viewState;
        if (playerView == PlayerViewState.full) {
          ref.read(playerProvider.notifier).collapsePlayer();
          return;
        }

        // Priority 1: If Explore tab has an active genre/mood detail, clear it first
        final nav = ref.read(navigationProvider);
        if (nav.currentTab == AppTab.explore &&
            !nav.hasSubView &&
            !nav.showSearch) {
          final explore = ref.read(exploreProvider);
          if (explore.selectedGenre != null) {
            ref.read(exploreProvider.notifier).clearGenre();
            return;
          }
        }
        final handled = ref.read(navigationProvider.notifier).handleBack();
        if (!handled) {
          // At root — double-back-to-exit pattern
          final now = DateTime.now();
          if (_lastBackPress != null &&
              now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
            // Second press within 2s → minimize app
            SystemNavigator.pop();
          } else {
            _lastBackPress = now;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  content: Text('Press back again to exit'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
          }
        }
      },
      child: Scaffold(
        backgroundColor: NinaadaColors.background,
        body: Stack(
          children: [
            // Main content area
            Positioned.fill(
              bottom: bottomNavHeight,
              child: Stack(
                children: [
                  // IndexedStack keeps all 4 tabs alive — scroll positions preserved
                  IndexedStack(
                    index: nav.currentTab.index,
                    children: const [
                      HomeScreen(),
                      ExploreScreen(),
                      LibraryScreen(),
                      RadioScreen(),
                    ],
                  ),
                  // Sub-view overlays on top without destroying the tab underneath
                  if (nav.subView != null)
                    Container(
                      color: NinaadaColors.background,
                      child: const SubViewRouter(),
                    ),
                  // Search overlay
                  if (nav.showSearch)
                    Container(
                      color: NinaadaColors.background,
                      child: const SearchOverlay(),
                    ),
                ],
              ),
            ),
            // Player overlay — single surface for mini + full player
            const Positioned.fill(
              child: PlayerOverlay(),
            ),
            // Bottom navigation bar — hidden when player is full-screen
            if (!isFullPlayer)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 70,
                child: const BottomNavBar(),
              ),
            // Ambient dim overlay (always returns Positioned)
            _AmbientDimOverlay(),
            // Phase 6: Offline mode banner
            const _OfflineBanner(),
            // Phase 9B: Behavior engine debug overlay (uncomment for debug)
            // if (kDebugMode) const BehaviorDebugOverlay(),
          ],
        ),
      ),
    );
  }

}

// ════════════════════════════════════════════════
//  AMBIENT DIM OVERLAY — Layer 4
// ════════════════════════════════════════════════
//
//  GPU-optimized: single black Container with controlled opacity.
//  Driven by ambientDimProvider (ValueNotifier<double>).
//  Uses ValueListenableBuilder to avoid full tree rebuilds.
//  IgnorePointer ensures all touches pass through.
// ════════════════════════════════════════════════

class _AmbientDimOverlay extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dimNotifier = ref.watch(ambientDimProvider);
    return ValueListenableBuilder<double>(
      valueListenable: dimNotifier,
      builder: (_, dimValue, __) {
        // IMPORTANT: Always return Positioned — non-Positioned children
        // in a Stack cause blank rendering on some Skia/OpenGLES devices
        // (e.g. OPPO CPH2001 with Adreno 610).
        if (dimValue <= 0.0) {
          return const Positioned(
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            child: SizedBox.shrink(),
          );
        }
        return Positioned.fill(
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withOpacity(dimValue.clamp(0.0, 0.8)),
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════
//  OFFLINE BANNER — Phase 6, Step 3
// ════════════════════════════════════════════════
//
//  32px subtle top banner. Visible only when network == offline.
//  No animation spam. No modal. Professional feel.
//  Positioned above safe area so it sits flush below the status bar.
// ════════════════════════════════════════════════

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final network = ref.watch(networkProvider);
    if (network != NetworkStatus.offline) {
      return const Positioned(
        left: 0, top: 0, width: 0, height: 0,
        child: SizedBox.shrink(),
      );
    }

    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: topPadding + 32,
      child: IgnorePointer(
        child: Container(
          alignment: Alignment.bottomCenter,
          padding: EdgeInsets.only(top: topPadding),
          decoration: const BoxDecoration(
            color: Color(0xDD1A1A2E),
            border: Border(
              bottom: BorderSide(color: Color(0xFF7C4DFF), width: 0.5),
            ),
          ),
          child: const SizedBox(
            height: 32,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off_rounded, size: 14, color: Color(0xFF999999)),
                SizedBox(width: 6),
                Text(
                  'Offline Mode',
                  style: TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
