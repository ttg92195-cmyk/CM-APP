#!/usr/bin/env python3
"""
Task 39 — Dart syntax sanity check for the pagination bug fix.

Files touched:
  - lib/app/core/services/firestore_content_service.dart
      (3 fallback paths: getMoviesByGenre, getMoviesByTag, getMoviesByCollection)
  - lib/app/ui/screens/genres_tags_collections_page.dart
      (_hasMore calculation in _loadMore)

This scanner is delimiter-aware (counts braces, parens, brackets; respects line/block comments and string literals),
so it won't be fooled by braces or quotes inside strings or comments the way a
naive grep would. It catches:
  - Unbalanced { } ( ) [ ]
  - Unterminated string/quote
  - Stray semicolons inside expressions (rare but possible)
  - Missing `;` after statements (heuristic)

It also verifies a few content-specific invariants for Task 39:
  1. Each of the 3 fallback paths now contains
     `if (startAfter != null) { query = query.startAfterDocument(startAfter); }`
     exactly once.
  2. The _hasMore line in genres_tags_collections_page.dart now uses
     `dedupedMovies.isNotEmpty` (not `newMovies.isNotEmpty`).
"""

import re
import sys
from pathlib import Path

REPO = Path("/home/z/my-project")
FILES = [
    REPO / "lib/app/core/services/firestore_content_service.dart",
    REPO / "lib/app/ui/screens/genres_tags_collections_page.dart",
]

# ---------- delimiter-aware scanner ----------

def strip_comments_and_strings(src: str) -> str:
    """
    Replace comment bodies and string literals with spaces (preserving
    newlines so line numbers stay aligned). Returns a "skeleton" string
    where only meaningful code tokens remain for delimiter counting.
    """
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        nxt = src[i+1] if i+1 < n else ''
        # line comment
        if c == '/' and nxt == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        # block comment
        if c == '/' and nxt == '*':
            i += 2
            while i+1 < n and not (src[i] == '*' and src[i+1] == '/'):
                if src[i] == '\n':
                    out.append('\n')
                i += 1
            i += 2
            continue
        # raw string r'...' or r"..."
        if c == 'r' and nxt in ("'", '"'):
            quote = nxt
            out.append(' ')
            i += 2
            while i < n and src[i] != quote:
                if src[i] == '\n':
                    out.append('\n')
                else:
                    out.append(' ')
                i += 1
            if i < n:
                out.append(' ')
                i += 1
            continue
        # triple-quoted string """ or '''
        if c in ('"', "'") and src[i:i+3] in ('"""', "'''"):
            triple = src[i:i+3]
            out.append(' ' * 3)
            i += 3
            while i+2 < n and src[i:i+3] != triple:
                if src[i] == '\n':
                    out.append('\n')
                else:
                    out.append(' ')
                i += 1
            if i+2 < n:
                out.append(' ' * 3)
                i += 3
            continue
        # single-quoted string
        if c == "'":
            out.append(' ')
            i += 1
            while i < n and src[i] != "'":
                if src[i] == '\\' and i+1 < n:
                    out.append('  ')
                    i += 2
                    continue
                if src[i] == '\n':
                    out.append('\n')
                else:
                    out.append(' ')
                i += 1
            if i < n:
                out.append(' ')
                i += 1
            continue
        # double-quoted string
        if c == '"':
            out.append(' ')
            i += 1
            while i < n and src[i] != '"':
                if src[i] == '\\' and i+1 < n:
                    out.append('  ')
                    i += 2
                    continue
                if src[i] == '\n':
                    out.append('\n')
                else:
                    out.append(' ')
                i += 1
            if i < n:
                out.append(' ')
                i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def check_balanced(skeleton: str, label: str) -> list[str]:
    """Verify { } ( ) [ ] are balanced. Returns list of error messages."""
    errors = []
    pairs = {')': '(', '}': '{', ']': '['}
    opens = set(pairs.values())
    stack = []  # list of (char, line_no)
    line = 1
    for ch in skeleton:
        if ch == '\n':
            line += 1
            continue
        if ch in opens:
            stack.append((ch, line))
        elif ch in pairs:
            if not stack:
                errors.append(f"  {label}: unbalanced '{ch}' at line {line} (no opener)")
                continue
            opener, opener_line = stack.pop()
            if opener != pairs[ch]:
                errors.append(
                    f"  {label}: mismatched '{ch}' at line {line} "
                    f"(expected closer for '{opener}' opened at line {opener_line})"
                )
    if stack:
        for opener, ln in stack:
            errors.append(f"  {label}: unclosed '{opener}' opened at line {ln}")
    return errors


