import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ════════════════════════════════════════════════════════════════
//  USER PROFILE — Phase 9A, Step 1
// ════════════════════════════════════════════════════════════════
//
//  Persistent, NON-DECAYING record of the user's onboarding choices.
//
//  Unlike TasteProfileManager.profile (which uses 14-day half-life),
//  this stores the ORIGINAL selections forever. It's the permanent
//  anchor for:
//    • Home feed language filtering
//    • Explore page ordering
//    • Autoplay candidate bias
//    • Cold-start override (first 20 sessions)
//
//  Stored in Hive 'settings' box under key 'user_profile'.
//  Single source of truth. Not scattered primitives.
// ════════════════════════════════════════════════════════════════

class UserProfile {
  /// Primary language (first selected, or highest-priority).
  final String primaryLanguage;

  /// All selected languages in order of selection.
  final List<String> preferredLanguages;

  /// Artist names selected during onboarding.
  final List<String> preferredArtistNames;

  /// When the profile was created (onboarding completion time).
  final DateTime createdAt;

  /// Session counter — incremented each time app launches.
  /// Used for cold-start vs. mature model detection.
  final int sessionCount;

  const UserProfile({
    required this.primaryLanguage,
    required this.preferredLanguages,
    required this.preferredArtistNames,
    required this.createdAt,
    this.sessionCount = 0,
  });

  /// Empty profile for users who skip onboarding.
  factory UserProfile.empty() => UserProfile(
        primaryLanguage: 'hindi',
        preferredLanguages: const ['hindi'],
        preferredArtistNames: const [],
        createdAt: DateTime.now(),
      );

  /// Whether this is a cold-start user (< 20 sessions).
  bool get isColdStart => sessionCount < 20;

  /// Whether the user actually completed onboarding (vs. skip).
  bool get hasPreferences => preferredArtistNames.isNotEmpty;

  UserProfile copyWith({
    String? primaryLanguage,
    List<String>? preferredLanguages,
    List<String>? preferredArtistNames,
    DateTime? createdAt,
    int? sessionCount,
  }) {
    return UserProfile(
      primaryLanguage: primaryLanguage ?? this.primaryLanguage,
      preferredLanguages: preferredLanguages ?? this.preferredLanguages,
      preferredArtistNames:
          preferredArtistNames ?? this.preferredArtistNames,
      createdAt: createdAt ?? this.createdAt,
      sessionCount: sessionCount ?? this.sessionCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'primaryLanguage': primaryLanguage,
        'preferredLanguages': preferredLanguages,
        'preferredArtistNames': preferredArtistNames,
        'createdAt': createdAt.toIso8601String(),
        'sessionCount': sessionCount,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        primaryLanguage: json['primaryLanguage'] as String? ?? 'hindi',
        preferredLanguages: (json['preferredLanguages'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const ['hindi'],
        preferredArtistNames: (json['preferredArtistNames'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        sessionCount: json['sessionCount'] as int? ?? 0,
      );
}

// ════════════════════════════════════════════════════════════════
//  USER PROFILE NOTIFIER — Riverpod provider
// ════════════════════════════════════════════════════════════════

class UserProfileNotifier extends StateNotifier<UserProfile> {
  UserProfileNotifier() : super(UserProfile.empty()) {
    _load();
  }

  static const String _boxKey = 'user_profile';

  /// Load profile from Hive (called in constructor).
  void _load() {
    try {
      final box = Hive.box('settings');
      final raw = box.get(_boxKey);
      if (raw != null) {
        state = UserProfile.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw)),
        );
        // Increment session count on each load
        final updated = state.copyWith(sessionCount: state.sessionCount + 1);
        state = updated;
        _save(updated);
        debugPrint('=== USER PROFILE: loaded — lang=${state.primaryLanguage}, '
            'artists=${state.preferredArtistNames.length}, '
            'sessions=${state.sessionCount} ===');
      }
    } catch (e) {
      debugPrint('=== USER PROFILE: load error: $e ===');
    }
  }

  /// Save the profile from onboarding selections.
  Future<void> saveFromOnboarding({
    required List<String> languages,
    required List<String> artistNames,
  }) async {
    final profile = UserProfile(
      primaryLanguage: languages.isNotEmpty ? languages.first : 'hindi',
      preferredLanguages: languages.isNotEmpty ? languages : const ['hindi'],
      preferredArtistNames: artistNames,
      createdAt: DateTime.now(),
      sessionCount: 1,
    );
    state = profile;
    await _save(profile);
    debugPrint('=== USER PROFILE: saved from onboarding — '
        'langs=${languages.join(", ")}, artists=${artistNames.length} ===');
  }

  /// Clear profile (reinstall / reset).
  Future<void> clear() async {
    state = UserProfile.empty();
    final box = Hive.box('settings');
    await box.delete(_boxKey);
  }

  Future<void> _save(UserProfile profile) async {
    final box = Hive.box('settings');
    await box.put(_boxKey, jsonEncode(profile.toJson()));
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>(
  (ref) => UserProfileNotifier(),
);
