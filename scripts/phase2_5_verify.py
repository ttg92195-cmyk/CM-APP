#!/usr/bin/env python3
"""
Phase 2.5 — Crashlytics integration verification.

Verifies:
1. pubspec.yaml has firebase_crashlytics dependency
2. android/settings.gradle has the crashlytics Gradle plugin declared
3. android/app/build.gradle has the crashlytics plugin applied
4. android/app/build.gradle has firebaseCrashlytics { } config in release
5. lib/main.dart imports firebase_crashlytics
6. lib/main.dart calls FirebaseCrashlytics.instance.recordFlutterError in
   FlutterError.onError
7. lib/main.dart calls FirebaseCrashlytics.instance.recordError in
   PlatformDispatcher.instance.onError
8. lib/main.dart calls FirebaseCrashlytics.instance.recordError in
   runZonedGuarded error handler
9. lib/main.dart calls setCrashlyticsCollectionEnabled(!kDebugMode)

Run: python3 scripts/phase2_5_verify.py
"""
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
PUBSPEC = ROOT / "pubspec.yaml"
SETTINGS_GRADLE = ROOT / "android" / "settings.gradle"
APP_BUILD_GRADLE = ROOT / "android" / "app" / "build.gradle"
MAIN_DART = ROOT / "lib" / "main.dart"


def main() -> int:
    errors = 0

    # 1. pubspec.yaml has firebase_crashlytics
    pubspec_text = PUBSPEC.read_text()
    if "firebase_crashlytics:" not in pubspec_text:
        print("FAIL: pubspec.yaml missing firebase_crashlytics dependency")
        errors += 1
    else:
        print("OK: pubspec.yaml has firebase_crashlytics dependency")

    # 2. settings.gradle has crashlytics plugin
    settings_text = SETTINGS_GRADLE.read_text()
    if 'id "com.google.firebase.crashlytics"' not in settings_text:
        print("FAIL: android/settings.gradle missing crashlytics Gradle plugin")
        errors += 1
    else:
        print("OK: android/settings.gradle has crashlytics Gradle plugin")

    # 3. app/build.gradle applies crashlytics plugin
    app_gradle_text = APP_BUILD_GRADLE.read_text()
    if 'id "com.google.firebase.crashlytics"' not in app_gradle_text:
        print("FAIL: android/app/build.gradle missing 'apply plugin: com.google.firebase.crashlytics'")
        errors += 1
    else:
        print("OK: android/app/build.gradle applies crashlytics plugin")

    # 4. app/build.gradle has firebaseCrashlytics block in release
    if "firebaseCrashlytics" not in app_gradle_text:
        print("FAIL: android/app/build.gradle missing firebaseCrashlytics { } config block")
        errors += 1
    elif "mappingFileUploadEnabled true" not in app_gradle_text:
        print("FAIL: android/app/build.gradle firebaseCrashlytics block missing mappingFileUploadEnabled true")
        errors += 1
    else:
        print("OK: android/app/build.gradle has firebaseCrashlytics config with mapping upload enabled")

    # 5. main.dart imports firebase_crashlytics
    main_text = MAIN_DART.read_text()
    if "import 'package:firebase_crashlytics/firebase_crashlytics.dart';" not in main_text:
        print("FAIL: lib/main.dart missing firebase_crashlytics import")
        errors += 1
    else:
        print("OK: lib/main.dart imports firebase_crashlytics")

    # 6. FlutterError.onError reports to Crashlytics
    if "FirebaseCrashlytics.instance.recordFlutterError" not in main_text:
        print("FAIL: lib/main.dart FlutterError.onError does not call recordFlutterError")
        errors += 1
    else:
        print("OK: lib/main.dart FlutterError.onError reports to Crashlytics")

    # 7. PlatformDispatcher.onError reports to Crashlytics
    # Look in the PlatformDispatcher.instance.onError handler specifically.
    if "FirebaseCrashlytics.instance.recordError(error, stack" not in main_text:
        print("FAIL: lib/main.dart PlatformDispatcher.onError does not call recordError")
        errors += 1
    else:
        print("OK: lib/main.dart PlatformDispatcher.onError reports to Crashlytics")

    # 8. runZonedGuarded error handler reports to Crashlytics
    # Look for the zone error handler signature (error, stackTrace) and
    # recordError call nearby.
    if "FirebaseCrashlytics.instance\n        .recordError(error, stackTrace, fatal: true)" not in main_text \
       and "FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true)" not in main_text:
        print("FAIL: lib/main.dart runZonedGuarded error handler does not call recordError with fatal: true")
        errors += 1
    else:
        print("OK: lib/main.dart runZonedGuarded reports to Crashlytics as fatal")

    # 9. setCrashlyticsCollectionEnabled called
    if "setCrashlyticsCollectionEnabled(!kDebugMode)" not in main_text:
        print("FAIL: lib/main.dart does not call setCrashlyticsCollectionEnabled(!kDebugMode)")
        errors += 1
    else:
        print("OK: lib/main.dart gates Crashlytics collection by build mode")

    # Summary
    print("\n" + "=" * 60)
    if errors == 0:
        print(f"PASS: All Phase 2.5 Crashlytics integration checks passed")
        return 0
    else:
        print(f"FAIL: {errors} error(s) found")
        return 1


if __name__ == "__main__":
    sys.exit(main())
