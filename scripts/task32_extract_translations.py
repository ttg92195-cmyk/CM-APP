#!/usr/bin/env python3
"""
Task 32-a: Extract translation maps from app_config.dart → write to
assets/lang/en.json and assets/lang/my.json.

Strategy: parse the Dart source, find the en and my map literals (between
'return {' and the closing '};'), then parse them key-by-key.

The Dart map values use single quotes; some values contain escaped
newlines (\\n) and apostrophes (escaped as \\' or wrapped in double quotes).
We use a small tokenizer that handles:
  - 'single-quoted strings' with \\' escapes
  - "double-quoted strings" (used in dont_have_account)
  - escaped \\n inside strings
  - numeric/bool values (not present here, but handled defensively)

Output: writes /home/z/my-project/CM-APP/assets/lang/en.json and
        /home/z/my-project/CM-APP/assets/lang/my.json
        with sorted keys, 2-space indent, ensure_ascii=False.
"""

import json
import re
import sys
from pathlib import Path

SRC = Path('/home/z/my-project/CM-APP/lib/more_libs/setting/app_config.dart')
OUT_EN = Path('/home/z/my-project/CM-APP/assets/lang/en.json')
OUT_MY = Path('/home/z/my-project/CM-APP/assets/lang/my.json')


def parse_string_literal(s, start):
    """
    Parse a Dart string literal starting at index `start` in `s`.
    `s[start]` is either ' or ".

    Returns (value, end_index) where end_index is one past the closing quote.
    Handles \\' and \\" escapes plus \\n, \\t, \\\\, etc.
    """
    quote = s[start]
    i = start + 1
    out = []
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt == 'n':
                out.append('\n')
            elif nxt == 't':
                out.append('\t')
            elif nxt == 'r':
                out.append('\r')
            elif nxt == '\\':
                out.append('\\')
            elif nxt == "'":
                out.append("'")
            elif nxt == '"':
                out.append('"')
            else:
                # Unknown escape — keep as-is
                out.append('\\')
                out.append(nxt)
            i += 2
            continue
        if c == quote:
            return ''.join(out), i + 1
        out.append(c)
        i += 1
    raise ValueError('Unterminated string literal at index %d' % start)


def parse_map(text, start):
    """
    Parse a Dart map literal starting at `start` (which must be '{').
    Returns (dict, end_index) where end_index is one past the closing '}'.
    """
    assert text[start] == '{', 'parse_map: expected { at start, got %r' % text[start]
    i = start + 1
    result = {}
    n = len(text)
    while i < n:
        # Skip whitespace and commas
        while i < n and text[i] in ' \t\r\n,':
            i += 1
        if i >= n:
            raise ValueError('Unexpected end of input inside map')
        if text[i] == '}':
            return result, i + 1
        # Expect a string key
        if text[i] not in ('"', "'"):
            raise ValueError('Expected string key at index %d, got %r' % (i, text[i]))
        key, i = parse_string_literal(text, i)
        # Skip whitespace
        while i < n and text[i] in ' \t\r\n':
            i += 1
        # Expect ':'
        if i >= n or text[i] != ':':
            raise ValueError('Expected ":" after key %r at index %d' % (key, i))
        i += 1
        # Skip whitespace
        while i < n and text[i] in ' \t\r\n':
            i += 1
        # Expect a string value
        if text[i] not in ('"', "'"):
            raise ValueError('Expected string value at index %d, got %r' % (i, text[i]))
        value, i = parse_string_literal(text, i)
        # Dart map literal: later keys override earlier — mirror that
        result[key] = value
    raise ValueError('Unterminated map literal')


def find_map_for_lang(text, lang_code):
    """
    Find the return {...}; block for the given language code.

    The code pattern is:
        if (code == 'en') {
          return { ... };
        }
        return { ... };  <-- this is the default (Myanmar)

    So for 'en' we look for "if (code == 'en') {" then 'return {'.
    For 'my' we look for the LAST 'return {' in the function.
    """
    if lang_code == 'en':
        m = re.search(r"if \(code == 'en'\)\s*\{", text)
        if not m:
            raise ValueError("Couldn't find 'en' branch in _getDefaultTranslations")
        # Find 'return' after that point
        after = text[m.end():]
        r = re.search(r'return\s*\{', after)
        if not r:
            raise ValueError("Couldn't find 'return {' in en branch")
        start_in_after = r.end() - 1  # index of '{'
        return m.end() + start_in_after
    else:  # myanmar (default branch)
        # Find all 'return {' positions, take the last one
        positions = [m.end() - 1 for m in re.finditer(r'return\s*\{', text)]
        if len(positions) < 2:
            raise ValueError('Expected at least 2 return statements; got %d' % len(positions))
        return positions[-1]


def main():
    text = SRC.read_text(encoding='utf-8')
    print('Source file: %d bytes' % len(text))

    # Parse EN
    en_start = find_map_for_lang(text, 'en')
    en_map, en_end = parse_map(text, en_start)
    print('EN: %d keys (after dedup)' % len(en_map))

    # Parse MY
    my_start = find_map_for_lang(text, 'my')
    my_map, my_end = parse_map(text, my_start)
    print('MY: %d keys (after dedup)' % len(my_map))

    # Compare key sets — flag any mismatch
    en_keys = set(en_map.keys())
    my_keys = set(my_map.keys())
    only_en = en_keys - my_keys
    only_my = my_keys - en_keys
    if only_en:
        print('WARNING: keys only in EN: %s' % sorted(only_en))
    if only_my:
        print('WARNING: keys only in MY: %s' % sorted(only_my))
    if not only_en and not only_my:
        print('OK: EN and MY key sets are identical.')

    # Add _meta block (Bro's versioning concern)
    en_out = {
        '_meta': {
            'language': 'en',
            'version': '1.0.0',
            'lastUpdated': '2026-06-22',
            'source': 'extracted from app_config.dart::_getDefaultTranslations',
        },
        **en_map,
    }
    my_out = {
        '_meta': {
            'language': 'my',
            'version': '1.0.0',
            'lastUpdated': '2026-06-22',
            'source': 'extracted from app_config.dart::_getDefaultTranslations',
        },
        **my_map,
    }

    # Write with sorted keys + 2-space indent + unicode preserved
    OUT_EN.parent.mkdir(parents=True, exist_ok=True)
    OUT_EN.write_text(
        json.dumps(en_out, indent=2, ensure_ascii=False, sort_keys=True) + '\n',
        encoding='utf-8',
    )
    OUT_MY.write_text(
        json.dumps(my_out, indent=2, ensure_ascii=False, sort_keys=True) + '\n',
        encoding='utf-8',
    )
    print('Wrote: %s (%d bytes)' % (OUT_EN, OUT_EN.stat().st_size))
    print('Wrote: %s (%d bytes)' % (OUT_MY, OUT_MY.stat().st_size))

    # Sanity: verify JSON parses back
    json.loads(OUT_EN.read_text(encoding='utf-8'))
    json.loads(OUT_MY.read_text(encoding='utf-8'))
    print('Sanity check OK.')


if __name__ == '__main__':
    main()
