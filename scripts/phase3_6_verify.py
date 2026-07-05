#!/usr/bin/env python3
"""Phase 3.6 verification — race condition guard + forceLogout self-update removal."""
import sys
from pathlib import Path

text = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart").read_text()

checks = [
    # Fix #2 — forceLogout self-update removed
    (
        "forceLogout self-update .update() call removed",
        ".update({\n            'forceLogout': false,\n          })" not in text
        and ".update({\n            'forceLogout': false,\n          });" not in text,
    ),
    (
        "forceLogout branch surfaces 'force-logout' diagnostic code",
        "lastProfileLoadErrorCode = 'force-logout';" in text,
    ),
    (
        "forceLogout branch still signs out and clears user",
        "if (data['forceLogout'] == true) {" in text,
    ),
    (
        "Phase 3.6 comment block for forceLogout present",
        "Phase 3.6 — DO NOT try to clear the flag from the client." in text,
    ),

    # Fix #3 — concurrent _loadUserProfile guard
    (
        "_isLoadingProfile bool field declared",
        "bool _isLoadingProfile = false;" in text,
    ),
    (
        "_loadUserProfile guards against re-entry",
        "if (_isLoadingProfile) {" in text
        and "skipping duplicate call" in text,
    ),
    (
        "_loadUserProfile sets _isLoadingProfile = true at start",
        "_isLoadingProfile = true;\n    // Phase 3.4 — clear diagnostic fields" in text,
    ),
    (
        "_loadUserProfile uses try/finally to release guard",
        "} finally {\n      // Phase 3.6 — release the guard" in text
        and "_isLoadingProfile = false;\n    }" in text,
    ),

    # Phase 3.5 list-query fix still in place (must not regress)
    (
        "Phase 3.5 list query still present",
        "where(FieldPath.documentId, isEqualTo: uid)" in text,
    ),
    (
        "Phase 3.5 .doc(uid).get() NOT reintroduced",
        "final doc = await _firestore.collection('users').doc(uid).get();" not in text,
    ),

    # Phase 3.4 diagnostics still in place
    (
        "lastProfileLoadErrorCode field still declared",
        "String? lastProfileLoadErrorCode;" in text,
    ),
    (
        "lastUsernameLookupErrorCode field still declared",
        "String? lastUsernameLookupErrorCode;" in text,
    ),
]

print(f"Phase 3.6 — running {len(checks)} checks\n")
failures = 0
for label, ok in checks:
    mark = "PASS" if ok else "FAIL"
    if not ok: failures += 1
    print(f"  [{mark}] {label}")

print(f"\n{len(checks) - failures}/{len(checks)} passed")
sys.exit(1 if failures else 0)
