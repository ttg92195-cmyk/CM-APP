#!/usr/bin/env python3
"""
Phase 3.3 Verification Script
Verifies that the App Check removal + diagnostic logging changes
are correctly applied across the codebase.

Run: python3 /home/z/my-project/scripts/phase3_3_verify.py
"""

import os
import re
import sys

CM_APP = '/home/z/my-project/cm-app'

checks_passed = 0
checks_failed = 0
failures = []

def check(label, condition, detail=''):
    global checks_passed, checks_failed
    if condition:
        checks_passed += 1
        print(f'  [PASS] {label}')
    else:
        checks_failed += 1
        failures.append(label)
        print(f'  [FAIL] {label} {detail}')

print('=' * 70)
print('Phase 3.3 Verification: App Check removal + diagnostic logging')
print('=' * 70)

# ============================================================
# [1] main.dart: App Check activation removed
# ============================================================
print('\n[1] main.dart — App Check activation removed')
main_path = os.path.join(CM_APP, 'lib/main.dart')
with open(main_path) as f:
    main_dart = f.read()

check('firebase_app_check import removed',
      'import \'package:firebase_app_check/firebase_app_check.dart\';' not in main_dart,
      'import still present')
check('FirebaseAppCheck.instance.activate() removed',
      'FirebaseAppCheck.instance.activate' not in main_dart
      or '// FirebaseAppCheck.instance.activate' in main_dart,
      'activate() call still present')
check('AndroidProvider reference removed (in code, allowed in comments)',
      'AndroidProvider.' not in re.sub(r'//.*', '', main_dart),
      'AndroidProvider still in code')
check('Phase 3.3 comment block present',
      'Phase 3.3' in main_dart,
      'Phase 3.3 marker missing')
check('debugPrint confirmation present',
      'Phase 3.3: Firebase App Check activation skipped' in main_dart,
      'confirmation debugPrint missing')

# ============================================================
# [2] pubspec.yaml: firebase_app_check removed
# ============================================================
print('\n[2] pubspec.yaml — firebase_app_check dependency removed')
pubspec_path = os.path.join(CM_APP, 'pubspec.yaml')
with open(pubspec_path) as f:
    pubspec = f.read()

# Strip comments
pubspec_no_comments = re.sub(r'#.*', '', pubspec)
check('firebase_app_check: line removed from active deps',
      'firebase_app_check:' not in pubspec_no_comments,
      'firebase_app_check still in active dependencies')
check('firebase_core still present',
      'firebase_core:' in pubspec_no_comments)
check('firebase_auth still present',
      'firebase_auth:' in pubspec_no_comments)
check('cloud_firestore still present',
      'cloud_firestore:' in pubspec_no_comments)
check('Phase 3.3 comment block present in pubspec',
      'Phase 3.3' in pubspec)

# ============================================================
# [3] app_config.dart: diagnostic fields + improved catch
# ============================================================
print('\n[3] app_config.dart — diagnostic fields + improved error capture')
ac_path = os.path.join(CM_APP, 'lib/more_libs/setting/app_config.dart')
with open(ac_path) as f:
    ac = f.read()

check('lastRegisterErrorCode field present',
      'lastRegisterErrorCode' in ac)
check('lastRegisterErrorMessage field present',
      'lastRegisterErrorMessage' in ac)
check('lastLoginErrorCode field present',
      'lastLoginErrorCode' in ac)
check('lastLoginErrorMessage field present',
      'lastLoginErrorMessage' in ac)
check('registerUser clears diagnostic fields at start',
      'lastRegisterErrorCode = null;' in ac
      and 'lastRegisterErrorMessage = null;' in ac)
check('loginUser clears diagnostic fields at start',
      'lastLoginErrorCode = null;' in ac
      and 'lastLoginErrorMessage = null;' in ac)
check('registerUser has FirebaseException catch block',
      'on FirebaseException catch' in ac)
check('registerUser sets lastRegisterErrorCode in FirebaseAuthException',
      bool(re.search(r'on FirebaseAuthException catch.*?lastRegisterErrorCode = e\.code', ac, re.DOTALL)))
check('registerUser sets lastRegisterErrorCode in FirebaseException',
      bool(re.search(r'on FirebaseException catch.*?lastRegisterErrorCode = e\.code', ac, re.DOTALL)))
check('registerUser sets lastRegisterErrorCode in generic catch',
      "lastRegisterErrorCode = 'non-auth-exception'" in ac)
check('loginUser sets lastLoginErrorCode in FirebaseAuthException',
      bool(re.search(r'on FirebaseAuthException catch.*?lastLoginErrorCode = e\.code', ac, re.DOTALL)))
check('loginUser sets lastLoginErrorCode in FirebaseException',
      bool(re.search(r'on FirebaseException catch.*?lastLoginErrorCode = e\.code', ac, re.DOTALL)))
check('loginUser sets lastLoginErrorCode in generic catch',
      "lastLoginErrorCode = 'non-auth-exception'" in ac)
check('loginUser handles profile-load-failed case',
      "'profile-load-failed'" in ac)
check('flutter/foundation.dart imported (for debugPrint + kDebugMode)',
      "import 'package:flutter/foundation.dart'" in ac)

# ============================================================
# [4] login_page.dart: diagnostic SnackBar messages
# ============================================================
print('\n[4] login_page.dart — diagnostic SnackBar messages')
lp_path = os.path.join(CM_APP, 'lib/app/ui/screens/login_page.dart')
with open(lp_path) as f:
    lp = f.read()

check('firebase_auth import removed (no longer needed)',
      "import 'package:firebase_auth/firebase_auth.dart'" not in lp)
check('_handleLogin reads lastLoginErrorCode',
      'lastLoginErrorCode' in lp)
check('_handleLogin shows "Login failed [code: ...]" format',
      "'Login failed [code: $code | $msg]'" in lp)
check('_handleRegister reads lastRegisterErrorCode',
      'lastRegisterErrorCode' in lp)
check('_handleRegister shows "Register failed [code: ...]" format',
      "'Register failed [code: $code | $msg]'" in lp)
check('SnackBar duration set to 8 seconds (readability)',
      'Duration(seconds: 8)' in lp)
check('Phase 3.3 marker present',
      'Phase 3.3' in lp)

# ============================================================
# [5] Brace/paren balance sanity check
# ============================================================
print('\n[5] Brace/paren/bracket balance sanity check')
for f in [main_path, ac_path, lp_path]:
    with open(f) as fp:
        s = fp.read()
    name = os.path.basename(f)
    check(f'{name} braces balance', s.count('{') == s.count('}'),
          f'{s.count("{")}/{s.count("}")}')
    check(f'{name} parens balance', s.count('(') == s.count(')'),
          f'{s.count("(")}/{s.count(")")}')
    check(f'{name} brackets balance', s.count('[') == s.count(']'),
          f'{s.count("[")}/{s.count("]")}')

# ============================================================
# Summary
# ============================================================
print()
print('=' * 70)
print(f'SUMMARY: {checks_passed}/{checks_passed + checks_failed} checks passed')
if failures:
    print(f'FAILURES:')
    for f in failures:
        print(f'  - {f}')
    sys.exit(1)
else:
    print('All Phase 3.3 checks PASS')
    sys.exit(0)
