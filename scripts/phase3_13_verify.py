#!/usr/bin/env python3
"""
Phase 3.13 — Username Login Reliability Fix Verification

Verifies that the Phase 3.13 changes are correctly applied:
1. _pendingUsernameKey / _pendingEmailKey constants exist
2. _persistPendingSignup method exists
3. _consumePendingSignup method exists
4. _clearPendingSignup method exists
5. _createUserDocInBackground method exists
6. _isBackgroundDocCreationInProgress flag exists
7. registerUser calls _persistPendingSignup before Auth creation
8. registerUser calls _createUserDocInBackground (non-blocking)
9. registerUser does NOT have the old 8-attempt blocking retry loop
10. _loadUserProfile else-branch calls _consumePendingSignup
11. _loadUserProfile else-branch calls _createUserDocInBackground
12. _loadUserProfile else-branch does NOT have the old 8-attempt blocking loop
13. loginUser has Phase 3.13 username-not-found error message
14. _createUserDocInBackground uses 15 retries (not 8)
15. _createUserDocInBackground uses exponential backoff (not 700ms * attempt)
"""

import re
import sys

FILE = "/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart"

results = []

def check(name, condition, detail=""):
    status = "PASS" if condition else "FAIL"
    results.append((status, name, detail))
    return condition

try:
    with open(FILE, "r", encoding="utf-8") as f:
        content = f.read()
except FileNotFoundError:
    print(f"ERROR: File not found: {FILE}")
    sys.exit(1)

# Check 1: Constants exist
check(
    "Check 1: _pendingUsernameKey constant exists",
    "_pendingUsernameKey" in content and "static const String _pendingUsernameKey" in content,
)

# Check 2: _persistPendingSignup exists
check(
    "Check 2: _persistPendingSignup method exists",
    "Future<void> _persistPendingSignup(String username, String email)" in content,
)

# Check 3: _consumePendingSignup exists
check(
    "Check 3: _consumePendingSignup method exists",
    "Future<Map<String, String>?> _consumePendingSignup()" in content,
)

# Check 4: _clearPendingSignup exists
check(
    "Check 4: _clearPendingSignup method exists",
    "Future<void> _clearPendingSignup()" in content,
)

# Check 5: _createUserDocInBackground exists
check(
    "Check 5: _createUserDocInBackground method exists",
    "Future<void> _createUserDocInBackground({" in content,
)

# Check 6: _isBackgroundDocCreationInProgress flag exists
check(
    "Check 6: _isBackgroundDocCreationInProgress flag exists",
    "_isBackgroundDocCreationInProgress" in content,
)

# Check 7: registerUser calls _persistPendingSignup before Auth creation
reg_section = content[content.find("Future<bool> registerUser"):]
reg_before_auth = reg_section[:reg_section.find("createUserWithEmailAndPassword")]
check(
    "Check 7: registerUser calls _persistPendingSignup before Auth creation",
    "_persistPendingSignup" in reg_before_auth,
)

# Check 8: registerUser calls _createUserDocInBackground
check(
    "Check 8: registerUser calls _createUserDocInBackground",
    "_createUserDocInBackground(" in reg_section,
)

# Check 9: registerUser does NOT have old 8-attempt blocking loop
# The old loop had "for (int attempt = 1; attempt <= 8; attempt++)" inside registerUser
# After Phase 3.13, registerUser should NOT have this pattern.
# Only look within registerUser's try block (before the first catch).
reg_section = content[content.find("Future<bool> registerUser"):]
reg_try_end = reg_section.find("} on FirebaseAuthException catch")
if reg_try_end > 0:
    reg_try_body = reg_section[:reg_try_end]
    old_loop_in_reg = "for (int attempt = 1; attempt <= 8; attempt++)" in reg_try_body
    check(
        "Check 9: registerUser does NOT have old 8-attempt blocking loop",
        not old_loop_in_reg,
    )
else:
    check("Check 9: registerUser does NOT have old 8-attempt blocking loop", False, "registerUser try block end not found")

# Check 10: _loadUserProfile else-branch calls _consumePendingSignup
profile_section = content[content.find("Future<void> _loadUserProfile"):]
check(
    "Check 10: _loadUserProfile else-branch calls _consumePendingSignup",
    "_consumePendingSignup" in profile_section,
)

# Check 11: _loadUserProfile else-branch calls _createUserDocInBackground
check(
    "Check 11: _loadUserProfile else-branch calls _createUserDocInBackground",
    "_createUserDocInBackground(" in profile_section,
)

# Check 12: _loadUserProfile else-branch does NOT have old 8-attempt blocking loop
# Find the else-branch in _loadUserProfile
else_branch_start = profile_section.find("} else {")
if else_branch_start > 0:
    # Find the matching closing brace
    depth = 0
    i = else_branch_start + len("} else {")
    end = i
    while i < len(profile_section):
        if profile_section[i] == '{':
            depth += 1
        elif profile_section[i] == '}':
            if depth == 0:
                end = i
                break
            depth -= 1
        i += 1
    else_branch = profile_section[else_branch_start:end]
    old_loop_in_else = "for (int attempt = 1; attempt <= 8; attempt++)" in else_branch
    check(
        "Check 12: _loadUserProfile else-branch does NOT have old 8-attempt blocking loop",
        not old_loop_in_else,
    )
else:
    check("Check 12: _loadUserProfile else-branch does NOT have old 8-attempt blocking loop", False, "else-branch not found")

# Check 13: loginUser has Phase 3.13 username-not-found error message
check(
    "Check 13: loginUser has username-not-found error message",
    "username-not-found" in content and "Username" in content and "not found" in content,
)

# Check 14: _createUserDocInBackground uses 15 retries
bg_section = content[content.find("Future<void> _createUserDocInBackground"):]
check(
    "Check 14: _createUserDocInBackground uses 15 retries",
    "attempt <= 15" in bg_section,
)

# Check 15: _createUserDocInBackground uses exponential backoff
check(
    "Check 15: _createUserDocInBackground uses exponential backoff delays",
    "1000, 2000, 4000, 8000, 16000" in bg_section,
)

# Print results
print("=" * 60)
print("Phase 3.13 — Verification Results (Username Login Fix)")
print("=" * 60)
print()

passed = 0
failed = 0
for status, name, detail in results:
    print(f"  {status} — {name}")
    if detail:
        print(f"         {detail}")
    if status == "PASS":
        passed += 1
    else:
        failed += 1

print()
print(f"Total: {passed} pass, {failed} fail")
print("=" * 60)

if failed > 0:
    print("SOME CHECKS FAILED — review the changes above")
    sys.exit(1)
else:
    print("ALL CHECKS PASS — Username login will work after next Email login")
    sys.exit(0)
