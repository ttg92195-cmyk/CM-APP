import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// Phase 3.2: firebase_app_check import REMOVED — package no longer in
// pubspec.yaml. App Check activation was disabled (sideloaded APK +
// Play Integrity incompatibility), so the package provides no benefit.
// Re-add the package + import only if Bro publishes to Play Store.
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_page.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';
import 'package:cm_movies/app/core/services/fcm_notification_service.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/login_page.dart';
import 'package:cm_movies/app/ui/screens/splash_screen.dart';
import 'package:cm_movies/app/ui/components/premium_snackbar.dart';
import 'firebase_options.dart';
// Phase 2.5: Crashlytics — crash + non-fatal error reporting.
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
// Task 32: flutter_localizations — gives us GlobalMaterialLocalizations,
// GlobalWidgetsLocalizations, GlobalCupertinoLocalizations for automatic
// locale-aware date/number formatting (DatePicker, TimePicker, etc.).
import 'package:flutter_localizations/flutter_localizations.dart';
// Task 33: Debug overflow detector — captures RenderFlex overflow errors
// in dev mode and surfaces them via debugPrint + SnackBar. No-op in release.
import 'package:cm_movies/app/core/services/debug_overflow_detector.dart';

// Task 33: Global scaffold-messenger key so the DebugOverflowDetector can
// show SnackBars from outside the widget tree (it has no BuildContext).
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

