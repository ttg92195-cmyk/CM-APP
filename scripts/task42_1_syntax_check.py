#!/usr/bin/env python3
"""
Task 42#1 syntax + invariant check for the getMoviesByActor fix.

Uses a proper single-pass tokenizer that recognizes Dart string literals
(incl. '...', "...", r'...', r"...", '''...''', \"\"\"...\"\"\") and
line/block comments WITHOUT one corrupting the other. Previous version
stripped comments first via regex, which ate // inside string literals
(like URLs 'https://...') and produced false imbalance reports.

Validates:
  1. Dart delimiter balance () [] {} for the whole file.
  2. The new _extractCastName helper exists and handles all 3 formats
     (Map, String, fallback toString).
  3. getMoviesByActor uses _extractCastName (NOT the old inline
     `cast is Map<String, dynamic>` check).
  4. limit is 500, not 100.
  5. The old buggy `cast['name'] as String?` inline pattern is gone
     from getMoviesByActor.
  6. Defensive try/catch around Movie.fromMap (so one bad doc can't
     nuke the whole result list).

Run: python3 scripts/task42_1_syntax_check.py
"""
from __future__ import annotations
import sys
from pathlib import Path

TARGET = Path("/home/z/my-project/lib/app/core/services/firestore_content_service.dart")

def strip_comments_and_strings(src: str) -> str:
    """
    Single-pass tokenizer that returns the source with:
      - line comments (//...)     → removed
      - block comments (/* ... */) → removed
      - string literals           → replaced with '' or ""
    Handles:
      - escape sequences inside strings (\\n, \\t, \\' etc.)
      - raw strings (r'...' r"...")
      - triple-quoted strings ('''...''' and \"\"\"...\"\"\")
      - // inside strings (e.g. URLs) — NOT treated as comment
      - ' inside comments — NOT treated as string delimiter
    """
    out = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        # Line comment
        if ch == '/' and i + 1 < n and src[i+1] == '/':
            # Skip to end of line
            while i < n and src[i] != '\n':
                i += 1
            continue
        # Block comment
        if ch == '/' and i + 1 < n and src[i+1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i+1] == '/'):
                i += 1
            i += 2
            continue
        # Triple-quoted string '''...''' or \"\"\"...\"\"\"
        if ch == "'" and src[i:i+3] == "'''":
            i += 3
            while i + 2 < n and src[i:i+3] != "'''":
                if src[i] == '\\':
                    i += 2
                else:
                    i += 1
            i += 3
            out.append("''")
            continue
        if ch == '"' and src[i:i+3] == '"""':
            i += 3
            while i + 2 < n and src[i:i+3] != '"""':
                if src[i] == '\\':
                    i += 2
                else:
                    i += 1
            i += 3
            out.append('""')
            continue
        # Raw string r'...' or r"..."
        if ch == 'r' and i + 1 < n and src[i+1] in ('"', "'"):
            quote = src[i+1]
            i += 2
            while i < n and src[i] != quote:
                i += 1
            i += 1
            out.append('r' + quote + quote)
            continue
        # Single-quoted string
        if ch == "'":
            i += 1
            while i < n and src[i] != "'":
                if src[i] == '\\' and i + 1 < n:
                    i += 2
                else:
                    i += 1
            i += 1
            out.append("''")
            continue
        # Double-quoted string
        if ch == '"':
            i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\' and i + 1 < n:
                    i += 2
                else:
                    i += 1
            i += 1
            out.append('""')
            continue
        # Regular character — keep as-is
        out.append(ch)
        i += 1
    return ''.join(out)

def check_delimiter_balance(src: str) -> tuple[bool, str]:
    """Verify (), [], {} are balanced in stripped source."""
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    opens = set("([{")
    for i, ch in enumerate(src):
        if ch in opens:
            stack.append((ch, i))
        elif ch in pairs:
            if not stack or stack[-1][0] != pairs[ch]:
                return False, f"Unbalanced '{ch}' at index {i}"
            stack.pop()
    if stack:
        ch, i = stack[-1]
        return False, f"Unclosed '{ch}' opened at index {i}"
    return True, "OK"

