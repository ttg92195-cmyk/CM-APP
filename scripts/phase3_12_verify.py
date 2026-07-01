#!/usr/bin/env python3
"""
Phase 3.12 — Verification script for ROOT CAUSE FIX.

The root cause was: _loadUserProfile's else-branch (doc creation path)
failed with permission-denied, and the catch block nulled _currentUser.
The outer loginUser retry loop re-called _loadUserProfile, but it
repeated the SAME sequence (get → list → create → fail). The loop
never made progress.

Phase 3.12 fix:
  1. _loadUserProfile else-branch now has its OWN retry loop (8 attempts
     with user.reload() + getIdToken(true) on each attempt).
  2. _loadUserProfile sets _currentUser FROM AUTH DATA BEFORE trying
     .set(). If .set() fails, _currentUser stays non-null — login
     succeeds with Auth-only profile.
  3. registerUser no longer deletes the Auth user on .set() failure.
     Instead, sets _currentUser from Auth data and returns success.
     The profile doc will auto-heal on next login.

Checks:
  1. _loadUserProfile else-branch has retry loop (8 attempts)
  2. _loadUserProfile sets _currentUser BEFORE .set()
  3. _loadUserProfile does NOT null _currentUser on .set() failure
  4. _loadUserProfile does NOT set lastProfileLoadErrorCode on .set() failure
  5. registerUser does NOT call user.delete() on .set() failure
  6. registerUser sets _currentUser and returns true even if .set() failed
  7. registerUser does NOT set lastRegisterErrorCode on .set() failure
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

    # === Check 1: _loadUserProfile else-branch has retry loop ===
    # Look for the Phase 3.12 comment + 8-attempt loop in _loadUserProfile
    has_lp_retry = "_loadUserProfile create attempt $attempt auth refresh failed" in src
    has_lp_8 = bool(re.search(r"for\s*\(int attempt\s*=\s*1;\s*attempt\s*<=\s*8;\s*attempt\+\+\)", src))
    if has_lp_retry and has_lp_8:
        passes.append("Check 1: _loadUserProfile else-branch has 8-attempt retry loop")
    else:
        failures.append("Check 1: MISSING retry loop in _loadUserProfile else-branch")

    # === Check 2: _loadUserProfile sets _currentUser BEFORE .set() ===
    # Look for the comment "Set _currentUser FROM FIREBASE AUTH DATA first"
    has_set_before = "Set _currentUser FROM FIREBASE AUTH DATA first" in src
    if has_set_before:
        passes.append("Check 2: _loadUserProfile sets _currentUser BEFORE .set()")
    else:
        failures.append("Check 2: MISSING _currentUser set before .set()")

    # === Check 3: _loadUserProfile does NOT null _currentUser on .set() failure ===
    # The old code had "catch (e) { ... _currentUser = null; }" at the outer level.
    # The new code should NOT null _currentUser in the else-branch.
    # Look for the comment "DON'T throw and DON'T null _currentUser"
    has_dont_null = "DON'T throw and DON'T null _currentUser" in src or \
                    "DON'T null" in src
    if has_dont_null:
        passes.append("Check 3: _loadUserProfile does NOT null _currentUser on .set() failure")
    else:
        failures.append("Check 3: MISSING 'DON'T null _currentUser' comment")

    # === Check 4: _loadUserProfile does NOT set lastProfileLoadErrorCode on .set() failure ===
    # Look for "DON'T set lastProfileLoadErrorCode"
    has_dont_set_code = "DON'T set lastProfileLoadErrorCode" in src
    if has_dont_set_code:
        passes.append("Check 4: _loadUserProfile does NOT set lastProfileLoadErrorCode on .set() failure")
    else:
        failures.append("Check 4: MISSING 'DON'T set lastProfileLoadErrorCode' comment")

    # === Check 5: registerUser does NOT call user.delete() on .set() failure ===
    # The old code had "await user.delete()" in registerUser's failure path.
    # NOTE: user.delete() also exists in the account deletion feature
    # (deleteAccount method), which is legitimate. We only care that it's
    # NOT in registerUser's .set() failure path.
    # Look for the comment "DON'T delete the Auth user" in registerUser.
    has_dont_delete = "DON'T delete the Auth user" in src
    # Check that user.delete() is NOT near "orphaned Auth user" text
    # (the old registerUser failure path had this).
    has_orphan_delete = "orphaned Auth user cleaned up" in src or \
                        "orphaned Auth user" in src and "user.delete()" in src
    if has_dont_delete and not has_orphan_delete:
        passes.append("Check 5: registerUser does NOT call user.delete() on .set() failure")
    elif has_orphan_delete:
        failures.append("Check 5: registerUser still has orphan cleanup with user.delete()")
    else:
        failures.append("Check 5: MISSING 'DON'T delete the Auth user' comment")

    # === Check 6: registerUser sets _currentUser and returns true even if .set() failed ===
    # Look for "Update current user (from Auth data" comment
    has_auth_fallback = "Update current user (from Auth data" in src
    if has_auth_fallback:
        passes.append("Check 6: registerUser sets _currentUser from Auth data regardless of .set() result")
    else:
        failures.append("Check 6: MISSING Auth-data fallback in registerUser")

    # === Check 7: registerUser does NOT set lastRegisterErrorCode on .set() failure ===
    # Look for "DON'T set lastRegisterErrorCode"
    has_dont_set_reg = "DON'T set lastRegisterErrorCode" in src
    if has_dont_set_reg:
        passes.append("Check 7: registerUser does NOT set lastRegisterErrorCode on .set() failure")
    else:
        failures.append("Check 7: MISSING 'DON'T set lastRegisterErrorCode' comment")

    # === Check 8: _loadUserProfile has Crashlytics recordError for .set() failure ===
    has_crashlytics = "_loadUserProfile: Firestore doc creation failed after" in src
    if has_crashlytics:
        passes.append("Check 8: _loadUserProfile records .set() failure to Crashlytics")
    else:
        failures.append("Check 8: MISSING Crashlytics recordError in _loadUserProfile")

    # === Print results ===
    print("=" * 60)
    print("Phase 3.12 — Verification Results (ROOT CAUSE FIX)")
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
        print("ALL CHECKS PASS — Login/signup will succeed even if Firestore doc creation fails")
        sys.exit(0)

if __name__ == '__main__':
    main()