// Netflix-style Red accent color
const Color kNetflixRed = Color(0xFFE50914);
const Color kNetflixDarkRed = Color(0xFFB81D24);
const Color kDarkBg = Color(0xFF121212);
const Color kDarkSurface = Color(0xFF121212);
const Color kDarkCard = Color(0xFF1E1E1E);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Task 33: Install the dev-only overflow detector BEFORE installing the
  // global FlutterError.onError handler below. The detector saves the
  // previously-installed handler (here: the one we set on line ~48) and
  // forwards to it, so we get dedup + SnackBar + log layer ON TOP of the
  // existing log-and-dont-crash behavior. In release builds, install() is
  // a silent no-op (see debug_overflow_detector.dart).
  DebugOverflowDetector.instance.install(
    scaffoldMessengerKey: scaffoldMessengerKey,
  );

  // FIX: Global error handlers to prevent unhandled exceptions from crashing the app.
  // This is critical for the video player — media_kit's native engine can throw
  // errors that would otherwise kill the app process.
  //
  // Phase 2.5: forward all errors to Firebase Crashlytics so Bro can see them
  // in the Firebase Console → Crashlytics dashboard. Fatal errors (those that
  // propagate through FlutterError.onError AND terminate the app) are reported
  // via recordFlutterFatalError. Non-fatal errors (caught but reported) go
  // through recordFlutterError. Both include the full stack trace.
  FlutterError.onError = (FlutterErrorDetails details) {
    // Report to Crashlytics BEFORE presenting — if presentation itself throws,
    // Crashlytics still gets the original error.
    FirebaseCrashlytics.instance.recordFlutterError(details);
    // Log the error but don't crash
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrint('Stack: ${details.stack}');
    }
    // Don't rethrow — keep the app alive
  };

  // Catch any unhandled platform errors (e.g., from plugins)
  // Phase 2.5: also forward to Crashlytics so platform-channel exceptions
  // and plugin errors show up in the dashboard. Returns true to suppress
  // the default crash behavior.
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Platform error: $error');
    debugPrint('Stack: $stack');
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: false);
    return true; // Return true to prevent crash
  };

  runZonedGuarded(() async {
    // Initialize media_kit (libmpv/VLC engine) for video playback
    MediaKit.ensureInitialized();

    // Load environment variables before Firebase init
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      debugPrint('Warning: .env file not found. Firebase config may be missing.');
    }

    // Initialize Firebase with error handling
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Enable Firestore offline persistence to reduce Firebase reads
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      // Phase 2.5: Configure Crashlytics collection.
      // - Debug builds: collection DISABLED (avoid dashboard noise from
      //   local dev crashes; developer can re-enable per-session if needed).
      // - Release builds: collection ENABLED (real user crashes roll up
      //   to Firebase Console → Crashlytics dashboard for triage).
      // Tag the build mode + app version so the dashboard can filter by them.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      await FirebaseCrashlytics.instance
          .setCustomKey('build_mode', kDebugMode ? 'debug' : 'release');
      await FirebaseCrashlytics.instance
          .setCustomKey('app_version', const String.fromEnvironment(
              'APP_VERSION', defaultValue: 'unknown'));

      // Initialize OneSignal push notifications (free, no Cloud Functions needed).
      //
      // CRITICAL FIX (Phase 4.30, 2026-07-26):
      // Previously this used `await FcmNotificationService().initialize();`
      // BEFORE runApp(). On Oppo A16 (ColorOS 11) and other Chinese OEM
      // Android variants, OneSignal.Notifications.requestPermission(true)
      // hangs indefinitely when notification permission is DENIED at the
      // system level — ColorOS's custom permission UI does not respond the
      // way stock Android 13+ does. Because this `await` sat before
      // runApp(), the entire app startup was blocked → user saw a permanent
      // WHITE SCREEN until they manually re-enabled notifications.
      //
      // Fix: Fire the OneSignal init as a non-blocking future. runApp()
      // proceeds immediately and the splash screen renders normally even
      // if OneSignal hangs. The FCM service itself also has an internal
      // timeout on requestPermission() as a second safety net.
      unawaited(_initNotificationsSafely());
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
      // Firebase failed to init — record the error so Bro sees it in the
      // dashboard. recordError is safe to call even before
      // setCrashlyticsCollectionEnabled (it just queues the report until
      // next launch if collection is disabled).
      FirebaseCrashlytics.instance
          .recordError(e, StackTrace.current, reason: 'Firebase init failure');
    }

    // ====================================================================
    // Phase 3.2 — App Check activation DISABLED (2026-06-29)
    // ====================================================================
    // Bro reported that after Phase 2.8, BOTH signup and login stopped
    // working on the sideloaded APK — signup shows "Username already
    // exists" and login shows "Invalid username or password" even with
    // correct credentials.
    //
    // Root cause analysis: The App Check activation code below tries to
    // use Play Integrity provider in release builds. For sideloaded APKs
    // (not installed from Play Store), Play Integrity CANNOT issue a
    // valid token. Even though `activate()` itself doesn't throw, when
    // Firebase Auth subsequently requests an App Check token for sign-in
    // requests, the token exchange fails. If Firebase Auth has App Check
    // enforcement enabled at the project level (Firebase Console →
    // Authentication → Settings → App Check), the request is rejected —
    // producing the generic auth failures Bro is seeing.
    //
    // This is consistent with the Phase 2.1 decision to REVERT App Check
    // enforcement in Firestore rules (also because of sideloaded APK
    // incompatibility). Since enforcement is OFF, activation provides no
    // security benefit — it only adds a failure point. Disabling it
    // aligns the codebase with the Phase 2.1 decision.
    //
    // The activation code is preserved below (commented out) so it can
    // be re-enabled if Bro ever publishes to Play Store (where Play
    // Integrity works correctly).
    // ====================================================================
    //
    // // Initialize Firebase App Check.
    // //
    // // Task 43.4: previous code always fell back to AndroidProvider.debug
    // // when Play Integrity failed — including in PRODUCTION builds. That
    // // leaked the debug token into release APKs, where it can be extracted
    // // and used to bypass App Check enforcement. Now we gate by
    // // kReleaseMode:
    // //   - Release builds: Play Integrity ONLY. If it fails, log the error
    // //     and continue without App Check (better than leaking debug).
    // //   - Debug builds (dev): allow debug fallback so local dev still
    // //     works without a Play Integrity setup.
    // if (kReleaseMode) {
    //   // Production — Play Integrity only, NO debug fallback.
    //   try {
    //     await FirebaseAppCheck.instance.activate(
    //       androidProvider: AndroidProvider.playIntegrity,
    //       appleProvider: AppleProvider.deviceCheck,
    //     );
    //     debugPrint('App Check activated: Play Integrity (release)');
    //   } catch (e) {
    //     // Do NOT fall back to debug in release. Surface the error so we
    //     // notice during release-channel testing.
    //     debugPrint('App Check Play Integrity failed in RELEASE mode — '
    //         'NOT falling back to debug. Error: $e');
    //   }
    // } else {
    //   // Debug build — try Play Integrity first, fall back to debug so
    //   // local dev doesn't require a real device with Play Integrity.
    //   try {
    //     await FirebaseAppCheck.instance.activate(
    //       androidProvider: AndroidProvider.playIntegrity,
    //       appleProvider: AppleProvider.deviceCheck,
    //     );
    //     debugPrint('App Check activated: Play Integrity (debug build)');
    //   } catch (e) {
    //     debugPrint('App Check Play Integrity failed in debug build, '
    //         'falling back to debug provider: $e');
    //     try {
    //       await FirebaseAppCheck.instance.activate(
    //         androidProvider: AndroidProvider.debug,
    //       );
    //       debugPrint('App Check activated: Debug mode (debug build only)');
    //     } catch (e2) {
    //       debugPrint('App Check activation error: $e2');
    //     }
    //   }
    // }
    debugPrint('Phase 3.2: App Check activation DISABLED (sideloaded APK + no enforcement)');

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    runApp(
      ChangeNotifierProvider(
        create: (_) => AppConfig(),
        child: const CMMoviesApp(),
      ),
    );
  }, (error, stackTrace) {
    // Catch any unhandled async errors — prevent app crash
    debugPrint('Unhandled async error: $error');
    debugPrint('Stack trace: $stackTrace');
    // Phase 2.5: forward unhandled async errors to Crashlytics. These are
    // typically the most severe (e.g., uncaught Future errors that would
    // have crashed the app if runZonedGuarded weren't installed).
    FirebaseCrashlytics.instance
        .recordError(error, stackTrace, fatal: true);
    // Don't rethrow — keep the app alive
  });
}

