#!/usr/bin/env python3
"""
Task 38 Req 2 — TMDB Generator data completeness fix.

Dart-aware delimiter scanner. Verifies that the four files we touched
(tmdb_service.dart, movie_detail.dart, tmdb_generator_page.dart,
movie_detail_screen.dart, series_detail_screen.dart) still have
balanced braces / parens / brackets AFTER our edits.

Same scanning strategy used in Task 33/36/37/38-req1 syntax checks.
"""

import sys
from pathlib import Path

FILES = [
    "/home/z/my-project/lib/app/core/services/tmdb_service.dart",
    "/home/z/my-project/lib/app/core/models/movie_detail.dart",
    "/home/z/my-project/lib/app/ui/screens/tmdb_generator_page.dart",
    "/home/z/my-project/lib/app/ui/screens/movie_detail_screen.dart",
    "/home/z/my-project/lib/app/ui/screens/series_detail_screen.dart",
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
            i += 2
            continue

        # triple-quoted string
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

        # single/double-quoted string
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
