#!/usr/bin/env python3
"""
Task 38 follow-up — .env sanity check.

Verifies that the .env file (committed at repo root, bundled into the APK
via flutter_dotenv) contains all the keys the app needs at runtime:

  - FIREBASE_API_KEY, FIREBASE_APP_ID, FIREBASE_MESSAGING_SENDER_ID,
    FIREBASE_PROJECT_ID, FIREBASE_STORAGE_BUCKET  (Firebase auth + Firestore)
  - TMDB_API_KEY                                        (TMDB lookups)
  - ONE_SIGNAL_APP_ID                                   (push notification subscription;
                                                         sending is done via OneSignal
                                                         Dashboard, REST API key no longer
                                                         in client)

Returns exit code 0 if ALL keys are present AND non-empty, 1 otherwise.
Designed to run in CI before `flutter build apk` so a missing-key build
fails loudly instead of silently shipping a broken APK.

History: on 2026-06-22 commit 1d67dc6 accidentally overwrote .env with
just `DATABASE_URL=...`, wiping all real secrets. The CI build silently
succeeded but the resulting APK threw HTTP 401 on every TMDB call. This
script prevents that class of regression.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ENV = ROOT / ".env"

REQUIRED_KEYS = [
    "FIREBASE_API_KEY",
    "FIREBASE_APP_ID",
    "FIREBASE_MESSAGING_SENDER_ID",
    "FIREBASE_PROJECT_ID",
    "FIREBASE_STORAGE_BUCKET",
    "TMDB_API_KEY",
    "ONE_SIGNAL_APP_ID",
]


def parse_env(path: Path) -> dict:
    """Parse a .env file into a dict. Last occurrence wins (matches dotenv)."""
    result = {}
    if not path.exists():
        return result
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        result[key.strip()] = value.strip()
    return result


def main() -> int:
    if not ENV.exists():
        print(f"FAIL: .env file missing at {ENV}")
        print("The app bundles .env at build time via flutter_dotenv.")
        print("Either commit a .env file, or have CI generate one before this step.")
        return 1

    env = parse_env(ENV)
    missing = []
    empty = []
    for key in REQUIRED_KEYS:
        if key not in env:
            missing.append(key)
        elif not env[key]:
            empty.append(key)

    print(f".env file: {ENV}")
    print(f"  total keys present: {len(env)}")
    print(f"  required keys: {len(REQUIRED_KEYS)}")
    print(f"  missing: {len(missing)}")
    print(f"  empty:   {len(empty)}")

    if missing:
        print("\nMISSING keys (not in .env at all):")
        for k in missing:
            print(f"  - {k}")

    if empty:
        print("\nEMPTY keys (present but value is blank):")
        for k in empty:
            print(f"  - {k}")

    if missing or empty:
        print("\nBuild will fail or ship broken. Fix .env and retry.")
        return 1

    print("\nAll required keys present and non-empty. OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
