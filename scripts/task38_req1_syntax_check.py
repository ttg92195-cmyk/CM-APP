#!/usr/bin/env python3
"""
Task 38 Req 1 — Dark Mode poster color fix.

Dart-aware delimiter scanner. Verifies that the two files we touched
(main.dart, movie_card.dart) still have balanced braces / parens /
brackets AFTER our edits.

Same scanning strategy used in Task 33/36/37 syntax checks:
- skips string literals (single quote, double quote, triple-quoted)
- skips // line comments and /* */ block comments
- tracks nesting depth for {} () []
- a file is OK if, at EOF, all three depths are zero
"""

import sys
from pathlib import Path

FILES = [
    "/home/z/my-project/lib/main.dart",
    "/home/z/my-project/lib/app/ui/components/movie_card.dart",
]


def scan(path: Path) -> tuple[bool, str]:
    src = path.read_text(encoding="utf-8")
    i = 0
    n = len(src)
    depth_brace = 0   # { }
    depth_paren = 0   # ( )
    depth_bracket = 0 # [ ]
    line = 1

    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""

        # newline tracking
        if c == "\n":
            line += 1
            i += 1
            continue

        # line comment
        if c == "/" and nxt == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue

        # block comment
        if c == "/" and nxt == "*":
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                if src[i] == "\n":
                    line += 1
                i += 1
            i += 2  # skip the closing */
            continue

        # triple-quoted string (""" or ''')
        if (c == '"' and nxt == '"' and i + 2 < n and src[i + 2] == '"') or \
           (c == "'" and nxt == "'" and i + 2 < n and src[i + 2] == "'"):
            quote = c * 3
            i += 3
            while i < n:
                if src[i] == "\n":
                    line += 1
                if src[i:i + 3] == quote:
                    i += 3
                    break
                i += 1
            continue

        # single/double-quoted string (with escape handling)
        if c == '"' or c == "'":
            quote = c
            i += 1
            while i < n:
                if src[i] == "\\" and i + 1 < n:
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                if src[i] == "\n":
                    line += 1
                i += 1
            continue

        # delimiters
        if c == "{":
            depth_brace += 1
        elif c == "}":
            depth_brace -= 1
        elif c == "(":
            depth_paren += 1
        elif c == ")":
            depth_paren -= 1
        elif c == "[":
            depth_bracket += 1
        elif c == "]":
            depth_bracket -= 1

        # early bail on negative depth (mismatched closer)
        if depth_brace < 0 or depth_paren < 0 or depth_bracket < 0:
            return False, f"line {line}: unmatched closer (brace={depth_brace}, paren={depth_paren}, bracket={depth_bracket})"

        i += 1

    ok = depth_brace == 0 and depth_paren == 0 and depth_bracket == 0
    msg = f"final depths: brace={depth_brace}, paren={depth_paren}, bracket={depth_bracket}"
    return ok, msg


def main() -> int:
    all_ok = True
    for f in FILES:
        path = Path(f)
        if not path.exists():
            print(f"MISSING: {f}")
            all_ok = False
            continue
        ok, msg = scan(path)
        status = "OK" if ok else "FAIL"
        print(f"{status}: {f}  ({msg})")
        if not ok:
            all_ok = False
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