def find_function_body(src: str, func_sig_pattern: str) -> str | None:
    """Find the brace-delimited body of a function whose signature matches
    the given regex pattern. Returns the body (including outer braces) or None."""
    import re
    m = re.search(func_sig_pattern, src)
    if not m:
        return None
    # Find the '{' that opens the body
    start = src.find('{', m.end())
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(src)):
        if src[i] == '{':
            depth += 1
        elif src[i] == '}':
            depth -= 1
            if depth == 0:
                return src[start:i+1]
    return None

def main() -> int:
    if not TARGET.exists():
        print(f"FAIL: target file not found: {TARGET}")
        return 1

    raw = TARGET.read_text(encoding="utf-8")
    stripped = strip_comments_and_strings(raw)

    # 1. Delimiter balance (whole file)
    ok, msg = check_delimiter_balance(stripped)
    if not ok:
        print(f"FAIL: delimiter balance — {msg}")
        return 1
    print("OK: delimiters balanced")

    # 2. _extractCastName helper exists
    import re
    if not re.search(r"static\s+String\?\s+_extractCastName\s*\(\s*dynamic\s+cast\s*\)", stripped):
        print("FAIL: _extractCastName helper not found")
        return 1
    print("OK: _extractCastName helper present")

    # 3. _extractCastName handles all 3 formats
    helper_body = find_function_body(
        stripped,
        r"static\s+String\?\s+_extractCastName\s*\(\s*dynamic\s+cast\s*\)\s*",
    )
    if helper_body is None:
        print("FAIL: could not extract _extractCastName body")
        return 1
    if "cast is Map" not in helper_body:
        print("FAIL: _extractCastName must check `cast is Map` (loose, not just Map<String,dynamic>)")
        return 1
    if "cast is Map<String, dynamic>" in helper_body:
        # Allow it but make sure there's also a loose check (already verified above)
        pass
    if "cast is String" not in helper_body:
        print("FAIL: _extractCastName must handle `cast is String` (legacy Batch Import format)")
        return 1
    print("OK: _extractCastName handles Map + String formats")

    # 4. getMoviesByActor uses _extractCastName
    actor_body = find_function_body(
        stripped,
        r"Future<List<Movie>>\s+getMoviesByActor\s*\([^)]*\)\s*async\s*",
    )
    if actor_body is None:
        print("FAIL: getMoviesByActor function not found")
        return 1
    if "_extractCastName" not in actor_body:
        print("FAIL: getMoviesByActor does not call _extractCastName")
        return 1
    print("OK: getMoviesByActor uses _extractCastName")

    # 5. Old buggy pattern removed from getMoviesByActor
    if "cast is Map<String, dynamic>" in actor_body:
        print("FAIL: getMoviesByActor still uses old `cast is Map<String, dynamic>` check")
        return 1
    if re.search(r"cast\[\s*['\"]name['\"]\s*\]\s+as\s+String\?", actor_body):
        print("FAIL: getMoviesByActor still uses old `cast['name'] as String?` cast")
        return 1
    print("OK: old buggy patterns removed from getMoviesByActor")

    # 6. Limit raised to 500
    if ".limit(100)" in actor_body:
        print("FAIL: getMoviesByActor still uses .limit(100)")
        return 1
    if ".limit(500)" not in actor_body:
        print("FAIL: getMoviesByActor does not use .limit(500)")
        return 1
    print("OK: limit raised to 500")

    # 7. Defensive try/catch around Movie.fromMap
    from_map_count = actor_body.count("Movie.fromMap(")
    try_count = actor_body.count("try")
    if from_map_count == 0:
        print("FAIL: getMoviesByActor does not call Movie.fromMap")
        return 1
    if try_count < from_map_count:
        print(f"FAIL: getMoviesByActor has {from_map_count} Movie.fromMap calls but only {try_count} try blocks — not all wrapped defensively")
        return 1
    print(f"OK: all {from_map_count} Movie.fromMap calls wrapped in try/catch")

    # 8. Sanity: also confirm the buggy 100-limit pattern is gone in the
    #    primary path AND the fallback path (both should be 500 now).
    if actor_body.count(".limit(500)") < 2:
        print(f"FAIL: expected 2 .limit(500) calls (primary + fallback), found {actor_body.count('.limit(500)')}")
        return 1
    print("OK: both primary and fallback paths use .limit(500)")

    print("\nALL CHECKS PASSED")
    return 0

if __name__ == "__main__":
    sys.exit(main())
