import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_page.dart';
import 'firebase_options.dart';

// Netflix-style Red accent color
const Color kNetflixRed = Color(0xFFE50914);
const Color kNetflixDarkRed = Color(0xFFB81D24);
const Color kDarkBg = Color(0xFF0A0A0A);
const Color kDarkSurface = Color(0xFF121212);
const Color kDarkCard = Color(0xFF1E1E1E);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables before Firebase init
  // If .env doesn't exist (e.g., during testing), try to load anyway but don't crash
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // .env file not found - Firebase will use empty strings
    // This should only happen during development/testing
    debugPrint('Warning: .env file not found. Firebase config may be missing.');
  }

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase App Check for security - prevents unauthorized API access
  // from outside the app (e.g., scripts, other apps)
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.playIntegrity,
  );

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
}

class CMMoviesApp extends StatelessWidget {
  const CMMoviesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);

    return MaterialApp(
      title: 'KMM',
      debugShowCheckedModeBanner: false,
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: appConfig.themeMode,
      home: const HomePage(),
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
