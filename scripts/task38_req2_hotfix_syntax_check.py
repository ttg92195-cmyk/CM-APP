#!/usr/bin/env python3
"""
Task 38 Req 2 hotfix — Dart-aware delimiter scanner.

Verifies that the two files patched in the hotfix
  - lib/app/ui/screens/movie_detail_screen.dart
  - lib/app/ui/screens/series_detail_screen.dart
have balanced (), {}, [] after the white45 -> white54 fix.

Skips string literals (single/double/triple-quoted, with escape handling)
and // comments and /* */ block comments.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [
    ROOT / "lib/app/ui/screens/movie_detail_screen.dart",
    ROOT / "lib/app/ui/screens/series_detail_screen.dart",
]

OPENERS = "({["
CLOSERS = ")}]"
PAIR = dict(zip(OPENERS, CLOSERS))


def scan(text: str):
    """Return list of (line, col, char) imbalance errors."""
    stack = []  # (closer, line, col)
    errors = []
    i = 0
    line = 1
    col = 1
    n = len(text)
    while i < n:
        c = text[i]
        # Newline tracking
        if c == "\n":
            line += 1
            col = 1
            i += 1
            continue
        # Line comment
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        # Block comment
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            col += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                if text[i] == "\n":
                    line += 1
                    col = 1
                else:
                    col += 1
                i += 1
            i += 2  # skip */
            col += 2
            continue
        # Triple-quoted string (raw or normal)
        if text[i:i + 3] in ('"""', "'''"):
            quote = text[i:i + 3]
            i += 3
            col += 3
            while i < n and text[i:i + 3] != quote:
                if text[i] == "\\":
                    i += 2
                    col += 2
                    continue
                if text[i] == "\n":
                    line += 1
                    col = 1
                else:
                    col += 1
                i += 1
            i += 3
            col += 3
            continue
        # Single-quoted string (raw 'r' prefix handled by escape skip below)
        if c in ('"', "'"):
            quote = c
            i += 1
            col += 1
            while i < n and text[i] != quote:
                if text[i] == "\\":
                    i += 2
                    col += 2
                    continue
                if text[i] == "\n":
                    # Dart single-line strings don't span newlines, but be tolerant
                    line += 1
                    col = 1
                else:
                    col += 1
                i += 1
            i += 1
            col += 1
            continue
        # Delimiters
        if c in OPENERS:
            stack.append((PAIR[c], line, col))
            i += 1
            col += 1
            continue
        if c in CLOSERS:
            if not stack:
                errors.append((line, col, f"unexpected '{c}'"))
            else:
                expected, ol, oc = stack.pop()
                if expected != c:
                    errors.append(
                        (line, col,
                         f"expected '{expected}' (to match {ol}:{oc}) got '{c}'"))
            i += 1
            col += 1
            continue
        i += 1
        col += 1
    for expected, ol, oc in stack:
        errors.append((ol, oc, f"unclosed '{expected}'"))
    return errors


def main():
    overall_ok = True
    for f in FILES:
        if not f.exists():
            print(f"MISSING: {f}")
            overall_ok = False
            continue
        text = f.read_text(encoding="utf-8")
        errs = scan(text)
        if errs:
            overall_ok = False
            print(f"FAIL: {f.name}")
            for line, col, msg in errs[:10]:
                print(f"  line {line}, col {col}: {msg}")
        else:
            # Quick stats
            opens = sum(text.count(o) for o in OPENERS)
            closes = sum(text.count(o) for o in CLOSERS)
            print(f"OK  : {f.name}  ({len(text.splitlines())} lines, "
                  f"{opens} openers, {closes} closers)")
    if overall_ok:
        print("\nAll files balanced.")
        return 0
    print("\nImbalance detected.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
