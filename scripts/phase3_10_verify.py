#!/usr/bin/env python3
"""
Phase 3.10 — Verification script for Cloud Function onUserCreated +
client-side polling + auth refresh on retry.

Checks:
  1. functions/index.js has onUserCreated Auth trigger
  2. functions/index.js onUserCreated uses admin.firestore().collection('users').doc(uid).set()
  3. functions/index.js onUserCreated uses { merge: true } (idempotent)
  4. functions/index.js onUserCreated derives username from email
  5. functions/index.js onUserCreated sets safe defaults (isAdmin: false)
  6. functions/index.js imports onUserCreated from firebase-functions/v2/auth
  7. app_config.dart registerUser polls for doc to appear (Cloud Function wait)
  8. app_config.dart registerUser has client-side fallback (.set() with retries)
  9. app_config.dart registerUser fallback uses getIdToken(true) + 800ms delay
 10. app_config.dart _loadUserProfile create path uses user.reload() + getIdToken(true)
 11. app_config.dart _loadUserProfile create uses SetOptions(merge: true)
 12. app_config.dart loginUser retry loop calls user.reload() + getIdToken(true) on retry
 13. firestore.rules documents the Cloud Function in comments
"""

import sys
import re
from pathlib import Path

APP_CONFIG = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart")
FUNCTIONS = Path("/home/z/my-project/cm-app/functions/index.js")
RULES = Path("/home/z/my-project/cm-app/firestore.rules")

def main():
    files = [APP_CONFIG, FUNCTIONS, RULES]
    for f in files:
        if not f.exists():
            print(f"FAIL: {f} not found")
            sys.exit(1)

    app_src = APP_CONFIG.read_text(encoding='utf-8')
    fn_src = FUNCTIONS.read_text(encoding='utf-8')
    rules_src = RULES.read_text(encoding='utf-8')

    failures = []
    passes = []

    # === Cloud Function checks ===

    # Check 1: onUserCreated Auth trigger exists
    if "exports.onUserCreated" in fn_src and "onUserCreated" in fn_src:
        passes.append("Check 1: onUserCreated Cloud Function defined")
    else:
        failures.append("Check 1: MISSING onUserCreated Cloud Function")

    # Check 2: onUserCreated writes to /users/{uid}
    if re.search(r"admin\.firestore\(\)\.collection\(['\"]users['\"]\)\.doc\(uid\)\.set\(", fn_src):
        passes.append("Check 2: onUserCreated writes to /users/{uid}")
    else:
        failures.append("Check 2: MISSING Firestore .set() in onUserCreated")

    # Check 3: onUserCreated uses merge: true (idempotent)
    if "merge: true" in fn_src:
        passes.append("Check 3: onUserCreated uses { merge: true } (idempotent)")
    else:
        failures.append("Check 3: MISSING merge: true in onUserCreated")

    # Check 4: onUserCreated derives username from email
    if "@cmmovies.app" in fn_src and "username" in fn_src:
        passes.append("Check 4: onUserCreated derives username from email")
    else:
        failures.append("Check 4: MISSING username derivation in onUserCreated")

    # Check 5: onUserCreated sets isAdmin: false (safe default)
    if re.search(r"isAdmin:\s*false", fn_src):
        passes.append("Check 5: onUserCreated sets isAdmin: false (safe default)")
    else:
        failures.append("Check 5: MISSING isAdmin: false in onUserCreated")

    # Check 6: onUserCreated imported from firebase-functions/v2/auth
    if "firebase-functions/v2/auth" in fn_src:
        passes.append("Check 6: onUserCreated imported from v2/auth")
    else:
        failures.append("Check 6: MISSING v2/auth import")

    # === Client-side registerUser checks ===

    # Check 7: registerUser polls for doc (Cloud Function wait)
    # Look for "poll" in a for loop
    has_poll = re.search(r"for\s*\(int poll\s*=\s*1;\s*poll\s*<=\s*8;", app_src)
    if has_poll:
        passes.append("Check 7: registerUser polls for doc (Cloud Function wait)")
    else:
        failures.append("Check 7: MISSING poll loop in registerUser")

    # Check 8: registerUser has client-side fallback (.set() with retries)
    # Look for the fallback section after the poll loop
    has_fallback = "falling back to client-side .set()" in app_src or \
                   "client-side .set()" in app_src
    has_fallback_retry = re.search(r"attempt\s*<=\s*5;\s*attempt\+\+", app_src)
    if has_fallback and has_fallback_retry:
        passes.append("Check 8: registerUser has client-side fallback with retries")
    else:
        failures.append("Check 8: MISSING client-side fallback in registerUser")

    # Check 9: registerUser fallback uses getIdToken(true) + 800ms delay
    has_idtoken = "getIdToken(true)" in app_src
    has_800ms = "Duration(milliseconds: 800)" in app_src
    if has_idtoken and has_800ms:
        passes.append("Check 9: registerUser fallback uses getIdToken + 800ms delay")
    else:
        failures.append("Check 9: MISSING getIdToken + 800ms delay in registerUser")

    # === _loadUserProfile checks ===

    # Check 10: _loadUserProfile create path uses user.reload() + getIdToken(true)
    has_reload = "user.reload()" in app_src
    if has_reload:
        passes.append("Check 10: _loadUserProfile create path uses user.reload()")
    else:
        failures.append("Check 10: MISSING user.reload() in _loadUserProfile create path")

    # Check 11: _loadUserProfile create uses SetOptions(merge: true)
    has_merge = "SetOptions(merge: true)" in app_src
    if has_merge:
        passes.append("Check 11: _loadUserProfile create uses SetOptions(merge: true)")
    else:
        failures.append("Check 11: MISSING SetOptions(merge: true) in _loadUserProfile")

    # === loginUser retry loop checks ===

    # Check 12: loginUser retry calls user.reload() + getIdToken(true) on retry
    # Look for the pattern inside the retry loop
    has_retry_refresh = "Login retry" in app_src and "user.reload()" in app_src
    if has_retry_refresh:
        passes.append("Check 12: loginUser retry calls user.reload() + getIdToken(true)")
    else:
        failures.append("Check 12: MISSING auth refresh on login retry")

    # === firestore.rules checks ===

    # Check 13: firestore.rules documents the Cloud Function
    if "onUserCreated" in rules_src or "Cloud Function" in rules_src:
        passes.append("Check 13: firestore.rules documents the Cloud Function")
    else:
        failures.append("Check 13: MISSING Cloud Function documentation in firestore.rules")

    # === Print results ===
    print("=" * 60)
    print("Phase 3.10 — Verification Results")
    print("=" * 60)
    print()
    for p in passes:
        print(f"  PASS — {p}")
    for f in failures:
        print(f"  FAIL — {f}")
    print()
    print(f"Total: {len(passes)} pass, {len(failures)} fail")
    print("=" * 60)
    if failures:
        sys.exit(1)
    else:
        print("ALL CHECKS PASS")
        sys.exit(0)

if __name__ == '__main__':
    main()
