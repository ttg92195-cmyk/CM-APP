#!/usr/bin/env python3
"""Phase 3.5 verification — list-query workaround for _loadUserProfile."""
import sys
from pathlib import Path

text = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart").read_text()

checks = [
    ("_loadUserProfile uses where(FieldPath.documentId, isEqualTo: uid)",
     "where(FieldPath.documentId, isEqualTo: uid)" in text),
    ("_loadUserProfile no longer uses .doc(uid).get() as primary",
     "final doc = await _firestore.collection('users').doc(uid).get();" not in text),
    ("Phase 3.5 comment present",
     "Phase 3.5 — Use a list query" in text),
    ("query.docs.isNotEmpty check",
     "query.docs.isNotEmpty" in text),
    ("Phase 3.4 diagnostic fields still present",
     "lastProfileLoadErrorCode" in text and "lastUsernameLookupErrorCode" in text),
    ("getIdToken(true) still present from Phase 3.4",
     "await user.getIdToken(true);" in text),
]

print(f"Phase 3.5 — running {len(checks)} checks\n")
failures = 0
for label, ok in checks:
    mark = "PASS" if ok else "FAIL"
    if not ok: failures += 1
    print(f"  [{mark}] {label}")

print(f"\n{len(checks) - failures}/{len(checks)} passed")
sys.exit(1 if failures else 0)