/// Phase 4.30 — Initialize OneSignal/Firebase Messaging in the background
/// AFTER runApp() has been called. This is intentionally fire-and-forget:
/// the app's UI must never be blocked by notification permission flows.
///
/// Why this exists: On Oppo A16 / ColorOS 11 (and several other Chinese
/// OEM Android variants), OneSignal's `requestPermission(true)` can hang
/// indefinitely when notifications are disabled at the system level. If
/// this were awaited inside main() before runApp(), the user would see a
/// permanent white screen. By running it as a detached future, the splash
/// screen renders immediately and OneSignal either completes in the
/// background or times out (see FcmNotificationService for the timeout).
Future<void> _initNotificationsSafely() async {
  try {
    await FcmNotificationService().initialize();
  } catch (e) {
    debugPrint('OneSignal initialization error: $e');
    try {
      FirebaseCrashlytics.instance.recordError(
        e,
        StackTrace.current,
        reason: 'OneSignal init failure (non-blocking)',
        fatal: false,
      );
    } catch (_) {
      // Crashlytics itself may not be ready — ignore.
    }
  }
}

class CMMoviesApp extends StatefulWidget {
  const CMMoviesApp({super.key});

  @override
  State<CMMoviesApp> createState() => _CMMoviesAppState();
}

class _CMMoviesAppState extends State<CMMoviesApp> with WidgetsBindingObserver {
  // Splash: minimum display time before dismissing
  bool _minSplashElapsed = false;

  // Feature 1: Internet connection state
  bool _hasInternet = true;
  bool _checkingInternet = false;

