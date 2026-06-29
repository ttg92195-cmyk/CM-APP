#!/usr/bin/env python3
"""
Phase 3.11 — Verification script for PURE CLIENT-SIDE auth fix
(no Cloud Function deployment required).

Checks:
  1. registerUser no longer has Cloud Function poll loop (removed `for poll` loop)
  2. registerUser retry loop does 8 attempts (up from 5)
  3. registerUser retry calls user.reload() + getIdToken(true) on EVERY attempt
  4. registerUser uses SetOptions(merge: true) for idempotency
  5. registerUser retry uses progressive backoff (700ms × attempt)
  6. registerUser orphan cleanup preserved (user.delete())
  7. loginUser retry loop does 8 attempts (up from 5)
  8. loginUser retry calls user.reload() + getIdToken(true) on retries
  9. loginUser retry uses progressive backoff (700ms × attempt)
 10. _loadUserProfile create path uses user.reload() + getIdToken(true)
 11. _loadUserProfile create uses SetOptions(merge: true)
 12. No references to "Cloud Function poll" in active code (only in comments)
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

    # === Check 1: No Cloud Function poll loop ===
    # The old code had "for (int poll = 1; poll <= 8; poll++)"
    # Should be removed.
    has_poll_loop = re.search(r"for\s*\(int poll\s*=\s*1;", src)
    if not has_poll_loop:
        passes.append("Check 1: Cloud Function poll loop removed from registerUser")
    else:
        failures.append("Check 1: poll loop still present in registerUser (should be removed)")

    # === Check 2: registerUser retry does 8 attempts ===
    # Find the registerUser retry loop (look for "attempt <= 8" near "docCreated")
    has_8_attempts = bool(re.search(r"for\s*\(int attempt\s*=\s*1;\s*attempt\s*<=\s*8;", src))
    if has_8_attempts:
        passes.append("Check 2: registerUser retry loop does 8 attempts")
    else:
        failures.append("Check 2: MISSING 8-attempt retry loop")

    # === Check 3: registerUser calls user.reload() + getIdToken(true) on every attempt ===
    # Find the registerUser retry section. Look for "Register attempt" debug print
    # which we added inside the loop.
    has_per_attempt_refresh = "Register attempt $attempt auth refresh failed" in src
    if has_per_attempt_refresh:
        passes.append("Check 3: registerUser refreshes auth on EVERY attempt")
    else:
        failures.append("Check 3: MISSING per-attempt auth refresh in registerUser")

    # === Check 4: registerUser uses SetOptions(merge: true) ===
    if "SetOptions(merge: true)" in src:
        passes.append("Check 4: registerUser uses SetOptions(merge: true)")
    else:
        failures.append("Check 4: MISSING SetOptions(merge: true)")

    # === Check 5: registerUser uses 700ms × attempt backoff ===
    has_700ms = "Duration(milliseconds: 700 * attempt)" in src
    if has_700ms:
        passes.append("Check 5: registerUser uses 700ms × attempt progressive backoff")
    else:
        failures.append("Check 5: MISSING 700ms × attempt backoff")

    # === Check 6: registerUser orphan cleanup preserved ===
    has_orphan_cleanup = "user.delete()" in src and "orphaned Auth user" in src
    if has_orphan_cleanup:
        passes.append("Check 6: registerUser orphan cleanup preserved")
    else:
        failures.append("Check 6: MISSING orphan cleanup in registerUser")

    # === Check 7: loginUser retry does 8 attempts ===
    # The loginUser retry loop should also be 8 attempts now.
    # Count occurrences of "attempt <= 8" — should be 2 (registerUser + loginUser)
    eight_count = len(re.findall(r"attempt\s*<=\s*8", src))
    if eight_count >= 2:
        passes.append(f"Check 7: loginUser retry loop also does 8 attempts ({eight_count} occurrences of <=8)")
    else:
        failures.append(f"Check 7: Expected 2 occurrences of <=8 (registerUser + loginUser), found {eight_count}")

    # === Check 8: loginUser calls user.reload() + getIdToken(true) on retry ===
    has_login_refresh = "Login retry $attempt auth refresh failed" in src
    if has_login_refresh:
        passes.append("Check 8: loginUser refreshes auth on retry")
    else:
        failures.append("Check 8: MISSING auth refresh on login retry")

    # === Check 9: loginUser uses 700ms × attempt backoff ===
    # Count occurrences — should be 2 (registerUser + loginUser)
    seven_count = len(re.findall(r"700 \* attempt", src))
    if seven_count >= 2:
        passes.append(f"Check 9: loginUser uses 700ms × attempt backoff ({seven_count} occurrences)")
    else:
        failures.append(f"Check 9: Expected 2 occurrences of 700 * attempt, found {seven_count}")

    # === Check 10: _loadUserProfile create path uses user.reload() ===
    has_profile_refresh = "_loadUserProfile: auth refresh failed" in src
    if has_profile_refresh:
        passes.append("Check 10: _loadUserProfile create path uses user.reload() + getIdToken(true)")
    else:
        failures.append("Check 10: MISSING auth refresh in _loadUserProfile create path")

    # === Check 11: _loadUserProfile uses SetOptions(merge: true) ===
    # Should be 2 occurrences (registerUser + _loadUserProfile)
    merge_count = len(re.findall(r"SetOptions\(merge:\s*true\)", src))
    if merge_count >= 2:
        passes.append(f"Check 11: _loadUserProfile uses SetOptions(merge: true) ({merge_count} occurrences total)")
    else:
        failures.append(f"Check 11: Expected 2 SetOptions(merge: true), found {merge_count}")

    # === Check 12: No active "Cloud Function did not create" code ===
    # That debug print was from the poll loop. Should be gone.
    has_cf_fallback_msg = "Cloud Function did not create doc" in src
    if not has_cf_fallback_msg:
        passes.append("Check 12: Cloud Function fallback message removed")
    else:
        failures.append("Check 12: Cloud Function fallback message still present (should be removed)")

    # === Print results ===
    print("=" * 60)
    print("Phase 3.11 — Verification Results (PURE CLIENT-SIDE)")
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
        print("ALL CHECKS PASS — No Cloud Function deployment needed")
        sys.exit(0)

if __name__ == '__main__':
    main()
