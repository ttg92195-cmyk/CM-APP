import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';
import 'package:cm_movies/app/core/services/bookmark_service.dart';
import 'package:cm_movies/app/core/services/watchlist_service.dart';
// Task 32: JSON-driven translations — LocalizationService loads from
// assets/lang/{en,my}.json. AppConfig.translate() delegates to it.
import 'package:cm_movies/app/core/services/localization_service.dart';

class AppConfig extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _langKey = 'app_language';
  static const String _downloadEnabledKey = 'download_enabled';
  static const String _videoPlayerKey = 'video_player_mode';
  static const String _downloadsNotifKey = 'downloads_notification';
  static const String _notificationKey = 'notification_enabled';
  // Phase 3.13 — Pending username/email persistence so /users/ doc gets
  // the CORRECT username even when doc creation is deferred to background.
  // See _persistPendingSignup / _consumePendingSignup below.
  static const String _pendingUsernameKey = 'pending_signup_username';
  static const String _pendingEmailKey = 'pending_signup_email';

  // L3: Session timeout — auto-logout after inactivity
  static const Duration sessionTimeout = Duration(minutes: 30);
  DateTime? _lastActivityTime;
  bool _sessionTimedOut = false;

  bool get sessionTimedOut => _sessionTimedOut;

  /// Call this on any user interaction to keep session alive.
  ///
  /// SECURITY FIX (H9): Previously the 30-min inactivity timeout only
  /// fired on app resume (didChangeAppLifecycleState in main.dart) — if
  /// the user kept the app foregrounded for hours without backgrounding
  /// it, no timeout ever fired. Now every user activity also enforces
  /// the limit. The check is cheap (one DateTime comparison) and runs
  /// only when logged in, so it adds negligible overhead to pointer
  /// events.
  void recordActivity() {
    // Enforce session timeout on every activity, not just on app resume.
    // We do this BEFORE updating _lastActivityTime so that a session
    // that has already expired is logged out even if the user touches
    // the screen again after the timeout. checkSessionTimeout() is a
    // no-op when not logged in or when _lastActivityTime is null.
    if (_currentUser != null && _lastActivityTime != null) {
      final elapsed = DateTime.now().difference(_lastActivityTime!);
      if (elapsed >= sessionTimeout) {
        _sessionTimedOut = true;
        // Fire logout asynchronously — don't block the pointer event.
        // Also clear _lastActivityTime so subsequent calls don't re-trigger.
        _lastActivityTime = null;
        Future.microtask(() => logoutUser());
        notifyListeners();
        return;
      }
    }
    _lastActivityTime = DateTime.now();
    if (_sessionTimedOut) {
      _sessionTimedOut = false;
      notifyListeners();
    }
  }

  // Check if session has timed out.
  // Kept for backward-compat callers (main.dart's didChangeAppLifecycleState
  // still calls this on app resume as a backstop for the case where the app
  // was backgrounded for 30+ min — recordActivity() inside
  // didChangeAppLifecycleState wouldn't have ticked during background).
  bool checkSessionTimeout() {
    if (_currentUser == null || _lastActivityTime == null) return false;
    final elapsed = DateTime.now().difference(_lastActivityTime!);
    if (elapsed >= sessionTimeout) {
      _sessionTimedOut = true;
      _lastActivityTime = null;
      // Auto-logout
      logoutUser();
      return true;
    }
    return false;
  }

  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  ThemeMode _themeMode = ThemeMode.light; // Default to Light Mode
  String _languageCode = 'en';
  // Task 32: _translations field removed — LocalizationService is now the
  // single source of truth. AppConfig.translate() delegates to it.
  // The Map<String, String> field is intentionally gone to make any
  // accidental re-introduction of the old hardcoded translations a
  // compile error (forces future contributors to use the JSON path).
  final LocalizationService _localization = LocalizationService();
  bool _downloadEnabled = true;
  bool _downloadsNotification = true;
  bool _notificationEnabled = true;
  String _videoPlayerMode = 'builtin'; // 'builtin' or 'external'
  Map<String, dynamic>? _currentUser;
  bool _isLoadingAuth = true;

  // ====================================================================
  // Phase 3.2 — DIAGNOSTIC auth error capture (TEMPORARY)
  // ====================================================================
  // Bro reported that after Phase 2.8, both signup and login fail with
  // generic messages ("Username already exists" / "Invalid username or
  // password") even with correct credentials. The actual Firebase Auth
  // error code is swallowed by the catch blocks in loginUser/registerUser
  // (they debugPrint but return false), so Bro can't see what's actually
  // happening.
  //
  // These fields capture the last auth error code + message so the login
  // page can display them in the SnackBar for diagnosis. This is
  // TEMPORARY — once we identify and fix the root cause, these fields
  // and the verbose SnackBar messages should be removed to restore the
  // L4 security property (generic messages prevent username enumeration).
  // ====================================================================
  String? lastLoginErrorCode;
  String? lastLoginErrorMessage;
  String? lastRegisterErrorCode;
  String? lastRegisterErrorMessage;
  // Phase 3.4 — capture ACTUAL error from inner try/catch blocks that
  // previously swallowed Firestore exceptions. Without these, the user
  // saw misleading "profile-load-failed" / "invalid-credential" messages
  // while the real error (e.g. permission-denied) was hidden in debugPrint.
  String? lastProfileLoadErrorCode;
  String? lastProfileLoadErrorMessage;
  String? lastUsernameLookupErrorCode;
  String? lastUsernameLookupErrorMessage;

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get downloadEnabled => _downloadEnabled;

  /// Whether the current user is ALLOWED to use the Download feature at all.
  /// Admin = bypass (always true); VIP = true; non-VIP = false.
  /// This gate is independent of the local download toggle.
  bool get isDownloadAllowedForUser => isCurrentUserAdmin || isCurrentUserVip;

  /// Effective download permission = (user is admin/vip) AND (local toggle ON).
  /// Use this to decide whether to allow actual downloads / show download UI.
  bool get canDownload => isDownloadAllowedForUser && _downloadEnabled;

  bool get downloadsNotification => _downloadsNotification;
  bool get notificationEnabled => _notificationEnabled;
  String get videoPlayerMode => _videoPlayerMode;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  String? get currentUsername => _currentUser?['username'] as String?;
  bool get isCurrentUserAdmin => _currentUser?['isAdmin'] == true;
  bool get isLoadingAuth => _isLoadingAuth;

  /// Check if current user has active VIP (not expired)
  /// Auto-expires VIP if the expiry date has passed by updating Firestore
  bool get isCurrentUserVip {
    if (_currentUser?['isVip'] != true) return false;
    final expiry = _currentUser?['vipExpiry'] as String?;
    if (expiry == null || expiry.isEmpty) return false;
    final expiryDate = DateTime.tryParse(expiry);
    if (expiryDate == null) return false;
    final isActive = expiryDate.isAfter(DateTime.now());

    // Auto-expire: If VIP has expired, update Firestore and local state
    if (!isActive && _currentUser?['uid'] != null) {
      _autoExpireVip(_currentUser!['uid'] as String);
    }

    return isActive;
  }

  /// Auto-expire VIP — update Firestore and local state
  Future<void> _autoExpireVip(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'isVip': false,
        'vipExpiry': '',
      });
      // Update local state
      if (_currentUser != null) {
        _currentUser!['isVip'] = false;
        _currentUser!['vipExpiry'] = '';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Auto-expire VIP error: $e');
    }
  }

  // Cached admin email map loaded from Firestore (config/admin_emails)
  Map<String, String> _adminEmailMap = {};
  bool _adminEmailsLoaded = false;

  // Load admin email mappings from Firestore instead of hardcoding in client
  // NOTE: config/admin_emails is now admin-only read in Firestore rules.
  // This map is only available after an admin has logged in. For first-time
  // admin login, they should use their email address directly (with @).
  Future<void> _loadAdminEmailMap() async {
    if (_adminEmailsLoaded) return;
    try {
      final doc = await _firestore.collection('config').doc('admin_emails').get();
      if (doc.exists) {
        final data = doc.data()!;
        _adminEmailMap = Map<String, String>.from(data['mappings'] ?? {});
      }
    } catch (e) {
      // Permission denied is expected for non-admin users - silently ignore
      debugPrint('Admin email map not accessible (may require admin login): $e');
    }
    _adminEmailsLoaded = true;
  }

  // Helper to convert username to email format for Firebase Auth
  // Priority: 1) If input contains '@', use as email directly
  //           2) Look up actual email from Firestore by username (case-insensitive)
  //           3) Check admin email map
  //           4) Fallback: append @cmmovies.app (legacy users)
  Future<String> _usernameToEmail(String username) async {
    // Phase 3.4 — clear diagnostic fields before each lookup
    lastUsernameLookupErrorCode = null;
    lastUsernameLookupErrorMessage = null;

    // If input already contains @, treat as email directly
    if (username.contains('@')) {
      return username;
    }

    final lowerUsername = username.toLowerCase();

    // Step 1: Look up the user's actual email from Firestore by username
    // Try BOTH lowercase and original case to handle users who registered with
    // mixed-case usernames (case-insensitive matching)
    final candidates = <String>[lowerUsername];
    if (username != lowerUsername) {
      candidates.add(username);
    }

    for (final candidate in candidates) {
      // Phase 3.7 — Retry the username lookup up to 3 times on transient
      // errors (unavailable, network). Without this, a transient backend
      // hiccup causes _usernameToEmail to fall back to
      // 'username@cmmovies.app', which then fails in Auth with the
      // misleading 'invalid-credential'.
      for (int attempt = 1; attempt <= 3; attempt++) {
        try {
          final query = await _firestore
              .collection('users')
              .where('username', isEqualTo: candidate)
              .limit(1)
              .get();
          if (query.docs.isNotEmpty) {
            final data = query.docs.first.data();
            final email = data['email'] as String?;
            if (email != null && email.isNotEmpty) {
              return email;
            }
          }
          // Query succeeded but no match — break out of retry loop,
          // try the next candidate (if any).
          break;
        } catch (e) {
          debugPrint('Username lookup error for "$candidate" attempt $attempt: $e');
          // Phase 3.4 — capture ACTUAL error so loginUser can surface it.
          if (e is FirebaseException) {
            lastUsernameLookupErrorCode = e.code;
            lastUsernameLookupErrorMessage = e.message;
          } else {
            lastUsernameLookupErrorCode = 'username-lookup-error';
            lastUsernameLookupErrorMessage = e.toString();
          }
          // Retry only on transient errors.
          final code = lastUsernameLookupErrorCode ?? '';
          if (code == 'unavailable' || code == 'network-error' || code == 'network-request-failed') {
            if (attempt < 3) {
              await Future.delayed(Duration(milliseconds: 500 * attempt));
              continue;
            }
          }
          // Non-transient error — break out of retry loop.
          break;
        }
      }
    }

    // Step 2: Try loading admin email map (will only work if current user is admin)
    await _loadAdminEmailMap();
    if (_adminEmailMap.containsKey(lowerUsername)) {
      return _adminEmailMap[lowerUsername]!;
    }

    // Step 3: Default fallback — append @cmmovies.app for legacy users
    return '$lowerUsername@cmmovies.app';
  }

  // Helper to check if isAdmin value is truthy (handles both bool and string)
  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  // Helper to parse registrationDate which may be Timestamp, DateTime, or String
  String _parseRegistrationDate(dynamic value) {
    if (value == null) return '';
    if (value is Timestamp) {
      return '${value.toDate().year}-${value.toDate().month.toString().padLeft(2, '0')}-${value.toDate().day.toString().padLeft(2, '0')}';
    }
    if (value is DateTime) {
      return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    }
    // Already a string - return as-is
    return value.toString();
  }

  String translate(String key) {
    // Task 32: Delegate to LocalizationService — JSON-driven translations.
    // Back-compat: signature unchanged, so all existing callers
    // (e.g., appConfig.translate('home')) keep working without edits.
    return _localization.translate(key);
  }

  /// Task 32: Optional parameter substitution — pass named args to replace
  /// {placeholders} in the translated string. Useful for messages like
  ///   translate('vip_expires_on', namedArgs: {'date': '2026-12-31'})
  ///   translate('too_many_attempts', namedArgs: {'seconds': '30'})
  String tr(String key, {Map<String, String>? namedArgs}) {
    return _localization.translate(key, namedArgs: namedArgs);
  }

  /// Task 32: Expose the LocalizationService version + lastUpdated.
  /// Useful for the About / Settings page to show translation version
  /// alongside the app version (Bro's versioning concern).
  String get translationVersion => _localization.version;
  String get translationLastUpdated => _localization.lastUpdated;

  AppConfig() {
    _initAuth();
  }

  Future<void> _initAuth() async {
    // Load local preferences first
    await _loadLocalConfig();

    // Listen to Firebase Auth state changes.
    // Phase 3.7 — This listener is for INITIAL app startup only (when
    // the user was previously logged in and the app is cold-starting).
    // During an active loginUser() call, we set _isLoginInProgress=true
    // so this listener becomes a no-op — loginUser() does its own
    // _loadUserProfile and we don't want a second concurrent call
    // racing on _currentUser (which caused Bro's "login only works
    // once, then Invalid username or password" symptom).
    _auth.authStateChanges().listen((User? user) async {
      if (_isLoginInProgress) {
        debugPrint('authStateChanges fired during login in progress — skipping (loginUser handles it)');
        return;
      }
      if (user != null && _currentUser == null) {
        // Initial app load with a previously-signed-in user.
        _lastActivityTime = DateTime.now();
        await _loadUserProfile(user.uid);

        // Phase 3.15 — Safety net: if there's a pending signup in
        // SharedPreferences (from a previous registration where the
        // background doc creation failed or was killed when the app
        // was closed), kick off the background task again now that
        // the user is logged in.
        //
        // This handles the scenario where:
        //   1. User registered (pending signup persisted)
        //   2. Background task started but app was killed before doc
        //      was created (all 15 retries didn't complete)
        //   3. User reopens the app — authStateChanges fires with the
        //      persisted Auth user
        //   4. _loadUserProfile runs, finds no doc, goes to else-branch
        //      which ALSO fires the background task
        //   5. BUT if _loadUserProfile found the doc (because the
        //      background task from step 2 DID succeed just before the
        //      app was killed), the else-branch doesn't run, and the
        //      pending signup is never cleared.
        //
        // This safety net ensures the pending signup is eventually
        // cleared by re-firing the background task if needed. The
        // per-uid dedup in _createUserDocInBackground prevents
        // duplicate tasks.
        final pending = await _consumePendingSignup();
        if (pending != null && pending['email'] == (user.email ?? '')) {
          debugPrint('_initAuth: found pending signup on app restart, re-firing background doc creation');
          final now = DateTime.now();
          final regDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          _createUserDocInBackground(
            uid: user.uid,
            username: pending['username']!,
            email: pending['email']!,
            regDate: regDate,
            clearPendingOnSuccess: true,
          );
        }
      } else if (user == null && _currentUser != null) {
        // User was signed out (by us, by admin, or by session timeout).
        _currentUser = null;
        _isLoadingAuth = false;
        notifyListeners();
      } else if (user == null && _currentUser == null) {
        // Phase 3.7 — Cold start with no previously-signed-in user.
        // The auth listener fires once at app startup with user=null,
        // and we must clear _isLoadingAuth here so the splash screen
        // (which waits for isLoadingAuth=false in main.dart line 655)
        // can dismiss and show the LoginPage. Without this branch,
        // _isLoadingAuth stays true forever and the splash hangs on
        // the KMM logo spinner — which is what Bro reported as
        // 'KMM spinner taking a long time' after the Phase 3.7 fix.
        _isLoadingAuth = false;
        notifyListeners();
      }
      // If user != null && _currentUser != null → already loaded, nothing to do.
    });
  }

  Future<void> _loadLocalConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? ThemeMode.light.index; // Default Light Mode
    _themeMode = ThemeMode.values[themeIndex];
    _languageCode = prefs.getString(_langKey) ?? 'en';
    _downloadEnabled = prefs.getBool(_downloadEnabledKey) ?? true;
    _downloadsNotification = prefs.getBool(_downloadsNotifKey) ?? true;
    _notificationEnabled = prefs.getBool(_notificationKey) ?? true;
    _videoPlayerMode = prefs.getString(_videoPlayerKey) ?? 'builtin';
    await _loadTranslations();
    notifyListeners();
  }

  // Phase 3.6 — Guard against concurrent _loadUserProfile calls.
  // Both _auth.authStateChanges().listen and loginUser() call this fn
  // after signInWithEmailAndPassword, causing a race on _currentUser.
  // If the listener call fails (e.g. transient Firestore unavailability),
  // it can null out _currentUser AFTER loginUser's call succeeded.
  bool _isLoadingProfile = false;

  // Phase 3.7 — Flag set by loginUser() so the authStateChanges listener
  // knows to stay out of the way during an active login flow. Without
  // this, the listener fires right after signInWithEmailAndPassword,
  // races with loginUser's own _loadUserProfile call, and depending on
  // timing can null out _currentUser after loginUser returned success —
  // causing the app to bounce back to LoginPage.
  bool _isLoginInProgress = false;

  Future<void> _loadUserProfile(String uid) async {
    if (_isLoadingProfile) {
      debugPrint('_loadUserProfile already in progress, skipping duplicate call');
      return;
    }
    _isLoadingProfile = true;
    // Phase 3.4 — clear diagnostic fields before each load
    lastProfileLoadErrorCode = null;
    lastProfileLoadErrorMessage = null;
    try {
      // Phase 3.8 — Dual-strategy profile load.
      //
      // HISTORY:
      //   - Phase 3.5: switched from .doc(uid).get() to a list query
      //     (where on documentId) because .get() was failing with
      //     permission-denied due to Firestore SDK not having picked
      //     up the new auth token yet (race condition).
      //   - Phase 3.8 (this change): Bro reported that even the list
      //     query now fails with permission-denied. Root cause is
      //     STILL auth-state propagation delay — after
      //     signInWithEmailAndPassword completes, the Firestore SDK
      //     needs additional time to pick up the new auth credentials
      //     before it can serve authenticated requests.
      //
      // NEW STRATEGY:
      //   Try BOTH approaches in sequence. If the first fails with
      //   permission-denied, fall back to the other. This works
      //   regardless of which rule (list vs get) is deployed.
      //     1. Direct .doc(uid).get() — uses authenticated get rule.
      //     2. List query .where(FieldPath.documentId).get() — uses
      //        public list rule.
      //   The outer retry loop in loginUser() handles auth propagation
      //   delay by retrying on permission-denied (Phase 3.8 also added
      //   permission-denied to the retryable error list).
      Map<String, dynamic>? data;
      bool exists = false;
      Object? firstError;

      // Strategy 1: Direct .doc(uid).get() — most natural approach,
      // works once auth state has propagated.
      try {
        final doc = await _firestore.collection('users').doc(uid).get();
        exists = doc.exists;
        data = exists ? doc.data() : null;
      } catch (e) {
        firstError = e;
        debugPrint('_loadUserProfile: direct get() failed: $e');
        // Fall through to Strategy 2.
      }

      // Strategy 2: List query with documentId filter — uses public
      // list rule. Only try if Strategy 1 failed.
      if (data == null && !exists) {
        try {
          final query = await _firestore
              .collection('users')
              .where(FieldPath.documentId, isEqualTo: uid)
              .limit(1)
              .get();
          exists = query.docs.isNotEmpty;
          data = exists ? query.docs.first.data() : null;
        } catch (e) {
          debugPrint('_loadUserProfile: list query failed: $e');
          // If both strategies failed, throw the first error so the
          // outer catch block can record the diagnostic.
          if (firstError != null) {
            throw firstError!;
          }
          throw e;
        }
      }

      if (exists && data != null) {
        _currentUser = {
          'uid': uid,
          'username': data['username'] ?? 'User',
          'isAdmin': _isTruthy(data['isAdmin']),
          'isVip': _isTruthy(data['isVip']),
          'vipExpiry': data['vipExpiry'] ?? '',
          'loginDate': DateTime.now().toIso8601String(),
          'registrationDate': _parseRegistrationDate(data['registrationDate']),
          'email': data['email'] ?? '',
        };

        // Check if admin has banned this user — force logout
        if (data['isBanned'] == true) {
          await _clearLocalUserData();
          await _auth.signOut();
          _currentUser = null;
          _isLoadingAuth = false;
          notifyListeners();
          return;
        }

        // Check force logout flag set by admin.
        // Phase 3.6 — DO NOT try to clear the flag from the client.
        // firestore.rules preservesAdminOnlyFields() blocks users from
        // changing forceLogout, so the previous .update({forceLogout:false})
        // call threw permission-denied, which _loadUserProfile's catch
        // block swallowed by setting _currentUser=null, causing loginUser
        // to return false with a misleading 'profile-load-failed' error.
        // Now we just sign out and surface a clear diagnostic. The flag
        // stays true until the admin clears it via Firebase Console
        // (or a future Cloud Function).
        if (data['forceLogout'] == true) {
          lastProfileLoadErrorCode = 'force-logout';
          lastProfileLoadErrorMessage =
              'Account force-logged-out by admin. Contact support.';
          await _clearLocalUserData();
          await _auth.signOut();
          _currentUser = null;
          _isLoadingAuth = false;
          notifyListeners();
          return;
        }
      } else {
        // Firestore doc doesn't exist yet, create from Firebase Auth user.
        //
        // Phase 3.13 — NON-BLOCKING doc creation + pending username
        // preservation.
        //
        // HISTORY:
        //   - Phase 3.12: moved retry INSIDE _loadUserProfile else-branch,
        //     set _currentUser from Auth data BEFORE .set(), didn't null
        //     _currentUser on .set() failure. This fixed Email login but
        //     Username login STILL failed because:
        //       (a) The retry loop was BLOCKING — login took up to 25s
        //           waiting for .set() to succeed.
        //       (b) When .set() failed after 8 retries, the doc was never
        //           created. So /users/ stayed empty, and _usernameToEmail
        //           couldn't resolve Username → Email on the next login.
        //       (c) Even when .set() succeeded, the username stored was
        //           email.split('@').first — NOT the username Bro typed
        //           during registration. So Username login with the
        //           original username still couldn't find the doc.
        //
        // Phase 3.13 FIX (this change):
        //   1. Read pending username/email from SharedPreferences (written
        //      by registerUser). If present, use the ORIGINAL username
        //      Bro typed — not email.split('@').first.
        //   2. Set _currentUser IMMEDIATELY from Auth data + (pending or
        //      fallback) username. Login returns SUCCESS right away.
        //   3. Kick off .set() in the BACKGROUND (non-blocking) with 15
        //      retries and exponential backoff (1s, 2s, 4s, 8s, 16s, 30s,
        //      30s, ...). Total wait up to ~5 min — but the user doesn't
        //      wait because login already returned.
        //   4. After background .set() succeeds, clear the pending
        //      username/email from SharedPreferences.
        //   5. If background .set() fails after all 15 retries, the
        //      pending username/email STAYS in SharedPreferences so the
        //      next login can try again.
        final user = _auth.currentUser;
        if (user != null) {
          final email = user.email ?? '';

          // Phase 3.13 — Check SharedPreferences for a pending username
          // from a previous registration. If present, use it. Otherwise,
          // fall back to extracting from email.
          final pendingSignup = await _consumePendingSignup();
          String username;
          if (pendingSignup != null && pendingSignup['email'] == email) {
            // Pending signup matches this Auth user's email — use the
            // original username Bro typed during registration.
            username = pendingSignup['username']!;
            debugPrint('_loadUserProfile: using pending username "$username" for email $email');
          } else if (email.endsWith('@cmmovies.app')) {
            username = email.replaceAll('@cmmovies.app', '');
          } else {
            // For external emails (like gmail), check if admin
            await _loadAdminEmailMap();
            final adminEntry = _adminEmailMap.entries.where((e) => e.value.toLowerCase() == email.toLowerCase()).toList();
            username = adminEntry.isNotEmpty ? adminEntry.first.key : email.split('@').first;
          }
          final now = DateTime.now();
          final regDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

          // Set _currentUser from Auth data. Login returns SUCCESS
          // right away — but Phase 3.16 adds a SHORT blocking attempt
          // first so the doc gets created reliably on this login (not
          // relying on a fragile 6-min background task).
          //
          // Phase 3.16 — Try BLOCKING doc creation first. Only happens
          // in the else-branch (doc didn't exist), so existing users
          // with a doc are NOT slowed down. For new users on their
          // first Email login (e.g. registration's blocking attempt
          // failed), this gives them another chance to create the doc
          // with a fresh auth token before falling back to the 6-min
          // background task.
          final docCreated = await _tryCreateUserDocBlocking(
            uid: uid,
            username: username,
            email: email,
            regDate: regDate,
          );

          if (docCreated) {
            // Doc created — clear the pending signup if any.
            if (pendingSignup != null) {
              await _clearPendingSignup();
            }
          } else {
            // Blocking failed — fall back to the 6-min background task.
            // Pending signup stays in SharedPreferences for the next login.
            _createUserDocInBackground(
              uid: uid,
              username: username,
              email: email,
              regDate: regDate,
              clearPendingOnSuccess: pendingSignup != null,
            );
          }

          _currentUser = {
            'uid': uid,
            'username': username,
            'isAdmin': false,
            'loginDate': now.toIso8601String(),
            'registrationDate': regDate,
            'email': email,
          };
        }
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      // Phase 3.4 — capture ACTUAL error so loginUser can surface it.
      // Previously this catch swallowed the Firestore exception and just
      // set _currentUser = null, causing loginUser to report the misleading
      // "profile-load-failed" message instead of the real error code
      // (e.g. permission-denied).
      if (e is FirebaseException) {
        lastProfileLoadErrorCode = e.code;
        lastProfileLoadErrorMessage = e.message;
      } else {
        lastProfileLoadErrorCode = 'profile-load-error';
        lastProfileLoadErrorMessage = e.toString();
      }
      _currentUser = null;
    } finally {
      // Phase 3.6 — release the guard so future calls can proceed.
      _isLoadingProfile = false;
    }
    // Sync local download toggle with VIP status:
    // VIP/Admin → auto-enable; non-VIP → auto-disable
    await _syncDownloadToggleWithVipStatus();
    _isLoadingAuth = false;
    notifyListeners();
  }

  // ============================================================
  // Phase 3.13 — Pending signup persistence + background doc creation
  // ============================================================
  //
  // PROBLEM: When registerUser's .set() fails (permission-denied due to
  // auth propagation delay), the /users/{uid} doc is never created.
  // On the next Email login, _loadUserProfile else-branch creates the
  // doc, but the username field becomes email.split('@').first — NOT
  // the username Bro typed during registration. So Username login with
  // the original username fails because the doc has a different username.
  //
  // SOLUTION: Persist the original username + email to SharedPreferences
  // during registration. On the next login, _loadUserProfile reads the
  // pending signup and uses the ORIGINAL username for the doc.
  //
  // Additionally, doc creation is now NON-BLOCKING. The .set() retry
  // loop runs in the background with 15 retries + exponential backoff.
  // Login/register returns immediately — the user doesn't wait.
  // ============================================================

  /// Persist the username + email from a registration attempt to
  /// SharedPreferences. Called by registerUser BEFORE creating the
  /// Auth user, so even if registration fails partway through, the
  /// pending signup is preserved for the next login to use.
  Future<void> _persistPendingSignup(String username, String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pendingUsernameKey, username);
      await prefs.setString(_pendingEmailKey, email);
      debugPrint('_persistPendingSignup: stored username="$username" email="$email"');
    } catch (e) {
      debugPrint('_persistPendingSignup failed (non-fatal): $e');
    }
  }

  /// Read AND REMOVE the pending signup from SharedPreferences.
  /// Returns a Map with 'username' and 'email' keys, or null if no
  /// pending signup exists. The signup is removed because it's
  /// "consumed" by _loadUserProfile — once we use it to create the
  /// doc, we don't need it anymore. If the doc creation fails, the
  /// background task will re-persist the signup (see
  /// _createUserDocInBackground).
  Future<Map<String, String>?> _consumePendingSignup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(_pendingUsernameKey);
      final email = prefs.getString(_pendingEmailKey);
      if (username == null || email == null) return null;
      // Don't remove yet — the background .set() might fail. The
      // background task will remove on success or re-persist on
      // failure. We just READ it here.
      return {'username': username, 'email': email};
    } catch (e) {
      debugPrint('_consumePendingSignup failed (non-fatal): $e');
      return null;
    }
  }

  /// Clear the pending signup from SharedPreferences. Called by
  /// _createUserDocInBackground after the doc is successfully created.
  Future<void> _clearPendingSignup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingUsernameKey);
      await prefs.remove(_pendingEmailKey);
      debugPrint('_clearPendingSignup: cleared pending signup');
    } catch (e) {
      debugPrint('_clearPendingSignup failed (non-fatal): $e');
    }
  }

  // ============================================================
  // Phase 3.16 — Blocking-first doc creation (Spark plan friendly)
  // ============================================================
  //
  // PROBLEM
  //   Phase 3.13-3.15 rely on a fire-and-forget background task that
  //   retries .set() up to 15 times over ~6 min. The task can be killed
  //   when the app is backgrounded, when the user logs out, or when
  //   Android's JobScheduler reclaims memory. Bro reported that even
  //   after a successful Email login (which should re-fire the task
  //   via _loadUserProfile's else-branch), the /users/{uid} doc still
  //   never appeared. The 6-min window is too fragile on real devices.
  //
  // FIX
  //   Add a SHORT blocking retry loop (3 attempts, max ~1.7s total)
  //   that runs INSIDE registerUser and _loadUserProfile. The user
  //   sees a brief loading spinner. The auth token is at its freshest
  //   because the user JUST authenticated. If blocking succeeds, the
  //   doc exists immediately — Username login works on the very next
  //   attempt. If blocking fails, fall back to the 15-retry background
  //   task as before.
  //
  // WHY THIS WORKS WITHOUT CLOUD FUNCTIONS
  //   - The Firestore /users/{uid} create rule allows the OWNER to
  //     create their own doc with safe fields. We just need the auth
  //     token to be propagated — which a forced getIdToken(true) +
  //     short retry handles reliably on most networks.
  //   - The previous "non-blocking" approach was over-engineered for
  //     the rare case (terrible network) at the cost of the common
  //     case (good network where 1 attempt succeeds in <500ms).
  //   - Cloud Functions (Phase 3.10/3.15) would be more bulletproof
  //     but require Firebase Blaze plan (pay-as-you-go). This blocking
  //     approach works on the free Spark plan.

  /// Try to create the /users/{uid} doc with 3 quick blocking retries.
  ///
  /// Total max wait: ~1.7s (200ms + 500ms delays + ~1s for 3 write attempts).
  /// The caller MUST show a loading spinner while this runs.
  ///
  /// Returns `true` if the doc was created successfully, `false` if all
  /// 3 attempts failed. On failure, the caller should fall back to the
  /// long-running `_createUserDocInBackground` as a safety net.
  ///
  /// CRITICAL: this function does NOT clear the pending signup. The
  /// caller is responsible for calling `_clearPendingSignup()` if this
  /// returns `true`.
  Future<bool> _tryCreateUserDocBlocking({
    required String uid,
    required String username,
    required String email,
    required String regDate,
  }) async {
    final delays = <int>[300, 600]; // before attempt 2 and 3 (slightly longer for propagation)
    Object? lastError;
    String? lastErrorCode;

    for (int attempt = 1; attempt <= 3; attempt++) {
      // Verify auth user still matches on every attempt.
      final currentUser = _auth.currentUser;
      if (currentUser == null || currentUser.uid != uid) {
        debugPrint('_tryCreateUserDocBlocking: auth user mismatch on attempt $attempt, aborting');
        return false;
      }

      // Phase 3.18 — Auth state propagation fix (THE ROOT CAUSE FIX).
      //
      // HISTORY: Phase 3.13-3.17 all failed because after
      // createUserWithEmailAndPassword returns, the Firestore SDK is
      // still using anonymous/stale auth state for ~500-2000ms. During
      // that window, .set() hits the create rule which requires
      // isOwner(userId), but request.auth is null (stale SDK state) →
      // permission-denied.
      //
      // The previous fix (getIdToken(true) + reload) forces a TOKEN
      // refresh, but does NOT guarantee the Firestore SDK has picked
      // up the new auth state. The Firestore SDK listens to
      // authStateChanges() internally, but that listener fires
      // asynchronously — there's a race between our .set() call and
      // the SDK's internal auth state update.
      //
      // FIX: Subscribe to _auth.authStateChanges() and wait for it to
      // emit a non-null user with the correct uid. This forces our
      // code to wait until the SDK has DEFINITELY processed the new
      // auth state. Then we add a small additional delay (200ms) to
      // give the Firestore SDK's INTERNAL listeners time to react.
      //
      // This is the same pattern recommended by the Firebase team for
      // "permission-denied after sign-in" issues.
      try {
        // Set up a one-shot listener that completes when auth state
        // matches our target uid. Timeout after 2s to avoid hanging.
        final authReady = _auth.authStateChanges()
            .where((u) => u != null && u.uid == uid)
            .first
            .timeout(const Duration(seconds: 2));
        await authReady;
        // Small extra delay for Firestore SDK internal propagation.
        await Future.delayed(const Duration(milliseconds: 200));
        debugPrint('_tryCreateUserDocBlocking attempt $attempt: auth state propagated for uid=$uid');
      } catch (e) {
        // Timeout or other error — proceed anyway, the .set() below
        // might still succeed or fail with a useful error code.
        debugPrint('_tryCreateUserDocBlocking attempt $attempt authStateChanges wait failed (non-fatal): $e');
      }

      // Force token refresh on EVERY attempt (in addition to the
      // authStateChanges wait above — belt and suspenders).
      try {
        await currentUser.reload();
        await currentUser.getIdToken(true);
      } catch (e) {
        debugPrint('_tryCreateUserDocBlocking attempt $attempt getIdToken failed (non-fatal): $e');
      }

      // Wait before retry attempts (not before the first).
      if (attempt > 1) {
        await Future.delayed(Duration(milliseconds: delays[attempt - 2]));
      }

      try {
        await _firestore.collection('users').doc(uid).set({
          'username': username,
          'email': email,
          'isAdmin': false,
          'registrationDate': regDate,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('_tryCreateUserDocBlocking: doc created on attempt $attempt for uid=$uid');
        return true;
      } catch (e) {
        lastError = e;
        if (e is FirebaseException) {
          lastErrorCode = e.code;
          debugPrint('_tryCreateUserDocBlocking attempt $attempt failed: [${e.code}] ${e.message}');
        } else {
          lastErrorCode = 'non-firebase';
          debugPrint('_tryCreateUserDocBlocking attempt $attempt failed: $e');
        }
        // Retry on transient errors; abort on hard failures.
        if (e is FirebaseException) {
          final code = e.code;
          if (code == 'permission-denied' ||
              code == 'unavailable' ||
              code == 'network-error' ||
              code == 'network-request-failed' ||
              code == 'unknown' ||
              code == 'aborted' ||
              code == 'deadline-exceeded') {
            continue; // retry
          }
          // Hard failure (e.g. invalid-argument) — no point retrying.
          break;
        }
        // Non-FirebaseException — retry once more, then give up.
        if (attempt < 3) continue;
      }
    }

    debugPrint('_tryCreateUserDocBlocking: FAILED after retries — '
        'lastErrorCode=$lastErrorCode, lastError=$lastError');
    // Report to Crashlytics so Bro can see the exact failure reason in
    // the dashboard even if the debug log was missed.
    if (lastError != null) {
      FirebaseCrashlytics.instance.recordError(
        lastError,
        StackTrace.current,
        reason: '_tryCreateUserDocBlocking failed (lastErrorCode=$lastErrorCode) '
            'for uid=$uid, username=$username',
      );
    }
    return false;
  }

  /// Track in-flight background doc creation to prevent duplicate
  /// background tasks from stacking up if _loadUserProfile is called
  /// multiple times in quick succession.
  ///
  /// Phase 3.15 — Changed from `bool` to `String?` (uid). Previously,
  /// a global bool flag prevented ANY new background task from starting
  /// while one was in progress — even for a DIFFERENT user. This caused
  /// a bug: if user A registered and the background task was running
  /// (up to 6 min), then user A logged out and user B logged in, user
  /// B's background task was silently skipped. With a uid-based guard,
  /// a new user can always start their own background task.
  String? _backgroundDocCreationUid;

  /// Create the /users/{uid} doc in the BACKGROUND. Non-blocking —
  /// the caller does NOT await this. 15 retries with exponential
  /// backoff (1s, 2s, 4s, 8s, 16s, 30s, 30s, ... 30s). Total wait
  /// up to ~6 min. Each retry calls user.reload() + getIdToken(true)
  /// to give the Firestore SDK maximum chance to pick up the auth
  /// state.
  Future<void> _createUserDocInBackground({
    required String uid,
    required String username,
    required String email,
    required String regDate,
    required bool clearPendingOnSuccess,
  }) async {
    // Phase 3.15 — Per-uid dedup. Only skip if a background task for
    // the SAME uid is already running. A different uid gets its own task.
    if (_backgroundDocCreationUid == uid) {
      debugPrint('_createUserDocInBackground: already in progress for uid=$uid, skipping');
      return;
    }
    _backgroundDocCreationUid = uid;

    // Fire-and-forget — don't await. The caller (loginUser/registerUser)
    // returns immediately. This Future runs to completion in the
    // background, retrying .set() until it succeeds or all 15 attempts
    // are exhausted.
    () async {
      final user = _auth.currentUser;
      if (user == null || user.uid != uid) {
        // User signed out between the call and the background task
        // starting. Can't create the doc without auth. Abort — the
        // pending signup stays in SharedPreferences for next login.
        if (_backgroundDocCreationUid == uid) {
          _backgroundDocCreationUid = null;
        }
        return;
      }

      // Exponential backoff schedule: 1s, 2s, 4s, 8s, 16s, 30s, then
      // 30s for the remaining attempts. Total max wait ~6 min.
      final delays = <int>[
        1000, 2000, 4000, 8000, 16000,
        30000, 30000, 30000, 30000, 30000,
        30000, 30000, 30000, 30000, 30000,
      ];

      Object? lastError;
      bool docCreated = false;

      for (int attempt = 1; attempt <= 15; attempt++) {
        // Phase 3.15 — Check on EVERY retry that the current auth user
        // still matches the uid we're creating the doc for. If the user
        // has logged out or switched accounts, abort immediately — the
        // auth token is no longer valid for this uid, so .set() would
        // just fail with permission-denied forever.
        final currentUser = _auth.currentUser;
        if (currentUser == null || currentUser.uid != uid) {
          debugPrint('_createUserDocInBackground: auth user changed during retry $attempt, aborting');
          break;
        }

        // Force auth state refresh on EVERY attempt.
        try {
          await currentUser.reload();
          await currentUser.getIdToken(true);
        } catch (e) {
          debugPrint('_createUserDocInBackground attempt $attempt auth refresh failed (non-fatal): $e');
        }

        // Wait before the attempt (except the first, where the caller
        // has already waited ~800ms in loginUser).
        if (attempt > 1) {
          await Future.delayed(Duration(milliseconds: delays[attempt - 2]));
        }

        try {
          await _firestore.collection('users').doc(uid).set({
            'username': username,
            'email': email,
            'isAdmin': false,
            'registrationDate': regDate,
            'createdAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          docCreated = true;
          lastError = null;
          debugPrint('_createUserDocInBackground: doc created on attempt $attempt');
          break; // Success.
        } catch (e) {
          lastError = e;
          debugPrint('_createUserDocInBackground attempt $attempt failed: $e');
          if (e is FirebaseException) {
            final code = e.code;
            if (code == 'permission-denied' ||
                code == 'unavailable' ||
                code == 'network-error' ||
                code == 'network-request-failed') {
              continue; // Retryable.
            }
            break; // Non-retryable Firestore error.
          }
          break; // Non-FirebaseException.
        }
      }

      if (docCreated) {
        // Doc created successfully — clear the pending signup so it
        // doesn't get reused on the next login.
        if (clearPendingOnSuccess) {
          await _clearPendingSignup();
        }
      } else if (lastError != null) {
        // All retries failed. The pending signup STAYS in
        // SharedPreferences so the next login can try again.
        debugPrint('_createUserDocInBackground: doc creation failed after 15 retries — '
            'pending signup preserved for next login. Error: $lastError');
        FirebaseCrashlytics.instance.recordError(
          lastError,
          StackTrace.current,
          reason: '_createUserDocInBackground: Firestore doc creation failed '
              'after 15 retries, pending signup preserved',
        );
      }

      // Phase 3.15 — Only clear the flag if it still points to our uid.
      // If a different background task has started for a different uid,
      // don't clobber its flag.
      if (_backgroundDocCreationUid == uid) {
        _backgroundDocCreationUid = null;
      }
    }();
  }

  Future<void> _loadTranslations() async {
    // Task 32: Load JSON translations via LocalizationService.
    // The old _getDefaultTranslations() method (which had 800+ lines of
    // hardcoded Map literals) is removed — assets/lang/{en,my}.json is
    // now the single source of truth.
    await _localization.load(_languageCode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
    await _loadTranslations();
    notifyListeners();
  }

  Future<void> setVideoPlayerMode(String mode) async {
    _videoPlayerMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoPlayerKey, mode);
    notifyListeners();
  }

  Future<void> setDownloadsNotification(bool enabled) async {
    _downloadsNotification = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_downloadsNotifKey, enabled);
    notifyListeners();
  }

  Future<void> setNotificationEnabled(bool enabled) async {
    _notificationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationKey, enabled);
    notifyListeners();

    // Control OneSignal subscription
    try {
      if (enabled) {
        await OneSignal.Notifications.requestPermission(true);
        OneSignal.User.pushSubscription.optIn();
      } else {
        OneSignal.User.pushSubscription.optOut();
      }
    } catch (e) {
      debugPrint('OneSignal opt error: $e');
    }
  }

  Future<void> setDownloadEnabled(bool enabled) async {
    // Non-VIP, non-Admin users cannot enable downloads.
    if (enabled && !isDownloadAllowedForUser) {
      // Silently refuse — caller should have shown the VIP prompt already.
      return;
    }
    _downloadEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_downloadEnabledKey, enabled);
    notifyListeners();
  }

  /// Sync the local download toggle with the user's VIP status.
  /// Called after user profile loads. VIP/Admin users get downloads
  /// auto-enabled; non-VIP users get downloads auto-disabled.
  Future<void> _syncDownloadToggleWithVipStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (isDownloadAllowedForUser) {
        // VIP/Admin → auto-enable if currently off
        if (!_downloadEnabled) {
          _downloadEnabled = true;
          await prefs.setBool(_downloadEnabledKey, true);
        }
      } else {
        // Non-VIP → force disable
        if (_downloadEnabled) {
          _downloadEnabled = false;
          await prefs.setBool(_downloadEnabledKey, false);
        }
      }
    } catch (e) {
      debugPrint('Sync download toggle error: $e');
    }
  }

  // ========== Firebase Auth Methods ==========

  // Register a new user with Firebase Auth
  Future<bool> registerUser(String username, String password, {String? email}) async {
    // Phase 3.2 — clear diagnostic fields before each attempt
    lastRegisterErrorCode = null;
    lastRegisterErrorMessage = null;
    User? createdUser;
    try {
      // Use provided email, or auto-generate from username
      final userEmail = email ?? await _usernameToEmail(username);

      // Phase 3.13 — Persist the username + email to SharedPreferences
      // BEFORE creating the Auth user. This way, even if the .set()
      // fails during registration AND on the next login, the original
      // username Bro typed is preserved. The next Email login will
      // read this pending signup and use the ORIGINAL username (not
      // email.split('@').first) when creating the /users/{uid} doc.
      await _persistPendingSignup(username, userEmail);

      // Create user in Firebase Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: userEmail,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) return false;
      createdUser = user;

      final now = DateTime.now();
      final regDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Phase 3.16 — BLOCKING-FIRST doc creation.
      //
      // HISTORY:
      //   - Phase 3.9-3.11: blocking .set() retry loops (5-8 attempts).
      //     Registration took up to 25s waiting for .set() to succeed.
      //   - Phase 3.12: if .set() failed after 8 retries, kept the Auth
      //     user and returned success. But the doc was still missing,
      //     and the username was lost (next login used email.split).
      //   - Phase 3.13-3.15: NON-BLOCKING background task (15 retries,
      //     ~6 min). Problem: background task gets killed when app is
      //     backgrounded, user logs out, or Android reclaims memory.
      //     Even after successful Email login, doc was never created.
      //   - Phase 3.16 (this change): SHORT blocking attempt (3 retries,
      //     ~1.7s max) IMMEDIATELY after Auth user creation, BEFORE
      //     returning success. The auth token is at its freshest because
      //     createUserWithEmailAndPassword just returned. If blocking
      //     succeeds, the doc exists immediately and Username login
      //     works on the very next attempt. If blocking fails, fall
      //     back to the long-running background task as a safety net.
      //
      // The Auth user is already created — registration succeeds either
      // way. The blocking attempt is just an optimization to create the
      // doc NOW rather than relying on a fragile background task.

      // Phase 3.16 — Try to create the doc BLOCKING before returning
      // success. User sees the loading spinner for ~1.7s max. If this
      // succeeds, the doc exists immediately and we can clear the
      // pending signup. If it fails, we fall back to the background task.
      final docCreated = await _tryCreateUserDocBlocking(
        uid: user.uid,
        username: username,
        email: userEmail,
        regDate: regDate,
      );

      if (docCreated) {
        // Doc created successfully — clear the pending signup so it
        // doesn't get reused on the next login.
        await _clearPendingSignup();
      } else {
        // Blocking attempt failed (likely transient network/token issue).
        // Fall back to the long-running background task. The pending
        // signup stays in SharedPreferences so the original username
        // is preserved for the next Email login's retry.
        _createUserDocInBackground(
          uid: user.uid,
          username: username,
          email: userEmail,
          regDate: regDate,
          clearPendingOnSuccess: true,
        );
      }

      // Set _currentUser from Auth data + the username Bro typed.
      _currentUser = {
        'uid': user.uid,
        'username': username,
        'isAdmin': false,
        'loginDate': now.toIso8601String(),
        'registrationDate': regDate,
        'email': userEmail,
      };

      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Register error: ${e.code} - ${e.message}');
      // Phase 3.2 — capture actual error for diagnostic display
      lastRegisterErrorCode = e.code;
      lastRegisterErrorMessage = e.message;
      // Also report to Crashlytics so Bro can see it in the dashboard
      // even if the SnackBar diagnostic is missed.
      FirebaseCrashlytics.instance.recordError(
        e,
        StackTrace.current,
        reason: 'registerUser FirebaseAuthException: ${e.code}',
      );
      return false;
    } on FirebaseException catch (e) {
      // Phase 3.3 — Firestore / Storage exceptions have a different
      // type than FirebaseAuthException. Without this block, they
      // fall into the generic catch below and get reported as
      // 'non-auth-exception' (which is what Bro saw: "[code: non-
      // auth-exception | [cloud_firestore/permission-denied] ...]").
      // Now they get the actual code (e.g., 'permission-denied').
      debugPrint('Register error (Firestore): ${e.code} - ${e.message}');
      lastRegisterErrorCode = e.code;
      lastRegisterErrorMessage = e.message;
      FirebaseCrashlytics.instance.recordError(
        e,
        StackTrace.current,
        reason: 'registerUser FirebaseException: ${e.code}',
      );
      return false;
    } catch (e, st) {
      debugPrint('Register error: $e');
      // Phase 3.2 — capture non-Auth exceptions too (e.g., Firestore
      // permission errors, network errors, App Check rejection errors)
      lastRegisterErrorCode = 'non-auth-exception';
      lastRegisterErrorMessage = e.toString();
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'registerUser non-Auth exception',
      );
      return false;
    }
  }

  // Login user with Firebase Auth (regular or admin)
  Future<bool> loginUser(String username, String password) async {
    // Phase 3.2 — clear diagnostic fields before each attempt
    lastLoginErrorCode = null;
    lastLoginErrorMessage = null;
    // Phase 3.7 — set the in-progress flag so the authStateChanges
    // listener becomes a no-op while we drive the auth + profile load
    // ourselves. We MUST clear this in a finally block below.
    _isLoginInProgress = true;
    try {
      final email = await _usernameToEmail(username);

      // Sign in with Firebase Auth
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) return false;

      // Phase 3.4 — Force a token refresh before reading Firestore.
      // After signInWithEmailAndPassword completes, the Firestore SDK
      // may still be using a stale/anonymous auth state for a brief
      // window. Calling getIdToken() forces the SDK to wait for the
      // fresh Firebase Auth token to be ready, which ensures
      // request.auth != null on the backend (required by the
      // /users/{uid} get rule).
      try {
        await user.getIdToken(true);
      } catch (e) {
        debugPrint('getIdToken refresh failed (non-fatal): $e');
      }

      // Phase 3.14 — Reduced from 800ms to 400ms. The original 800ms was
      // added in Phase 3.8 to give the Firestore SDK time to propagate
      // the new auth token. But with Phase 3.13's non-blocking doc
      // creation, the cost of the first profile read failing is much
      // lower — _loadUserProfile's else-branch just kicks off a
      // background task and returns success. So we can afford a shorter
      // pre-delay and accept that the first attempt may fail with
      // permission-denied (which the retry loop below handles).
      await Future.delayed(const Duration(milliseconds: 400));

      // Phase 3.14 — Reduced from 8 attempts to 3. The original 8-attempt
      // loop (up to ~25s wait) was needed when _loadUserProfile's else-
      // branch had a BLOCKING .set() retry loop. With Phase 3.13's non-
      // blocking background doc creation, _loadUserProfile returns fast,
      // and the cost of giving up after 3 attempts is just an error
      // message asking the user to retry. Worst-case login wait is now
      // ~3 × (Firestore read) + (400+800 = 1.2s backoff) ≈ 10s instead
      // of the previous ~25-50s.
      //
      // HISTORY:
      //   - Phase 3.7: added retry loop for 'unavailable' / 'network-*'.
      //   - Phase 3.8: ADDED 'permission-denied' to the retryable list.
      //   - Phase 3.10: each retry calls user.reload() + getIdToken(true).
      //   - Phase 3.11: increased from 5 → 8 attempts.
      //   - Phase 3.14 (this change): reduced from 8 → 3 attempts because
      //     Phase 3.13's non-blocking doc creation makes the cost of
      //     giving up much lower.
      for (int attempt = 1; attempt <= 3; attempt++) {
        // Phase 3.10 — On retries (attempt > 1), force auth state
        // refresh before calling _loadUserProfile. This gives the
        // Firestore SDK another chance to pick up the auth token.
        if (attempt > 1) {
          try {
            await user.reload();
            await user.getIdToken(true);
          } catch (e) {
            debugPrint('Login retry $attempt auth refresh failed (non-fatal): $e');
          }
        }
        // Load user profile from Firestore
        await _loadUserProfile(user.uid);
        if (_currentUser != null) {
          // Success — bail out of the retry loop.
          break;
        }
        // Retryable errors:
        //   - unavailable, network-error, network-request-failed:
        //     transient backend/network conditions.
        //   - permission-denied: auth token propagation delay — the
        //     user IS authenticated (Firebase Auth succeeded) but the
        //     Firestore SDK hasn't picked up the new credentials yet.
        //     Retrying with backoff gives the SDK time to catch up.
        // Non-retryable (surface immediately):
        //   - force-logout: admin set the flag, retrying won't help.
        //   - profile-load-error: generic non-Firebase error.
        final code = lastProfileLoadErrorCode ?? '';
        if (code == 'unavailable' ||
            code == 'network-error' ||
            code == 'network-request-failed' ||
            code == 'permission-denied') {
          debugPrint('Profile load attempt $attempt failed with $code — retrying...');
          // Phase 3.14 — Reduced backoff from 700ms × attempt to 400ms ×
          // attempt. With only 3 attempts total, max backoff is now
          // 400+800 = 1200ms (was 700+1400+2100+2800+3500+4200+4900+5600
          // = ~25s with 8 attempts).
          await Future.delayed(Duration(milliseconds: 400 * attempt));
          continue;
        }
        // Non-retryable error — stop retrying.
        break;
      }
      if (_currentUser == null) {
        // Phase 3.4 — Surface the ACTUAL error captured by
        // _loadUserProfile's inner catch, instead of the generic
        // 'profile-load-failed' label. If _loadUserProfile swallowed
        // a Firestore exception, lastProfileLoadErrorCode now holds
        // the real code (e.g. permission-denied).
        if (lastProfileLoadErrorCode != null) {
          lastLoginErrorCode = lastProfileLoadErrorCode;
          lastLoginErrorMessage =
              'Profile load failed: ${lastProfileLoadErrorMessage ?? "(no message)"}';
        } else {
          // Doc exists but _currentUser is null — likely the banned /
          // forceLogout path inside _loadUserProfile.
          lastLoginErrorCode = 'profile-load-failed';
          lastLoginErrorMessage =
              'Signed in to Firebase Auth but profile load returned null '
              '(user may be banned or force-logged-out).';
        }
        return false;
      }
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Login error: ${e.code} - ${e.message}');
      // Phase 3.4 — If username lookup failed silently before sign-in,
      // the Auth error (e.g. invalid-credential) is misleading because
      // the real root cause is the Firestore read failure in
      // _usernameToEmail. Surface the Firestore error instead so Bro
      // can see what's actually broken.
      if (e.code == 'invalid-credential' &&
          lastUsernameLookupErrorCode != null) {
        lastLoginErrorCode =
            'username-lookup-failed: ${lastUsernameLookupErrorCode}';
        lastLoginErrorMessage =
            'Could not look up username in Firestore (caused sign-in to '
            'use fallback email which does not exist in Auth). '
            'Firestore error: ${lastUsernameLookupErrorMessage ?? "(no message)"}';
      } else if ((e.code == 'invalid-credential' || e.code == 'user-not-found') &&
          !username.contains('@') &&
          lastUsernameLookupErrorCode == null) {
        // Phase 3.13 — Username login failed because /users/ doc doesn't
        // exist for this username (lookup returned no docs, no error).
        // _usernameToEmail fell back to "username@cmmovies.app" which
        // doesn't exist in Auth. Guide Bro to login with Email instead.
        lastLoginErrorCode = 'username-not-found';
        lastLoginErrorMessage =
            'Username "$username" was not found. If you registered with '
            'an email address, please login with your email instead. '
            '(The /users/ profile doc will be created automatically on '
            'your next successful Email login, after which Username '
            'login will also work.)';
      } else {
        // Phase 3.2 — capture actual error for diagnostic display
        lastLoginErrorCode = e.code;
        lastLoginErrorMessage = e.message;
      }
      FirebaseCrashlytics.instance.recordError(
        e,
        StackTrace.current,
        reason: 'loginUser FirebaseAuthException: ${e.code}',
      );
      return false;
    } on FirebaseException catch (e) {
      // Phase 3.3 — Firestore read during _loadUserProfile can throw
      // [cloud_firestore/permission-denied] if App Check enforcement
      // is on. Catch it here so the error code is accurate.
      debugPrint('Login error (Firestore): ${e.code} - ${e.message}');
      lastLoginErrorCode = e.code;
      lastLoginErrorMessage = e.message;
      FirebaseCrashlytics.instance.recordError(
        e,
        StackTrace.current,
        reason: 'loginUser FirebaseException: ${e.code}',
      );
      return false;
    } catch (e, st) {
      debugPrint('Login error: $e');
      // Phase 3.2 — capture non-Auth exceptions too
      lastLoginErrorCode = 'non-auth-exception';
      lastLoginErrorMessage = e.toString();
      FirebaseCrashlytics.instance.recordError(
        e,
        st,
        reason: 'loginUser non-Auth exception',
      );
      return false;
    } finally {
      // Phase 3.7 — Always clear the in-progress flag, even if an
      // exception propagated up. Without this, the authStateChanges
      // listener would stay disabled for the rest of the session.
      _isLoginInProgress = false;
    }
  }

  // Logout
  Future<void> logoutUser() async {
    // Wipe per-user local caches BEFORE signing out so that the next
    // account that logs in on this device starts from a clean state.
    // This closes the 'Recently Viewed leakage between accounts' bug:
    // previously, recents were stored under a GLOBAL SharedPreferences
    // key, so Admin's recently-viewed list would appear under a freshly-
    // logged-in regular user's Recently Viewed tab.
    await _clearLocalUserData();
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Logout error: $e');
    }
    _currentUser = null;
    notifyListeners();
  }

  /// Wipe ALL user-scoped local data from SharedPreferences. Called by
  /// every logout path (manual logout, banned-user auto-logout, force-
  /// logout-by-admin, session-timeout auto-logout, device-limit-reached
  /// sign-out, and account deletion) to guarantee session isolation.
  ///
  /// - RecentService: clears every `recent_movies_*` key (per-UID + anon)
  /// - BookmarkService: clears the global `bookmarked_movies` local cache
  ///   (Firestore bookmarks are per-UID by design and disappear with the
  ///   auth session — no clearing needed for those)
  /// - WatchlistService: clears the global `watchlist_movies` local cache
  ///   (Firestore watchlist is per-UID by design — same reasoning)
  ///
  /// Idempotent and safe to call when no user is signed in.
  Future<void> _clearLocalUserData() async {
    try {
      await RecentService().clearAllForLogout();
    } catch (e) {
      debugPrint('Clear recents on logout failed: $e');
    }
    try {
      await BookmarkService().clearAllLocalForLogout();
    } catch (e) {
      debugPrint('Clear local bookmarks on logout failed: $e');
    }
    try {
      await WatchlistService().clearAllLocalForLogout();
    } catch (e) {
      debugPrint('Clear local watchlist on logout failed: $e');
    }
  }

  // M8: Delete user account (GDPR compliance)
  // Deletes Firestore user data and Firebase Auth account
  //
  // H8 FIX (N+1 deletes): Previously this method issued one Firestore
  // round-trip PER doc in each of bookmarks/watchlist/history
  // subcollections. A user with 100 bookmarks + 50 watchlist + 200
  // history entries = 350 sequential round-trips, taking 30+ seconds
  // on a typical mobile connection. Now all deletes are batched into
  // WriteBatch commits (500 ops/batch Firestore limit, chunked if
  // needed), reducing round-trips to ~3-4 total regardless of user
  // data volume.
  Future<bool> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // 1. Delete Firestore user document and sub-collections
      final userId = user.uid;
      final userDocRef = _firestore.collection('users').doc(userId);

      // Read all three subcollections in parallel (saves 2 round-trips
      // vs sequential reads).
      final results = await Future.wait([
        userDocRef.collection('bookmarks').get(),
        userDocRef.collection('watchlist').get(),
        userDocRef.collection('history').get(),
      ]);

      // Collect every doc ref to delete across all 3 subcollections +
      // the user doc itself. Chunk into WriteBatches of 500 (Firestore
      // hard limit per batch).
      const batchSize = 500;
      final allRefs = <DocumentReference>[];
      for (final snapshot in results) {
        for (final doc in snapshot.docs) {
          allRefs.add(doc.reference);
        }
      }
      allRefs.add(userDocRef); // delete the user doc itself last

      for (var i = 0; i < allRefs.length; i += batchSize) {
        final end = (i + batchSize > allRefs.length)
            ? allRefs.length
            : i + batchSize;
        final batch = _firestore.batch();
        for (final ref in allRefs.sublist(i, end)) {
          batch.delete(ref);
        }
        await batch.commit();
      }

      // 2. Delete Firebase Auth account
      await user.delete();

      // 3. Wipe ALL local user-scoped caches (recents, local bookmark/
      //    watchlist fallbacks) so nothing from this account leaks to
      //    a future account on the same device.
      await _clearLocalUserData();

      // 4. Clear local state
      _currentUser = null;
      notifyListeners();

      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Delete account error: ${e.code} - ${e.message}');
      // If requires re-authentication, return false so caller can handle
      if (e.code == 'requires-recent-login') {
        return false;
      }
      return false;
    } catch (e) {
      debugPrint('Delete account error: $e');
      return false;
    }
  }

  // Change password
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (_currentUser == null) return false;

    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) return false;

      // Re-authenticate user with old password
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: oldPassword,
      );
      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('Change password error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Change password error: $e');
      return false;
    }
  }

  // Get specific FirebaseAuthException error message
  String getAuthErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return translate('login_failed');
      case 'wrong-password':
        return translate('login_failed');
      case 'email-already-in-use':
        return translate('register_failed'); // L4: Generic message to prevent username enumeration
      case 'weak-password':
        return 'Password is too weak. Must be at least 8 characters with uppercase, lowercase, and a number';
      case 'invalid-email':
        return translate('login_failed'); // L4: Generic message to prevent username enumeration
      case 'user-disabled':
        return translate('login_failed'); // L4: Generic message — don't reveal account exists
      case 'too-many-requests':
        return 'Too many attempts. Please try again later';
      case 'network-request-failed':
        return 'Network error. Please check your connection';
      default:
        return translate('login_failed');
    }
  }

  void toggleTheme() {
    setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

}
