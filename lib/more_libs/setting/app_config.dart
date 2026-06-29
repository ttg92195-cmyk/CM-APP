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
      } catch (e) {
        debugPrint('Username lookup error for "$candidate" (may be rules): $e');
        // Phase 3.4 — capture ACTUAL error so loginUser can surface it.
        // Previously this catch swallowed the exception and silently fell
        // back to username@cmmovies.app, which then failed with the
        // misleading "invalid-credential" Auth error.
        if (e is FirebaseException) {
          lastUsernameLookupErrorCode = e.code;
          lastUsernameLookupErrorMessage = e.message;
        } else {
          lastUsernameLookupErrorCode = 'username-lookup-error';
          lastUsernameLookupErrorMessage = e.toString();
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

    // Listen to Firebase Auth state changes
    _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        // User is signed in - load profile from Firestore
        _lastActivityTime = DateTime.now(); // L3: Record login time
        await _loadUserProfile(user.uid);
      } else {
        // User is signed out
        _currentUser = null;
        _isLoadingAuth = false;
        notifyListeners();
      }
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

  Future<void> _loadUserProfile(String uid) async {
    // Phase 3.4 — clear diagnostic fields before each load
    lastProfileLoadErrorCode = null;
    lastProfileLoadErrorMessage = null;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data()!;
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

        // Check force logout flag set by admin
        if (data['forceLogout'] == true) {
          // Clear the flag and logout
          await _firestore.collection('users').doc(uid).update({
            'forceLogout': false,
          });
          await _clearLocalUserData();
          await _auth.signOut();
          _currentUser = null;
          _isLoadingAuth = false;
          notifyListeners();
          return;
        }
      } else {
        // Firestore doc doesn't exist yet, create from Firebase Auth user
        final user = _auth.currentUser;
        if (user != null) {
          final email = user.email ?? '';
          // Extract username from email - handle both internal and external emails
          String username;
          if (email.endsWith('@cmmovies.app')) {
            username = email.replaceAll('@cmmovies.app', '');
          } else {
            // For external emails (like gmail), check if admin
            // Look up admin username from cached admin email map
            await _loadAdminEmailMap();
            final adminEntry = _adminEmailMap.entries.where((e) => e.value.toLowerCase() == email.toLowerCase()).toList();
            username = adminEntry.isNotEmpty ? adminEntry.first.key : email.split('@').first;
          }
          final now = DateTime.now();
          final regDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

          _currentUser = {
            'uid': uid,
            'username': username,
            'isAdmin': false,
            'loginDate': now.toIso8601String(),
            'registrationDate': regDate,
            'email': email,
          };

          // Create Firestore doc
          await _firestore.collection('users').doc(uid).set({
            'username': username,
            'email': email,
            'isAdmin': false,
            'registrationDate': regDate,
            'createdAt': FieldValue.serverTimestamp(),
          });
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
    }
    // Sync local download toggle with VIP status:
    // VIP/Admin → auto-enable; non-VIP → auto-disable
    await _syncDownloadToggleWithVipStatus();
    _isLoadingAuth = false;
    notifyListeners();
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
    try {
      // Use provided email, or auto-generate from username
      final userEmail = email ?? await _usernameToEmail(username);

      // Create user in Firebase Auth
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: userEmail,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) return false;

      final now = DateTime.now();
      final regDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Create user profile in Firestore
      await _firestore.collection('users').doc(user.uid).set({
        'username': username,
        'email': userEmail,
        'isAdmin': false,
        'registrationDate': regDate,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update current user
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

      // Load user profile from Firestore
      await _loadUserProfile(user.uid);
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
