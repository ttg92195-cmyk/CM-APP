#!/usr/bin/env python3
"""
Task 42#2 syntax + invariant check.

Validates BOTH fixes:
  A. Casts section SizedBox height tightened 140 → 116 in
     movie_detail_screen.dart AND series_detail_screen.dart.
  B. _loadRelatedMovies / _loadRelatedSeries rewritten to:
     - Loop through MULTIPLE categories (take(3)), not just first
     - Pass typeFilter 'movie' / 'series' so wrong-type doesn't leak
     - Score candidates by category overlap
     - Sort by score desc, then createdAt desc
     - Take 10
     - NO trending fallback (no getTrendingMovies / getTrendingTvShows
       call inside _loadRelated*)

Uses the same single-pass tokenizer as task42_1_syntax_check.py
(comments and strings don't corrupt each other).

Run: python3 scripts/task42_2_syntax_check.py
"""
from __future__ import annotations
import re
import sys
from pathlib import Path

MOVIE_DETAIL = Path("/home/z/my-project/lib/app/ui/screens/movie_detail_screen.dart")
SERIES_DETAIL = Path("/home/z/my-project/lib/app/ui/screens/series_detail_screen.dart")


def strip_comments_and_strings(src: str) -> str:
    """Single-pass tokenizer — same impl as task42_1_syntax_check.py."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if ch == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                i += 1
            i += 2
            continue
        if ch == "'" and src[i:i + 3] == "'''":
            i += 3
            while i + 2 < n and src[i:i + 3] != "'''":
                if src[i] == '\\':
                    i += 2
                else:
                    i += 1
            i += 3
            out.append("''")
            continue
        if ch == '"' and src[i:i + 3] == '"""':
            i += 3
            while i + 2 < n and src[i:i + 3] != '"""':
                if src[i] == '\\':
                    i += 2
                else:
                    i += 1
            i += 3
            out.append('""')
            continue
        if ch == 'r' and i + 1 < n and src[i + 1] in ('"', "'"):
            quote = src[i + 1]
            i += 2
            while i < n and src[i] != quote:
                i += 1
            i += 1
            out.append('r' + quote + quote)
            continue
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
        out.append(ch)
        i += 1
    return ''.join(out)


def check_delimiter_balance(src: str) -> tuple[bool, str]:
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


def find_function_body(src: str, sig_pattern: str) -> str | None:
    m = re.search(sig_pattern, src)
    if not m:
        return None
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
                return src[start:i + 1]
    return None


def _find_function_body_raw(raw_src: str, func_name: str) -> str | None:
    """Find the raw (un-stripped) body of a function by name. Uses the
    same brace-matching logic, but operates on raw source so string
    literals like 'movie' / 'series' are preserved."""
    # Find the function signature in raw source.
    pattern = rf"Future<void>\s+{func_name}\s*\(\s*MovieDetail\s+detail\s*\)\s*async\s*"
    m = re.search(pattern, raw_src)
    if not m:
        return None
    # Find opening '{' after signature. Skip over strings/comments while
    # searching so we don't accidentally match a '{' inside one.
    i = m.end()
    n = len(raw_src)
    start = -1
    while i < n:
        ch = raw_src[i]
        if ch == '/' and i + 1 < n and raw_src[i + 1] == '/':
            while i < n and raw_src[i] != '\n':
                i += 1
            continue
        if ch == '/' and i + 1 < n and raw_src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (raw_src[i] == '*' and raw_src[i + 1] == '/'):
                i += 1
            i += 2
            continue
        if ch == "'":
            i += 1
            while i < n and raw_src[i] != "'":
                if raw_src[i] == '\\' and i + 1 < n:
                    i += 2
                else:
                    i += 1
            i += 1
            continue
        if ch == '"':
            i += 1
            while i < n and raw_src[i] != '"':
                if raw_src[i] == '\\' and i + 1 < n:
                    i += 2
                else:
                    i += 1
            i += 1
            continue
        if ch == '{':
            start = i
            break
        i += 1
    if start < 0:
        return None
    # Brace-match the body, skipping strings/comments.
    depth = 0
    i = start
    while i < n:
        ch = raw_src[i]
        if ch == '/' and i + 1 < n and raw_src[i + 1] == '/':
            while i < n and raw_src[i] != '\n':
                i += 1
            continue
        if ch == '/' and i + 1 < n and raw_src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (raw_src[i] == '*' and raw_src[i + 1] == '/'):
                i += 1
            i += 2
            continue
        if ch == "'":
            i += 1
            while i < n and raw_src[i] != "'":
                if raw_src[i] == '\\' and i + 1 < n:
                    i += 2
                else:
                    i += 1
            i += 1
            continue
        if ch == '"':
            i += 1
            while i < n and raw_src[i] != '"':
                if raw_src[i] == '\\' and i + 1 < n:
                    i += 2
                else:
                    i += 1
            i += 1
            continue
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return raw_src[start:i + 1]
        i += 1
    return None


