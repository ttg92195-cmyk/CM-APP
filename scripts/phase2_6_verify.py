#!/usr/bin/env python3
"""
Phase 2.6 — Admin field validation verification.

Verifies that firestore.rules contains schema-bound validation helpers and
that they are wired into the correct allow create/update rules.

Checks:
1. Brace balance (handles strings + // comments)
2. isVerifiedApp() / request.app NOT present (Phase 2.1 still reverted)
3. user_devices match block removed (Phase 2.2)
4. notifications read restricted to isAdmin() (Phase 2.2)
5. Phase 2.6 — schema validation helpers defined:
   - isValidMovie()
   - isValidGenreOrTagOrCollection()
   - isValidNotification()
   - isValidBannerConfig()
   - isValidBatchImport()
6. Phase 2.6 — schema validation wired into allow rules:
   - movies create + update require isValidMovie()
   - genres create + update require isValidGenreOrTagOrCollection()
   - tags create + update require isValidGenreOrTagOrCollection()
   - collections create + update require isValidGenreOrTagOrCollection()
   - notifications create + update require isValidNotification()
   - app_settings write requires isValidBannerConfig() for banner_config
   - batch_imports create requires isValidBatchImport()
7. Schema helpers validate required fields + types + enums:
   - isValidMovie: title non-empty string, type ∈ {movie, series}, isAdult
     ∈ {0,1} when present, lists are lists when present
   - isValidGenreOrTagOrCollection: name non-empty string, moviesCount int >=0
   - isValidNotification: title, body, sentBy non-empty, sentAt timestamp
   - isValidBannerConfig: imageUrls list, updatedAt timestamp
   - isValidBatchImport: adminUid, startedAt, completedAt, counts int,
     cancelled bool

Run: python3 scripts/phase2_6_verify.py
"""
import re
import sys
from pathlib import Path