  // Real-time connectivity monitor
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Feature 2: Force update state
  bool _forceUpdate = false;
  bool _forceUpdateDialogShown = false;
  String _latestVersion = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start minimum splash delay (3 seconds)
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _minSplashElapsed = true);
        // After splash, check internet and updates
        _checkInternet();
      }
    });

    // Real-time internet monitoring: listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _onConnectivityChanged(results);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  /// Handle connectivity changes in real-time
  /// Shows "No Internet" screen immediately when connection is lost,
  /// and auto-refreshes when connection is restored
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasConnection = results.any((r) => r != ConnectivityResult.none);

    if (!hasConnection && _hasInternet) {
      // Internet just went down — show No Internet screen
      if (mounted) {
        setState(() => _hasInternet = false);
      }
    } else if (hasConnection && !_hasInternet) {
      // Internet just came back — auto-refresh
      if (mounted) {
        setState(() {
          _hasInternet = true;
          _checkingInternet = false;
        });
        // Check for updates now that we have internet
        _checkForUpdate();
      }
    }
  }

  /// Whether splash screen should still be shown.
  /// True if auth is still loading OR minimum splash time hasn't elapsed.
  bool get _showSplash => !_minSplashElapsed;

  // Feature 1: Check internet connection using DNS lookup
  Future<void> _checkInternet() async {
    if (_checkingInternet) return;
    setState(() => _checkingInternet = true);
    try {
      final result = await InternetAddress.lookup('google.com');
      final hasConnection = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted) {
        setState(() {
          _hasInternet = hasConnection;
          _checkingInternet = false;
        });
        // If we have internet, check for force update
        if (hasConnection) {
          _checkForUpdate();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasInternet = false;
          _checkingInternet = false;
        });
      }
    }
  }

  // Feature 2: Check for force update from Firestore config
  Future<void> _checkForUpdate() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc('app_version')
          .get();
      if (!doc.exists) return;
      final data = doc.data()!;
      _latestVersion = data['latestVersion'] as String? ?? '';
      final forceUpdate = data['forceUpdate'] as bool? ?? false;

      if (_latestVersion.isNotEmpty && forceUpdate) {
        const currentVersion = '2.0.0';
        if (_isNewerVersion(_latestVersion, currentVersion)) {
          if (mounted) {
            setState(() => _forceUpdate = true);
          }
        }
      }
    } catch (e) {
      debugPrint('Version check error: $e');
    }
  }

  // Feature 2: Compare version strings (e.g. "2.0.0" > "1.9.0")
  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
      return false;
    } catch (e) {
      debugPrint('Version comparison error: $e');
      return false;
    }
  }

  // Feature 2: Show non-dismissible force update dialog
  void _showForceUpdateDialog() {
    showDialog(
      context: navigatorKey.currentContext ?? context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: kDarkCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.system_update, color: kNetflixRed, size: 28),
              const SizedBox(width: 12),
              Text(
                'Update Required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            'A new version ($_latestVersion) is available. Please update to continue using the app.',
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kNetflixRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  // Try to open Play Store, fallback to a message.
                  // Task 43.5: package id was wrong — real applicationId is
                  // than.pre.cm (see android/app/build.gradle:55). The old
                  // 'com.cm.movies' value opened a non-existent Play Store
                  // listing, so the Update button was effectively broken.
                  final uri = Uri.parse(
                    'https://play.google.com/store/apps/details?id=than.pre.cm',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Please update the app manually.'),
                          backgroundColor: kNetflixRed,
                        ),
                      );
                    }
                  }
                },
                child: const Text(
                  'Update',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Feature 1: Build "No Internet" dark page
  Widget _buildNoInternetPage() {
    return Scaffold(
      backgroundColor: kDarkBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kNetflixRed.withOpacity(0.15),
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 64,
                  color: kNetflixRed,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'No Internet Connection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Please check your internet connection and try again.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kNetflixRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _checkingInternet ? null : () => _checkInternet(),
                  child: _checkingInternet
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Retry',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // L3: Track app lifecycle for session timeout
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        // Recover orphaned downloads (stuck in "downloading" after app was in background)
        DownloadManagerService.instance.recoverOrphanedDownloads();

        // App came back to foreground — check session timeout
        final appConfig = Provider.of<AppConfig>(context, listen: false);
        if (appConfig.isLoggedIn && appConfig.checkSessionTimeout()) {
          // Session timed out while app was in background
          // Only show SnackBar if still mounted (prevents crash)
          if (mounted) {
            // Phase 4.35: Premium styled SnackBar replaces the old plain
            // orange bar. Uses warning amber accent (rather than brand
            // red) to distinguish "session expired" from "user logged out".
            final isMy = appConfig.languageCode == 'my';
            ScaffoldMessenger.of(context).showSnackBar(
              PremiumSnackBar(
                context: context,
                icon: Icons.timer_off_rounded,
                title: isMy
                    ? 'ဆက်ရှင် ကုန်သွားပါပြီ'
                    : 'Session expired',
                subtitle: isMy
                    ? 'မအောင်မြင်ခဲ့ပါ။ ပြန်လည် login ၀င်ပါ။'
                    : 'Please login again to continue.',
                accentColor: const Color(0xFFFFB300), // amber warning
                duration: const Duration(seconds: 4),
              ).build(),
            );
          }
        } else {
          appConfig.recordActivity();
        }
      } catch (e) {
        debugPrint('App resume lifecycle error: $e');
        // Don't crash — just continue normally
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);

    // Feature 2: If force update required, show dialog after frame builds
    if (_forceUpdate && !_forceUpdateDialogShown) {
      _forceUpdateDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showForceUpdateDialog();
      });
    }

    // IMPORTANT: We use a Listener (NOT GestureDetector) at the root so that
    // activity tracking observes pointer events WITHOUT participating in the
    // gesture arena. A GestureDetector with both onTap + onPanDown at the
    // root would force the arena to disambiguate tap-vs-pan on every touch,
    // which competes with the internal drag recognizer used by EditableText's
    // text-selection handles — causing the "selection handle drag lock" bug
    // (handles visible but cannot be dragged to extend/reduce selection) on
    // every TextField / TextFormField / SelectableText in the entire app.
    //
    // Listener simply observes raw pointer events; it never claims gestures,
    // so selection handles, scrolls, taps, and all other interactions work
    // normally while we still get an activity tick on every user touch.
    return Listener(
      // L3: Record activity on any user pointer-down to keep session alive.
      // Every user interaction (tap, drag, scroll, selection-handle drag,
      // long-press, etc.) starts with a pointer-down event, so this single
      // callback covers all interaction types without interfering with them.
      onPointerDown: (_) => appConfig.recordActivity(),
      onPointerMove: (_) => appConfig.recordActivity(),
      child: MaterialApp(
        title: 'KMM',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        // Task 33: scaffoldMessengerKey so DebugOverflowDetector can show
        // SnackBars from outside the widget tree (it has no BuildContext).
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: appConfig.themeMode,
        // Task 32: Localization — wire up flutter_localizations so that
        // Material/Cupertino widgets (DatePicker, AlertDialog buttons, etc.)
        // are translated automatically based on the user's language choice.
        // The app's own translations are still loaded from assets/lang/*.json
        // via LocalizationService, but these delegates fill in the platform
        // widgets we don't translate ourselves.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('my'),
        ],
        locale: Locale(appConfig.languageCode),
        // Named routes for notification tap navigation
        routes: {
          '/movie-detail': (context) {
            final slug = ModalRoute.of(context)?.settings.arguments as String? ?? '';
            return MovieDetailScreen(slug: slug);
          },
        },
        // Auth gate: show LoginPage if not logged in, HomePage if logged in
        // This ensures Firestore reads only happen after authentication
        // Splash is shown until both: auth loads AND minimum 3s elapsed
        // Feature 1: No internet page shown when !_hasInternet
        home: !_hasInternet
            ? _buildNoInternetPage()
            : (_showSplash || appConfig.isLoadingAuth)
                ? _buildSplashScreen(isDark: appConfig.isDarkMode)
                : appConfig.isLoggedIn
                    ? const HomePage()
                    : const LoginPage(),
      ),
    );
  }

  Widget _buildSplashScreen({required bool isDark}) {
    // Phase 4.34: Premium animated splash screen.
    // Phase 4.40: Theme-aware — splash variant matches the app's current
    // theme mode. Dark Mode gets the cinematic dark splash (Netflix/Disney+
    // tier, preserved from Phase 4.34). Light Mode gets a new clean/
    // airy variant (premium stationery feel — Apple Notes / Linear / Notion
    // light mode). Bro's exact brief: "Dark Mode သုံးထားရင် ... ဖန်တီးထား
    // ပြီးသားဖြစ်တယ် ... Light Mode သုံးထားရင် ... အဖြူသီသန့် splash screen က
    // ဖန်တီးရနိုင်မလာမသိပါဘူ".
    //
    // We pass `isDark: appConfig.isDarkMode` from the parent build() (which
    // already has appConfig via Provider.of) so the SplashScreen can pick
    // the right variant. Reading appConfig.isDarkMode in the parent rather
    // than inside the SplashScreen widget keeps the SplashScreen widget
    // pure and testable, and matches how the rest of the app reads theme
    // state.
    return SplashScreen(isDark: isDark);
  }

  ThemeData _buildDarkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      // Task 32: Myanmar-aware text theme.
      //
      // Bro's UI/UX concern: Myanmar text is taller than English and uses
      // combining marks (stacked diacritics) that often get clipped when
      // line-height is too tight. Two mitigations here:
      //
      // 1. fontFamilyFallback: ['Noto Sans Myanmar', 'Padauk']
      //    On Android, both fonts are typically pre-installed at the system
      //    level (Noto Sans Myanmar ships with every Android 7+ device via
      //    the system font stack). On devices that don't have them, Flutter
      //    falls back to Roboto, which still has Myanmar glyph coverage via
      //    its bundled Noto fallback.
      //
      // 2. height: 1.3 (line-height multiplier)
      //    Gives Myanmar stacked diacritics breathing room. For English
      //    text this is slightly loose but doesn't look weird — it's a
      //    safe default that works for both scripts.
      //
      // 3. fontSize base untouched — Material 3 defaults are fine.
      //    We rely on maxLines + overflow rules in individual widgets to
      //    handle text-overflow (Phase 2 work, separate task).
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: kNetflixRed,
        brightness: Brightness.dark,
        primary: kNetflixRed,
        onPrimary: Colors.white,
        secondary: kNetflixDarkRed,
        onSecondary: Colors.white,
        surface: kDarkSurface,
        onSurface: Colors.white,
        surfaceContainerHighest: const Color(0xFF1A1A2E),
        error: Colors.redAccent,
        onError: Colors.white,
        outline: Colors.white24,
        outlineVariant: Colors.white12,
        primaryContainer: const Color(0xFF4A0E14),
        onPrimaryContainer: Colors.red.shade200,
        secondaryContainer: const Color(0xFF3A0A10),
        onSecondaryContainer: Colors.red.shade200,
      ),
      scaffoldBackgroundColor: kDarkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: kDarkSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      // Task 38 Req 1: surfaceTintColor MUST be transparent for Cards.
      // In Material 3, an elevated Card receives a "surface tint" overlay
      // equal to colorScheme.primary (kNetflixRed) at ~3% opacity per
      // elevation level. Without this override, every Card in dark mode
      // gets a faint red tint over its surface — and because the Admin
      // Panel post list, Download list, Profile cards, etc. all sit
      // inside Card widgets, Bro reported this as "posters look dull /
      // incorrect in Dark Mode". The poster thumbnails inside those
      // Cards appeared to take on a reddish cast from the Card surface
      // behind them. Setting surfaceTintColor: Colors.transparent kills
      // the tint while keeping the elevation shadow. (The AppBar theme
      // already does this at line 692 — we're now extending the same
      // pattern to Card.)
      cardTheme: CardTheme(
        color: kDarkCard,
        elevation: 2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: kDarkSurface,
        indicatorColor: kNetflixRed.withOpacity(0.15),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF2A2A2A),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      tabBarTheme: const TabBarTheme(
        labelColor: kNetflixRed,
        unselectedLabelColor: Colors.grey,
        indicatorColor: kNetflixRed,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: kDarkCard,
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: kDarkCard,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return kNetflixRed;
          }
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return kNetflixRed.withOpacity(0.4);
          }
          return Colors.grey.withOpacity(0.3);
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: kNetflixRed.withOpacity(0.15),
        foregroundColor: kNetflixRed,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kNetflixRed,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kNetflixRed,
          side: const BorderSide(color: kNetflixRed),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kNetflixRed,
        ),
      ),
      // Phase 4.47 — Make every IconButton's ripple + (optional) background
      // a true CIRCLE instead of the Material 3 default stadium (pill).
      // This applies app-wide so AppBar back-buttons, AppBar action icons,
      // suffixIcon toggles, list-row edit/delete buttons, video-player
      // controls — ALL get the same circular ripple shape without any
      // call-site changes. Background tint (when set via styleFrom) also
      // becomes circular.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A1A2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kNetflixRed.withOpacity(0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kNetflixRed, width: 1.5),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white12,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Colors.white,
        iconColor: Colors.white70,
      ),
    );
  }

  ThemeData _buildLightTheme() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      // Task 32: Myanmar-aware text theme (mirror of dark theme).
      // See _buildDarkTheme for the full rationale.
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          height: 1.3,
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontFamilyFallback: const ['Noto Sans Myanmar', 'Padauk'],
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: kNetflixRed,
        brightness: Brightness.light,
        primary: kNetflixRed,
        onPrimary: Colors.white,
        secondary: kNetflixDarkRed,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black87,
        surfaceContainerHighest: Colors.grey.shade100,
        error: Colors.redAccent,
        onError: Colors.white,
        outline: Colors.grey.shade400,
        outlineVariant: Colors.grey.shade300,
        primaryContainer: const Color(0xFFFFDAD6),
        onPrimaryContainer: const Color(0xFF410001),
        secondaryContainer: const Color(0xFFFFDAD6),
        onSecondaryContainer: const Color(0xFF410001),
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      // Task 38 Req 1: surfaceTintColor transparent for light Cards too
      // (parity with the dark theme — see comment in _buildDarkTheme).
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: kNetflixRed.withOpacity(0.12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey.shade200,
        labelStyle: const TextStyle(color: Colors.black87, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      tabBarTheme: const TabBarTheme(
        labelColor: kNetflixRed,
        unselectedLabelColor: Colors.grey,
        indicatorColor: kNetflixRed,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: Colors.white,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return kNetflixRed;
          }
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return kNetflixRed.withOpacity(0.4);
          }
          return Colors.grey.withOpacity(0.3);
        }),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kNetflixRed,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kNetflixRed,
          side: const BorderSide(color: kNetflixRed),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kNetflixRed,
        ),
      ),
      // Phase 4.47 — Same circular ripple for IconButtons in Light Mode.
      // See the dark theme block above for full rationale.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: const CircleBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade100,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kNetflixRed, width: 1.5),
        ),
        labelStyle: TextStyle(color: Colors.grey.shade700),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade200,
      ),
      listTileTheme: const ListTileThemeData(
        textColor: Colors.black87,
        iconColor: Colors.black54,
      ),
    );
  }
}
