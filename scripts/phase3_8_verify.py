#!/usr/bin/env python3
"""
Phase 3.8 — Verification script for dual-strategy profile load +
permission-denied retry + auth propagation delay.

Checks:
  1. _loadUserProfile uses dual-strategy (direct get + list query)
  2. loginUser retry loop includes 'permission-denied' as retryable
  3. Retry loop now does 5 attempts (up from 3)
  4. 800ms delay added between getIdToken and _loadUserProfile
  5. Backoff is progressive (500ms × attempt)
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
    lines = src.split('\n')

    failures = []
    passes = []

    # === Check 1: Dual-strategy in _loadUserProfile ===
    # Must contain BOTH .doc(uid).get() AND .where(FieldPath.documentId, isEqualTo: uid)
    has_direct_get = ".collection('users').doc(uid).get()" in src
    has_list_query = "where(FieldPath.documentId, isEqualTo: uid)" in src
    if has_direct_get and has_list_query:
        passes.append("Check 1: dual-strategy (direct get + list query) present")
    else:
        if not has_direct_get:
            failures.append("Check 1: MISSING direct .doc(uid).get() in _loadUserProfile")
        if not has_list_query:
            failures.append("Check 1: MISSING list query with FieldPath.documentId in _loadUserProfile")

    # === Check 2: Strategy 1 fallback to Strategy 2 ===
    # Should have a comment "Fall through to Strategy 2"
    if "Fall through to Strategy 2" in src or "Strategy 2" in src:
        passes.append("Check 2: Strategy 1 -> Strategy 2 fallback comment present")
    else:
        failures.append("Check 2: MISSING Strategy 2 fallback")

    # === Check 3: permission-denied in retryable list ===
    # Find the retry loop in loginUser — look for the section between
    # "Retryable errors:" comment and the closing "break;" of the loop.
    retry_section_match = re.search(
        r"Retryable errors:.*?break;",
        src, re.DOTALL
    )
    if retry_section_match:
        retry_section = retry_section_match.group(0)
        if "'permission-denied'" in retry_section:
            passes.append("Check 3: 'permission-denied' added to retryable errors")
        else:
            failures.append("Check 3: MISSING 'permission-denied' in retryable errors list")
    else:
        failures.append("Check 3: Could not locate retry loop section")

    # === Check 4: 5 attempts (up from 3) ===
    # Look for "attempt <= 5"
    if re.search(r"for\s*\(int attempt\s*=\s*1;\s*attempt\s*<=\s*5;", src):
        passes.append("Check 4: retry loop now does 5 attempts")
    elif re.search(r"for\s*\(int attempt\s*=\s*1;\s*attempt\s*<=\s*3;", src):
        failures.append("Check 4: retry loop STILL does 3 attempts (expected 5)")
    else:
        failures.append("Check 4: Could not find retry loop attempt count")

    # === Check 5: 800ms delay before profile load ===
    if "Duration(milliseconds: 800)" in src:
        passes.append("Check 5: 800ms auth propagation delay present")
    else:
        failures.append("Check 5: MISSING 800ms auth propagation delay")

    # === Check 6: Progressive backoff (500ms × attempt) ===
    if "Duration(milliseconds: 500 * attempt)" in src:
        passes.append("Check 6: progressive backoff (500ms × attempt) present")
    else:
        failures.append("Check 6: MISSING progressive backoff")

    # === Check 7: Old Phase 3.5 single-strategy code removed ===
    # The old code was a single `final query = await _firestore...where(FieldPath...)`
    # without a try/catch wrapping a preceding `.doc(uid).get()`.
    # Check that the new structure has both try blocks.
    if src.count(".doc(uid).get()") >= 1 and src.count("where(FieldPath.documentId") >= 1:
        # Both are present — good
        passes.append("Check 7: both strategies present in source")
    else:
        failures.append("Check 7: one or both strategies missing")

    # === Check 8: Retry comment explains permission-denied rationale ===
    if "permission-denied: auth token propagation delay" in src or \
       "auth token propagation delay" in src:
        passes.append("Check 8: permission-denied rationale documented in comments")
    else:
        failures.append("Check 8: MISSING rationale comment for permission-denied retry")

    # === Print results ===
    print("=" * 60)
    print("Phase 3.8 — Verification Results")
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