def check_file(path: Path, screen_label: str, func_name: str, type_filter: str) -> int:
    print(f"\n=== Checking {path.name} ({screen_label}) ===")
    if not path.exists():
        print(f"FAIL: file not found: {path}")
        return 1

    raw = path.read_text(encoding="utf-8")
    stripped = strip_comments_and_strings(raw)

    # 1. Delimiter balance
    ok, msg = check_delimiter_balance(stripped)
    if not ok:
        print(f"FAIL: delimiter balance — {msg}")
        return 1
    print("OK: delimiters balanced")

    # 2. Casts SizedBox height is 116 (not 140).
    # The 'CAST SECTION' marker is inside a // comment, so it gets
    # stripped. Use raw source to locate it, then verify height: 116
    # appears within the next ~800 chars (also in raw source).
    if "height: 140" in raw:
        idx = raw.find("height: 140")
        context = raw[max(0, idx - 400):idx + 400]
        if "CAST SECTION" in context.upper():
            print(f"FAIL: Casts section still has height: 140")
            return 1
        print("NOTE: height: 140 found elsewhere (not Casts) — OK")
    if "height: 116" not in raw:
        print("FAIL: height: 116 not found in file")
        return 1
    casts_idx = raw.upper().find("CAST SECTION")
    if casts_idx >= 0:
        after_casts = raw[casts_idx:casts_idx + 1200]
        if "height: 116" not in after_casts:
            print("FAIL: height: 116 not found within 1200 chars after 'CAST SECTION' comment")
            return 1
        print("OK: Casts SizedBox height is 116 (in CAST SECTION)")
    else:
        print("OK: Casts SizedBox height is 116 (no CAST SECTION comment found, but 116 is present)")

    # 3. _loadRelated* function exists
    body = find_function_body(
        stripped,
        rf"Future<void>\s+{func_name}\s*\(\s*MovieDetail\s+detail\s*\)\s*async\s*",
    )
    if body is None:
        print(f"FAIL: {func_name} function not found")
        return 1
    print(f"OK: {func_name} function present")

    # 4. Uses .take(3) for categories (multiple-category loop)
    if ".take(3)" not in body:
        print(f"FAIL: {func_name} does not use .take(3) for category cap")
        return 1
    print(f"OK: {func_name} caps categories at 3")

    # 5. Passes typeFilter
    # 'movie' / 'series' are string literals → stripped to ''. Check raw
    # source inside the function body's line range instead.
    raw_body = _find_function_body_raw(raw, func_name)
    if raw_body is None:
        print(f"FAIL: could not extract raw body for {func_name}")
        return 1
    if f"typeFilter: '{type_filter}'" not in raw_body:
        print(f"FAIL: {func_name} does not pass typeFilter: '{type_filter}'")
        return 1
    print(f"OK: {func_name} passes typeFilter: '{type_filter}'")

    # 6. NO trending fallback (no getTrendingMovies / getTrendingTvShows)
    if "getTrendingMovies" in body or "getTrendingTvShows" in body:
        print(f"FAIL: {func_name} still has trending fallback")
        return 1
    print(f"OK: {func_name} has NO trending fallback")

    # 7. Scoring by category overlap (look for 'score' variable)
    if "int score" not in body or "score +=" not in body:
        print(f"FAIL: {func_name} does not compute category-overlap score")
        return 1
    print(f"OK: {func_name} computes category-overlap score")

    # 8. Sort by score desc, then createdAt desc
    if "b.score.compareTo(a.score)" not in body:
        print(f"FAIL: {func_name} does not sort by score desc")
        return 1
    if "b.movie.createdAt" not in body or "a.movie.createdAt" not in body:
        print(f"FAIL: {func_name} does not sort by createdAt as tiebreaker")
        return 1
    print(f"OK: {func_name} sorts by score desc then createdAt desc")

    # 9. Takes 10
    if ".take(10)" not in body:
        print(f"FAIL: {func_name} does not take 10")
        return 1
    print(f"OK: {func_name} takes top 10")

    # 10. Uses getMoviesByGenre (with typeFilter)
    if "getMoviesByGenre" not in body:
        print(f"FAIL: {func_name} does not call getMoviesByGenre")
        return 1
    print(f"OK: {func_name} calls getMoviesByGenre")

    # 11. Uses getMoviesByTagSimple for tag-based candidates
    if "getMoviesByTagSimple" not in body:
        print(f"FAIL: {func_name} does not call getMoviesByTagSimple")
        return 1
    print(f"OK: {func_name} calls getMoviesByTagSimple")

    return 0


def main() -> int:
    rc1 = check_file(MOVIE_DETAIL, "movie", "_loadRelatedMovies", "movie")
    rc2 = check_file(SERIES_DETAIL, "series", "_loadRelatedSeries", "series")

    if rc1 == 0 and rc2 == 0:
        print("\nALL CHECKS PASSED")
        return 0
    print("\nFAILURES DETECTED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
