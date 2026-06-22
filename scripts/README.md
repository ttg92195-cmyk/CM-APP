# scripts/

Helper scripts for the CM Movies Flutter app. Run from the repo root
unless noted otherwise.

## verify_translations.py

Translation parity check between `assets/lang/en.json` and
`assets/lang/my.json`. Runs locally before pushing translation changes,
and automatically on every PR via
`.github/workflows/translations-check.yml`.

### What it checks

1. Both JSON files exist and are valid JSON.
2. Each file has a `_meta` block with the required fields:
   `language`, `version`, `lastUpdated`, `source`.
3. The key sets of both files are IDENTICAL (excluding `_meta`).
4. No translation value is empty (`""`).
5. Placeholders (`{name}`) in the English source must appear in the
   Myanmar translation (and vice versa).
6. All non-`_meta` values are strings (not numbers/bools).

### Usage

```bash
# Default — strict errors only
python3 scripts/verify_translations.py

# Also warn on suspicious length ratios (MY 3x longer or shorter than EN)
python3 scripts/verify_translations.py --strict

# Suppress OK output (only print errors/warnings) — useful in CI logs
python3 scripts/verify_translations.py --quiet
```

### Exit codes

| Code | Meaning                                  |
| ---- | ---------------------------------------- |
| 0    | All checks passed (CI gate opens)       |
| 1    | One or more checks failed (CI blocks PR)|

### When CI fails

The PR will be blocked and the GitHub Actions summary will tell you
which check failed. Common causes:

- **Missing key**: you added a key to `en.json` but forgot the
  `my.json` translation (or vice versa). The error message lists the
  exact key(s) missing.
- **Empty value**: you added a new key with `""` as a placeholder
  meaning to fill it in later. Fix the value, don't commit empty
  strings — they cause silent UI glitches.
- **Placeholder mismatch**: you changed `vip_expires_on` from
  `"Expires: {date}"` to `"Expires: {expires}"` in one file but not
  the other. The error message shows which placeholders are missing
  in each direction.

### Local development workflow

Before pushing any change that touches `assets/lang/*.json`:

```bash
# 1. Make your edits
$EDITOR assets/lang/en.json
$EDITOR assets/lang/my.json

# 2. Run the parity check locally
python3 scripts/verify_translations.py

# 3. Fix any errors it reports

# 4. Commit and push — CI will re-run the same check as a gate
git add assets/lang/*.json
git commit -m "feat(l10n): add new translation key"
git push
```

If you skip step 2, CI will catch the issue on the PR — but fixing
locally is faster (5 seconds vs. waiting for the GitHub Actions runner
to spin up).

## (Future) Other scripts

This directory is the canonical home for repo-helper Python scripts.
When adding new scripts:

- Prefix with a verb (`verify_`, `extract_`, `migrate_`, `lint_`).
- Add a `--help` summary via `argparse`.
- Exit non-zero on failure so CI can use them as gates.
- Document the script in this README.
- If the script should run in CI, add a workflow file in
  `.github/workflows/`.
