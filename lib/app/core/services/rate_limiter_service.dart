// Client-side rate limiter — Phase 2.8
//
// Sliding-window rate limiter that throttles high-frequency actions to
// prevent runaway loops, casual abuse, and to act as defense-in-depth
// alongside Firestore Security Rules + Firebase Auth's own rate limits.
//
// IMPORTANT — what this is and isn't:
//   - This is CLIENT-SIDE only. A determined attacker who modifies the
//     APK can bypass it. The authoritative protections remain:
//       * Firestore Security Rules (Phase 2.2 / 2.6) — admin-only writes
//       * Firebase App Check activation code (kept as no-op per Phase 2.1
//         revert) — would enforce if Play Integrity was available
//       * Firebase Auth built-in rate limits (~100 req/min/IP for sign-in
//         and account creation)
//       * Admin Audit Log (Phase 2.4) — every admin write is recorded
//   - This adds UX-layer protection: prevents a misbehaving batch loop
//     from flooding Firestore with hundreds of writes per second, stops
//     accidental double-taps, and gives clear "try again in N seconds"
//     feedback instead of cryptic Firebase quota errors.
//
// Design:
//   1. **In-memory only.** No SharedPreferences persistence. Rationale:
//      - Admin actions: admins don't usually hit limits; persistence
//        adds complexity for little benefit. The audit log already
//        records every action.
//      - Login attempts: Firebase Auth already enforces server-side
//        rate limits (~100/min/IP). The in-memory limit here is a
//        UX-layer early-warning, not a security control.
//      - Restarting the app resets limits. This is acceptable for v1.
//        If we later need persistence (e.g., to stop an attacker from
//        restarting the app to bypass login lockout), we can add it in
//        a future phase. Firebase Auth's server-side limit is the real
//        backstop.
//   2. **Sliding window.** Each action has a (maxCount, window) policy.
//      We keep a list of recent timestamps and prune entries older than
//      the window. If the list length >= maxCount, the action is denied
//      with a `retryAfter` Duration (time until the oldest timestamp
//      expires out of the window).
//   3. **Throws, doesn't return bool.** The `check()` method throws
//      `RateLimitExceededException`. This forces callers to handle it
//      explicitly (existing try/catch blocks already display `Error: $e`
//      via SnackBar). The `tryCheck()` and `canDo()` variants are
//      provided for callers that want a non-throwing API.
//   4. **Singleton.** One instance per app session. State is process-wide
//      so all call sites share the same counters.
//   5. **No cleanup needed.** The Map grows with the number of distinct
//      action IDs, which is small (~20). Pruning happens lazily on each
//      `check()` call. Memory overhead is negligible.
//   6. **Thread-safe-ish.** Dart is single-threaded per isolate; the
//      main UI isolate owns this singleton. Background isolates (if any
//      are added later for batch imports) should not call this — they
//      should report progress back to the main isolate which then
//      decides whether to continue.

import 'package:flutter/foundation.dart';

/// Thrown by [RateLimiter.check] when an action exceeds its rate limit.
///
/// Callers should catch this and display a user-friendly message. The
/// default `toString()` includes the action ID, the limit, and how long
/// to wait — this is what shows up in the existing `Error: $e` SnackBars
/// throughout the admin UI.
class RateLimitExceededException implements Exception {
  /// Identifier of the action that was rate-limited (e.g.
  /// 'admin.movie.add', 'auth.login.attempt').
  final String actionId;

  /// How long until the caller can retry successfully. Computed as
  /// `window - (now - oldestTimestamp)`. Always positive.
  final Duration retryAfter;

  /// The maximum number of calls allowed within [window].
  final int limit;

  /// The sliding window duration.
  final Duration window;

  const RateLimitExceededException({
    required this.actionId,
    required this.retryAfter,
    required this.limit,
    required this.window,
  });

  /// Human-readable message suitable for display in a SnackBar.
  ///
  /// Example: "Too many actions. Try again in 24s. (Limit: 30 per 1m)"
  String get userMessage {
    final secs = retryAfter.inSeconds;
    final waitStr = secs >= 60
        ? '${(secs / 60).ceil()} minute(s)'
        : '${secs + 1}s'; // +1 to round up so we don't show "0s"
    final windowStr = window.inSeconds >= 60
        ? '${(window.inSeconds / 60).round()}m'
        : '${window.inSeconds}s';
    return 'Too many actions. Try again in $waitStr. '
        '(Limit: $limit per $windowStr)';
  }

  @override
  String toString() => userMessage;
}

