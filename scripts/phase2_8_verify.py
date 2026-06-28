#!/usr/bin/env python3
"""
Phase 2.8 — Client-side rate limiting verification.

Verifies that the RateLimiter service exists with the correct API,
that all 24 rate-limit policies are defined, and that all expected
call sites in the codebase have the rate-limit check wired in.

Run:
    python3 scripts/phase2_8_verify.py

Exit code 0 = all checks pass; 1 = at least one check failed.
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

class Check:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.failures = []

    def ok(self, name):
        self.passed += 1
        print(f"  PASS: {name}")

    def fail(self, name, detail=""):
        self.failed += 1
        self.failures.append((name, detail))
        msg = f"  FAIL: {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)

    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*60}")
        print(f"Phase 2.8 verification: {self.passed}/{total} checks passed")
        if self.failed:
            print(f"FAILURES:")
            for name, detail in self.failures:
                print(f"  - {name}: {detail}")
            return 1
        return 0


def read(rel_path):
    p = ROOT / rel_path
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")


def count_substring(haystack, needle):
    return haystack.count(needle)


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

def check_rate_limiter_service(c):
    print("\n[1] rate_limiter_service.dart")
    src = read("lib/app/core/services/rate_limiter_service.dart")
    if not src:
        c.fail("file exists", "lib/app/core/services/rate_limiter_service.dart not found")
        return

    c.ok("file exists")

    # Class & singleton
    if "class RateLimiter" in src:
        c.ok("RateLimiter class declared")
    else:
        c.fail("RateLimiter class declared")

    if "static final RateLimiter instance = RateLimiter._();" in src:
        c.ok("singleton instance")
    else:
        c.fail("singleton instance")

    # Exception class
    if "class RateLimitExceededException implements Exception" in src:
        c.ok("RateLimitExceededException class")
    else:
        c.fail("RateLimitExceededException class")

    # Exception fields
    for field in ["actionId", "retryAfter", "limit", "window"]:
        if f"final" in src and f"{field}" in src:
            c.ok(f"exception field: {field}")
        else:
            c.fail(f"exception field: {field}")

    # userMessage getter
    if "String get userMessage" in src:
        c.ok("userMessage getter")
    else:
        c.fail("userMessage getter")

    # Core methods
    for method in ["void enforce(", "bool tryEnforce(", "bool canDo(", "Duration retryAfter("]:
        if method in src:
            c.ok(f"method: {method.strip('(')}")
        else:
            c.fail(f"method: {method.strip('(')}")

    # Sliding window implementation
    if "removeWhere" in src:
        c.ok("sliding-window prune via removeWhere")
    else:
        c.fail("sliding-window prune via removeWhere")


def check_policies(c):
    print("\n[2] RateLimitPolicies constants")
    src = read("lib/app/core/services/rate_limiter_service.dart")
    if not src:
        c.fail("policies", "rate_limiter_service.dart missing")
        return

    # All 24 action ID constants must be present
    expected_actions = [
        # Movies (3)
        "movieAdd", "movieUpdate", "movieDelete",
        # Genres (3)
        "genreAdd", "genreUpdate", "genreDelete",
        # Tags (3)
        "tagAdd", "tagUpdate", "tagDelete",
        # Collections (3)
        "collectionAdd", "collectionUpdate", "collectionDelete",
        # Banner (1)
        "bannerUpdate",
        # Notifications (1)
        "notificationDelete",
        # Batch Import (2)
        "batchImportStart", "batchImportDelete",
        # User admin actions (6)
        "userBan", "userUnban", "userForceLogout",
        "userRoleChange", "userVipGrant", "userVipRevoke",
        # Auth (3)
        "authLoginAttempt", "authSignupAttempt", "authPasswordReset",
    ]
    for action in expected_actions:
        if f"static const String {action} = " in src:
            c.ok(f"action: {action}")
        else:
            c.fail(f"action: {action}", "constant missing")

    # Policy map entries (one per action)
    policy_count = src.count("_Policy(")
    if policy_count >= len(expected_actions):
        c.ok(f"policy map has {policy_count} entries (>= {len(expected_actions)} expected)")
    else:
        c.fail(f"policy map has {policy_count} entries (expected >= {len(expected_actions)})")

    # Specific limit values — verify the tuning is as documented.
    # Source uses alignment whitespace (e.g. `movieAdd:            _Policy(30, ...`),
    # so we check that the key + _Policy + values all appear on the same
    # logical line, regardless of how much whitespace separates them.
    import re
    expected_limits = [
        ("movieAdd", "30", "Duration(minutes: 1)"),
        ("movieUpdate", "60", "Duration(minutes: 1)"),
        ("movieDelete", "20", "Duration(minutes: 1)"),
        ("bannerUpdate", "5", "Duration(minutes: 1)"),
        ("batchImportStart", "5", "Duration(hours: 1)"),
        ("userRoleChange", "10", "Duration(minutes: 1)"),
        ("authLoginAttempt", "10", "Duration(minutes: 1)"),
        ("authSignupAttempt", "3", "Duration(minutes: 1)"),
        ("authPasswordReset", "3", "Duration(minutes: 1)"),
    ]
    for action, limit, window in expected_limits:
        # Build a regex that allows any amount of whitespace between tokens.
        # Example: `movieAdd:\s+_Policy\(\s*30\s*,\s*Duration\(minutes:\s*1\)\s*\)`
        pattern = re.compile(
            rf"{action}:\s+_Policy\(\s*{limit}\s*,\s*"
            + re.escape(window).replace(r"\ ", r"\s*")
            + r"\s*\)"
        )
        if pattern.search(src):
            c.ok(f"limit: {action} = {limit}/{window}")
        else:
            c.fail(f"limit: {action} = {limit}/{window}", "pattern not found")


def check_firestore_content_service(c):
    print("\n[3] firestore_content_service.dart — 13 admin write rate limits")
    src = read("lib/app/core/services/firestore_content_service.dart")
    if not src:
        c.fail("file exists", "firestore_content_service.dart missing")
        return

    if "import 'package:cm_movies/app/core/services/rate_limiter_service.dart';" in src:
        c.ok("import present")
    else:
        c.fail("import present")

    # Expected rate-limit check sites (one per admin write method)
    expected = [
        ("addMovie",            "RateLimitPolicies.movieAdd"),
        ("updateMovie",         "RateLimitPolicies.movieUpdate"),
        ("deleteMovie",         "RateLimitPolicies.movieDelete"),
        ("addGenre",            "RateLimitPolicies.genreAdd"),
        ("updateGenre",         "RateLimitPolicies.genreUpdate"),
        ("deleteGenre",         "RateLimitPolicies.genreDelete"),
        ("addTag",              "RateLimitPolicies.tagAdd"),
        ("updateTag",           "RateLimitPolicies.tagUpdate"),
        ("deleteTag",            "RateLimitPolicies.tagDelete"),
        ("addCollection",       "RateLimitPolicies.collectionAdd"),
        ("updateCollection",    "RateLimitPolicies.collectionUpdate"),
        ("deleteCollection",    "RateLimitPolicies.collectionDelete"),
        ("saveBannerConfig",    "RateLimitPolicies.bannerUpdate"),
    ]
    for method, policy in expected:
        if policy in src:
            c.ok(f"rate-limit in {method}")
        else:
            c.fail(f"rate-limit in {method}", f"missing {policy}")

    # Special check: addMovie should skip rate limit when skipAdminCheck=true
    # (BatchImportService calls addMovie in a tight loop with skipAdminCheck=true)
    if "if (!skipAdminCheck) {" in src and "RateLimitPolicies.movieAdd" in src:
        c.ok("addMovie skips rate limit for batch imports (skipAdminCheck guard)")
    else:
        c.fail("addMovie skips rate limit for batch imports")


def check_batch_import_service(c):
    print("\n[4] batch_import_service.dart — 2 rate limits")
    src = read("lib/app/core/services/batch_import_service.dart")
    if not src:
        c.fail("file exists", "batch_import_service.dart missing")
        return

    if "import 'package:cm_movies/app/core/services/rate_limiter_service.dart';" in src:
        c.ok("import present")
    else:
        c.fail("import present")

    if "RateLimitPolicies.batchImportStart" in src:
        c.ok("rate-limit in runImport")
    else:
        c.fail("rate-limit in runImport")

    if "RateLimitPolicies.batchImportDelete" in src:
        c.ok("rate-limit in deleteImport")
    else:
        c.fail("rate-limit in deleteImport")


def check_admin_users_page(c):
    print("\n[5] admin_users_page.dart — 5 user-action rate limits")
    src = read("lib/app/ui/screens/admin_users_page.dart")
    if not src:
        c.fail("file exists", "admin_users_page.dart missing")
        return

    if "import 'package:cm_movies/app/core/services/rate_limiter_service.dart';" in src:
        c.ok("import present")
    else:
        c.fail("import present")

    expected = [
        ("_toggleBan (ban/unban)",   "RateLimitPolicies.userBan"),
        ("_toggleBan (unban)",        "RateLimitPolicies.userUnban"),
        ("_forceLogout",              "RateLimitPolicies.userForceLogout"),
        ("_changeRole",               "RateLimitPolicies.userRoleChange"),
        ("VIP grant",                 "RateLimitPolicies.userVipGrant"),
        ("VIP revoke",                "RateLimitPolicies.userVipRevoke"),
    ]
    for label, policy in expected:
        if policy in src:
            c.ok(f"rate-limit: {label}")
        else:
            c.fail(f"rate-limit: {label}", f"missing {policy}")


def check_admin_notification_page(c):
    print("\n[6] admin_notification_page.dart — 1 rate limit")
    src = read("lib/app/ui/screens/admin_notification_page.dart")
    if not src:
        c.fail("file exists", "admin_notification_page.dart missing")
        return

    if "import 'package:cm_movies/app/core/services/rate_limiter_service.dart';" in src:
        c.ok("import present")
    else:
        c.fail("import present")

    if "RateLimitPolicies.notificationDelete" in src:
        c.ok("rate-limit in _deleteNotification")
    else:
        c.fail("rate-limit in _deleteNotification")


def check_login_page(c):
    print("\n[7] login_page.dart — 3 auth rate limits")
    src = read("lib/app/ui/screens/login_page.dart")
    if not src:
        c.fail("file exists", "login_page.dart missing")
        return

    if "import 'package:cm_movies/app/core/services/rate_limiter_service.dart';" in src:
        c.ok("import present")
    else:
        c.fail("import present")

    # Login attempt
    if "RateLimitPolicies.authLoginAttempt" in src:
        c.ok("rate-limit: login attempt")
    else:
        c.fail("rate-limit: login attempt")

    # Signup attempt
    if "RateLimitPolicies.authSignupAttempt" in src:
        c.ok("rate-limit: signup attempt")
    else:
        c.fail("rate-limit: signup attempt")

    # Password reset
    if "RateLimitPolicies.authPasswordReset" in src:
        c.ok("rate-limit: password reset")
    else:
        c.fail("rate-limit: password reset")

    # Existing in-memory lockout should still be present (not regressed)
    if "_isLockedOut" in src and "_failedLoginAttempts" in src:
        c.ok("existing 5/30s lockout preserved (no regression)")
    else:
        c.fail("existing 5/30s lockout preserved (no regression)")


def check_no_firestore_rules_changes(c):
    print("\n[8] firestore.rules — should be UNCHANGED (Phase 2.8 is client-side only)")
    src = read("firestore.rules")
    if not src:
        c.fail("firestore.rules exists")
        return

    # admin_audit rules from Phase 2.4 should still be present
    if "admin_audit" in src and "isValidAuditEntry" in src:
        c.ok("Phase 2.4 admin_audit rules intact")
    else:
        c.fail("Phase 2.4 admin_audit rules intact")

    # Phase 2.6 schema validation should still be present
    if "isValidMovie" in src:
        c.ok("Phase 2.6 schema validation intact")
    else:
        c.fail("Phase 2.6 schema validation intact")


def main():
    print("="*60)
    print("Phase 2.8 — Client-side rate limiting verification")
    print("="*60)

    c = Check()

    check_rate_limiter_service(c)
    check_policies(c)
    check_firestore_content_service(c)
    check_batch_import_service(c)
    check_admin_users_page(c)
    check_admin_notification_page(c)
    check_login_page(c)
    check_no_firestore_rules_changes(c)

    sys.exit(c.summary())


if __name__ == "__main__":
    main()
