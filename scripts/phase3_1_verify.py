#!/usr/bin/env python3
"""
Phase 3.1 — Banner Auto-Scroll Glitch on Tab Switch verification.

Verifies that the fix for the "fast-forward banner" glitch is correctly
implemented:
  1. HomeScreen exposes pauseAutoScroll() and resumeAutoScroll() public
     methods.
  2. _HomePageState calls pause when leaving Home tab and resume when
     entering Home tab, in BOTH tab-switch paths (onDestinationSelected
     and onNavigateToTab).
  3. All Navigator.push calls from home_page.dart go through the
     _pushRouteWithBannerPause helper so drawer/app-bar navigation also
     pauses/resumes the banner.
  4. Existing patterns (didChangeAppLifecycleState, _resetBannerController,
     _refreshHomeIfMounted) are preserved — no regression.

Run:
    python3 scripts/phase3_1_verify.py

Exit code 0 = all checks pass; 1 = at least one check failed.
"""

import sys
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Check:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.failures = []

    def ok(self, name):
        self.passed += 1
        print(f"  PASS: {name}")

    def fail(self, name, detail=""):
        self.failed += 1
        self.failures.append((name, detail))
        msg = f"  FAIL: {name}"
        if detail:
            msg += f" — {detail}"
        print(msg)

    def summary(self):
        total = self.passed + self.failed
        print(f"\n{'='*60}")
        print(f"Phase 3.1 verification: {self.passed}/{total} checks passed")
        if self.failed:
            print(f"FAILURES:")
            for name, detail in self.failures:
                print(f"  - {name}: {detail}")
            return 1
        return 0


def read(rel_path):
    p = ROOT / rel_path
    if not p.exists():
        return ""
    return p.read_text(encoding="utf-8", errors="replace")


def check_home_screen(c):
    print("\n[1] home_screen.dart — public pause/resume methods")
    src = read("lib/app/ui/home/home_screen.dart")
    if not src:
        c.fail("file exists", "home_screen.dart missing")
        return

    c.ok("file exists")

    # Public methods exposed
    if "void pauseAutoScroll()" in src:
        c.ok("pauseAutoScroll() public method declared")
    else:
        c.fail("pauseAutoScroll() public method declared")

    if "void resumeAutoScroll()" in src:
        c.ok("resumeAutoScroll() public method declared")
    else:
        c.fail("resumeAutoScroll() public method declared")

    # resumeAutoScroll MUST re-sync _currentAbsolutePage before starting timer
    # This is the critical fix — without it, drift accumulates and causes
    # the fast-forward glitch on resume.
    resume_section = src[src.index("void resumeAutoScroll()"):]
    resume_section = resume_section[:resume_section.index("void _startAutoScrollIfNeeded()")]
    if "_currentAbsolutePage = _bannerController!.page?.round()" in resume_section:
        c.ok("resumeAutoScroll re-syncs _currentAbsolutePage BEFORE restart")
    else:
        c.fail("resumeAutoScroll re-syncs _currentAbsolutePage BEFORE restart",
               "critical fix missing — drift will cause fast-forward glitch")

    # _startAutoScrollIfNeeded helper
    if "void _startAutoScrollIfNeeded()" in src:
        c.ok("_startAutoScrollIfNeeded() helper declared")
    else:
        c.fail("_startAutoScrollIfNeeded() helper declared")

    # Guard conditions in _startAutoScrollIfNeeded
    helper_section = src[src.index("void _startAutoScrollIfNeeded()"):]
    helper_section = helper_section[:helper_section.index("\n  ///", helper_section.index("}") + 1) if "}" in helper_section else len(helper_section)]
    for guard in ["!mounted", "!_bannerAutoScrollEnabled", "_bannerImageUrls.isEmpty", "_isLoading"]:
        if guard in helper_section:
            c.ok(f"guard: {guard}")
        else:
            c.fail(f"guard: {guard}")

    # Existing patterns preserved (no regression)
    if "didChangeAppLifecycleState" in src:
        c.ok("didChangeAppLifecycleState preserved (app background/foreground)")
    else:
        c.fail("didChangeAppLifecycleState preserved (app background/foreground)")

    if "_resetBannerController" in src:
        c.ok("_resetBannerController preserved (pull-to-refresh)")
    else:
        c.fail("_resetBannerController preserved (pull-to-refresh)")

    if "_pauseAutoScroll({bool keepEnabledFlag = true})" in src:
        c.ok("_pauseAutoScroll(keepEnabledFlag) signature preserved")
    else:
        c.fail("_pauseAutoScroll(keepEnabledFlag) signature preserved")

    # Timer cancelled in dispose (no leak)
    dispose_section = src[src.index("void dispose()"):]
    dispose_section = dispose_section[:dispose_section.index("}", dispose_section.index("_pauseAutoScroll") if "_pauseAutoScroll" in dispose_section else 0) + 1]
    if "_pauseAutoScroll" in dispose_section and "_bannerController?.dispose()" in dispose_section:
        c.ok("dispose() cancels timer + disposes controller (no leak)")
    else:
        c.fail("dispose() cancels timer + disposes controller (no leak)")


