// ════════════════════════════════════════════════════════════════
//  APP VERSION — Phase 8, Step 5
// ════════════════════════════════════════════════════════════════
//
//  Single source of truth for version display in the app.
//  Must be kept in sync with pubspec.yaml on every release.
//
//  Versioning scheme:
//    major.minor.patch+buildNumber
//    - major: Breaking changes / major redesign
//    - minor: New features / significant improvements
//    - patch: Bug fixes / minor tweaks
//    - buildNumber: Monotonically increasing (Play Store requires this)
//
//  Pre-release checklist:
//    1. Bump version in pubspec.yaml
//    2. Update this file to match
//    3. Build release APK: flutter build apk --release
//    4. Test on physical device
//    5. Tag git: git tag v{version}
// ════════════════════════════════════════════════════════════════

const String appVersion = '1.0.0';
const int appBuildNumber = 1;
const String appVersionFull = '$appVersion+$appBuildNumber';
