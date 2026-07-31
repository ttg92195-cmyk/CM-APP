#!/usr/bin/env python3
"""
Dart-aware brace/paren/bracket balance checker.
Properly handles:
- Single-line strings: "..." and '...'
- Raw strings: r"..." and r'...'
- Multi-line strings: \"\"\"...\"\"\" and '''...'''
- String interpolation: "value: $x" and "value: ${expr}"
- Line comments: //
- Block comments: / * ... * /
"""
import sys
from pathlib import Path

def check_balance(text):
    """Returns dict with imbalance counts for (), {}, []."""
    i = 0
    n = len(text)
    # Stack of (kind, line) for unmatched openers
    # We just count diffs since string interpolation makes {} matching tricky.
    counts = {'(': 0, '{': 0, '[': 0}
    # Track whether we're inside a string/comment to handle interpolation {} correctly
    line = 1
    while i < n:
        c = text[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        # Line comment
        if c == '/' and i + 1 < n and text[i+1] == '/':
            # Skip to end of line
            while i < n and text[i] != '\n':
                i += 1
            continue
        # Block comment
        if c == '/' and i + 1 < n and text[i+1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i+1] == '/'):
                if text[i] == '\n':
                    line += 1
                i += 1
            i += 2
            continue
        # Triple-quoted string
        if i + 2 < n and text[i:i+3] in ('"""', "'''"):
            quote = text[i:i+3]
            i += 3
            while i + 2 < n and text[i:i+3] != quote:
                if text[i] == '\n':
                    line += 1
                i += 1
            i += 3
            continue
        # Raw string r"..." or r'...'
        if c == 'r' and i + 1 < n and text[i+1] in ('"', "'"):
            quote = text[i+1]
            i += 2
            while i < n and text[i] != quote:
                if text[i] == '\n':
                    line += 1
                i += 1
            i += 1
            continue
        # Single-line string "..." or '...'
        if c in ('"', "'"):
            quote = c
            i += 1
            while i < n and text[i] != quote:
                if text[i] == '\\' and i + 1 < n:
                    i += 2  # skip escape
                    continue
                if text[i] == '\n':
                    # Single-line strings shouldn't span newlines, but Dart
                    # allows continuation in some cases. Just count and continue.
                    line += 1
                # Handle ${...} interpolation — track nested braces
                if text[i] == '$' and i + 1 < n and text[i+1] == '{':
                    # Find matching close brace, respecting nested strings
                    depth = 1
                    i += 2
                    while i < n and depth > 0:
                        if text[i] == '{':
                            depth += 1
                        elif text[i] == '}':
                            depth -= 1
                        elif text[i] in ('"', "'"):
                            # Nested string — skip it
                            q2 = text[i]
                            i += 1
                            while i < n and text[i] != q2:
                                if text[i] == '\\' and i + 1 < n:
                                    i += 2
                                    continue
                                i += 1
                        i += 1
                    continue
                i += 1
            i += 1
            continue
        # Plain openers/closers
        if c in '({[':
            counts[c] += 1
        elif c == ')':
            counts['('] -= 1
        elif c == '}':
            counts['{'] -= 1
        elif c == ']':
            counts['['] -= 1
        i += 1
    return counts

if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart")
    text = path.read_text()
    counts = check_balance(text)
    print(f"File: {path}")
    print(f"Size: {len(text)} chars, {text.count(chr(10))} lines")
    print()
    all_ok = True
    for k, v in counts.items():
        closer = {'(': ')', '{': '}', '[': ']'}[k]
        status = "OK" if v == 0 else ("EXTRA OPENERS" if v > 0 else "EXTRA CLOSERS")
        if v != 0:
            all_ok = False
        print(f"  {k}{closer}: diff = {v}  [{status}]")
    print()
    if all_ok:
        print("All balanced.")
        sys.exit(0)
    else:
        print("IMBALANCE detected!")
        sys.exit(1)