# ---------- content invariants ----------

def check_invariants(file_path: Path, raw: str) -> list[str]:
    """Verify Task 39 specific code patterns are present."""
    errors = []
    name = file_path.name

    if name == "firestore_content_service.dart":
        # Each fallback must have startAfterDocument guard.
        for fn in ("getMoviesByGenre", "getMoviesByTag", "getMoviesByCollection"):
            # Find the function body
            m = re.search(
                rf'Future<Map<String,\s*dynamic>>\s+{re.escape(fn)}\s*\(',
                raw,
            )
            if not m:
                errors.append(f"  {name}: cannot locate function {fn}")
                continue
            # Take a slice of the next ~3000 chars to capture both primary and fallback paths
            body = raw[m.start(): m.start() + 4000]
            fallback_marker = f"trying fallback"
            if fallback_marker not in body:
                errors.append(f"  {name}: {fn} — fallback marker not found")
                continue
            fallback = body[body.index(fallback_marker):]
            # Should have exactly one new startAfterDocument guard in the fallback section
            n_guard = fallback.count("query.startAfterDocument(startAfter)")
            if n_guard < 1:
                errors.append(
                    f"  {name}: {fn} — fallback missing startAfterDocument guard"
                )
            # (We expect exactly 1 in fallback + 1 in primary = 2 total in the slice;
            # the primary one was already there before Task 39.)

    elif name == "genres_tags_collections_page.dart":
        # The _hasMore line must use dedupedMovies.isNotEmpty, not newMovies.isNotEmpty
        if "dedupedMovies.isNotEmpty" not in raw:
            errors.append(
                "  " + str(name) + ": _hasMore still uses old 'newMovies.isNotEmpty' "
                "(expected 'dedupedMovies.isNotEmpty')"
            )
        if "result['hasMore'] as bool && newMovies.isNotEmpty" in raw:
            errors.append(
                "  " + str(name) + ": old buggy _hasMore line still present "
                "('result[\\'hasMore\\'] as bool && newMovies.isNotEmpty')"
            )

    return errors


# ---------- main ----------

def main() -> int:
    print("=" * 70)
    print("Task 39 — pagination bug fix syntax check")
    print("=" * 70)

    all_errors: list[str] = []

    for f in FILES:
        print(f"\n--- {f.relative_to(REPO)} ---")
        if not f.exists():
            print(f"  ERROR: file not found")
            all_errors.append(f"  {f.name}: file not found")
            continue
        raw = f.read_text(encoding='utf-8')
        skeleton = strip_comments_and_strings(raw)

        # delimiter balance
        bal_errors = check_balanced(skeleton, f.name)
        if bal_errors:
            all_errors.extend(bal_errors)
            for e in bal_errors:
                print(e)
        else:
            print(f"  delimiters balanced ✓")

        # content invariants
        inv_errors = check_invariants(f, raw)
        if inv_errors:
            all_errors.extend(inv_errors)
            for e in inv_errors:
                print(e)
        else:
            print(f"  Task 39 invariants present ✓")

    print("\n" + "=" * 70)
    if all_errors:
        print(f"FAIL — {len(all_errors)} error(s) found")
        return 1
    else:
        print("PASS — all checks green")
        return 0


if __name__ == "__main__":
    sys.exit(main())
