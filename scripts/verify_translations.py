#!/usr/bin/env python3
"""
verify_translations.py — Task 34 (Phase 3: CI/CD Translation Parity Check)

Verifies that the app's translation files (`assets/lang/en.json` and
`assets/lang/my.json`) are structurally valid and translationally
equivalent. Run locally before pushing translation changes, and
automatically on every PR via `.github/workflows/translations-check.yml`.

Checks performed (any failure exits non-zero, failing CI):

  1. Both `assets/lang/en.json` and `assets/lang/my.json` exist and
     are valid JSON.
  2. Each file has a `_meta` block with the required fields:
     `language`, `version`, `lastUpdated`, `source`.
  3. The key sets of both files are IDENTICAL (excluding `_meta`).
     - Missing keys in either direction are reported.
  4. No translation value is empty (`""`).
     - Empty values cause the UI to render an empty string in that
       language, which is almost always a missed-edit mistake during
       translation, never intentional.
  5. Placeholders (`{name}`) in the English source must appear in
     the Myanmar translation (and vice versa). Mismatched placeholders
     cause runtime crashes when `LocalizationService.translate()` tries
     to substitute a value that isn't there.

Exit codes:
  0 = all checks passed
  1 = one or more checks failed (CI blocks the PR)

Usage:
  python3 scripts/verify_translations.py
  python3 scripts/verify_translations.py --strict   # also warn on long translations
  python3 scripts/verify_translations.py --quiet    # suppress OK output
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# Resolve repo root as the parent of the scripts/ directory.
REPO_ROOT = Path(__file__).resolve().parent.parent
EN_PATH = REPO_ROOT / 'assets' / 'lang' / 'en.json'
MY_PATH = REPO_ROOT / 'assets' / 'lang' / 'my.json'

REQUIRED_META_FIELDS = ['language', 'version', 'lastUpdated', 'source']
RESERVED_KEYS = {'_meta'}

# Placeholder pattern: {name} where name is 1+ word chars (letters, digits, underscore).
PLACEHOLDER_RE = re.compile(r'\{(\w+)\}')


class CheckResult:
    """Accumulates errors and warnings during a verification run."""

    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    @property
    def ok(self) -> bool:
        return not self.errors

    def merge(self, other: 'CheckResult') -> None:
        self.errors.extend(other.errors)
        self.warnings.extend(other.warnings)


def load_json(path: Path, result: CheckResult) -> dict | None:
    """Load a JSON file, returning None and recording an error on failure."""
    try:
        with path.open(encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        result.error(f'{path.relative_to(REPO_ROOT)}: file not found')
        return None
    except json.JSONDecodeError as e:
        result.error(f'{path.relative_to(REPO_ROOT)}: invalid JSON at line {e.lineno} col {e.colno}: {e.msg}')
        return None
    if not isinstance(data, dict):
        result.error(f'{path.relative_to(REPO_ROOT)}: top-level JSON must be an object, got {type(data).__name__}')
        return None
    return data


def check_meta_block(data: dict, lang_code: str, path: Path, result: CheckResult) -> None:
    """Verify the _meta block has all required fields with correct types."""
    rel = path.relative_to(REPO_ROOT)
    meta = data.get('_meta')
    if meta is None:
        result.error(f'{rel}: missing _meta block')
        return
    if not isinstance(meta, dict):
        result.error(f'{rel}: _meta must be an object, got {type(meta).__name__}')
        return
    for field in REQUIRED_META_FIELDS:
        if field not in meta:
            result.error(f'{rel}: _meta missing required field "{field}"')
            continue
        val = meta[field]
        if not isinstance(val, str) or not val.strip():
            result.error(f'{rel}: _meta.{field} must be a non-empty string, got {val!r}')
    # Cross-check: _meta.language should match the filename.
    if isinstance(meta.get('language'), str) and meta['language'] != lang_code:
        result.error(
            f'{rel}: _meta.language="{meta["language"]}" does not match filename '
            f'(expected "{lang_code}")'
        )


def extract_placeholders(value: str) -> set[str]:
    """Extract the set of {name} placeholders from a translation string."""
    return set(PLACEHOLDER_RE.findall(value))


def check_key_parity(
    en_data: dict,
    my_data: dict,
    en_path: Path,
    my_path: Path,
    result: CheckResult,
) -> tuple[set[str], set[str]]:
    """Verify both files have the same set of translation keys (excluding _meta).

    Returns the canonical key set (intersection of both files' keys minus
    reserved keys) for downstream checks.
    """
    en_rel = en_path.relative_to(REPO_ROOT)
    my_rel = my_path.relative_to(REPO_ROOT)

    en_keys = set(en_data.keys()) - RESERVED_KEYS
    my_keys = set(my_data.keys()) - RESERVED_KEYS

    missing_in_my = en_keys - my_keys
    missing_in_en = my_keys - en_keys

    if missing_in_my:
        sorted_missing = sorted(missing_in_my)
        result.error(
            f'{my_rel}: missing {len(sorted_missing)} key(s) present in {en_rel}:\n'
            + '\n'.join(f'    - {k}' for k in sorted_missing[:20])
            + (f'\n    ... and {len(sorted_missing) - 20} more' if len(sorted_missing) > 20 else '')
        )

    if missing_in_en:
        sorted_missing = sorted(missing_in_en)
        result.error(
            f'{en_rel}: missing {len(sorted_missing)} key(s) present in {my_rel}:\n'
            + '\n'.join(f'    - {k}' for k in sorted_missing[:20])
            + (f'\n    ... and {len(sorted_missing) - 20} more' if len(sorted_missing) > 20 else '')
        )

    return en_keys & my_keys


def check_empty_values(data: dict, lang_code: str, path: Path, result: CheckResult) -> None:
    """Verify no translation value is an empty string."""
    rel = path.relative_to(REPO_ROOT)
    empty_keys = []
    for k, v in data.items():
        if k in RESERVED_KEYS:
            continue
        if v == '' or (isinstance(v, str) and v.strip() == ''):
            empty_keys.append(k)
    if empty_keys:
        result.error(
            f'{rel}: {len(empty_keys)} translation key(s) have empty values:\n'
            + '\n'.join(f'    - {k}' for k in sorted(empty_keys)[:20])
            + (f'\n    ... and {len(empty_keys) - 20} more' if len(empty_keys) > 20 else '')
        )


def check_placeholder_parity(
    en_data: dict,
    my_data: dict,
    shared_keys: set[str],
    en_path: Path,
    my_path: Path,
    result: CheckResult,
) -> None:
    """Verify {name} placeholders match between English and Myanmar translations.

    Mismatched placeholders cause runtime crashes when
    LocalizationService.translate() tries to substitute a value that
    isn't there in the active language's string.
    """
    en_rel = en_path.relative_to(REPO_ROOT)
    my_rel = my_path.relative_to(REPO_ROOT)

    mismatches = []
    for key in sorted(shared_keys):
        en_val = en_data[key]
        my_val = my_data[key]
        if not isinstance(en_val, str) or not isinstance(my_val, str):
            continue  # type errors caught elsewhere
        en_ph = extract_placeholders(en_val)
        my_ph = extract_placeholders(my_val)
        if en_ph != my_ph:
            missing_in_my = en_ph - my_ph
            missing_in_en = my_ph - en_ph
            detail = []
            if missing_in_my:
                detail.append(f'missing in MY: {sorted(missing_in_my)}')
            if missing_in_en:
                detail.append(f'missing in EN: {sorted(missing_in_en)}')
            mismatches.append((key, ' | '.join(detail)))

    if mismatches:
        msg_lines = [f'    - {k}: {detail}' for k, detail in mismatches[:20]]
        result.error(
            f'Placeholder mismatch between {en_rel} and {my_rel} '
            f'({len(mismatches)} key(s)):\n'
            + '\n'.join(msg_lines)
            + (f'\n    ... and {len(mismatches) - 20} more' if len(mismatches) > 20 else '')
        )


def check_value_types(data: dict, lang_code: str, path: Path, result: CheckResult) -> None:
    """Verify all non-_meta values are strings (JSON allows other types but
    our translator expects strings)."""
    rel = path.relative_to(REPO_ROOT)
    bad = []
    for k, v in data.items():
        if k in RESERVED_KEYS:
            continue
        if not isinstance(v, str):
            bad.append((k, type(v).__name__))
    if bad:
        result.error(
            f'{rel}: {len(bad)} translation value(s) are not strings:\n'
            + '\n'.join(f'    - {k}: {typ}' for k, typ in bad[:20])
            + (f'\n    ... and {len(bad) - 20} more' if len(bad) > 20 else '')
        )


def check_length_ratio(
    en_data: dict,
    my_data: dict,
    shared_keys: set[str],
    result: CheckResult,
    max_ratio: float = 3.0,
) -> None:
    """Warn (not error) if Myanmar translation is dramatically longer or
    shorter than English. Caught some real translation mistakes during
    Task 32 development. Not blocking by default."""
    for key in sorted(shared_keys):
        en_val = en_data[key]
        my_val = my_data[key]
        if not isinstance(en_val, str) or not isinstance(my_val, str):
            continue
        if len(en_val) == 0:
            continue
        ratio = len(my_val) / len(en_val)
        if ratio > max_ratio:
            result.warn(
                f'length ratio: "{key}" MY is {ratio:.1f}x longer than EN '
                f'({len(en_val)} → {len(my_val)} chars)'
            )
        elif ratio < 1.0 / max_ratio:
            result.warn(
                f'length ratio: "{key}" MY is {1.0/ratio:.1f}x shorter than EN '
                f'({len(en_val)} → {len(my_val)} chars) — possible truncated translation?'
            )


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Verify translation parity between en.json and my.json.',
    )
    parser.add_argument(
        '--strict',
        action='store_true',
        help='Also warn on suspicious length ratios (default: warnings off).',
    )
    parser.add_argument(
        '--quiet',
        action='store_true',
        help='Suppress OK output (only print errors/warnings).',
    )
    args = parser.parse_args()

    result = CheckResult()

    # Check 1: load both files
    if not args.quiet:
        print(f'Checking {EN_PATH.relative_to(REPO_ROOT)} and {MY_PATH.relative_to(REPO_ROOT)}...')
    en_data = load_json(EN_PATH, result)
    my_data = load_json(MY_PATH, result)
    if en_data is None or my_data is None:
        return _finish(result, args)

    # Check 2: _meta blocks
    check_meta_block(en_data, 'en', EN_PATH, result)
    check_meta_block(my_data, 'my', MY_PATH, result)

    # Check 3: value types are strings
    check_value_types(en_data, 'en', EN_PATH, result)
    check_value_types(my_data, 'my', MY_PATH, result)

    # Check 4: key parity (returns shared keys for downstream checks)
    shared_keys = check_key_parity(en_data, my_data, EN_PATH, MY_PATH, result)

    # Check 5: no empty values
    check_empty_values(en_data, 'en', EN_PATH, result)
    check_empty_values(my_data, 'my', MY_PATH, result)

    # Check 6: placeholder parity
    check_placeholder_parity(en_data, my_data, shared_keys, EN_PATH, MY_PATH, result)

    # Optional: length ratio warnings
    if args.strict:
        check_length_ratio(en_data, my_data, shared_keys, result)

    return _finish(result, args)


def _finish(result: CheckResult, args: argparse.Namespace) -> int:
    """Print accumulated errors/warnings and return exit code."""
    if result.warnings:
        print('\nWarnings:')
        for w in result.warnings:
            print(f'  ⚠️  {w}')

    if result.errors:
        print('\nErrors:')
        for e in result.errors:
            print(f'  ❌ {e}')
        print(f'\n{len(result.errors)} error(s), {len(result.warnings)} warning(s).')
        print('Translation parity check FAILED.')
        return 1

    if not args.quiet:
        print(f'\nAll checks passed. {len(result.warnings)} warning(s).')
        print('Translation parity check OK.')
    elif result.warnings:
        print(f'{len(result.warnings)} warning(s).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