/// Predefined rate limit policies for admin and auth actions.
///
/// Centralized here so that all call sites use the same limits and the
/// values can be tuned in one place. Limits are intentionally generous
/// for normal admin use but tight enough to stop runaway loops.
///
/// Tuning rationale:
///   - movie.add: 30/min — a fast admin can add ~1 movie every 2s; a
///     misbehaving batch loop without skipAdminCheck would hit this in
///     30s. (BatchImportService passes skipAdminCheck:true so its
///     internal loop is fine; this limit only catches the OUTER call.)
///   - movie.update: 60/min — updates are more frequent (inline edits
///     on detail page); 60/min = 1/sec sustained.
///   - movie.delete: 20/min — deletes are rare; 20/min catches
///     accidental rapid taps.
///   - genre/tag/collection CRUD: 30/min each — admins rarely touch
///     these in bulk.
///   - banner.update: 5/min — banner edits are very rare; 5/min is
///     plenty and stops accidental double-save.
///   - user.ban/unban/forceLogout: 20/min each — admin user actions
///     are rare; 20/min is plenty.
///   - user.role_change: 10/min — role changes are sensitive; tighter
///     limit.
///   - user.vip_grant/revoke: 20/min each.
///   - notification.delete: 20/min.
///   - batch_import.start: 5/hour — heavy operation; 5/hour prevents
///     abuse while allowing retries.
///   - batch_import.delete: 30/min.
///   - auth.login.attempt: 10/min — supplement to existing in-memory
///     5-attempt/30s-lockout in login_page.dart (Firebase Auth's own
///     ~100/min/IP limit is the real backstop).
///   - auth.signup.attempt: 3/min — signups are rare for this app;
///     tight limit stops spam.
class RateLimitPolicies {
  RateLimitPolicies._();

  // === Admin: Movies ===
  static const String movieAdd = 'admin.movie.add';
  static const String movieUpdate = 'admin.movie.update';
  static const String movieDelete = 'admin.movie.delete';

  // === Admin: Genres ===
  static const String genreAdd = 'admin.genre.add';
  static const String genreUpdate = 'admin.genre.update';
  static const String genreDelete = 'admin.genre.delete';

  // === Admin: Tags ===
  static const String tagAdd = 'admin.tag.add';
  static const String tagUpdate = 'admin.tag.update';
  static const String tagDelete = 'admin.tag.delete';

  // === Admin: Collections ===
  static const String collectionAdd = 'admin.collection.add';
  static const String collectionUpdate = 'admin.collection.update';
  static const String collectionDelete = 'admin.collection.delete';

  // === Admin: Banner ===
  static const String bannerUpdate = 'admin.banner.update';

  // === Admin: Notifications ===
  static const String notificationDelete = 'admin.notification.delete';

  // === Admin: Batch Import ===
  static const String batchImportStart = 'admin.batch_import.start';
  static const String batchImportDelete = 'admin.batch_import.delete';

  // === Admin: User Actions ===
  static const String userBan = 'admin.user.ban';
  static const String userUnban = 'admin.user.unban';
  static const String userForceLogout = 'admin.user.force_logout';
  static const String userRoleChange = 'admin.user.role_change';
  static const String userVipGrant = 'admin.user.vip_grant';
  static const String userVipRevoke = 'admin.user.vip_revoke';

  // === Auth ===
  static const String authLoginAttempt = 'auth.login.attempt';
  static const String authSignupAttempt = 'auth.signup.attempt';
  static const String authPasswordReset = 'auth.password.reset';

  /// Default limit (maxCount) for each action ID. Admin write actions
  /// use 30/min by default; some sensitive ones override.
  static const Map<String, _Policy> _policies = {
    movieAdd:            _Policy(30, Duration(minutes: 1)),
    movieUpdate:         _Policy(60, Duration(minutes: 1)),
    movieDelete:         _Policy(20, Duration(minutes: 1)),
    genreAdd:            _Policy(30, Duration(minutes: 1)),
    genreUpdate:         _Policy(30, Duration(minutes: 1)),
    genreDelete:         _Policy(30, Duration(minutes: 1)),
    tagAdd:              _Policy(30, Duration(minutes: 1)),
    tagUpdate:           _Policy(30, Duration(minutes: 1)),
    tagDelete:           _Policy(30, Duration(minutes: 1)),
    collectionAdd:       _Policy(30, Duration(minutes: 1)),
    collectionUpdate:    _Policy(30, Duration(minutes: 1)),
    collectionDelete:    _Policy(30, Duration(minutes: 1)),
    bannerUpdate:        _Policy(5,  Duration(minutes: 1)),
    notificationDelete:  _Policy(20, Duration(minutes: 1)),
    batchImportStart:    _Policy(5,  Duration(hours: 1)),
    batchImportDelete:   _Policy(30, Duration(minutes: 1)),
    userBan:             _Policy(20, Duration(minutes: 1)),
    userUnban:           _Policy(20, Duration(minutes: 1)),
    userForceLogout:     _Policy(20, Duration(minutes: 1)),
    userRoleChange:      _Policy(10, Duration(minutes: 1)),
    userVipGrant:        _Policy(20, Duration(minutes: 1)),
    userVipRevoke:       _Policy(20, Duration(minutes: 1)),
    authLoginAttempt:    _Policy(10, Duration(minutes: 1)),
    authSignupAttempt:   _Policy(3,  Duration(minutes: 1)),
    authPasswordReset:   _Policy(3,  Duration(minutes: 1)),
  };

