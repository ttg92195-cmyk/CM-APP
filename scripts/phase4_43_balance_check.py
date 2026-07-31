#!/usr/bin/env python3
"""Phase 4.43 — Dart bracket balance checker for admin_panel_page.dart.

Properly strips:
- Line comments (//...)
- Block comments (/* ... */)
- Single-quoted strings (with escape handling)
- Double-quoted strings (with escape handling)
- Raw strings (r'...' and r"...")
- String interpolation is NOT handled (would require a Dart lexer), but
  brackets inside ${} are rare in this file so this is good enough for
  a sanity check.
"""
import sys
from pathlib import Path

def check_balance(path: Path) -> int:
    src = path.read_text()
    i = 0
    n = len(src)
    stack = []
    errors = []
    line = 1

    while i < n:
        c = src[i]

        # Track newlines for error reporting
        if c == '\n':
            line += 1
            i += 1
            continue

        # Line comment
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue

        # Block comment
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            i += 2
            while i + 1 < n and not (src[i] == '*' and src[i + 1] == '/'):
                if src[i] == '\n':
                    line += 1
                i += 1
            i += 2  # skip closing */
            continue

        # Raw string
        if c == 'r' and i + 1 < n and src[i + 1] in ("'", '"'):
            quote = src[i + 1]
            i += 2
            while i < n and src[i] != quote:
                if src[i] == '\n':
                    line += 1
                i += 1
            i += 1  # skip closing quote
            continue

        # Regular string
        if c in ("'", '"'):
            quote = c
            i += 1
            while i < n:
                if src[i] == '\\' and i + 1 < n:
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                if src[i] == '\n':
                    line += 1
                i += 1
            continue

        # Brackets
        if c in '({[':
            stack.append((c, line))
        elif c in ')}]':
            if not stack:
                errors.append(f'Line {line}: unexpected closer {c!r}')
            else:
                opener, opener_line = stack.pop()
                pairs = {'(': ')', '{': '}', '[': ']'}
                if pairs[opener] != c:
                    errors.append(
                        f'Line {line}: mismatched — opened {opener!r} '
                        f'at line {opener_line}, closed with {c!r}'
                    )
        i += 1

    if stack:
        for opener, opener_line in stack:
            errors.append(f'Line {opener_line}: unclosed {opener!r}')

    if errors:
        print(f'FAIL — {len(errors)} error(s) in {path}:')
        for e in errors[:30]:
            print(f'  {e}')
        return 1

    # Report counts
    counts = {'(': 0, '{': 0, '[': 0}
    for ch in src:
        if ch in counts:
            counts[ch] += 1
    closers = {')': src.count(')'), '}': src.count('}'), ']': src.count(']')}
    print(f'OK — balanced. openers={counts} closers={closers}')
    return 0


if __name__ == '__main__':
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        '/home/z/my-project/lib/app/ui/screens/admin_panel_page.dart'
    )
    sys.exit(check_balance(target))
