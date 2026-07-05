#!/usr/bin/env python3
"""
Task 32-g: Localization parity-check unit test.

Verifies that assets/lang/en.json and assets/lang/my.json have identical
key sets (excluding the reserved `_meta` key) and that no value is empty.

Run before every commit that touches localization files:
    python3 scripts/task32_verify_translations.py

Exit code 0 = OK, non-zero = drift detected (CI should fail).

This script is the CI gate Bro asked for in the migration-risk concern
("App_config.dart မှာ Key 400 ကျော် ပြောင်းလိုက်တဲ့အခါ အရင်လို အလုပ်လုပ်မှာ
မဟုတ်ဘူးဆိုတာ သိချင်တယ် — Unit Test နဲ့ စစ်ပေးမယ်").
"""

import json
import sys
from pathlib import Path

EN = Path('/home/z/my-project/CM-APP/assets/lang/en.json')
MY = Path('/home/z/my-project/CM-APP/assets/lang/my.json')


def main():
    failures = []

    if not EN.exists():
        failures.append(f'Missing file: {EN}')
    if not MY.exists():
        failures.append(f'Missing file: {MY}')
    if failures:
        for f in failures:
            print(f'FAIL: {f}')
        sys.exit(1)

    en = json.loads(EN.read_text(encoding='utf-8'))
    my = json.loads(MY.read_text(encoding='utf-8'))

    # Strip reserved keys
    for k in ('_meta',):
        en.pop(k, None)
        my.pop(k, None)

    en_keys = set(en.keys())
    my_keys = set(my.keys())

    only_en = en_keys - my_keys
    only_my = my_keys - en_keys

    if only_en:
        failures.append(
            f'Keys only in en.json ({len(only_en)}): {sorted(only_en)[:10]}'
            + (' ...' if len(only_en) > 10 else '')
        )
    if only_my:
        failures.append(
            f'Keys only in my.json ({len(only_my)}): {sorted(only_my)[:10]}'
            + (' ...' if len(only_my) > 10 else '')
        )

    # Check for empty values (would cause silent fallback to key as-is)
    empty_en = [k for k, v in en.items() if not v or not str(v).strip()]
    empty_my = [k for k, v in my.items() if not v or not str(v).strip()]
    if empty_en:
        failures.append(f'Empty values in en.json: {empty_en}')
    if empty_my:
        failures.append(f'Empty values in my.json: {empty_my}')

    # Check _meta block exists with version (Task 32-f: versioning)
    en_full = json.loads(EN.read_text(encoding='utf-8'))
    my_full = json.loads(MY.read_text(encoding='utf-8'))
    for lang, data in [('en', en_full), ('my', my_full)]:
        meta = data.get('_meta')
        if not isinstance(meta, dict):
            failures.append(f'Missing _meta block in {lang}.json')
        else:
            if not meta.get('version'):
                failures.append(f'_meta.version missing in {lang}.json')
            if not meta.get('lastUpdated'):
                failures.append(f'_meta.lastUpdated missing in {lang}.json')

    if failures:
        print('FAIL: localization parity check failed.')
        for f in failures:
            print(f'  - {f}')
        sys.exit(1)

    print(f'OK: en.json ({len(en_keys)} keys) and my.json ({len(my_keys)} keys) '
          f'have identical key sets, no empty values, _meta blocks present.')


if __name__ == '__main__':
    main()