  /// Look up the policy for an action ID. Returns null if unknown
  /// (caller should handle this gracefully — usually by skipping the
  /// rate limit check rather than blocking the action).
  static _Policy? policyFor(String actionId) => _policies[actionId];
}

/// Internal: an immutable (maxCount, window) pair.
class _Policy {
  final int maxCount;
  final Duration window;
  const _Policy(this.maxCount, this.window);
}

/// Singleton sliding-window rate limiter.
///
/// Usage:
///   ```dart
///   // Throws RateLimitExceededException if limit exceeded
///   RateLimiter.instance.enforce(RateLimitPolicies.movieAdd);
///
///   // Non-throwing variant
///   if (!RateLimiter.instance.tryEnforce(RateLimitPolicies.movieAdd)) {
///     // show snackbar, return early
///   }
///
///   // Peek without recording (for UI disable state)
///   if (!RateLimiter.instance.canDo(RateLimitPolicies.movieAdd)) {
///     // disable button
///   }
///   ```
class RateLimiter {
  RateLimiter._();
  static final RateLimiter instance = RateLimiter._();

  /// Internal per-action bucket: list of recent timestamps (millis).
  /// Using a plain List rather than a Queue because we occasionally
  /// need to scan it (in `canDo`) and the lists are tiny (< 60 entries).
  final Map<String, List<int>> _timestamps = {};

  /// Throw [RateLimitExceededException] if the action's rate limit has
  /// been exceeded; otherwise record a new timestamp.
  ///
  /// This is the primary API. Call it at the START of the operation
  /// you want to throttle. If it throws, the operation should be
  /// aborted — the existing `try/catch (e) { SnackBar(...) }` pattern
  /// throughout the admin UI will display the error.
  ///
  /// [actionId] must be one of the [RateLimitPolicies.*] constants.
  /// If unknown, this is a no-op (defensive — don't break the action
  /// just because a policy wasn't defined).
  void enforce(String actionId) {
    final policy = RateLimitPolicies.policyFor(actionId);
    if (policy == null) {
      // Unknown action — don't enforce (fail open, not closed, for
      // availability). Log so devs notice during development.
      debugPrint('RateLimiter: no policy for actionId=$actionId — skipping');
      return;
    }
    _enforceWith(actionId, maxCount: policy.maxCount, window: policy.window);
  }

  /// Non-throwing variant. Returns true if the action was allowed (and
  /// a timestamp was recorded), false if the rate limit was exceeded
  /// (and no timestamp was recorded — caller should not perform the
  /// action).
  bool tryEnforce(String actionId) {
    try {
      enforce(actionId);
      return true;
    } on RateLimitExceededException {
      return false;
    }
  }

  /// Peek whether the action would be allowed WITHOUT recording a
  /// timestamp. Use this for UI state (e.g., disabling a button) where
  /// you don't want to "consume" a slot.
  bool canDo(String actionId) {
    final policy = RateLimitPolicies.policyFor(actionId);
    if (policy == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowMs = policy.window.inMilliseconds;
    final cutoff = now - windowMs;
    final list = _timestamps[actionId] ?? const [];
    final recent = list.where((ts) => ts > cutoff).length;
    return recent < policy.maxCount;
  }

  /// Returns the time until the action can be retried, or
  /// [Duration.zero] if it can be done now.
  Duration retryAfter(String actionId) {
    final policy = RateLimitPolicies.policyFor(actionId);
    if (policy == null) return Duration.zero;
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowMs = policy.window.inMilliseconds;
    final cutoff = now - windowMs;
    final list = _timestamps[actionId] ?? const [];
    final recent = list.where((ts) => ts > cutoff).toList()..sort();
    if (recent.length < policy.maxCount) return Duration.zero;
    final oldest = recent.first;
    final retryMs = (oldest + windowMs) - now;
    return retryMs <= 0 ? Duration.zero : Duration(milliseconds: retryMs);
  }

  /// Internal: the actual sliding-window check.
  void _enforceWith(
    String actionId, {
    required int maxCount,
    required Duration window,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final windowMs = window.inMilliseconds;
    final cutoff = now - windowMs;

    final list = _timestamps.putIfAbsent(actionId, () => <int>[]);
    // Prune expired entries. Using removeWhere is O(n) but n is tiny
    // (capped at maxCount+1 typically).
    list.removeWhere((ts) => ts <= cutoff);

    if (list.length >= maxCount) {
      final oldest = list.first;
      final retryMs = (oldest + windowMs) - now;
      throw RateLimitExceededException(
        actionId: actionId,
        retryAfter: retryMs <= 0
            ? const Duration(milliseconds: 1)
            : Duration(milliseconds: retryMs),
        limit: maxCount,
        window: window,
      );
    }

    list.add(now);
  }

  /// Clear all recorded timestamps. For testing/debugging only —
  /// not wired into any UI in production.
  void reset() {
    _timestamps.clear();
  }

  /// Clear recorded timestamps for a single action. For testing.
  void resetAction(String actionId) {
    _timestamps.remove(actionId);
  }
}
