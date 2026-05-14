import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:media_kit/media_kit.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_page.dart';
import 'package:cm_movies/app/ui/screens/login_page.dart';
import 'firebase_options.dart';

// Netflix-style Red accent color
const Color kNetflixRed = Color(0xFFE50914);
const Color kNetflixDarkRed = Color(0xFFB81D24);
const Color kDarkBg = Color(0xFF121212);
const Color kDarkSurface = Color(0xFF121212);
const Color kDarkCard = Color(0xFF1E1E1E);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // FIX: Global error handlers to prevent unhandled exceptions from crashing the app.
  // This is critical for the video player — media_kit's native engine can throw
  // errors that would otherwise kill the app process.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
    // Don't rethrow — keep the app alive
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
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
    }

    // Initialize Firebase App Check — use Debug provider always for now
    // because Play Integrity requires SHA-256 fingerprint registration
    // in Firebase Console (not yet set up).
    // TODO: Switch to Play Integrity when SHA-256 is registered
    try {
      await FirebaseAppCheck.instance.activate(
        androidProvider: AndroidProvider.debug,
      );
    } catch (e) {
      debugPrint('App Check activation error: $e');
    }

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
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
    // Don't rethrow — keep the app alive
  });
}

class CMMoviesApp extends StatefulWidget {
  const CMMoviesApp({super.key});

  @override
  State<CMMoviesApp> createState() => _CMMoviesAppState();
}

class _CMMoviesAppState extends State<CMMoviesApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // L3: Track app lifecycle for session timeout
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        // App came back to foreground — check session timeout
        final appConfig = Provider.of<AppConfig>(context, listen: false);
        if (appConfig.isLoggedIn && appConfig.checkSessionTimeout()) {
          // Session timed out while app was in background
          // Only show SnackBar if still mounted (prevents crash)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Session expired due to inactivity. Please login again.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
              ),
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

    return GestureDetector(
      // L3: Record activity on any user tap to keep session alive
      onTap: () => appConfig.recordActivity(),
      onPanDown: (_) => appConfig.recordActivity(),
      child: MaterialApp(
        title: 'KMM',
        debugShowCheckedModeBanner: false,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: appConfig.themeMode,
        // Auth gate: show LoginPage if not logged in, HomePage if logged in
        // This ensures Firestore reads only happen after authentication
        home: appConfig.isLoadingAuth
            ? _buildSplashScreen(appConfig)
            : appConfig.isLoggedIn
                ? const HomePage()
                : const LoginPage(),
      ),
    );
  }

  Widget _buildSplashScreen(AppConfig appConfig) {
    return Scaffold(
      backgroundColor: kDarkBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE50914).withOpacity(0.15),
              ),
              child: const Icon(
                Icons.play_circle_fill,
                size: 60,
                color: Color(0xFFE50914),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'KMM',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(
              color: Color(0xFFE50914),
            ),
          ],
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
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
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      cardTheme: CardTheme(
        color: kDarkCard,
        elevation: 2,
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
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 2,
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
