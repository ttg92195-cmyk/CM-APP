#!/usr/bin/env python3
"""
Task 33 syntax sanity check (Dart-aware).

Verifies brace/paren/bracket balance for all Dart files modified in this
task, plus basic import/export sanity. We don't have Flutter SDK locally
(Bro's CI does the build), so this is a structural smoke test only.

This script uses a character-level scanner that properly handles:
  - // line comments
  - /* */ block comments
  - single-quoted strings '...'
  - double-quoted strings "..."
  - escape sequences \\.
  - raw strings r'...' and r"..." (no escape processing)
  - string interpolation ${...} (braces inside strings are not counted)

Usage:
    python3 task33_syntax_check.py
"""
import sys
from pathlib import Path

CM_APP = Path('/home/z/my-project/CM-APP')

FILES_TO_CHECK = [
    'lib/app/ui/components/safe_text.dart',
    'lib/app/core/services/debug_overflow_detector.dart',
    'lib/app/ui/home/trending_movie_component.dart',
    'lib/app/ui/screens/movie_detail_screen.dart',
    'lib/main.dart',
]


def scan_dart_balance(src: str) -> dict:
    """Scan Dart source code character-by-character, skipping strings
    and comments, and track brace/paren/bracket balance.

    Returns dict with:
      'braces_open', 'braces_close', 'braces_balanced' (bool)
      'parens_open', 'parens_close', 'parens_balanced' (bool)
      'brackets_open', 'brackets_close', 'brackets_balanced' (bool)
      'issues': list of (line_num, message) tuples for negative-depth
    """
    bo = bc = po = pc = ko = kc = 0
    brace_depth = paren_depth = bracket_depth = 0
    issues = []

    in_string = False
    string_quote = None
    raw_string = False  # r'...' or r"..." — no escape processing
    i = 0
    while i < len(src):
        c = src[i]
        nxt = src[i+1] if i+1 < len(src) else ''
        line = src[:i].count('\n') + 1

        if in_string:
            if not raw_string and c == '\\':
                i += 2
                continue
            if c == string_quote:
                in_string = False
                string_quote = None
                raw_string = False
                i += 1
                continue
            i += 1
            continue

        # Not in string
        if c == '/' and nxt == '/':
            while i < len(src) and src[i] != '\n':
                i += 1
            continue
        if c == '/' and nxt == '*':
            i += 2
            while i < len(src)-1 and not (src[i] == '*' and src[i+1] == '/'):
                i += 1
            i += 2
            continue
        if c == 'r' and (nxt == "'" or nxt == '"'):
            raw_string = True
            in_string = True
            string_quote = nxt
            i += 2
            continue
        if c == "'" or c == '"':
            in_string = True
            string_quote = c
            raw_string = False
            i += 1
            continue

        if c == '{':
            brace_depth += 1
            bo += 1
        elif c == '}':
            brace_depth -= 1
            bc += 1
            if brace_depth < 0:
                issues.append((line, 'extra } '))
                brace_depth = 0
        elif c == '(':
            paren_depth += 1
            po += 1
        elif c == ')':
            paren_depth -= 1
            pc += 1
            if paren_depth < 0:
                issues.append((line, 'extra ) '))
                paren_depth = 0
        elif c == '[':
            bracket_depth += 1
            ko += 1
        elif c == ']':
            bracket_depth -= 1
            kc += 1
            if bracket_depth < 0:
                issues.append((line, 'extra ] '))
                bracket_depth = 0
        i += 1

    return {
        'braces_open': bo,
        'braces_close': bc,
        'braces_balanced': bo == bc and brace_depth == 0,
        'parens_open': po,
        'parens_close': pc,
        'parens_balanced': po == pc and paren_depth == 0,
        'brackets_open': ko,
        'brackets_close': kc,
        'brackets_balanced': ko == kc and bracket_depth == 0,
        'issues': issues,
    }


def check_imports(path: Path, expected_imports: list[str]) -> list[str]:
    """Verify expected imports/snippets appear in the file."""
    errors = []
    src = path.read_text(encoding='utf-8')
    for imp in expected_imports:
        if imp not in src:
            errors.append(f'  missing: {imp}')
    return errors


def main():
    print('=' * 60)
    print('Task 33 syntax sanity check (Dart-aware)')
    print('=' * 60)

    all_ok = True
    for rel in FILES_TO_CHECK:
        path = CM_APP / rel
        print(f'\n--- {rel} ---')
        if not path.exists():
            print('  FILE NOT FOUND')
            all_ok = False
            continue

        src = path.read_text(encoding='utf-8')
        result = scan_dart_balance(src)

        errors = []
        if not result['braces_balanced']:
            errors.append(
                f"  braces:  {result['braces_open']} open / "
                f"{result['braces_close']} close  MISMATCH"
            )
        if not result['parens_balanced']:
            errors.append(
                f"  parens:  {result['parens_open']} open / "
                f"{result['parens_close']} close  MISMATCH"
            )
        if not result['brackets_balanced']:
            errors.append(
                f"  brackets: {result['brackets_open']} open / "
                f"{result['brackets_close']} close  MISMATCH"
            )
        for line, msg in result['issues']:
            errors.append(f'  line {line}: {msg}')

        # File-specific checks
        if rel == 'lib/main.dart':
            errors += check_imports(path, [
                "import 'package:cm_movies/app/core/services/debug_overflow_detector.dart';",
                'scaffoldMessengerKey: scaffoldMessengerKey',
                'DebugOverflowDetector.instance.install(',
            ])
        elif rel == 'lib/app/ui/home/trending_movie_component.dart':
            errors += check_imports(path, [
                "import 'package:cm_movies/app/ui/components/safe_text.dart';",
                'SafeText(',
            ])
        elif rel == 'lib/app/ui/screens/movie_detail_screen.dart':
            errors += check_imports(path, [
                'maxLines: 1',
                'maxLines: 3',
            ])

        if errors:
            all_ok = False
            for e in errors:
                print(e)
        else:
            print(
                f"  braces {result['braces_open']}/{result['braces_close']}  "
                f"parens {result['parens_open']}/{result['parens_close']}  "
                f"brackets {result['brackets_open']}/{result['brackets_close']}  OK"
            )

    print('\n' + '=' * 60)
    if all_ok:
        print('ALL CHECKS PASSED')
        return 0
    else:
        print('FAILURES DETECTED - see above')
        return 1


if __name__ == '__main__':
    sys.exit(main())
