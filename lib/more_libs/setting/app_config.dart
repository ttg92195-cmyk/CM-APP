import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';
import 'package:cm_movies/app/core/services/bookmark_service.dart';
import 'package:cm_movies/app/core/services/watchlist_service.dart';

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
  Map<String, String> _translations = {};
  bool _downloadEnabled = true;
  bool _downloadsNotification = true;
  bool _notificationEnabled = true;
  String _videoPlayerMode = 'builtin'; // 'builtin' or 'external'
  Map<String, dynamic>? _currentUser;
  bool _isLoadingAuth = true;

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
    return _translations[key] ?? key;
  }

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
      _currentUser = null;
    }
    // Sync local download toggle with VIP status:
    // VIP/Admin → auto-enable; non-VIP → auto-disable
    await _syncDownloadToggleWithVipStatus();
    _isLoadingAuth = false;
    notifyListeners();
  }

  Future<void> _loadTranslations() async {
    _translations = _getDefaultTranslations(_languageCode);
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
      return false;
    } catch (e) {
      debugPrint('Register error: $e');
      return false;
    }
  }

  // Login user with Firebase Auth (regular or admin)
  Future<bool> loginUser(String username, String password) async {
    try {
      final email = await _usernameToEmail(username);

      // Sign in with Firebase Auth
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) return false;

      // Load user profile from Firestore
      await _loadUserProfile(user.uid);
      return _currentUser != null;
    } on FirebaseAuthException catch (e) {
      debugPrint('Login error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
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
  Future<bool> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      // 1. Delete Firestore user document and sub-collections
      final userId = user.uid;

      // Delete bookmarks sub-collection
      final bookmarks = await _firestore.collection('users').doc(userId).collection('bookmarks').get();
      for (final doc in bookmarks.docs) {
        await doc.reference.delete();
      }

      // Delete watchlist sub-collection
      final watchlist = await _firestore.collection('users').doc(userId).collection('watchlist').get();
      for (final doc in watchlist.docs) {
        await doc.reference.delete();
      }

      // Delete history sub-collection
      final history = await _firestore.collection('users').doc(userId).collection('history').get();
      for (final doc in history.docs) {
        await doc.reference.delete();
      }

      // Delete user document
      await _firestore.collection('users').doc(userId).delete();

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

  Map<String, String> _getDefaultTranslations(String code) {
    if (code == 'en') {
      return {
        'app_name': 'KMM',
        'home': 'Home',
        'movies': 'Movies',
        'series': 'Series',
        'search': 'Search',
        'bookmarks': 'Bookmarks',
        'settings': 'Settings',
        'trending_movies': 'Trending Movies',
        'trending_tv_shows': 'Trending TV Shows',
        'genre': 'Genre',
        'genres': 'Genres',
        'tag': 'Tag',
        'tags': 'Tags',
        'collections': 'Collections',
        'year': 'Year',
        'overview': 'Overview',
        'cast': 'Cast',
        'download': 'Download',
        'downloads': 'Downloads',
        'director': 'Director',
        'rating': 'Rating',
        'resolution': 'Resolution',
        'quality': 'Quality',
        'server': 'Server',
        'size': 'Size',
        'search_hint': 'Search movies...',
        'no_results': 'No results found',
        'loading': 'Loading...',
        'error_occurred': 'An error occurred',
        'retry': 'Retry',
        'bookmark_added': 'Added to bookmarks',
        'bookmark_removed': 'Removed from bookmarks',
        'no_bookmarks': 'No bookmarks yet',
        'add_to_bookmark': 'Add to Bookmark',
        'remove_from_bookmark': 'Remove from Bookmark',
        'language': 'Language',
        'theme': 'Theme',
        'dark_mode': 'Dark Mode',
        'light_mode': 'Light Mode',
        'recently_viewed': 'Recently Viewed',
        'recent': 'Recent',
        'all': 'All',
        'movies_count': 'Movies Count',
        'filter_by_genre': 'Filter by Genre',
        'filter_by_tag': 'Filter by Tag',
        'filter_by_year': 'Filter by Year',
        'view_detail': 'View Detail',
        'more': 'More',
        'categories': 'Categories',
        'adult_content': 'Adult Content',
        'clear_history': 'Clear History',
        'no_history': 'No viewing history',
        'about_app': 'About',
        'about': 'About',
        'version': 'Version',
        'help_support': 'Help & Support',
        'about_kmm': 'About KMM',
        'faq': 'Frequently Asked Questions',
        'contact_us': 'Contact Us',
        'app_version': 'App Version',
        'troubleshooting': 'Troubleshooting Tips',
        'features': 'Features',
        'credits': 'Credits & Acknowledgments',
        'data_collection': 'Data Collection',
        'data_usage': 'Data Usage',
        'third_party_services': 'Third-Party Services',
        'data_security': 'Data Security',
        'children_privacy': "Children's Privacy",
        'changes_to_policy': 'Changes to This Policy',
        'streaming': 'Streaming',
        'downloading': 'Downloading',
        'watchlist': 'Watchlist',
        'bookmarks': 'Bookmarks',
        'register': 'Register',
        'admin_login': 'Admin Login',
        'username': 'Username',
        'password': 'Password',
        'login': 'Login',
        'logout': 'Logout',
        'login_success': 'Login successful',
        'login_failed': 'Invalid username or password',
        'register_success': 'Registration successful',
        'register_failed': 'Username already exists',
        'privacy_policy': 'Privacy and Policy',
        'about_cm_movies': 'About KMM',
        'download_toggle': 'Show Download',
        'download_toggle_desc': 'Enable to show download in movie details',
        'download_disabled_msg': 'Download links are currently disabled. Go to Download settings to enable them.',
        'vip_active': 'VIP Active',
        'vip_active_desc': 'Thank you for supporting KMM',
        'vip_inactive': 'VIP Not Active',
        'vip_inactive_desc': 'Tap to upgrade and unlock downloads',
        'vip_expires_on': 'Expires: {date}',
        'vip_get_now': 'Get VIP',
        'search_history': 'Recent Searches',
        'search_history_clear_all': 'Clear All',
        'video_player': 'Video Player',
        'video_player_desc': 'Choose default video player',
        'built_in_player': 'Built-in Player',
        'external_player': 'External Player (VLC/MX Player)',
        'select_video_player': 'Select Video Player',
        'select_language': 'Select Language',
        'no_downloads': 'No downloads available',
        'genres_tags_collections': 'Genres/Tags/Collections',
        'profile': 'Profile',
        'account_information': 'Account Information',
        'account_name': 'Account Name',
        'account_active': 'Account Active',
        'change_password': 'Change Password',
        'old_password': 'Old Password',
        'new_password': 'New Password',
        'confirm_new_password': 'Confirm New Password',
        'password_changed': 'Password changed successfully',
        'password_change_failed': 'Old password is incorrect',
        'k_drama': 'K Drama',
        'trending': 'Trending',
        '4k_movies': '4K Movies',
        '4k_series': '4K Series',
        'animation': 'Animation',
        'anime': 'Anime',
        'bollywood': 'Bollywood',
        'donghua': 'Donghua',
        'c_drama': 'C Drama',
        'total_posts': 'Total',
        'filters': 'Filters',
        'clear_filters': 'Clear Filters',
        'apply_filters': 'Apply',
        'sort_by': 'Sort By',
        'sort_latest': 'Latest',
        'sort_rating': 'Rating',
        'sort_name': 'Name',
        'type_all': 'All',
        'type_movie': 'Movie',
        'type_series': 'Series',
        'min_rating': 'Min Rating',
        'results': 'results',
        'no_filters': 'No filters applied',
        'active_filters': 'Active Filters',
        'watchlist': 'Watchlist',
        'add_to_watchlist': 'Add to Watchlist',
        'remove_from_watchlist': 'Remove from Watchlist',
        'watchlist_added': 'Added to Watchlist',
        'watchlist_removed': 'Removed from Watchlist',
        'no_watchlist': 'Your watchlist is empty',
        'download_manager': 'Download Manager',
        'downloading': 'Downloading',
        'paused': 'Paused',
        'completed': 'Completed',
        'failed': 'Failed',
        'pause': 'Pause',
        'resume': 'Resume',
        'retry': 'Retry',
        'no_downloads_yet': 'No downloads yet',
        'active_downloads': 'Active Downloads',
        'completed_downloads': 'Completed Downloads',
        'clear_completed': 'Clear Completed',
        'age_gate_title': 'Age Restriction',
        'age_gate_desc': 'This content is rated 18+ and contains adult material. Please confirm you are 18 years or older to proceed.',
        'age_gate_confirm': 'I am 18+',
        'age_gate_cancel': 'Go Back',
        'back': 'Back',
        'press_back_again_exit': 'Press back again to exit',
        'storage_permission_required': 'Storage permission is required to access downloads',
        'confirm_password': 'Confirm Password',
        'create_account': 'Create Account',
        'already_have_account': 'Already have an account?',
        'dont_have_account': "Don't have an account?",
        'sign_in': 'Sign In',
        'sign_up': 'Sign Up',
        'login_and_register': 'Login & Register',
        'login_subtitle': 'Sign in to your account',
        'register_subtitle': 'Create a new account to get started',
        'enter_username': 'Please enter username',
        'enter_password': 'Please enter password',
        'username_min_length': 'Username must be at least 3 characters',
        'username_invalid_chars': 'Username cannot contain @ or spaces',
        'password_hint': '8+ chars, uppercase, lowercase, number',
        'password_min_length': 'Password must be at least 8 characters',
        'password_uppercase': 'Password must contain at least one uppercase letter',
        'password_lowercase': 'Password must contain at least one lowercase letter',
        'password_number': 'Password must contain at least one number',
        'confirm_password_empty': 'Please confirm password',
        'passwords_no_match': 'Passwords do not match',
        'too_many_attempts': 'Too many failed attempts. Please wait {seconds}s before trying again.',
        'too_many_attempts_short': 'Too many failed attempts. Wait {seconds}s.',
        'switch_language': 'Switch Language',
        'myanmar': 'Myanmar',
        'english': 'English',
        'privacy_policy_text': 'Privacy Policy\n\nKMM is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our application.\n\nInformation We Collect:\n- Account credentials (username, email) — stored securely via Firebase Authentication\n- Bookmarks, watchlist, and viewing history — synced to your account via Firebase Firestore\n- App settings and preferences — stored locally on your device\n\nHow We Use Your Information:\n- To provide and improve our services\n- To sync your bookmarks and watchlist across devices\n- To maintain your viewing history and preferences\n\nData Storage:\nYour account data (bookmarks, watchlist, viewing history) is stored securely on Google Firebase Firestore cloud servers, encrypted in transit and at rest. App settings and preferences are stored locally on your device. Your password is never stored in plain text — Firebase Authentication handles it securely.\n\nData Sharing:\nWe do not sell or share your personal data with third parties. Your data is only accessible to you and is protected by Firebase Security Rules that require authentication.\n\nThird-Party Services:\nOur app uses Google Firebase (Authentication, Firestore, Storage, App Check) which has its own privacy policy. We encourage you to review the Google privacy policy.\n\nYour Rights:\n- You can delete your account and all associated data at any time from your Profile page\n- You can export your bookmarks and watchlist locally\n- You can logout at any time to stop cloud sync\n\nContact Us:\nIf you have any questions about this Privacy Policy, please contact us at support@cmmovies.app.\n\nLast updated: 2026',
        'about_cm_movies_text': 'KMM\n\nYour ultimate movie and series companion app. Browse, search, and discover movies and TV series from around the world.\n\nFeatures:\n- Browse trending movies and TV shows\n- Search by title, genre, or tag\n- Bookmark your favorites\n- Download management\n- Multi-language support (Myanmar & English)\n- Dark & Light theme\n\nVersion 1.0.0\nDeveloped with love for movie enthusiasts.',
        'notifications': 'Notifications',
        'downloads_notification': 'Downloads Notification',
        'downloads_notification_desc': 'Show notifications for download progress',
        'push_notification': 'Push Notification',
        'push_notification_desc': 'Receive push notifications from admin',
        'storage': 'Storage',
        'clear_cache': 'Clear Cache',
        'clear_cache_desc': 'Clear cached images and temporary data',
        'cache_cleared': 'Cache cleared successfully',
      };
    }
    return {
      'app_name': 'KMM',
      'home': 'ပင်မ',
      'movies': 'ရုပ်ရှင်များ',
      'series': 'ဇာတ်လမ်းတွဲများ',
      'search': 'ရှာဖွေရန်',
      'bookmarks': 'သိမ်းဆည်းမှု',
      'settings': 'ဆက်တင်',
      'trending_movies': 'လူကြိုက်များသော ရုပ်ရှင်များ',
      'trending_tv_shows': 'လူကြိုက်များသော တီဗွီရုပ်သံ',
      'genre': 'အမျိုးအစား',
      'genres': 'အမျိုးအစားများ',
      'tag': 'တက်ဂ်',
      'tags': 'တက်ဂ်များ',
      'collections': 'စုစည်းမှုများ',
      'year': 'နှစ်',
      'overview': 'အကျဉ်းချုပ်',
      'cast': 'သရုပ်ဆောင်များ',
      'download': 'ဒေါင်းလုဒ်',
      'downloads': 'ဒေါင်းလုဒ်များ',
      'director': 'ဒါရိုက်တာ',
      'rating': 'ရမတ်',
      'resolution': 'ရီဇော်လူးရှင်',
      'quality': 'အရည်အသွေး',
      'server': 'ဆာဗာ',
      'size': 'အရွယ်အစား',
      'search_hint': 'ရုပ်ရှင်အမည် ရှာဖွေရန်...',
      'no_results': 'ရလဒ်မတွေ့ပါ',
      'loading': 'ခဏစောင့်ပါ...',
      'error_occurred': 'အမှားတစ်ခုဖြစ်ပွားခဲ့ပါသည်',
      'retry': 'ထပ်စမ်းကြည့်ပါ',
      'bookmark_added': 'သိမ်းဆည်းပြီးပါပြီ',
      'bookmark_removed': 'သိမ်းဆည်းမှုမှ ဖယ်ရှားပြီးပါပြီ',
      'no_bookmarks': 'သိမ်းဆည်းထားသော ရုပ်ရှင်မရှိပါ',
      'add_to_bookmark': 'သိမ်းဆည်းရန်',
      'remove_from_bookmark': 'သိမ်းဆည်းမှုမှ ဖယ်ရှားရန်',
      'language': 'ဘာသာစကား',
      'theme': 'အပြင်အဆင်',
      'dark_mode': 'အမှောင်မိုဒ်',
      'light_mode': 'အလင်းမိုဒ်',
      'recently_viewed': 'မကြာသေးမီက ကြည့်ရှုခဲ့သည်',
      'recent': 'မကြာသေးမီ',
      'all': 'အားလုံး',
      'movies_count': 'ရုပ်ရှင်အရေအတွက်',
      'filter_by_genre': 'အမျိုးအစားအလိုက် စစ်ထုတ်ရန်',
      'filter_by_tag': 'တက်ဂ်အလိုက် စစ်ထုတ်ရန်',
      'filter_by_year': 'နှစ်အလိုက် စစ်ထုတ်ရန်',
      'view_detail': 'အသေးစိတ်ကြည့်ရန်',
      'more': 'ပိုမို',
      'categories': 'အမျိုးအစားများ',
      'adult_content': 'လူကြီးများအတွက်',
      'clear_history': 'မှတ်တမ်းရှင်းလင်းရန်',
      'no_history': 'ကြည့်ရှုမှုမှတ်တမ်း မရှိပါ',
      'about_app': 'အကြောင်း',
      'about': 'အကြောင်း',
      'version': 'ဗားရှင်း',
      'help_support': 'အကူအညီနှင့် ပံ့ပိုးမှု',
      'about_kmm': 'KMM အကြောင်း',
      'faq': 'မေးလေ့ရှိသော မေးခွန်းများ',
      'contact_us': 'ဆက်သွယ်ရန်',
      'app_version': 'App ဗားရှင်း',
      'troubleshooting': 'ပြဿနာဖြေရှင်းရန် အကြံပြုချက်များ',
      'features': 'အသွင်အပြင်များ',
      'credits': 'အသိအမှတ်ပြုမှုများ',
      'data_collection': 'ဒေတာ စုဆောင်းမှု',
      'data_usage': 'ဒေတာ အသုံးပြုမှု',
      'third_party_services': 'တတိယဦး ဝန်ဆောင်မှုများ',
      'data_security': 'ဒေတာ လုံခြုံရေး',
      'children_privacy': 'ကလေးများ၏ ကိုယ်ရေးအချက်အလက်',
      'changes_to_policy': 'မူဝါဒ ပြောင်းလဲမှုများ',
      'streaming': 'စထရင်းမင်း',
      'downloading': 'ဒေါင်းလုဒ်',
      'watchlist': 'ကြည့်ရန်စာရင်း',
      'bookmarks': 'သိမ်းဆည်းမှု',
      'register': 'မှတ်ပုံတင်ရန်',
      'admin_login': 'အက်ဒမင့် ဝင်ရောက်ရန်',
      'username': 'အသုံးပြုသူအမည်',
      'password': 'စကားဝှက်',
      'login': 'ဝင်ရောက်ရန်',
      'logout': 'ထွက်ရန်',
      'login_success': 'ဝင်ရောက်ပြီးပါပြီ',
      'login_failed': 'အသုံးပြုသူအမည် သို့မဟုတ် စကားဝှက် မှားယွင်းနေပါသည်',
      'register_success': 'မှတ်ပုံတင်ပြီးပါပြီ',
      'register_failed': 'အသုံးပြုသူအမည် ရှိပြီးသားဖြစ်ပါသည်',
      'privacy_policy': 'ကိုယ်ရေးအချက်အလက် မူဝါဒ',
      'about_cm_movies': 'KMM အကြောင်း',
      'download_toggle': 'Download ပြသရန်',
      'download_toggle_desc': 'Movie အသေးစိတ်တွင် Download ပြသလိုပါက ဖွင့်ပါ',
      'download_disabled_msg': 'Download Link များကို လက်ရှိ ပိတ်ထားပါသည်။ Download Settings တွင် ဖွင့်ပါ။',
      'vip_active': 'VIP ဝယ်ယူထားပါသည်',
      'vip_active_desc': 'KMM ကို ပံ့ပိုးကူညီမှုအတွက် ကျေးဇူးတင်ပါသည်',
      'vip_inactive': 'VIP မဝယ်ယူထားသေးပါ',
      'vip_inactive_desc': 'တို့ပြီး VIP ဝယ်ယူပါ — Download များ အသုံးပြုနိုင်ရန်',
      'vip_expires_on': 'သက်တမ်း: {date}',
      'vip_get_now': 'VIP ဝယ်ယူရန်',
      'search_history': 'လတ်တလော ရှာဖွေမှုများ',
      'search_history_clear_all': 'အားလုံး ဖျက်ရန်',
      'video_player': 'ဗီဒီယိုပလေယာ',
      'video_player_desc': 'ဗီဒီယိုပလေယာ ရွေးချယ်ရန်',
      'built_in_player': 'Built-in ပလေယာ',
      'external_player': 'External ပလေယာ (VLC/MX Player)',
      'select_video_player': 'ဗီဒီယိုပလေယာ ရွေးချယ်ရန်',
      'select_language': 'ဘာသာစကား ရွေးချယ်ရန်',
      'no_downloads': 'ဒေါင်းလုဒ် မရှိပါ',
      'genres_tags_collections': 'အမျိုးအစား/တက်ဂ်/စုစည်းမှု',
      'profile': 'ကိုယ်ရေးအချက်အလက်',
      'account_information': 'အကောင့် အချက်အလက်',
      'account_name': 'အသုံးပြုသူ အမည်',
      'account_active': 'အကောင့် စတင်ရက်',
      'change_password': 'စကားဝှက် ပြောင်းရန်',
      'old_password': 'ယခင် စကားဝှက်',
      'new_password': 'စကားဝှက်အသစ်',
      'confirm_new_password': 'စကားဝှက်အသစ် အတည်ပြုရန်',
      'password_changed': 'စကားဝှက် ပြောင်းလဲပြီးပါပြီ',
      'password_change_failed': 'ယခင် စကားဝှက် မှားယွင်းနေပါသည်',
      'k_drama': 'K Drama',
      'trending': 'လူကြိုက်များ',
      '4k_movies': '4K ရုပ်ရှင်များ',
      '4k_series': '4K ဇာတ်လမ်းတွဲများ',
      'animation': 'Animation',
      'anime': 'Anime',
      'bollywood': 'Bollywood',
      'donghua': 'Donghua',
      'c_drama': 'C Drama',
      'total_posts': 'စုစုပေါင်း',
      'filters': 'စစ်ထုတ်ရန်',
      'clear_filters': 'စစ်ထုတ်မှု ရှင်းလင်းရန်',
      'apply_filters': 'အသုံးပြုရန်',
      'sort_by': 'စီစဉ်ရန်',
      'sort_latest': 'နောက်ဆုံး',
      'sort_rating': 'ရမတ်',
      'sort_name': 'အမည်',
      'type_all': 'အားလုံး',
      'type_movie': 'ရုပ်ရှင်',
      'type_series': 'ဇာတ်လမ်းတွဲ',
      'min_rating': 'အနိမ့်ဆုံး ရမတ်',
      'results': 'ရလဒ်များ',
      'no_filters': 'စစ်ထုတ်မှု မရှိပါ',
      'active_filters': 'ရွေးချယ်ထားသော စစ်ထုတ်မှုများ',
      'watchlist': 'ကြည့်ရန်စာရင်း',
      'add_to_watchlist': 'ကြည့်ရန်စာရင်းသိမ်းရန်',
      'remove_from_watchlist': 'ကြည့်ရန်စာရင်းမှ ဖယ်ရှားရန်',
      'watchlist_added': 'ကြည့်ရန်စာရင်းသိမ်းပြီးပါပြီ',
      'watchlist_removed': 'ကြည့်ရန်စာရင်းမှ ဖယ်ရှားပြီးပါပြီ',
      'no_watchlist': 'ကြည့်ရန်စာရင်းတွင် အကြောင်းအရာ မရှိပါ',
      'download_manager': 'ဒေါင်းလုဒ် မန်နေဂျာ',
      'downloading': 'ဒေါင်းလုဒ်လုပ်နေသည်',
      'paused': 'ရပ်နားသည်',
      'completed': 'ပြီးမြောက်သည်',
      'failed': 'မအောင်မြင်ပါ',
      'pause': 'ရပ်ရန်',
      'resume': 'ဆက်လုပ်ရန်',
      'retry': 'ထပ်စမ်းကြည့်ပါ',
      'no_downloads_yet': 'ဒေါင်းလုဒ် မရှိသေးပါ',
      'active_downloads': 'လက်ရှိ ဒေါင်းလုဒ်များ',
      'completed_downloads': 'ပြီးမြောက်ပြီး ဒေါင်းလုဒ်များ',
      'clear_completed': 'ပြီးမြောက်မှုများ ရှင်းလင်းရန်',
      'age_gate_title': 'အသက်အရွယ် ကန့်သတ်ချက်',
      'age_gate_desc': 'ဤအကြောင်းအရာသည် 18+ အဆင့်သတ်မှတ်ထားပြီး လူကြီးများအတွက်သာ ဖြစ်ပါသည်။ သင့်အသက် 18 နှစ်နှင့်အထက်ဖြစ်ကြောင်း အတည်ပြုပါ။',
      'age_gate_confirm': '18 နှစ်နှင့်အထက်ဖြစ်ပါသည်',
      'age_gate_cancel': 'နောက်သို့ပြန်သွားရန်',
      'back': 'နောက်သို့',
      'press_back_again_exit': 'ထွက်ရန် နောက်တစ်ကြိမ်နိုပါ',
      'storage_permission_required': 'ဒေါင်းလုဒ်များကို အသုံးပြုရန် သိုလှောင်မှု ခွင့်ပြုချက် လိုအပ်ပါသည်',
      'confirm_password': 'စကားဝှက် အတည်ပြုရန်',
      'create_account': 'အကောင့်သစ် ဖွင့်ရန်',
      'already_have_account': 'အကောင့်ရှိပြီးသားလား?',
      'dont_have_account': 'အကောင့်မရှိသေးဘူးလား?',
      'sign_in': 'ဝင်ရောက်ရန်',
      'sign_up': 'မှတ်ပုံတင်ရန်',
      'login_and_register': 'ဝင်ရောက်ရန်နှင့် မှတ်ပုံတင်ရန်',
      'login_subtitle': 'သင့်အကောင့်သို့ ဝင်ရောက်ရန်',
      'register_subtitle': 'အကောင့်သစ်ဖွင့်ရန် အောက်ပါအချက်အလက်များ ဖြည့်စွက်ပါ',
      'enter_username': 'အသုံးပြုသူအမည် ထည့်ပါ',
      'enter_password': 'စကားဝှက် ထည့်ပါ',
      'username_min_length': 'အသုံးပြုသူအမည်သည် အနည်းဆုံး ၃ လုံး ရှိရပါမည်',
      'username_invalid_chars': 'အသုံးပြုသူအမည်တွင် @ သို့မဟုတ် ကွက်လပ် မပါရှိရပါ',
      'password_hint': '၈+ စာလုံး၊ အကြီး၊ အသေး၊ ဂဏန်း',
      'password_min_length': 'စကားဝှက်သည် အနည်းဆုံး ၈ လုံး ရှိရပါမည်',
      'password_uppercase': 'စကားဝှက်တွင် အကြီးစာလုံး အနည်းဆုံး တစ်လုံး ပါရပါမည်',
      'password_lowercase': 'စကားဝှက်တွင် အသေးစာလုံး အနည်းဆုံး တစ်လုံး ပါရပါမည်',
      'password_number': 'စကားဝှက်တွင် ဂဏန်း အနည်းဆုံး တစ်လုံး ပါရပါမည်',
      'confirm_password_empty': 'စကားဝှက် အတည်ပြုပါ',
      'passwords_no_match': 'စကားဝှက်များ မတူညီပါ',
      'too_many_attempts': 'ကြိုးစားမှုများစွာ မအောင်မြင်ပါ။ ကျေးဇူးပြု၍ {seconds}စက္ကန့် စောင့်ပါ။',
      'too_many_attempts_short': 'ကြိုးစားမှုများစွာ မအောင်မြင်ပါ။ {seconds}စက္ကန့် စောင့်ပါ။',
      'switch_language': 'ဘာသာစကား ပြောင်းရန်',
      'myanmar': 'မြန်မာ',
      'english': 'English',
      'privacy_policy_text': 'ကိုယ်ရေးအချက်အလက် မူဝါဒ\n\nKMM သည် သင့်ကိုယ်ရေးအချက်အလက်များကို ကာကွယ်ရန် ကတိကဝတ် ပြုထားပါသည်။ ဤ မူဝါဒသည် သင့်အချက်အလက်များကို မည်သို့ စုဆောင်း၊ အသုံးပြု၊ ကာကွယ်သည်ကို ရှင်းပြပါသည်။\n\nစုဆောင်းသော အချက်အလက်များ:\n- အကောင့်အချက်အလက် (အသုံးပြုသူအမည်၊ အီးမေးလ်) — Firebase Authentication မှ ဘေးကင်းစွာ သိမ်းဆည်း\n- သိမ်းဆည်းမှု၊ ကြည့်ရန်စာရင်း၊ ကြည့်ရှုမှတ်တမ်း — Firebase Firestore မှတဆင့် သင့်အကောင့်သို့ ချိတ်ဆက်\n- App ဆက်တင်နှင့် ကိုယ်ကြိုက်ဆန္ဒများ — သင့်စက်ပေါ်တွင် ဒေသန္တရအားဖြင့် သိမ်းဆည်း\n\nအချက်အလက် အသုံးပြုပုံ:\n- ဝန်ဆောင်မှုများ ပေးရန်နှင့် တိုးတက်စေရန်\n- သင့်သိမ်းဆည်းမှုနှင့် ကြည့်ရန်စာရင်းကို စက်အချင်းချင်း ချိတ်ဆက်ရန်\n- ကြည့်ရှုမှတ်တမ်းနှင့် ကိုယ်ကြိုက်ဆန္ဒများ ထိန်းသိမ်းရန်\n\nဒေတာ သိမ်းဆည်းမှု:\nသင့်အကောင့်ဒေတာ (သိမ်းဆည်းမှု၊ ကြည့်ရန်စာရင်း၊ ကြည့်ရှုမှတ်တမ်း) ကို Google Firebase Firestore ကလောင့်ဆာဗာများတွင် ဘေးကင်းစွာ သိမ်းဆည်းထားပြီး ဖြတ်သန်းရာတွင်လည်းကောင်း၊ သိမ်းဆည်းစဉ်လည်းကောင်း ဝှက်စာပြုလုပ်ထားပါသည်။ App ဆက်တင်များကို သင့်စက်ပေါ်တွင် ဒေသန္တရအားဖြင့် သိမ်းဆည်းပါသည်။ သင့်စကားဝှက်ကို မည်သောအခါမှ ရှင်းလင်းသောစာသားအဖြစ် မသိမ်းဆည်းပါ — Firebase Authentication က ဘေးကင်းစွာ စီမံခန့်ခွဲပါသည်။\n\nဒေတာ မျှဝေမှု:\nကျွန်တော်တို့သည် သင့်ကိုယ်ရေးအချက်အလက်ကို တတိယဦးများထံ ရောင်းချခြင်း သို့မဟုတ် မျှဝေခြင်း မပြုပါ။ သင့်ဒေတာကို သင်တစ်ဦးတည်းသာ ဝင်ရောက်ကြည့်ရှုနိုင်ပြီး Firebase လုံခြုံရေးစည်းမျဉ်းများဖြင့် ကာကွယ်ထားပါသည်။\n\nတတိယဦး ဝန်ဆောင်မှုများ:\nကျွန်တော်တို့ App သည် Google Firebase (Authentication, Firestore, Storage, App Check) ကို အသုံးပြုပါသည်။ Google ၏ ကိုယ်ရေးအချက်အလက် မူဝါဒကို ဖတ်ရှုရန် အကြံပြုပါသည်။\n\nသင့်အခွင့်အရေးများ:\n- သင့်အကောင့်နှင့် ဆက်စပ်ဒေတာအားလုံးကို သင့် Profile စာမျက်နှာမှ အချိန်မရွေး ဖျက်နိုင်ပါသည်\n- သင့်သိမ်းဆည်းမှုနှင့် ကြည့်ရန်စာရင်းကို ဒေသန္တရသို့ ထုတ်ယူနိုင်ပါသည်\n- ကလောင့်ချိတ်ဆက်မှုကို ရပ်နားရန် အချိန်မရွေး ထွက်နိုင်ပါသည်\n\nဆက်သွယ်ရန်:\nကိုယ်ရေးအချက်အလက် မူဝါဒအတွက် မေးခွန်းရှိပါက support@cmmovies.app သို့ ဆက်သွယ်ပါ။\n\nနောက်ဆုံး အသစ်ပြင်ဆင်ချက်: ၂၀၂၆',
      'about_cm_movies_text': 'KMM\n\nရုပ်ရှင်နှင့် ဇာတ်လမ်းတွဲများ ကြည့်ရှုရန် အကောင်းဆုံး App ဖြစ်ပါသည်။ ကမ္ဘာအနှံ့ရုပ်ရှင်နှင့် TV ဇာတ်လမ်းတွဲများကို ရှာဖွေ၊ ကြည့်ရှုနိုင်ပါသည်။\n\nအသွင်အပြင်များ:\n- လူကြိုက်များရုပ်ရှင်နှင့် TV ရှိုးများ ကြည့်ရှုရန်\n- ခေါင်းစဉ်၊ အမျိုးအစား၊ တက်ဂ်အလိုက် ရှာဖွေရန်\n- နှစ်သက်ရာများ သိမ်းဆည်းရန်\n- Download စီမံခန့်ခွဲရန်\n- ဘာသာစကား ၂ မျိုး ပံ့ပိုးမှု (မြန်မာ & English)\n- အမှောင်နှင့် အလင်း Theme\n\nဗားရှင်း 1.0.0\nရုပ်ရှင်ချစ်သူများအတွက် ချစ်ခြင်းမေတ္တာဖြင့် ဖန်တီးထားပါသည်။',
      'notifications': 'အကြောင်းကြားချက်များ',
      'downloads_notification': 'ဒေါင်းလုဒ် အကြောင်းကြားချက်',
      'downloads_notification_desc': 'ဒေါင်းလုဒ်တိုးတက်မှု အကြောင်းကြားချက် ပြသရန်',
      'push_notification': 'Push အကြောင်းကြားချက်',
      'push_notification_desc': 'အက်ဒမင်ထံမှ အကြောင်းကြားချက်များ လက်ခံရန်',
      'storage': 'သိုလှောင်မှု',
      'clear_cache': 'Cache ရှင်းလင်းရန်',
      'clear_cache_desc': 'ဓာတ်ပုံနှင့် ယာယီဒေတာများ ဖျက်ရန်',
      'cache_cleared': 'Cache ရှင်းလင်းပြီးပါပြီ',
    };
  }
}
