import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_page.dart';

// Netflix-style Red accent color
const Color kNetflixRed = Color(0xFFE50914);
const Color kNetflixDarkRed = Color(0xFFB81D24);
const Color kDarkBg = Color(0xFF0A0A0A);
const Color kDarkSurface = Color(0xFF121212);
const Color kDarkCard = Color(0xFF1E1E1E);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      title: 'CM Movies',
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
        secondary: kNetflixDarkRed,
        surface: kDarkSurface,
        onSurface: Colors.white,
        primaryContainer: const Color(0xFF4A0E14),
        onPrimaryContainer: Colors.red.shade200,
        secondaryContainer: const Color(0xFF3A0A10),
        onSecondaryContainer: Colors.red.shade200,
        surfaceContainerHighest: const Color(0xFF1A1A2E),
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
        secondary: kNetflixDarkRed,
        surface: Colors.white,
        onSurface: Colors.black87,
        primaryContainer: const Color(0xFFFFDAD6),
        onPrimaryContainer: const Color(0xFF410001),
        secondaryContainer: const Color(0xFFFFDAD6),
        onSecondaryContainer: const Color(0xFF410001),
        surfaceContainerHighest: Colors.grey.shade100,
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