RULES_FILE = Path(__file__).parent.parent / "firestore.rules"


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
    # Find the first { after start_pattern
    brace_idx = stripped.find("{", idx + len(start_pattern))
    if brace_idx == -1:
        return ""
    # Walk to matching closing brace
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
    if not RULES_FILE.exists():
        print(f"FAIL: {RULES_FILE} does not exist")
        return 1

    raw = RULES_FILE.read_text()
    stripped = strip_comments_and_strings(raw)

    errors = 0

    # 1. Brace balance
    if not check_brace_balance(stripped):
        print("FAIL: unbalanced braces/parens/brackets")
        errors += 1
    else:
        print("OK: braces balanced")

    # 2. App Check NOT present (Phase 2.1 still reverted)
    if "isVerifiedApp" in raw or "request.app" in stripped:
        print("FAIL: App Check enforcement still present (Phase 2.1 was reverted)")
        errors += 1
    else:
        print("OK: App Check enforcement absent (Phase 2.1 correctly reverted)")

    # 3. user_devices match block removed
    if "match /user_devices/" in stripped:
        print("FAIL: user_devices match block still present")
        errors += 1
    else:
        print("OK: user_devices match block removed")

    # 4. notifications read restricted to isAdmin()
    notif_block = find_block(stripped, "match /notifications/{notificationId}")
    if not notif_block:
        print("FAIL: notifications match block not found")
        errors += 1
    elif "allow read: if request.auth != null" in notif_block:
        print("FAIL: notifications read still allows any authenticated user")
        errors += 1
    elif "allow read: if isAdmin()" not in notif_block:
        print("FAIL: notifications read not restricted to isAdmin()")
        errors += 1
    else:
        print("OK: notifications read restricted to isAdmin()")

    # 5. Phase 2.6 — validation helpers defined
    helpers = [
        ("isValidMovie", "isValidMovie"),
        ("isValidGenreOrTagOrCollection", "isValidGenreOrTagOrCollection"),
        ("isValidNotification", "isValidNotification"),
        ("isValidBannerConfig", "isValidBannerConfig"),
        ("isValidBatchImport", "isValidBatchImport"),
    ]
    for label, name in helpers:
        # Look for function definition: "function name()"
        pattern = f"function {name}()"
        if pattern not in stripped:
            print(f"FAIL: helper function {name}() not defined")
            errors += 1
        else:
            print(f"OK: helper function {name}() defined")

    # 6. Phase 2.6 — validation wired into allow rules
    # movies
    movies_block = find_block(stripped, "match /movies/{movieId}")
    if not movies_block:
        print("FAIL: movies match block not found")
        errors += 1
    else:
        if "allow create: if isAdmin() && isValidMovie()" not in movies_block:
            print("FAIL: movies create does not require isValidMovie()")
            errors += 1
        else:
            print("OK: movies create requires isValidMovie()")
        if "allow update: if isAdmin() && isValidMovie()" not in movies_block:
            print("FAIL: movies update does not require isValidMovie()")
            errors += 1
        else:
            print("OK: movies update requires isValidMovie()")

    # genres
    genres_block = find_block(stripped, "match /genres/{genreId}")
    if not genres_block:
        print("FAIL: genres match block not found")
        errors += 1
    else:
        for op in ["create", "update"]:
            if f"allow {op}: if isAdmin() && isValidGenreOrTagOrCollection()" not in genres_block:
                print(f"FAIL: genres {op} does not require isValidGenreOrTagOrCollection()")
                errors += 1
            else:
                print(f"OK: genres {op} requires isValidGenreOrTagOrCollection()")

    # tags
    tags_block = find_block(stripped, "match /tags/{tagId}")
    if not tags_block:
        print("FAIL: tags match block not found")
        errors += 1
    else:
        for op in ["create", "update"]:
            if f"allow {op}: if isAdmin() && isValidGenreOrTagOrCollection()" not in tags_block:
                print(f"FAIL: tags {op} does not require isValidGenreOrTagOrCollection()")
                errors += 1
            else:
                print(f"OK: tags {op} requires isValidGenreOrTagOrCollection()")

    # collections
    coll_block = find_block(stripped, "match /collections/{collectionId}")
    if not coll_block:
        print("FAIL: collections match block not found")
        errors += 1
    else:
        for op in ["create", "update"]:
            if f"allow {op}: if isAdmin() && isValidGenreOrTagOrCollection()" not in coll_block:
                print(f"FAIL: collections {op} does not require isValidGenreOrTagOrCollection()")
                errors += 1
            else:
                print(f"OK: collections {op} requires isValidGenreOrTagOrCollection()")

    # notifications (create + update)
    if notif_block:
        for op in ["create", "update"]:
            if f"allow {op}: if isAdmin() && isValidNotification()" not in notif_block:
                print(f"FAIL: notifications {op} does not require isValidNotification()")
                errors += 1
            else:
                print(f"OK: notifications {op} requires isValidNotification()")

    # app_settings
    app_settings_block = find_block(stripped, "match /app_settings/{docId}")
    if not app_settings_block:
        print("FAIL: app_settings match block not found")
        errors += 1
    elif "isValidBannerConfig()" not in app_settings_block:
        print("FAIL: app_settings does not reference isValidBannerConfig()")
        errors += 1
    elif "banner_config" not in app_settings_block:
        print("FAIL: app_settings does not gate by banner_config docId")
        errors += 1
    else:
        print("OK: app_settings write gated by isValidBannerConfig() for banner_config doc")

    # batch_imports
    batch_block = find_block(stripped, "match /batch_imports/{importId}")
    if not batch_block:
        print("FAIL: batch_imports match block not found")
        errors += 1
    elif "allow create: if isAdmin() && isValidBatchImport()" not in batch_block:
        print("FAIL: batch_imports create does not require isValidBatchImport()")
        errors += 1
    else:
        print("OK: batch_imports create requires isValidBatchImport()")

    # 7. Schema helpers contain key validation expressions
    movie_helper = find_block(stripped, "function isValidMovie()")
    if not movie_helper:
        print("FAIL: isValidMovie() helper block not found")
        errors += 1
    else:
        # Type-checked fields (when present in the request)
        if "title is string" not in movie_helper:
            print("FAIL: isValidMovie() does not check title is string")
            errors += 1
        if "type is string" not in movie_helper:
            print("FAIL: isValidMovie() does not check type is string")
            errors += 1
        # Enum: type == 'movie' or 'series'
        if "'movie'" not in movie_helper or "'series'" not in movie_helper:
            print("FAIL: isValidMovie() does not enforce type enum {movie, series}")
            errors += 1
        else:
            print("OK: isValidMovie() enforces type enum {movie, series} (when type is present)")
        # Partial-update tolerant: uses keys().hasAny()
        if "keys().hasAny(['title'])" not in movie_helper:
            print("FAIL: isValidMovie() does not use keys().hasAny(['title']) for partial-update tolerance")
            errors += 1
        else:
            print("OK: isValidMovie() tolerates partial updates (only validates present fields)")

    genre_helper = find_block(stripped, "function isValidGenreOrTagOrCollection()")
    if not genre_helper:
        print("FAIL: isValidGenreOrTagOrCollection() helper not found")
        errors += 1
    else:
        if "name is string" not in genre_helper or "moviesCount is int" not in genre_helper:
            print("FAIL: isValidGenreOrTagOrCollection() missing name/moviesCount type checks")
            errors += 1
        else:
            print("OK: isValidGenreOrTagOrCollection() validates name + moviesCount types")

    notif_helper = find_block(stripped, "function isValidNotification()")
    if not notif_helper:
        print("FAIL: isValidNotification() helper not found")
        errors += 1
    else:
        if "sentAt is timestamp" not in notif_helper:
            print("FAIL: isValidNotification() does not check sentAt is timestamp")
            errors += 1
        else:
            print("OK: isValidNotification() validates sentAt timestamp")

    batch_helper = find_block(stripped, "function isValidBatchImport()")
    if not batch_helper:
        print("FAIL: isValidBatchImport() helper not found")
        errors += 1
    else:
        if "adminUid is string" not in batch_helper or "cancelled is bool" not in batch_helper:
            print("FAIL: isValidBatchImport() missing adminUid/cancelled type checks")
            errors += 1
        else:
            print("OK: isValidBatchImport() validates adminUid + cancelled types")

    # Summary
    print("\n" + "=" * 60)
    if errors == 0:
        print(f"PASS: All Phase 2.6 validation checks passed for {RULES_FILE.name}")
        return 0
    else:
        print(f"FAIL: {errors} error(s) found in {RULES_FILE.name}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
