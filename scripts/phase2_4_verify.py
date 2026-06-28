#!/usr/bin/env python3
"""
Phase 2.4 — Admin audit log verification.

Verifies that:
1. firestore.rules contains a new `admin_audit` match block with:
   - admin-only read
   - admin-only create gated by isValidAuditEntry()
   - update/delete DENIED (`if false`) — immutable audit trail
2. isValidAuditEntry() helper is defined and validates required fields
   (action, collection, adminUid, timestamp, success, details) + types.
3. AdminAuditService Dart service exists with:
   - AdminAuditAction constants class (movie/genre/tag/collection/banner/
     notification/batch_import/user actions)
   - AdminAuditCollection constants class
   - record() method that catches errors silently (never throws)
   - recordFailure() convenience method
4. Audit-log calls are wired into all admin write call sites:
   - FirestoreContentService: addMovie (3 paths), updateMovie, deleteMovie,
     addGenre/updateGenre/deleteGenre, addTag/updateTag/deleteTag,
     addCollection/updateCollection/deleteCollection, saveBannerConfig
   - BatchImportService: _recordAudit (writes summary), deleteImport,
     addMovie call site passes skipAuditLog: true
   - admin_users_page.dart: _toggleBan, _forceLogout, _changeRole,
     VIP grant + VIP revoke
   - admin_notification_page.dart: _deleteNotification
5. No regression from Phase 2.2 / 2.6: App Check absent, user_devices
   removed, schema validators still wired in.

Run: python3 scripts/phase2_4_verify.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent.parent
RULES_FILE = ROOT / "firestore.rules"
AUDIT_SVC_FILE = ROOT / "lib" / "app" / "core" / "services" / "admin_audit_service.dart"
CONTENT_SVC_FILE = ROOT / "lib" / "app" / "core" / "services" / "firestore_content_service.dart"
BATCH_SVC_FILE = ROOT / "lib" / "app" / "core" / "services" / "batch_import_service.dart"
ADMIN_USERS_FILE = ROOT / "lib" / "app" / "ui" / "screens" / "admin_users_page.dart"
ADMIN_NOTIF_FILE = ROOT / "lib" / "app" / "ui" / "screens" / "admin_notification_page.dart"


def strip_comments_and_strings(text: str) -> str:
    """Remove // comments and string literals while preserving brace structure."""
    out = []
    i = 0
    in_str = False
    str_delim = ""
    while i < len(text):
        c = text[i]
        if in_str:
            if c == "\\":
                out.append(c)
                if i + 1 < len(text):
                    out.append(text[i + 1])
                i += 2
                continue
            if c == str_delim:
                in_str = False
            out.append(c)
            i += 1
            continue
        if c in ("'", '"'):
            in_str = True
            str_delim = c
            out.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            while i < len(text) and text[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def check_brace_balance(text: str) -> bool:
    depth_curly = 0
    depth_paren = 0
    depth_bracket = 0
    for c in text:
        if c == "{":
            depth_curly += 1
        elif c == "}":
            depth_curly -= 1
            if depth_curly < 0:
                return False
        elif c == "(":
            depth_paren += 1
        elif c == ")":
            depth_paren -= 1
            if depth_paren < 0:
                return False
        elif c == "[":
            depth_bracket += 1
        elif c == "]":
            depth_bracket -= 1
            if depth_bracket < 0:
                return False
    return depth_curly == 0 and depth_paren == 0 and depth_bracket == 0


def find_block(stripped: str, start_pattern: str) -> str:
    """Find a block starting with start_pattern and return its contents
    (including the opening { and matching closing })."""
    idx = stripped.find(start_pattern)
    if idx == -1:
        return ""
    brace_idx = stripped.find("{", idx + len(start_pattern))
    if brace_idx == -1:
        return ""
    depth = 0
    i = brace_idx
    while i < len(stripped):
        if stripped[i] == "{":
            depth += 1
        elif stripped[i] == "}":
            depth -= 1
            if depth == 0:
                return stripped[idx:i + 1]
        i += 1
    return ""


def main() -> int:
    errors = 0

    # ===== PART 1: firestore.rules =====
    if not RULES_FILE.exists():
        print(f"FAIL: {RULES_FILE} does not exist")
        return 1

    raw_rules = RULES_FILE.read_text()
    stripped_rules = strip_comments_and_strings(raw_rules)

    # 1. Brace balance
    if not check_brace_balance(stripped_rules):
        print("FAIL: unbalanced braces/parens/brackets in firestore.rules")
        errors += 1
    else:
        print("OK: firestore.rules braces balanced")

    # 2. App Check NOT present (Phase 2.1 still reverted)
    if "isVerifiedApp" in raw_rules or "request.app" in stripped_rules:
        print("FAIL: App Check enforcement still present (Phase 2.1 was reverted)")
        errors += 1
    else:
        print("OK: App Check enforcement absent (Phase 2.1 correctly reverted)")

    # 3. user_devices match block removed (Phase 2.2)
    if "match /user_devices/" in stripped_rules:
        print("FAIL: user_devices match block still present")
        errors += 1
    else:
        print("OK: user_devices match block removed (Phase 2.2)")

    # 4. notifications read restricted to isAdmin() (Phase 2.2)
    notif_block = find_block(stripped_rules, "match /notifications/{notificationId}")
    if not notif_block:
        print("FAIL: notifications match block not found")
        errors += 1
    elif "allow read: if isAdmin()" not in notif_block:
        print("FAIL: notifications read not restricted to isAdmin()")
        errors += 1
    else:
        print("OK: notifications read restricted to isAdmin() (Phase 2.2)")

    # 5. Phase 2.6 schema helpers still wired (no regression)
    movies_block = find_block(stripped_rules, "match /movies/{movieId}")
    if "isValidMovie()" not in movies_block:
        print("FAIL: movies rules do not require isValidMovie() (Phase 2.6 regression)")
        errors += 1
    else:
        print("OK: Phase 2.6 isValidMovie() still wired into movies rules")

    # 6. Phase 2.4 — admin_audit match block exists with correct rules
    audit_block = find_block(stripped_rules, "match /admin_audit/{auditId}")
    if not audit_block:
        print("FAIL: admin_audit match block not found")
        errors += 1
    else:
        print("OK: admin_audit match block found")
        # read: admin-only
        if "allow read: if isAdmin()" not in audit_block:
            print("FAIL: admin_audit read not restricted to isAdmin()")
            errors += 1
        else:
            print("OK: admin_audit read restricted to isAdmin()")
        # create: admin-only + schema-validated
        if "allow create: if isAdmin() && isValidAuditEntry()" not in audit_block:
            print("FAIL: admin_audit create does not require isAdmin() && isValidAuditEntry()")
            errors += 1
        else:
            print("OK: admin_audit create requires isAdmin() && isValidAuditEntry()")
        # update, delete: DENIED
        if "allow update, delete: if false" not in audit_block:
            print("FAIL: admin_audit update/delete not denied (should be `if false`)")
            errors += 1
        else:
            print("OK: admin_audit update/delete denied (immutable audit trail)")

    # 7. isValidAuditEntry() helper defined with required field checks
    audit_helper = find_block(stripped_rules, "function isValidAuditEntry()")
    if not audit_helper:
        print("FAIL: isValidAuditEntry() helper not defined")
        errors += 1
    else:
        print("OK: isValidAuditEntry() helper defined")
        required_checks = [
            ("action is string", "action is string"),
            ("collection is string", "collection is string"),
            ("adminUid is string", "adminUid is string"),
            ("timestamp is timestamp", "timestamp is timestamp"),
            ("success is bool", "success is bool"),
            ("details is map", "details is map"),
        ]
        for label, pattern in required_checks:
            if pattern not in audit_helper:
                print(f"FAIL: isValidAuditEntry() missing check: {label}")
                errors += 1
            else:
                print(f"OK: isValidAuditEntry() checks {label}")
        # Optional field type checks (when present)
        if "docId is string" not in audit_helper:
            print("FAIL: isValidAuditEntry() missing optional docId type check")
            errors += 1
        else:
            print("OK: isValidAuditEntry() validates optional docId type")

    # ===== PART 2: AdminAuditService Dart file =====
    if not AUDIT_SVC_FILE.exists():
        print(f"FAIL: {AUDIT_SVC_FILE} does not exist")
        errors += 1
        return errors  # Can't continue checking call sites without the service

    audit_svc = AUDIT_SVC_FILE.read_text()

    # 8. AdminAuditAction constants class with all expected actions
    expected_actions = [
        "movieCreate", "movieUpdate", "movieDelete",
        "genreCreate", "genreUpdate", "genreDelete",
        "tagCreate", "tagUpdate", "tagDelete",
        "collectionCreate", "collectionUpdate", "collectionDelete",
        "bannerUpdate",
        "notificationDelete",
        "batchImportComplete", "batchImportDelete",
        "userBan", "userUnban", "userForceLogout",
        "userRoleChange", "userVipGrant", "userVipRevoke",
    ]
    for action in expected_actions:
        if f"static const {action} =" not in audit_svc:
            print(f"FAIL: AdminAuditAction.{action} constant not defined")
            errors += 1
    if errors == 0:
        print(f"OK: all {len(expected_actions)} AdminAuditAction constants defined")

    # 9. AdminAuditCollection constants class
    expected_collections = [
        "movies", "genres", "tags", "collections",
        "appSettings", "notifications", "batchImports", "users",
    ]
    for coll in expected_collections:
        if f"static const {coll} =" not in audit_svc:
            print(f"FAIL: AdminAuditCollection.{coll} constant not defined")
            errors += 1
    if errors == 0:
        print(f"OK: all {len(expected_collections)} AdminAuditCollection constants defined")

    # 10. record() method exists and catches errors
    if "Future<String?> record(" not in audit_svc:
        print("FAIL: record() method not found in AdminAuditService")
        errors += 1
    else:
        print("OK: record() method found")
        # Must catch errors and return null (never throw)
        if "return null;" not in audit_svc:
            print("FAIL: record() does not return null on failure (would throw)")
            errors += 1
        else:
            print("OK: record() returns null on failure (never throws)")

    # 11. recordFailure() convenience method
    if "Future<String?> recordFailure(" not in audit_svc:
        print("FAIL: recordFailure() method not found")
        errors += 1
    else:
        print("OK: recordFailure() method found")

    # 12. Singleton pattern
    if "static final AdminAuditService instance" not in audit_svc:
        print("FAIL: AdminAuditService.instance singleton not found")
        errors += 1
    else:
        print("OK: AdminAuditService.instance singleton defined")

    # ===== PART 3: FirestoreContentService wiring =====
    content_svc = CONTENT_SVC_FILE.read_text()

    # 13. Import present
    if "import 'package:cm_movies/app/core/services/admin_audit_service.dart';" not in content_svc:
        print("FAIL: firestore_content_service.dart does not import admin_audit_service")
        errors += 1
    else:
        print("OK: firestore_content_service.dart imports admin_audit_service")

    # 14. addMovie has skipAuditLog parameter
    if "bool skipAuditLog = false" not in content_svc:
        print("FAIL: addMovie does not have skipAuditLog parameter")
        errors += 1
    else:
        print("OK: addMovie has skipAuditLog parameter")

    # 15. addMovie audit-log calls — at least 2 unawaited(record( calls for movie actions
    # (3 paths in addMovie: duplicate-tmdbId update, duplicate-slug update, new doc create)
    # Plus updateMovie and deleteMovie = 5 total movie audit-log call sites
    movie_audit_count = content_svc.count("AdminAuditAction.movie")
    if movie_audit_count < 5:
        print(f"FAIL: expected at least 5 movie audit-log call sites, found {movie_audit_count}")
        errors += 1
    else:
        print(f"OK: {movie_audit_count} movie audit-log call sites found (addMovie 3 paths + update + delete)")

    # 16. Genre/Tag/Collection audit-log calls (3 each = 9 total)
    gtc_audit_count = (
        content_svc.count("AdminAuditAction.genre") +
        content_svc.count("AdminAuditAction.tag") +
        content_svc.count("AdminAuditAction.collection")
    )
    if gtc_audit_count < 9:
        print(f"FAIL: expected at least 9 genre/tag/collection audit-log call sites, found {gtc_audit_count}")
        errors += 1
    else:
        print(f"OK: {gtc_audit_count} genre/tag/collection audit-log call sites found")

    # 17. saveBannerConfig audit-log call
    if "AdminAuditAction.bannerUpdate" not in content_svc:
        print("FAIL: saveBannerConfig does not audit-log")
        errors += 1
    else:
        print("OK: saveBannerConfig audit-logs banner.update")

    # ===== PART 4: BatchImportService wiring =====
    batch_svc = BATCH_SVC_FILE.read_text()

    # 18. Import present
    if "import 'package:cm_movies/app/core/services/admin_audit_service.dart';" not in batch_svc:
        print("FAIL: batch_import_service.dart does not import admin_audit_service")
        errors += 1
    else:
        print("OK: batch_import_service.dart imports admin_audit_service")

    # 19. addMovie call site passes skipAuditLog: true
    if "skipAuditLog: true" not in batch_svc:
        print("FAIL: BatchImportService does not pass skipAuditLog: true to addMovie")
        errors += 1
    else:
        print("OK: BatchImportService passes skipAuditLog: true to addMovie")

    # 20. _recordAudit writes a summary admin_audit entry
    if "AdminAuditAction.batchImportComplete" not in batch_svc:
        print("FAIL: _recordAudit does not write a summary admin_audit entry")
        errors += 1
    else:
        print("OK: _recordAudit writes summary admin_audit entry")

    # 21. deleteImport audit-logs the delete
    if "AdminAuditAction.batchImportDelete" not in batch_svc:
        print("FAIL: deleteImport does not audit-log")
        errors += 1
    else:
        print("OK: deleteImport audit-logs batch_import.delete")

    # ===== PART 5: admin_users_page.dart wiring =====
    admin_users = ADMIN_USERS_FILE.read_text()

    # 22. Import present
    if "import 'package:cm_movies/app/core/services/admin_audit_service.dart';" not in admin_users:
        print("FAIL: admin_users_page.dart does not import admin_audit_service")
        errors += 1
    else:
        print("OK: admin_users_page.dart imports admin_audit_service")

    # 23. All 6 user admin actions audit-logged
    user_actions = [
        ("_toggleBan", "AdminAuditAction.userBan", "AdminAuditAction.userUnban"),
        ("_forceLogout", "AdminAuditAction.userForceLogout", None),
        ("_changeRole", "AdminAuditAction.userRoleChange", None),
        ("VIP grant", "AdminAuditAction.userVipGrant", None),
        ("VIP revoke", "AdminAuditAction.userVipRevoke", None),
    ]
    for label, action1, action2 in user_actions:
        if action1 not in admin_users:
            print(f"FAIL: {label} does not audit-log ({action1})")
            errors += 1
        elif action2 and action2 not in admin_users:
            print(f"FAIL: {label} does not audit-log ({action2})")
            errors += 1
        else:
            print(f"OK: {label} audit-logs")
    # Check both ban + unban are present
    if "AdminAuditAction.userBan" in admin_users and "AdminAuditAction.userUnban" in admin_users:
        print("OK: _toggleBan audits both ban + unban")
    else:
        print("FAIL: _toggleBan does not audit both ban + unban paths")
        errors += 1

    # ===== PART 6: admin_notification_page.dart wiring =====
    admin_notif = ADMIN_NOTIF_FILE.read_text()

    # 24. Import present
    if "import 'package:cm_movies/app/core/services/admin_audit_service.dart';" not in admin_notif:
        print("FAIL: admin_notification_page.dart does not import admin_audit_service")
        errors += 1
    else:
        print("OK: admin_notification_page.dart imports admin_audit_service")

    # 25. _deleteNotification audit-logs
    if "AdminAuditAction.notificationDelete" not in admin_notif:
        print("FAIL: _deleteNotification does not audit-log")
        errors += 1
    else:
        print("OK: _deleteNotification audit-logs notification.delete")

    # ===== SUMMARY =====
    print("\n" + "=" * 60)
    if errors == 0:
        print(f"PASS: All Phase 2.4 audit-log verification checks passed")
        return 0
    else:
        print(f"FAIL: {errors} error(s) found")
        return 1


if __name__ == "__main__":
    sys.exit(main())
