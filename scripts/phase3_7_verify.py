#!/usr/bin/env python3
"""Phase 3.7 verification — authStateChanges listener guard + retry on transient errors."""
import sys
from pathlib import Path

text = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart").read_text()

checks = [
    # _isLoginInProgress flag
    ("_isLoginInProgress field declared",
     "bool _isLoginInProgress = false;" in text),
    ("_isLoginInProgress set true at loginUser start",
     "_isLoginInProgress = true;" in text),
    ("_isLoginInProgress cleared in finally block",
     "} finally {\n      // Phase 3.7 — Always clear the in-progress flag" in text
     and "_isLoginInProgress = false;\n    }" in text),

    # authStateChanges listener guard
    ("authStateChanges listener checks _isLoginInProgress",
     "if (_isLoginInProgress) {" in text),
    ("listener has 'skipping' debug log",
     "skipping (loginUser handles it)" in text),
    ("listener only loads profile when _currentUser is null",
     "if (user != null && _currentUser == null)" in text),

    # Retry logic in _loadUserProfile call
    ("loginUser retries _loadUserProfile up to 3 times",
     "for (int attempt = 1; attempt <= 3; attempt++)" in text),
    ("retry only on transient error codes",
     "code == 'unavailable' || code == 'network-error'" in text),
    ("retry uses backoff delay",
     "Duration(milliseconds: 500 * attempt)" in text),

    # _usernameToEmail retry
    ("_usernameToEmail retries up to 3 times",
     "// Phase 3.7 — Retry the username lookup up to 3 times" in text),
    ("_usernameToEmail retry loop present",
     "for (int attempt = 1; attempt <= 3; attempt++) {\n        try {\n          final query = await _firestore" in text),

    # Phase 3.5/3.6 fixes retained
    ("Phase 3.5 list query retained",
     "where(FieldPath.documentId, isEqualTo: uid)" in text),
    ("Phase 3.6 _isLoadingProfile guard retained",
     "bool _isLoadingProfile = false;" in text),
    ("Phase 3.6 forceLogout self-update still removed",
     ".update({\n            'forceLogout': false,\n          });" not in text),
    ("Phase 3.4 diagnostics retained",
     "lastProfileLoadErrorCode" in text and "lastUsernameLookupErrorCode" in text),
]

print(f"Phase 3.7 — running {len(checks)} checks\n")
failures = 0
for label, ok in checks:
    mark = "PASS" if ok else "FAIL"
    if not ok: failures += 1
    print(f"  [{mark}] {label}")

print(f"\n{len(checks) - failures}/{len(checks)} passed")
sys.exit(1 if failures else 0)
