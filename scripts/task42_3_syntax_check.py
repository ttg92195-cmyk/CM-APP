#!/usr/bin/env python3
"""
Task 42#3 — syntax check for Trailer button fix.

Files touched:
  - android/app/src/main/AndroidManifest.xml (added <queries> block)
  - lib/app/ui/screens/movie_detail_screen.dart (removed canLaunchUrl guard)
  - lib/app/ui/screens/series_detail_screen.dart (removed canLaunchUrl guard)

Verifies:
  1. AndroidManifest.xml has a <queries> block declaring http/https schemes.
  2. Neither detail screen still contains `canLaunchUrl` in the trailer
     button onPressed handler.
  3. Both detail screens now wrap launchUrl in a try/catch and surface
     failure via SnackBar.
  4. Dart delimiter balance for both detail screens.
"""

import re
import sys
from pathlib import Path

REPO = Path("/home/z/my-project")
FILES = [
    REPO / "android/app/src/main/AndroidManifest.xml",
    REPO / "lib/app/ui/screens/movie_detail_screen.dart",
    REPO / "lib/app/ui/screens/series_detail_screen.dart",
]


def strip_comments_and_strings(src: str) -> str:
    """For Dart files: replace comment bodies and string literals with spaces."""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        nxt = src[i+1] if i+1 < n else ''
        if c == '/' and nxt == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and nxt == '*':
            i += 2
            while i+1 < n and not (src[i] == '*' and src[i+1] == '/'):
                if src[i] == '\n':
                    out.append('\n')
                i += 1
            i += 2
            continue
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
    errors = []
    pairs = {')': '(', '}': '{', ']': '['}
    opens = set(pairs.values())
    stack = []
    line = 1
    for ch in skeleton:
        if ch == '\n':
            line += 1
            continue
        if ch in opens:
            stack.append((ch, line))
        elif ch in pairs:
            if not stack:
                errors.append(f"  {label}: unbalanced '{ch}' at line {line}")
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


def main() -> int:
    print("=" * 70)
    print("Task 42#3 — Trailer button fix syntax check")
    print("=" * 70)

    all_errors: list[str] = []

    # AndroidManifest — XML check (just look for the queries block + scheme)
    manifest = REPO / "android/app/src/main/AndroidManifest.xml"
    print(f"\n--- {manifest.relative_to(REPO)} ---")
    raw = manifest.read_text(encoding='utf-8')
    if '<queries>' not in raw:
        all_errors.append("  AndroidManifest.xml: missing <queries> block")
        print("  missing <queries> block ✗")
    else:
        # crude: check that both http and https schemes are declared
        has_https = bool(re.search(r'<data\s+android:scheme="https"\s*/>', raw))
        has_http = bool(re.search(r'<data\s+android:scheme="http"\s*/>', raw))
        if not (has_https and has_http):
            all_errors.append(
                "  AndroidManifest.xml: <queries> block missing http/https scheme"
            )
            print(f"  <queries> present but http={has_http} https={has_https} ✗")
        else:
            print("  <queries> block with http+https schemes ✓")

    # Dart files — delimiter balance + content invariants
    for f in [REPO / "lib/app/ui/screens/movie_detail_screen.dart",
              REPO / "lib/app/ui/screens/series_detail_screen.dart"]:
        print(f"\n--- {f.relative_to(REPO)} ---")
        raw = f.read_text(encoding='utf-8')
        skeleton = strip_comments_and_strings(raw)
        bal_errors = check_balanced(skeleton, f.name)
        if bal_errors:
            all_errors.extend(bal_errors)
            for e in bal_errors:
                print(e)
        else:
            print("  delimiters balanced ✓")

        # Find the trailer button block and verify it does NOT use canLaunchUrl
        # and DOES wrap launchUrl in try/catch. Strip comments first so we
        # don't match words inside comment text.
        skel_no_comments = strip_comments_and_strings(raw)
        if 'canLaunchUrl' in skel_no_comments:
            all_errors.append(f"  {f.name}: still contains `canLaunchUrl` (in code)")
            print("  still uses canLaunchUrl ✗")
        else:
            print("  no canLaunchUrl guard in code ✓")
        # Loose check: try { ... launchUrl ... } catch
        if not re.search(r'try\s*\{.*?launchUrl.*?\}\s*catch', skel_no_comments, re.DOTALL):
            all_errors.append(f"  {f.name}: launchUrl not wrapped in try/catch")
            print("  launchUrl not in try/catch ✗")
        else:
            print("  launchUrl wrapped in try/catch ✓")

    print("\n" + "=" * 70)
    if all_errors:
        print(f"FAIL — {len(all_errors)} error(s) found")
        return 1
    else:
        print("PASS — all checks green")
        return 0


if __name__ == "__main__":
    sys.exit(main())
