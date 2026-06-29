#!/usr/bin/env python3
"""
Phase 3.10 — Dart syntax sanity check for app_config.dart.
Checks for balanced braces, brackets, and parentheses.
"""

import sys
from pathlib import Path

APP_CONFIG = Path("/home/z/my-project/cm-app/lib/more_libs/setting/app_config.dart")

def main():
    src = APP_CONFIG.read_text(encoding='utf-8')

    # Strip strings and comments to avoid false positives
    # (simplified — just count raw braces; Dart syntax is close enough)
    # Remove single-line comments
    cleaned = []
    in_string = False
    string_char = None
    in_line_comment = False
    in_block_comment = False
    i = 0
    while i < len(src):
        c = src[i]
        nxt = src[i+1] if i+1 < len(src) else ''

        if in_line_comment:
            if c == '\n':
                in_line_comment = False
                cleaned.append(c)
            i += 1
            continue

        if in_block_comment:
            if c == '*' and nxt == '/':
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue

        if in_string:
            if c == '\\':
                cleaned.append(c)
                cleaned.append(nxt)
                i += 2
                continue
            if c == string_char:
                in_string = False
                cleaned.append(c)
                i += 1
                continue
            cleaned.append(c)
            i += 1
            continue

        if c == '/' and nxt == '/':
            in_line_comment = True
            i += 2
            continue

        if c == '/' and nxt == '*':
            in_block_comment = True
            i += 2
            continue

        if c in ('"', "'"):
            in_string = True
            string_char = c
            cleaned.append(c)
            i += 1
            continue

        cleaned.append(c)
        i += 1

    cleaned_src = ''.join(cleaned)

    # Count braces
    opens = {'{': 0, '[': 0, '(': 0}
    closes = {'}': 0, ']': 0, ')': 0}
    for c in cleaned_src:
        if c in opens:
            opens[c] += 1
        if c in closes:
            closes[c] += 1

    print("Brace counts (opens / closes):")
    print(f"  {{ }} : {opens['{']} / {closes['}']}")
    print(f"  [ ] : {opens['[']} / {closes[']']}")
    print(f"  ( ) : {opens['(']} / {closes[')']}")

    failures = []
    if opens['{'] != closes['}']:
        failures.append(f"Unbalanced {{ }}: {opens['{']} opens vs {closes['}']} closes")
    if opens['['] != closes[']']:
        failures.append(f"Unbalanced [ ]: {opens['[']} opens vs {closes[']']} closes")
    if opens['('] != closes[')']:
        failures.append(f"Unbalanced ( ): {opens['(']} opens vs {closes[')']} closes")

    if failures:
        print("\nFAIL:")
        for f in failures:
            print(f"  {f}")
        sys.exit(1)
    else:
        print("\nALL BALANCED")
        sys.exit(0)

if __name__ == '__main__':
    main()
