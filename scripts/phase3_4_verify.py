#!/usr/bin/env python3
"""
Phase 3.4 verification script.
Checks that the diagnostic error capture changes are in place.
"""
import sys
from pathlib import Path

APP_CONFIG = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart")
LOGIN_PAGE = Path("/home/z/my-project/cm-app/lib/app/ui/screens/login_page.dart")

text = APP_CONFIG.read_text()

checks = [
    # New diagnostic fields declared
    (
        "lastProfileLoadErrorCode field declared",
        "String? lastProfileLoadErrorCode;" in text,
    ),
    (
        "lastProfileLoadErrorMessage field declared",
        "String? lastProfileLoadErrorMessage;" in text,
    ),
    (
        "lastUsernameLookupErrorCode field declared",
        "String? lastUsernameLookupErrorCode;" in text,
    ),
    (
        "lastUsernameLookupErrorMessage field declared",
        "String? lastUsernameLookupErrorMessage;" in text,
    ),

    # _usernameToEmail captures real error
    (
        "_usernameToEmail clears diagnostic at start",
        "lastUsernameLookupErrorCode = null;\n    lastUsernameLookupErrorMessage = null;" in text,
    ),
    (
        "_usernameToEmail catch block captures FirebaseException",
        "if (e is FirebaseException) {\n          lastUsernameLookupErrorCode = e.code;\n          lastUsernameLookupErrorMessage = e.message;" in text,
    ),
    (
        "_usernameToEmail catch block handles non-FirebaseException",
        "lastUsernameLookupErrorCode = 'username-lookup-error';" in text,
    ),

    # _loadUserProfile captures real error
    (
        "_loadUserProfile clears diagnostic at start",
        "lastProfileLoadErrorCode = null;\n    lastProfileLoadErrorMessage = null;" in text,
    ),
    (
        "_loadUserProfile catch block captures FirebaseException",
        "if (e is FirebaseException) {\n        lastProfileLoadErrorCode = e.code;\n        lastProfileLoadErrorMessage = e.message;" in text,
    ),
    (
        "_loadUserProfile catch block handles non-FirebaseException",
        "lastProfileLoadErrorCode = 'profile-load-error';" in text,
    ),

    # loginUser uses new diagnostic
    (
        "loginUser calls getIdToken(true) before _loadUserProfile",
        "await user.getIdToken(true);" in text,
    ),
    (
        "loginUser surfaces lastProfileLoadErrorCode",
        "if (lastProfileLoadErrorCode != null) {" in text,
    ),
    (
        "loginUser FirebaseAuthException catch checks lastUsernameLookupErrorCode",
        "if (e.code == 'invalid-credential' &&\n          lastUsernameLookupErrorCode != null)" in text,
    ),
    (
        "loginUser surfaces username-lookup-failed prefix",
        "'username-lookup-failed: ${lastUsernameLookupErrorCode}'" in text,
    ),

    # login_page.dart still surfaces diagnostic
    (
        "login_page.dart reads lastLoginErrorCode",
        "appConfig.lastLoginErrorCode" in LOGIN_PAGE.read_text(),
    ),
    (
        "login_page.dart reads lastLoginErrorMessage",
        "appConfig.lastLoginErrorMessage" in LOGIN_PAGE.read_text(),
    ),
]

print(f"Phase 3.4 — running {len(checks)} structural checks\n")
failures = 0
for label, ok in checks:
    mark = "PASS" if ok else "FAIL"
    if not ok:
        failures += 1
    print(f"  [{mark}] {label}")

print(f"\n{len(checks) - failures}/{len(checks)} checks passed")
sys.exit(1 if failures else 0)
