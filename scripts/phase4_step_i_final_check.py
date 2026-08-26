#!/usr/bin/env python3
"""Phase 4 Step I — Final verification for the Reels feature.

Checks (run against the CM-APP working tree, which equals origin/main code):
1. Bracket balance on all 6 Reels dart files (delegates to phase4_43_balance_check.py logic)
2. Translation parity: en.json vs my.json key sets
3. Bad pattern scan: the 5 known Flutter/Dart compile pitfalls from this project's history
4. Confirm no code files (lib/, assets/) differ from HEAD (only worklog.md + upload/ are dirty)
"""
import json
import re
import subprocess
import sys

APP = "/home/z/my-project/CM-APP"

REELS_FILES = [
    "lib/app/core/models/reel.dart",
    "lib/app/core/services/reels_service.dart",
    "lib/app/ui/screens/reels_page.dart",
    "lib/app/ui/screens/reels_video_player_screen.dart",
    "lib/app/ui/screens/admin_reels_tab.dart",
    "lib/app/ui/screens/reel_form_page.dart",
]

BAD_PATTERNS = [
    (r"Colors\.black0[0-9]", "Colors.black0X does not exist (use black12/black26/black45/black54/black87)"),
    (r"await\s+\w+\?\. currentState[^;]*\?\?\s*Future\.value", "Future<void> ?? Future.value() pattern (Dart 3.5 rejects)"),
    (r"const\s+Duration\.zero", "const Duration.zero is not const-constructible in this SDK"),
    (r"snap\.data\(\)\[", "snap.data()[] indexing on dynamic (cast to Map first)"),
    (r"(VideoColors|fillColors)", "non-existent color helpers"),
]

failures = []


def balance_check(path):
    """Same logic as phase4_43_balance_check.py: () {} [] balance outside strings/comments."""
    src = open(path, encoding="utf-8").read()
    counts = {"(": 0, ")": 0, "{": 0, "}": 0, "[": 0, "]": 0}
    i, n = 0, len(src)
    in_str = None  # "'", '"', or "'''"
    in_line_comment = in_block_comment = False
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
        elif in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif in_str:
            if c == "\\":
                i += 1
            elif src.startswith(in_str * 3 if in_str == "'" else in_str, i) and in_str == "'''" if False else False:
                pass
            elif c == in_str:
                # handle triple-quoted strings
                if in_str == "'" and src.startswith("'''", i):
                    pass  # fall through to simple close; triple strings handled below
                in_str = None
        else:
            if c == "/" and nxt == "/":
                in_line_comment = True
                i += 1
            elif c == "/" and nxt == "*":
                in_block_comment = True
                i += 1
            elif src.startswith("'''", i) or src.startswith('"""', i):
                q = src[i] * 3
                j = src.find(q, i + 3)
                i = j + 2 if j != -1 else n
            elif c in ("'", '"'):
                in_str = c
            elif c in counts:
                counts[c] += 1
        i += 1
    ok = counts["("] == counts[")"] and counts["{"] == counts["}"] and counts["["] == counts["]"]
    return ok, counts


print("=" * 70)
print("PHASE 4 STEP I — FINAL VERIFICATION")
print("=" * 70)

# --- 1. Bracket balance ---
print("\n[1] Bracket balance (all 6 Reels files)")
for f in REELS_FILES:
    ok, counts = balance_check(f"{APP}/{f}")
    status = "OK " if ok else "FAIL"
    print(f"  [{status}] {f.split('/')[-1]:38s} ( {counts['(']}/{counts[')']}  {{ {counts['{']}/{counts['}']} }}  [ {counts['[']}/{counts[']']} ])")
    if not ok:
        failures.append(f"bracket imbalance in {f}")

# --- 2. Translation parity ---
print("\n[2] Translation parity en.json vs my.json")
en = json.load(open(f"{APP}/assets/lang/en.json", encoding="utf-8"))
my = json.load(open(f"{APP}/assets/lang/my.json", encoding="utf-8"))
en_keys, my_keys = set(en.keys()), set(my.keys())
print(f"  en.json keys: {len(en_keys)}   my.json keys: {len(my_keys)}")
only_en, only_my = en_keys - my_keys, my_keys - en_keys
if only_en or only_my:
    failures.append(f"translation parity broken: only-en={sorted(only_en)} only-my={sorted(only_my)}")
    print(f"  [FAIL] only in en: {sorted(only_en)}")
    print(f"  [FAIL] only in my: {sorted(only_my)}")
else:
    print(f"  [OK ] full parity ({len(en_keys)} keys, incl. 9 Reels keys from Steps G+H)")
reels_keys = ["copy_link", "link_copied", "reel_description", "close", "mute", "unmute", "eps", "reel_play_error", "reels_load_failed"]
missing = [k for k in reels_keys if k not in en_keys or k not in my_keys]
print(f"  [{'OK ' if not missing else 'FAIL'}] all 9 Step G+H keys present" + (f" — missing {missing}" if missing else ""))
if missing:
    failures.append(f"missing reels keys {missing}")

# --- 3. Bad pattern scan ---
print("\n[3] Known compile-pitfall pattern scan")
for f in REELS_FILES:
    src = open(f"{APP}/{f}", encoding="utf-8").read()
    for pat, why in BAD_PATTERNS:
        m = re.search(pat, src)
        if m:
            line = src[: m.start()].count("\n") + 1
            print(f"  [FAIL] {f.split('/')[-1]}:{line}  {why}")
            failures.append(f"bad pattern in {f}:{line} ({why})")
print("  [OK ] no pitfall patterns found" if not any("pattern" in x for x in failures) else "")

# --- 4. Working tree code cleanliness ---
print("\n[4] Working tree vs HEAD — code files must be untouched")
r = subprocess.run(["git", "-C", APP, "diff", "HEAD", "--stat", "--", "lib/", "assets/", "pubspec.yaml"],
                   capture_output=True, text=True)
out = r.stdout.strip()
if out:
    print(f"  [FAIL] code files dirty:\n{out}")
    failures.append("code files differ from HEAD")
else:
    print("  [OK ] lib/, assets/, pubspec.yaml identical to HEAD (cd2fc7c = what Bro built)")

print("\n" + "=" * 70)
print("RESULT: " + ("ALL CHECKS PASSED ✓" if not failures else f"{len(failures)} FAILURE(S) ✗"))
for x in failures:
    print(f"  - {x}")
sys.exit(0 if not failures else 1)