def check_home_page_tab_switch(c):
    print("\n[2] home_page.dart — tab switch pause/resume wiring")
    src = read("lib/app/ui/home/home_page.dart")
    if not src:
        c.fail("file exists", "home_page.dart missing")
        return

    c.ok("file exists")

    # Helper methods on _HomePageState
    if "void _pauseHomeBannerAutoScroll()" in src:
        c.ok("_pauseHomeBannerAutoScroll() helper declared")
    else:
        c.fail("_pauseHomeBannerAutoScroll() helper declared")

    if "void _resumeHomeBannerAutoScroll()" in src:
        c.ok("_resumeHomeBannerAutoScroll() helper declared")
    else:
        c.fail("_resumeHomeBannerAutoScroll() helper declared")

    # _resumeHomeBannerAutoScroll MUST use addPostFrameCallback
    resume_helper = src[src.index("void _resumeHomeBannerAutoScroll()"):]
    resume_helper = resume_helper[:resume_helper.index("/// Push a new route")]
    if "addPostFrameCallback" in resume_helper:
        c.ok("_resumeHomeBannerAutoScroll uses addPostFrameCallback")
    else:
        c.fail("_resumeHomeBannerAutoScroll uses addPostFrameCallback")

    # onDestinationSelected wiring
    # Look for the previousIndex capture pattern
    if "final previousIndex = _currentIndex;" in src:
        c.ok("previousIndex captured BEFORE setState (both tab-switch paths)")
    else:
        c.fail("previousIndex captured BEFORE setState")

    if "final isLeavingHome" in src and "final isEnteringHome" in src:
        c.ok("isLeavingHome + isEnteringHome direction flags computed")
    else:
        c.fail("isLeavingHome + isEnteringHome direction flags computed")

    # Count pause/resume call sites in tab-switch paths
    # Should be 2 pause calls (onNavigateToTab + onDestinationSelected)
    # and 2 resume calls (same)
    pause_calls = len(re.findall(r"if \(isLeavingHome\)\s*\{\s*_pauseHomeBannerAutoScroll\(\)", src))
    if pause_calls >= 2:
        c.ok(f"pause called in {pause_calls} tab-switch paths (>= 2 expected)")
    else:
        c.fail(f"pause called in {pause_calls} tab-switch paths (expected >= 2)")

    resume_calls = len(re.findall(r"if \(isEnteringHome\)\s*\{\s*_resumeHomeBannerAutoScroll\(\)", src))
    if resume_calls >= 2:
        c.ok(f"resume called in {resume_calls} tab-switch paths (>= 2 expected)")
    else:
        c.fail(f"resume called in {resume_calls} tab-switch paths (expected >= 2)")


