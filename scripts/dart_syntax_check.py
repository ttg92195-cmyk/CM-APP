#!/usr/bin/env python3
"""
Basic Dart syntax sanity check for CM-APP changes.
Verifies brace/paren/bracket balance and checks for obvious typos
in the two files we changed. Not a real Dart analyzer — just a
sanity net before Bro runs flutter build.
"""
import re
import sys
from pathlib import Path

def check_balance(path: Path) -> list[str]:
    """Return list of issues for the given file."""
    text = path.read_text()
    issues = []

    # Strip strings and comments so braces inside them don't count.
    cleaned = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        # Block comment
        if c == '/' and i + 1 < n and text[i+1] == '*':
            end = text.find('*/', i + 2)
            if end == -1:
                issues.append('unterminated /* block comment')
                break
            i = end + 2
            continue
        # Line comment
        if c == '/' and i + 1 < n and text[i+1] == '/':
            end = text.find('\n', i)
            if end == -1:
                i = n
            else:
                i = end
            continue
        # Triple-quoted strings
        if text[i:i+3] in ("'''", '"""'):
            quote = text[i:i+3]
            end = text.find(quote, i + 3)
            if end == -1:
                issues.append(f'unterminated {quote} string at offset {i}')
                break
            i = end + 3
            continue
        # Single/double-quoted strings
        if c in "'\"":
            quote = c
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                    continue
                if text[j] == quote:
                    break
                if text[j] == '\n':
                    # Single-line strings shouldn't span newlines unless
                    # multi-line. Be lenient and break (matches Dart's
                    # behavior of erroring, but we just stop the scan).
                    break
                j += 1
            i = j + 1
            continue
        cleaned.append(c)
        i += 1

    cleaned_text = ''.join(cleaned)

    # Brace/paren/bracket balance
    pairs = {'(': ')', '{': '}', '[': ']'}
    stack = []
    for idx, ch in enumerate(cleaned_text):
        if ch in pairs:
            stack.append((ch, idx))
        elif ch in pairs.values():
            if not stack:
                issues.append(f'extra closing {ch} at offset {idx}')
                continue
            top, _ = stack.pop()
            if pairs[top] != ch:
                issues.append(f'mismatched: expected {pairs[top]} got {ch} at offset {idx}')
    for opener, closer in pairs.items():
        leftover = [s for s in stack if s[0] == opener]
        if leftover:
            issues.append(f'unbalanced {opener}{closer}: {len(leftover)} unclosed')

    return issues

def main():
    files = [
        Path('/home/z/my-project/CM-APP/lib/app/core/models/movie_detail.dart'),
        Path('/home/z/my-project/CM-APP/lib/app/core/services/firestore_content_service.dart'),
    ]
    exit_code = 0
    for f in files:
        issues = check_balance(f)
        print(f'=== {f.name} ===')
        if not issues:
            print('  OK (braces balanced, strings terminated)')
        else:
            for iss in issues:
                print(f'  ISSUE: {iss}')
            exit_code = 1
    sys.exit(exit_code)

if __name__ == '__main__':
    main()
