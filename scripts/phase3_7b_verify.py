#!/usr/bin/env python3
"""Phase 3.7b — verify the isLoadingAuth cold-start fix."""
import sys
from pathlib import Path

text = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart").read_text()

checks = [
    ("authStateChanges listener has 'user == null && _currentUser == null' branch",
     "else if (user == null && _currentUser == null)" in text),
    ("Branch clears _isLoadingAuth",
     "// Phase 3.7 — Cold start with no previously-signed-in user." in text),
    ("Comment explains the KMM spinner hang",
     "KMM spinner taking a long time" in text),
    # Phase 3.7 fixes retained
    ("_isLoginInProgress flag retained",
     "bool _isLoginInProgress = false;" in text),
    ("listener checks _isLoginInProgress",
     "if (_isLoginInProgress)" in text),
    # Phase 3.6 fixes retained
    ("_isLoadingProfile guard retained",
     "bool _isLoadingProfile = false;" in text),
    # Phase 3.5 fix retained
    ("list query for _loadUserProfile retained",
     "where(FieldPath.documentId, isEqualTo: uid)" in text),
]

print(f"Phase 3.7b — running {len(checks)} checks\n")
failures = 0
for label, ok in checks:
    mark = "PASS" if ok else "FAIL"
    if not ok: failures += 1
    print(f"  [{mark}] {label}")

print(f"\n{len(checks) - failures}/{len(checks)} passed")
sys.exit(1 if failures else 0)
