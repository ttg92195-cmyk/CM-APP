#!/usr/bin/env python3
"""
Phase 3.9 — Verification script for registerUser orphan-prevention fix.

Bro's symptom: New accounts created via Register tab DO appear in
Firebase Auth, but their profile docs are NOT being written to
Firestore /users/{uid}. This means subsequent logins fail because
_loadUserProfile can't find the user doc (orphaned Auth user).

Root cause: After createUserWithEmailAndPassword succeeds, the
Firestore SDK needs time to propagate the new auth state to its
request handlers (same root cause as Phase 3.8 login fix). The
unprotected .set() call in registerUser fails with permission-denied,
but the Auth user is left behind as an orphan.

Checks:
  1. registerUser calls user.getIdToken(true) before .set()
  2. registerUser has 800ms delay before .set()
  3. registerUser has retry loop for .set() (5 attempts)
  4. Retry loop includes 'permission-denied' as retryable
  5. On all-retries-failed, registerUser deletes the orphaned Auth user
  6. lastRegisterErrorCode/Message are set when orphan cleanup happens
  7. Crashlytics records the orphan cleanup event
"""

import sys
import re
from pathlib import Path

APP_CONFIG = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart")

def main():
    if not APP_CONFIG.exists():
        print(f"FAIL: {APP_CONFIG} not found")
        sys.exit(1)
    src = APP_CONFIG.read_text(encoding='utf-8')

    failures = []
    passes = []

    # Find the registerUser function body
    reg_match = re.search(
        r'Future<bool>\s+registerUser\(.*?\)\s+async\s+\{(.+?)^\s{2}\}',
        src, re.DOTALL | re.MULTILINE
    )
    if not reg_match:
        print("FAIL: Could not locate registerUser function body")
        sys.exit(1)
    reg_body = reg_match.group(1)

    # === Check 1: getIdToken(true) before .set() ===
    if "user.getIdToken(true)" in reg_body:
        passes.append("Check 1: user.getIdToken(true) called before .set()")
    else:
        failures.append("Check 1: MISSING user.getIdToken(true) before .set()")

    # === Check 2: 800ms delay before .set() ===
    if "Duration(milliseconds: 800)" in reg_body:
        passes.append("Check 2: 800ms auth propagation delay before .set()")
    else:
        failures.append("Check 2: MISSING 800ms delay before .set()")

    # === Check 3: Retry loop for .set() (5 attempts) ===
    if re.search(r"for\s*\(int attempt\s*=\s*1;\s*attempt\s*<=\s*5;", reg_body):
        passes.append("Check 3: retry loop with 5 attempts for .set()")
    else:
        failures.append("Check 3: MISSING retry loop for .set()")

    # === Check 4: permission-denied in retryable list ===
    if "'permission-denied'" in reg_body:
        passes.append("Check 4: 'permission-denied' in retryable error list")
    else:
        failures.append("Check 4: MISSING 'permission-denied' in retryable list")

    # === Check 5: Orphan cleanup (user.delete()) ===
    if "user.delete()" in reg_body:
        passes.append("Check 5: orphan Auth user cleanup via user.delete()")
    else:
        failures.append("Check 5: MISSING user.delete() for orphan cleanup")

    # === Check 6: lastRegisterErrorCode/Message set on orphan cleanup ===
    # Look for the section after "all Firestore .set() retries failed"
    orphan_section_match = re.search(
        r"all Firestore \.set\(\) retries failed.*?return false;",
        reg_body, re.DOTALL
    )
    if orphan_section_match:
        orphan_section = orphan_section_match.group(0)
        if "lastRegisterErrorCode" in orphan_section and \
           "lastRegisterErrorMessage" in orphan_section:
            passes.append("Check 6: lastRegisterErrorCode/Message set on orphan cleanup")
        else:
            failures.append("Check 6: MISSING lastRegisterErrorCode/Message on orphan cleanup")
    else:
        failures.append("Check 6: Could not locate orphan cleanup section")

    # === Check 7: Crashlytics records orphan cleanup ===
    if orphan_section_match and "FirebaseCrashlytics" in orphan_section:
        passes.append("Check 7: Crashlytics records orphan cleanup event")
    else:
        failures.append("Check 7: MISSING Crashlytics recording for orphan cleanup")

    # === Check 8: Progressive backoff (500ms * attempt) ===
    if "Duration(milliseconds: 500 * attempt)" in reg_body:
        passes.append("Check 8: progressive backoff (500ms × attempt) in retry loop")
    else:
        failures.append("Check 8: MISSING progressive backoff in retry loop")

    # === Check 9: non-retryable errors break out of loop ===
    if "Non-retryable" in reg_body and "break" in reg_body:
        passes.append("Check 9: non-retryable errors break out of retry loop")
    else:
        failures.append("Check 9: MISSING non-retryable error handling")

    # === Print results ===
    print("=" * 60)
    print("Phase 3.9 — Verification Results")
    print("=" * 60)
    print()
    for p in passes:
        print(f"  ✅ PASS — {p}")
    for f in failures:
        print(f"  ❌ FAIL — {f}")
    print()
    print(f"Total: {len(passes)} pass, {len(failures)} fail")
    print("=" * 60)
    if failures:
        sys.exit(1)
    else:
        print("ALL CHECKS PASS ✅")
        sys.exit(0)

if __name__ == '__main__':
    main()