def check_home_page_navigator_push(c):
    print("\n[3] home_page.dart — Navigator.push wrapped with banner pause")
    src = read("lib/app/ui/home/home_page.dart")
    if not src:
        c.fail("file exists", "home_page.dart missing")
        return

    # _pushRouteWithBannerPause helper
    if "Future<T?> _pushRouteWithBannerPause<T>" in src:
        c.ok("_pushRouteWithBannerPause<T>() helper declared")
    else:
        c.fail("_pushRouteWithBannerPause<T>() helper declared")

    # Helper must pause before push and resume in .then()
    helper_section = src[src.index("Future<T?> _pushRouteWithBannerPause<T>"):]
    helper_section = helper_section[:helper_section.index("\n\n", helper_section.index("return result;") if "return result;" in helper_section else len(helper_section))]
    if "_pauseHomeBannerAutoScroll()" in helper_section:
        c.ok("helper pauses banner before push")
    else:
        c.fail("helper pauses banner before push")

    if "_resumeHomeBannerAutoScroll()" in helper_section:
        c.ok("helper resumes banner on return")
    else:
        c.fail("helper resumes banner on return")

    if "refreshOnReturn" in helper_section:
        c.ok("helper supports refreshOnReturn parameter")
    else:
        c.fail("helper supports refreshOnReturn parameter")

    # Count call sites — should be 10 (SearchScreen, DownloadPage x2,
    # RecentPage, GenresTagsCollectionsPage, AdminPanelPage,
    # TmdbGeneratorPage, ProfilePage, LoginPage, VipPage)
    #
    # NOTE: The helper definition is "Future<T?> _pushRouteWithBannerPause<T>("
    # which does NOT match the regex below (there's <T> between the function
    # name and the open-paren), so we do NOT subtract 1 from the count.
    push_helper_calls = len(re.findall(r"_pushRouteWithBannerPause\(", src))
    if push_helper_calls >= 10:
        c.ok(f"_pushRouteWithBannerPause called {push_helper_calls} times (>= 10 expected)")
    else:
        c.fail(f"_pushRouteWithBannerPause called {push_helper_calls} times (expected >= 10)")

    # Verify NO raw Navigator.push calls remain (except inside the helper)
    # Find all "Navigator.push(" and check each is inside the helper
    raw_pushes = []
    for match in re.finditer(r"Navigator\.push\(", src):
        # Get the line and check if it's inside the helper definition
        line_start = src.rfind("\n", 0, match.start()) + 1
        line = src[line_start:src.index("\n", match.start())]
        # The helper definition has "return Navigator.push<T>(context, ...)"
        if "return Navigator.push<T>" in line or "return Navigator.push<T>" in src[max(0, match.start()-20):match.start()+30]:
            continue
        raw_pushes.append(line.strip())
    if not raw_pushes:
        c.ok("no raw Navigator.push calls remain (all wrapped)")
    else:
        c.fail("no raw Navigator.push calls remain",
               f"found {len(raw_pushes)}: {raw_pushes[:3]}")


def check_no_phase2_regression(c):
    print("\n[4] Phase 2 — no regression on security rules + audit log")
    rules = read("firestore.rules")
    if "admin_audit" in rules and "isValidAuditEntry" in rules:
        c.ok("Phase 2.4 admin_audit rules intact")
    else:
        c.fail("Phase 2.4 admin_audit rules intact")

    if "isValidMovie" in rules:
        c.ok("Phase 2.6 schema validation intact")
    else:
        c.fail("Phase 2.6 schema validation intact")

    fcs = read("lib/app/core/services/firestore_content_service.dart")
    if "RateLimiter.instance.enforce" in fcs:
        c.ok("Phase 2.8 rate limiting intact in FirestoreContentService")
    else:
        c.fail("Phase 2.8 rate limiting intact in FirestoreContentService")

    login = read("lib/app/ui/screens/login_page.dart")
    if "RateLimitPolicies.authLoginAttempt" in login:
        c.ok("Phase 2.8 rate limiting intact in LoginPage")
    else:
        c.fail("Phase 2.8 rate limiting intact in LoginPage")


def main():
    print("="*60)
    print("Phase 3.1 — Banner Auto-Scroll Glitch on Tab Switch verification")
    print("="*60)

    c = Check()

    check_home_screen(c)
    check_home_page_tab_switch(c)
    check_home_page_navigator_push(c)
    check_no_phase2_regression(c)

    sys.exit(c.summary())


if __name__ == "__main__":
    main()
