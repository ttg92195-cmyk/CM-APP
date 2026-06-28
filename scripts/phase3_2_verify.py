#!/usr/bin/env python3
"""
Phase 3.2 — Login/Signup diagnostic build verification.

Verifies that the diagnostic changes are correctly implemented:
  1. App Check activation is DISABLED in main.dart (commented out).
  2. app_config.dart captures actual Firebase error codes in
     lastLoginErrorCode / lastRegisterErrorCode fields.
  3. login_page.dart surfaces the actual error code in the SnackBar.
  4. Errors are reported to Crashlytics for dashboard visibility.
  5. No regression on Phase 2.8 rate limiting or Phase 3.1 banner fix.

Run:
    python3 scripts/phase3_2_verify.py

Exit code 0 = all checks pass; 1 = at least one check failed.
"""

import sys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Check:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.failures = []

    def ok(self, name):
        self.passed += 1
        print(f"  PASS: {name}")

    def fail(self, name, detail=""):
        self.failed += 1
        self.failures.append((name, detail))
        msg = f"  FAIL: {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)

    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*60}")
        print(f"Phase 3.2 verification: {self.passed}/{total} checks passed")
        if self.failed:
            print(f"FAILURES:")
            for name, detail in self.failures:
                print(f"  - {name}: {detail}")
            return 1
        return 0


def read(rel_path):
    p = ROOT / rel_path
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")


def check_main_app_check_disabled(c):
    print("\n[1] main.dart — App Check activation disabled")
    src = read("lib/main.dart")
    if not src:
        c.fail("file exists", "main.dart missing")
        return

    c.ok("file exists")

    # The activate() calls should be commented out
    active_calls = len(re.findall(r"^\s*await\s+FirebaseAppCheck\.instance\.activate", src, re.MULTILINE))
    commented_calls = len(re.findall(r"^\s*//\s*await\s+FirebaseAppCheck\.instance\.activate", src, re.MULTILINE))

    if active_calls == 0:
        c.ok(f"no active FirebaseAppCheck.activate() calls (found {active_calls})")
    else:
        c.fail(f"no active FirebaseAppCheck.activate() calls", f"found {active_calls} active calls")

    if commented_calls >= 2:
        c.ok(f"FirebaseAppCheck.activate() commented out ({commented_calls} instances preserved)")
    else:
        c.fail(f"FirebaseAppCheck.activate() commented out", f"found {commented_calls} commented instances (expected >= 2)")

    # Phase 3.2 marker should be present
    if "Phase 3.2" in src and "App Check activation DISABLED" in src:
        c.ok("Phase 3.2 disable marker present")
    else:
        c.fail("Phase 3.2 disable marker present")

    # The debugPrint confirming disable should be active (not commented)
    if "debugPrint('Phase 3.2: App Check activation DISABLED" in src:
        c.ok("Phase 3.2 disable debugPrint active")
    else:
        c.fail("Phase 3.2 disable debugPrint active")


def check_app_config_diagnostic_fields(c):
    print("\n[2] app_config.dart — diagnostic error capture fields")
    src = read("lib/more_libs/setting/app_config.dart")
    if not src:
        c.fail("file exists", "app_config.dart missing")
        return

    c.ok("file exists")

    # Diagnostic fields
    for field in ["lastLoginErrorCode", "lastLoginErrorMessage",
                  "lastRegisterErrorCode", "lastRegisterErrorMessage"]:
        if field in src:
            c.ok(f"field '{field}' declared")
        else:
            c.fail(f"field '{field}' declared")

    # Crashlytics import
    if "import 'package:firebase_crashlytics/firebase_crashlytics.dart'" in src:
        c.ok("firebase_crashlytics import present")
    else:
        c.fail("firebase_crashlytics import present")

    # loginUser captures error code
    login_section = src[src.index("Future<bool> loginUser("):]
    login_section = login_section[:login_section.index("  // Logout")]
    if "lastLoginErrorCode = e.code" in login_section:
        c.ok("loginUser captures FirebaseAuthException error code")
    else:
        c.fail("loginUser captures FirebaseAuthException error code")

    if "lastLoginErrorCode = 'non-auth-exception'" in login_section:
        c.ok("loginUser captures non-Auth exceptions too")
    else:
        c.fail("loginUser captures non-Auth exceptions too")

    if "FirebaseCrashlytics.instance.recordError" in login_section:
        c.ok("loginUser reports errors to Crashlytics")
    else:
        c.fail("loginUser reports errors to Crashlytics")

    # registerUser captures error code
    reg_section = src[src.index("Future<bool> registerUser("):]
    reg_section = reg_section[:reg_section.index("  // Login user with Firebase Auth")]
    if "lastRegisterErrorCode = e.code" in reg_section:
        c.ok("registerUser captures FirebaseAuthException error code")
    else:
        c.fail("registerUser captures FirebaseAuthException error code")

    if "lastRegisterErrorCode = 'non-auth-exception'" in reg_section:
        c.ok("registerUser captures non-Auth exceptions too")
    else:
        c.fail("registerUser captures non-Auth exceptions too")

    if "FirebaseCrashlytics.instance.recordError" in reg_section:
        c.ok("registerUser reports errors to Crashlytics")
    else:
        c.fail("registerUser reports errors to Crashlytics")

    # Fields cleared before each attempt
    if "lastLoginErrorCode = null" in login_section:
        c.ok("loginUser clears diagnostic fields before attempt")
    else:
        c.fail("loginUser clears diagnostic fields before attempt")

    if "lastRegisterErrorCode = null" in reg_section:
        c.ok("registerUser clears diagnostic fields before attempt")
    else:
        c.fail("registerUser clears diagnostic fields before attempt")


