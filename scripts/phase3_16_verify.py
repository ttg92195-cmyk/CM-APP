#!/usr/bin/env python3
"""
Phase 3.16 verification script.

Checks that:
1. _tryCreateUserDocBlocking helper exists and is well-formed.
2. registerUser calls _tryCreateUserDocBlocking BEFORE returning success.
3. _loadUserProfile else-branch calls _tryCreateUserDocBlocking.
4. _createUserDocInBackground is still used as a fallback.
5. Brace/paren/bracket balance is correct.
6. No orphan references to removed Phase 3.13 patterns.
"""
import re
import sys
from pathlib import Path

APP_CONFIG = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart")
text = APP_CONFIG.read_text()

errors = []
warnings = []
passed = []

# ---------- 1. Brace balance ----------
def balance(s, op, cl):
    return s.count(op) - s.count(cl)

for op, cl, name in [('{', '}', 'braces'),
                     ('(', ')', 'parens'),
                     ('[', ']', 'brackets')]:
    # Strip strings & comments to avoid false positives.
    stripped = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)
    stripped = re.sub(r"'(?:[^'\\]|\\.)*'", "''", stripped)
    stripped = re.sub(r'//[^\n]*', '', stripped)
    stripped = re.sub(r'/\*.*?\*/', '', stripped, flags=re.DOTALL)
    diff = balance(stripped, op, cl)
    if diff == 0:
        passed.append(f"Balance OK: {name}")
    else:
        errors.append(f"IMBALANCE {name}: diff={diff}")

# ---------- 2. Helper exists ----------
m = re.search(r'Future<bool>\s+_tryCreateUserDocBlocking\(', text)
if m:
    passed.append("_tryCreateUserDocBlocking helper defined")
else:
    errors.append("_tryCreateUserDocBlocking helper NOT defined")

# ---------- 3. Helper signature ----------
sig = re.search(
    r'Future<bool>\s+_tryCreateUserDocBlocking\(\{[^}]*required\s+String\s+uid,'
    r'[^}]*required\s+String\s+username,'
    r'[^}]*required\s+String\s+email,'
    r'[^}]*required\s+String\s+regDate,',
    text, re.DOTALL)
if sig:
    passed.append("Helper signature has all 4 required params")
else:
    errors.append("Helper signature missing required params")

# ---------- 4. Helper returns true on success ----------
if re.search(r"return\s+true\s*;", text[text.find("_tryCreateUserDocBlocking"):text.find("_tryCreateUserDocBlocking")+3000]):
    passed.append("Helper returns true on success")
else:
    errors.append("Helper does not return true on success")

# ---------- 5. Helper returns false on all-fail ----------
if re.search(r"return\s+false\s*;", text[text.find("_tryCreateUserDocBlocking"):text.find("_tryCreateUserDocBlocking")+5000]):
    passed.append("Helper returns false on failure")
else:
    errors.append("Helper does not return false on failure")

# ---------- 6. registerUser calls helper ----------
# Find registerUser function body
reg_match = re.search(r'Future<bool>\s+registerUser\([^)]*\)\s*async\s*\{', text)
if reg_match:
    reg_start = reg_match.end()
    # Find matching closing brace
    depth = 1
    i = reg_start
    while i < len(text) and depth > 0:
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
        i += 1
    reg_body = text[reg_start:i]
    if "_tryCreateUserDocBlocking" in reg_body:
        passed.append("registerUser calls _tryCreateUserDocBlocking")
        # Check it's called BEFORE the background task fallback
        blocking_pos = reg_body.find("_tryCreateUserDocBlocking")
        bg_pos = reg_body.find("_createUserDocInBackground")
        if 0 <= blocking_pos < bg_pos:
            passed.append("Blocking call comes BEFORE background fallback in registerUser")
        else:
            errors.append("Blocking call does NOT come before background fallback")
        # Check it's called BEFORE return true
        ret_pos = reg_body.find("return true")
        if 0 <= blocking_pos < ret_pos:
            passed.append("Blocking call comes BEFORE return true in registerUser")
        else:
            errors.append("Blocking call does NOT come before return true")
    else:
        errors.append("registerUser does NOT call _tryCreateUserDocBlocking")
else:
    errors.append("registerUser function not found")

# ---------- 7. _loadUserProfile else-branch calls helper ----------
# Just check that _loadUserProfile contains the helper call somewhere
profile_match = re.search(r'Future<void>\s+_loadUserProfile\(', text)
if profile_match:
    profile_start = profile_match.end()
    depth = 1
    i = profile_start
    while i < len(text) and depth > 0:
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
        i += 1
    profile_body = text[profile_start:i]
    if "_tryCreateUserDocBlocking" in profile_body:
        passed.append("_loadUserProfile calls _tryCreateUserDocBlocking")
        blocking_pos = profile_body.find("_tryCreateUserDocBlocking")
        bg_pos = profile_body.find("_createUserDocInBackground")
        if 0 <= blocking_pos < bg_pos:
            passed.append("Blocking call comes BEFORE background fallback in _loadUserProfile")
        else:
            errors.append("Blocking call does NOT come before background fallback in _loadUserProfile")
    else:
        errors.append("_loadUserProfile does NOT call _tryCreateUserDocBlocking")
else:
    errors.append("_loadUserProfile function not found")

# ---------- 8. Background task still exists as fallback ----------
if re.search(r'_createUserDocInBackground\(', text):
    passed.append("_createUserDocInBackground still exists as fallback")
else:
    errors.append("_createUserDocInBackground was removed entirely")

# ---------- 9. Crashlytics reporting on blocking failure ----------
helper_section = text[text.find("_tryCreateUserDocBlocking"):text.find("_tryCreateUserDocBlocking")+5000]
if "FirebaseCrashlytics.instance.recordError" in helper_section:
    passed.append("Blocking failure reports to Crashlytics")
else:
    warnings.append("Blocking failure does NOT report to Crashlytics")

# ---------- 10. Delays schedule ----------
if re.search(r"final\s+delays\s*=\s*<int>\s*\[\s*200\s*,\s*500\s*\]", helper_section):
    passed.append("Delays schedule: [200, 500] ms")
else:
    warnings.append("Delays schedule not as expected (expected [200, 500])")

# ---------- 11. Old Phase 3.13 misleading comment removed from registerUser ----------
if "Phase 3.13 — NON-BLOCKING doc creation" in text:
    # Find context
    idx = text.find("Phase 3.13 — NON-BLOCKING doc creation")
    context = text[max(0,idx-100):idx+200]
    if "registerUser" in context or "_loadUserProfile" in context:
        errors.append(f"Old Phase 3.13 NON-BLOCKING comment still in function body: ...{context[:200]}...")
    else:
        passed.append("Old Phase 3.13 NON-BLOCKING comment cleaned from registerUser")

# ---------- Report ----------
print("=" * 60)
print("Phase 3.16 Verification")
print("=" * 60)
print(f"\nPASS: {len(passed)}")
for p in passed:
    print(f"  ✓ {p}")
if warnings:
    print(f"\nWARN: {len(warnings)}")
    for w in warnings:
        print(f"  ! {w}")
if errors:
    print(f"\nFAIL: {len(errors)}")
    for e in errors:
        print(f"  ✗ {e}")
    sys.exit(1)
print("\nAll checks passed.")
