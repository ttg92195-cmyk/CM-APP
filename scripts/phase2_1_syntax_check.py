#!/usr/bin/env python3
"""
Quick syntax + structure check for Phase 2.1 rules changes.
Checks:
  - Brace balance for both rules files
  - isVerifiedApp() helper is defined in both files
  - Every allow statement in firestore.rules has isVerifiedApp() in its condition
    (except users/{userId} list — special case for login flow)
  - Every allow statement in storage.rules has isVerifiedApp() in its condition
    (except the catch-all deny which uses 'if false')
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FS_RULES = ROOT / "firestore.rules"
ST_RULES = ROOT / "storage.rules"

errors = 0


def check_brace_balance(path):
    """Check that braces are balanced, ignoring strings and comments."""
    src = path.read_text(encoding="utf-8")
    depth = 0
    in_line_comment = False
    in_block_comment = False
    in_str = None
    line = 1
    i = 0
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
        if c == '/' and nxt == '/':
            in_line_comment = True
            i += 2
            continue
        if c == '/' and nxt == '*':
            in_block_comment = True
            i += 2
            continue
        if src[i:i + 3] in ("'''", '"""'):
            in_str = src[i:i + 3]
            i += 3
            continue
        if c in ("'", '"'):
            in_str = c
            i += 1
            continue
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth < 0:
                print(f"FAIL {path.name}: unmatched }} at line {line}")
                return False
        i += 1
    if depth != 0:
        print(f"FAIL {path.name}: brace imbalance (final depth = {depth})")
        return False
    print(f"OK {path.name}: brace balance OK")
    return True


def check_helper_defined(path, helper_name):
    src = path.read_text(encoding="utf-8")
    if f"function {helper_name}()" not in src:
        print(f"FAIL {path.name}: helper '{helper_name}' is not defined")
        return False
    print(f"OK {path.name}: helper '{helper_name}' defined")
    return True


def check_allow_verified(path, exceptions=None):
    """Every 'allow' statement must include 'isVerifiedApp()' unless it's in
    exceptions (a list of substrings). An allow statement may span multiple
    lines, ending with a semicolon."""
    exceptions = exceptions or []
    src = path.read_text(encoding="utf-8")

    # Tokenize: strip block comments first, then walk line-by-line
    # to extract allow statements (terminated by ';').
    out_lines = []
    in_block_comment = False
    for line in src.splitlines():
        s = line
        # crude block-comment stripping per line
        if in_block_comment:
            if '*/' in s:
                in_block_comment = False
                s = s.split('*/', 1)[1]
            else:
                continue
        if '/*' in s and '*/' not in s:
            in_block_comment = True
            s = s.split('/*', 1)[0]
        # strip line comments (only outside strings — accept some imprecision)
        # find '//' that is not inside a string — heuristic: ignore if inside quotes
        # Simple approach: find first '//' that is not preceded by an odd number of ' or "
        # For our purposes, a simpler heuristic: only strip '//' that comes after
        # stripping leading whitespace, AND the line doesn't start with '//' (already
        # filtered above). Strip from the first '//' that is not inside quotes.
        # Easiest: walk char-by-char tracking quote state.
        out_chars = []
        in_str = None
        i = 0
        while i < len(s):
            c = s[i]
            nxt = s[i + 1] if i + 1 < len(s) else ''
            if in_str is not None:
                if c == '\\' and in_str in ("'", '"'):
                    out_chars.append(s[i:i + 2])
                    i += 2
                    continue
                if c == in_str:
                    in_str = None
                out_chars.append(c)
                i += 1
                continue
            if c == '/' and nxt == '/':
                break  # rest of line is a comment
            if c in ("'", '"'):
                in_str = c
            out_chars.append(c)
            i += 1
        out_lines.append(''.join(out_chars))

    text = '\n'.join(out_lines)
    # Now find allow statements terminated by ';'
    statements = []
    buf = []
    for line in text.splitlines():
        if buf or line.lstrip().startswith('allow '):
            buf.append(line)
            if ';' in line:
                statements.append('\n'.join(buf))
                buf = []
    if buf:
        statements.append('\n'.join(buf))

    failures = []
    for stmt in statements:
        one_line = ' '.join(s.strip() for s in stmt.splitlines())
        if any(ex in one_line for ex in exceptions):
            continue
        if 'isVerifiedApp()' not in one_line:
            # extract first line number for reporting
            first = stmt.splitlines()[0]
            failures.append(one_line[:160])
    if failures:
        for txt in failures:
            print(f"FAIL {path.name}: missing isVerifiedApp() in: {txt}")
        return False
    print(f"OK {path.name}: all allow rules have isVerifiedApp() check ({len(statements)} rules)")
    return True


print("=" * 60)
print("Phase 2.1 — App Check Enforcement Syntax Check")
print("=" * 60)

if not check_brace_balance(FS_RULES):
    errors += 1
if not check_brace_balance(ST_RULES):
    errors += 1

if not check_helper_defined(FS_RULES, "isVerifiedApp"):
    errors += 1
if not check_helper_defined(ST_RULES, "isVerifiedApp"):
    errors += 1

# firestore.rules: exception for the public list on users/{userId}
# (login flow runs pre-auth so App Check token may not be attached)
if not check_allow_verified(FS_RULES, exceptions=["allow list: if true;"]):
    errors += 1

# storage.rules: exception for the catch-all deny rule
if not check_allow_verified(ST_RULES, exceptions=["allow read, write: if false;"]):
    errors += 1

print()
print(f"Summary: {errors} errors")
sys.exit(1 if errors > 0 else 0)
