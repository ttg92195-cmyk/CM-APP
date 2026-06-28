#!/usr/bin/env python3
"""
Quick Dart syntax sanity check for Task 43.1 modified files.
Checks:
  - Brace/paren/bracket balance
  - No leftover references to removed identifiers
  - All imports look reasonable
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [
    ROOT / "lib/app/ui/screens/admin_notification_page.dart",
    ROOT / "lib/app/core/services/fcm_notification_service.dart",
]

# Identifiers that should NO LONGER appear after Task 43.1
FORBIDDEN = [
    "sendNotificationToAll",
    "_oneSignalRestApiKey",
    "ONE_SIGNAL_REST_API_KEY",
    "restApiKey",
    "DioException",
    "import 'package:dio/dio.dart'",
    "Dio(",
]

errors = 0
warnings = 0

for f in FILES:
    if not f.exists():
        print(f"FAIL: file missing: {f}")
        errors += 1
        continue
    src = f.read_text(encoding="utf-8")
    rel = f.relative_to(ROOT)

    # 1. Brace balance (single-pass tokenizer to ignore // and /* */ and strings)
    depth_brace = 0
    depth_paren = 0
    depth_bracket = 0
    i = 0
    line = 1
    in_line_comment = False
    in_block_comment = False
    in_str = None  # ' or " or '''
    line_at_depth_zero = 1
    bad = False
    while i < len(src):
        c = src[i]
        nxt = src[i + 1] if i + 1 < len(src) else ''
        if c == '\n':
            line += 1
            in_line_comment = False
            i += 1
            continue
        if in_line_comment:
            i += 1
            continue
        if in_block_comment:
            if c == '*' and nxt == '/':
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue
        if in_str is not None:
            if c == '\\' and in_str in ("'", '"'):
                # escape next char
                i += 2
                continue
            # Check for triple-quote close
            if in_str == "'''" or in_str == '"""':
                triple = src[i:i + 3]
                if triple == in_str:
                    in_str = None
                    i += 3
                    continue
            elif c == in_str:
                in_str = None
                i += 1
                continue
            i += 1
            continue
        # not in string/comment
        if c == '/' and nxt == '/':
            in_line_comment = True
            i += 2
            continue
        if c == '/' and nxt == '*':
            in_block_comment = True
            i += 2
            continue
        # check for triple-quoted string start
        if src[i:i + 3] in ("'''", '"""'):
            in_str = src[i:i + 3]
            i += 3
            continue
        if c in ("'", '"'):
            in_str = c
            i += 1
            continue
        if c == '{':
            depth_brace += 1
        elif c == '}':
            depth_brace -= 1
            if depth_brace < 0:
                print(f"FAIL {rel}: unmatched }} at line {line}")
                bad = True
                break
        elif c == '(':
            depth_paren += 1
        elif c == ')':
            depth_paren -= 1
            if depth_paren < 0:
                print(f"FAIL {rel}: unmatched ) at line {line}")
                bad = True
                break
        elif c == '[':
            depth_bracket += 1
        elif c == ']':
            depth_bracket -= 1
            if depth_bracket < 0:
                print(f"FAIL {rel}: unmatched ] at line {line}")
                bad = True
                break
        i += 1

    if bad:
        errors += 1
        continue

    if in_str is not None:
        print(f"FAIL {rel}: unterminated string starting at end of file")
        errors += 1
    if in_block_comment:
        print(f"FAIL {rel}: unterminated block comment")
        errors += 1
    if depth_brace != 0:
        print(f"FAIL {rel}: brace imbalance (final depth = {depth_brace})")
        errors += 1
    if depth_paren != 0:
        print(f"FAIL {rel}: paren imbalance (final depth = {depth_paren})")
        errors += 1
    if depth_bracket != 0:
        print(f"FAIL {rel}: bracket imbalance (final depth = {depth_bracket})")
        errors += 1

    if errors == 0:
        print(f"OK {rel}: brace/paren/bracket balance OK")

    # 2. Forbidden identifier scan (whole-line, so we don't false-positive on substrings in comments)
    for i, line_text in enumerate(src.splitlines(), 1):
        stripped = line_text.lstrip()
        if stripped.startswith('//') or stripped.startswith('*'):
            continue
        for token in FORBIDDEN:
            # whole-word-ish check
            if token in line_text:
                # but skip lines that are clearly comments about the removal
                if 'Task 43.1' in line_text or 'removed' in line_text.lower() or 'intentionally' in line_text.lower():
                    continue
                # skip .env.example note (not in these files anyway)
                print(f"WARN {rel}:{i}: forbidden token '{token}' in line: {line_text.strip()[:120]}")
                warnings += 1

print(f"\nSummary: {errors} errors, {warnings} warnings")
sys.exit(1 if errors > 0 else 0)
