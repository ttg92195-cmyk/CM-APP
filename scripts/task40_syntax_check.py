#!/usr/bin/env python3
"""
Task 40 — Dart syntax sanity check for the poster-loading improvements.

Files touched:
  - lib/app/ui/components/movie_card.dart

This scanner is delimiter-aware (counts braces, parens, brackets; respects
line/block comments and string literals), so it won't be fooled by braces
or quotes inside strings or comments the way a naive grep would.

It also verifies a few content-specific invariants for Task 40:
  1. `_posterRetryCount` field is declared.
  2. `_maxAutoRetries` const is declared.
  3. `_posterImageUrl` getter is declared.
  4. `memCacheWidth: 400` is present in the CachedNetworkImage.
  5. `cacheKey` no longer uses just `widget.movie.id` (must combine
     with retry count).
  6. `errorWidget` is a function (not a direct widget) — needed for
     the auto-retry logic.
  7. `placeholder` does NOT contain CircularProgressIndicator (we
     replaced it with a quiet Container).
"""

import re
import sys
from pathlib import Path

REPO = Path("/home/z/my-project")
FILES = [
    REPO / "lib/app/ui/components/movie_card.dart",
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
        # triple-quoted string
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
    """Verify braces, parens, brackets are balanced. Returns list of error messages."""
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
    """Verify Task 40 specific code patterns are present."""
    errors = []
    name = file_path.name

    if "_posterRetryCount" not in raw:
        errors.append(f"  {name}: missing `_posterRetryCount` field")
    if "_maxAutoRetries" not in raw:
        errors.append(f"  {name}: missing `_maxAutoRetries` const")
    if "_posterImageUrl" not in raw:
        errors.append(f"  {name}: missing `_posterImageUrl` getter")
    if "memCacheWidth: 400" not in raw:
        errors.append(f"  {name}: missing `memCacheWidth: 400`")
    if "cacheKey: widget.movie.id," in raw:
        errors.append(
            f"  {name}: cacheKey still uses just `widget.movie.id` "
            "(must combine with retry count for cache-busting)"
        )
    # errorWidget must be a function (arrow or block) — i.e. `errorWidget: (context, url, error) =>` or `errorWidget: (context, url, error) {`
    if not re.search(r"errorWidget:\s*\(context,\s*url,\s*error\)\s*(=>|\{)", raw):
        errors.append(
            f"  {name}: errorWidget is not a function (must be `(context, url, error) => ...` "
            "or `(context, url, error) {{ ... }}` for the auto-retry logic to work)"
        )
    if "CircularProgressIndicator" in raw:
        errors.append(
            f"  {name}: CircularProgressIndicator still present in placeholder "
            "(should be replaced with a quiet Container to match skeleton style)"
        )
    return errors


# ---------- main ----------

def main() -> int:
    print("=" * 70)
    print("Task 40 — poster loading fix syntax check")
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
            print(f"  Task 40 invariants present ✓")

    print("\n" + "=" * 70)
    if all_errors:
        print(f"FAIL — {len(all_errors)} error(s) found")
        return 1
    else:
        print("PASS — all checks green")
        return 0


if __name__ == "__main__":
    sys.exit(main())
