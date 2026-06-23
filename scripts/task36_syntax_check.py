#!/usr/bin/env python3
"""Task 36 syntax check — Dart-aware brace/paren/bracket scanner.

Checks the files modified in Task 36 #1 for balanced delimiters
and basic Dart sanity (no obvious orphaned braces, no unclosed
string literals across the modified regions).

This is NOT a full Dart parser — it is a quick sanity gate that
catches the most common edit mistakes (unbalanced delimiters,
half-deleted blocks, mis-pasted replacements) before the file is
handed off to Bro for the actual `flutter build` run.
"""

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent / "CM-APP"

FILES_TO_CHECK = [
    "lib/app/ui/home/home_screen.dart",
]

OPEN = "([{"
CLOSE = ")]}"
PAIR = {o: c for o, c in zip(OPEN, CLOSE)}
PAIR_REV = {c: o for o, c in zip(OPEN, CLOSE)}


def scan_file(path: Path) -> list[str]:
    """Scan one Dart file for delimiter balance and basic sanity.

    Returns a list of error messages (empty list = OK).
    Strategy:
      - Walk the file char by char, skipping string literals and
        comments so braces inside them don't count.
      - Track a stack of open delimiters.
      - On a close, verify it matches the top of the stack.
      - At EOF, the stack must be empty.
    """
    text = path.read_text(encoding="utf-8")
    errors: list[str] = []
    stack: list[tuple[str, int]] = []  # (delimiter, line_number)
    i = 0
    line = 1
    n = len(text)

    while i < n:
        c = text[i]

        # Track line numbers for error messages
        if c == "\n":
            line += 1
            i += 1
            continue

        # Line comment //  → skip to end of line
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue

        # Block comment /* ... */  → skip to closing */
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                if text[i] == "\n":
                    line += 1
                i += 1
            i += 2  # skip past */
            continue

        # String literal (single or double quote, no raw/concat handling)
        # We treat ' and " as string starts. Backslash escapes next char.
        # Triple-quoted strings (''' or """) span multiple lines.
        if c in ("'", '"'):
            # Check for triple-quote
            triple = text[i:i + 3]
            if text[i:i + 3] == "'''" or text[i:i + 3] == '"""':
                q = text[i:i + 3]
                i += 3
                # find closing triple
                while i + 2 < n and text[i:i + 3] != q:
                    if text[i] == "\n":
                        line += 1
                    i += 1
                i += 3  # skip past closing triple
                continue
            # Single-line string
            q = c
            i += 1
            while i < n and text[i] != q:
                if text[i] == "\\" and i + 1 < n:
                    i += 2
                    continue
                if text[i] == "\n":
                    # Unterminated single-line string — Dart treats this
                    # as an error, but our scanner just notes it and moves
                    # on so we don't lose the rest of the file.
                    errors.append(f"line {line}: unterminated string literal")
                    line += 1
                    break
                i += 1
            i += 1  # skip past closing quote
            continue

        # Delimiters
        if c in OPEN:
            stack.append((c, line))
            i += 1
            continue
        if c in CLOSE:
            if not stack:
                errors.append(f"line {line}: unexpected '{c}' (no matching open)")
                i += 1
                continue
            top, top_line = stack.pop()
            if PAIR_REV[c] != top:
                errors.append(
                    f"line {line}: mismatched '{c}' — expected "
                    f"'{PAIR[top]}' to close '{top}' opened at line {top_line}"
                )
                i += 1
                continue
            i += 1
            continue

        i += 1

    if stack:
        for delim, ln in stack:
            errors.append(f"line {ln}: unclosed '{delim}' (no matching close before EOF)")

    return errors


def main() -> int:
    any_error = False
    for rel in FILES_TO_CHECK:
        path = REPO_ROOT / rel
        if not path.exists():
            print(f"MISSING: {path}")
            any_error = True
            continue
        errors = scan_file(path)
        if errors:
            any_error = True
            print(f"FAIL: {rel}")
            for e in errors:
                print(f"  {e}")
        else:
            print(f"OK:   {rel}")
    return 1 if any_error else 0


if __name__ == "__main__":
    sys.exit(main())