def check_login_page_diagnostic_display(c):
    print("\n[3] login_page.dart — diagnostic SnackBar display")
    src = read("lib/app/ui/screens/login_page.dart")
    if not src:
        c.fail("file exists", "login_page.dart missing")
        return

    c.ok("file exists")

    # Login failure path shows diagnostic
    if "appConfig.lastLoginErrorCode" in src:
        c.ok("login_page reads lastLoginErrorCode from AppConfig")
    else:
        c.fail("login_page reads lastLoginErrorCode from AppConfig")

    if "Login failed [code:" in src:
        c.ok("login SnackBar shows 'Login failed [code: ...]' format")
    else:
        c.fail("login SnackBar shows 'Login failed [code: ...]' format")

    # Register failure path shows diagnostic
    if "appConfig.lastRegisterErrorCode" in src:
        c.ok("login_page reads lastRegisterErrorCode from AppConfig")
    else:
        c.fail("login_page reads lastRegisterErrorCode from AppConfig")

    if "Register failed [code:" in src:
        c.ok("register SnackBar shows 'Register failed [code: ...]' format")
    else:
        c.fail("register SnackBar shows 'Register failed [code: ...]' format")

    # SnackBar duration increased for readability
    if "duration: const Duration(seconds: 8)" in src:
        c.ok("SnackBar duration increased to 8s for diagnostic readability")
    else:
        c.fail("SnackBar duration increased to 8s for diagnostic readability")

    # Phase 3.2 marker
    if "Phase 3.2" in src and "TEMPORARY diagnostic" in src:
        c.ok("Phase 3.2 TEMPORARY diagnostic markers present")
    else:
        c.fail("Phase 3.2 TEMPORARY diagnostic markers present")


def check_no_regression(c):
    print("\n[4] No regression on Phase 2.8 + Phase 3.1")
    login = read("lib/app/ui/screens/login_page.dart")
    if "RateLimitPolicies.authLoginAttempt" in login:
        c.ok("Phase 2.8 rate limiting intact in LoginPage (login)")
    else:
        c.fail("Phase 2.8 rate limiting intact in LoginPage (login)")

    if "RateLimitPolicies.authSignupAttempt" in login:
        c.ok("Phase 2.8 rate limiting intact in LoginPage (signup)")
    else:
        c.fail("Phase 2.8 rate limiting intact in LoginPage (signup)")

    if "RateLimitPolicies.authPasswordReset" in login:
        c.ok("Phase 2.8 rate limiting intact in LoginPage (password reset)")
    else:
        c.fail("Phase 2.8 rate limiting intact in LoginPage (password reset)")

    fcs = read("lib/app/core/services/firestore_content_service.dart")
    if "RateLimiter.instance.enforce" in fcs:
        c.ok("Phase 2.8 rate limiting intact in FirestoreContentService")
    else:
        c.fail("Phase 2.8 rate limiting intact in FirestoreContentService")

    home_screen = read("lib/app/ui/home/home_screen.dart")
    if "pauseAutoScroll" in home_screen and "resumeAutoScroll" in home_screen:
        c.ok("Phase 3.1 banner pause/resume methods intact")
    else:
        c.fail("Phase 3.1 banner pause/resume methods intact")

    home_page = read("lib/app/ui/home/home_page.dart")
    if "_pushRouteWithBannerPause" in home_page:
        c.ok("Phase 3.1 Navigator.push wrapper intact")
    else:
        c.fail("Phase 3.1 Navigator.push wrapper intact")

    rules = read("firestore.rules")
    if "admin_audit" in rules and "isValidMovie" in rules:
        c.ok("Phase 2.4 + 2.6 Firestore rules intact")
    else:
        c.fail("Phase 2.4 + 2.6 Firestore rules intact")


def main():
    print("="*60)
    print("Phase 3.2 — Login/Signup diagnostic build verification")
    print("="*60)

    c = Check()

    check_main_app_check_disabled(c)
    check_app_config_diagnostic_fields(c)
    check_login_page_diagnostic_display(c)
    check_no_regression(c)

    sys.exit(c.summary())


if __name__ == "__main__":
    main()
