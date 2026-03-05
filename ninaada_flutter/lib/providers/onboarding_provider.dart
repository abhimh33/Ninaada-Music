import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ninaada_music/data/network_manager.dart';

// ════════════════════════════════════════════════════════════════
//  ONBOARDING GUARD — One-time taste bootstrapping gate
// ════════════════════════════════════════════════════════════════
//
//  Controls whether the user has completed the cold-start onboarding
//  flow. Stored in the Hive 'settings' box under 'hasCompletedOnboarding'.
//
//  If false → OnboardingScreen (pushReplacement, no back button escape)
//  If true  → AppShell (normal app)
//
//  This provider is read-only from UI; mutation happens through the
//  notifier's completeOnboarding() method.
// ════════════════════════════════════════════════════════════════

class OnboardingState {
  final bool hasCompletedOnboarding;
  const OnboardingState({this.hasCompletedOnboarding = false});

  OnboardingState copyWith({bool? hasCompletedOnboarding}) {
    return OnboardingState(
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  OnboardingNotifier() : super(const OnboardingState()) {
    _load();
  }

  void _load() {
    final box = Hive.box('settings');
    final done = box.get('hasCompletedOnboarding', defaultValue: false) as bool;
    state = OnboardingState(hasCompletedOnboarding: done);
  }

  /// Mark onboarding as complete and persist to Hive.
  /// Phase 9A: Also clears stale API caches so the home feed
  /// fetches fresh language-personalized content.
  Future<void> completeOnboarding() async {
    final box = Hive.box('settings');
    await box.put('hasCompletedOnboarding', true);
    state = state.copyWith(hasCompletedOnboarding: true);

    // Phase 9A, Step 6: Cache busting — clear stale API caches so
    // home feed, search, and explore fetch fresh personalized content.
    try {
      await NetworkManager().clearCache();
      final searchBox = Hive.box('search');
      await searchBox.clear();
    } catch (_) {
      // Non-critical — app works without cache clearing
    }
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>(
  (ref) => OnboardingNotifier(),
);
