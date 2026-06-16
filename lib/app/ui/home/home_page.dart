import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_screen.dart';
import 'package:cm_movies/app/ui/screens/movies_page.dart';
import 'package:cm_movies/app/ui/screens/series_page.dart';
import 'package:cm_movies/app/ui/screens/recent_page.dart';
import 'package:cm_movies/app/ui/screens/genres_tags_collections_page.dart';
import 'package:cm_movies/app/ui/screens/download_page.dart';
import 'package:cm_movies/app/ui/screens/settings_page.dart';
import 'package:cm_movies/app/ui/screens/login_page.dart';
import 'package:cm_movies/app/ui/screens/profile_page.dart';
import 'package:cm_movies/app/ui/screens/search_screen.dart';
import 'package:cm_movies/app/ui/screens/admin_panel_page.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';
import 'package:cm_movies/app/ui/screens/tmdb_generator_page.dart';
import 'package:cm_movies/app/ui/components/download_notification_banner.dart';

// Bottom nav tab indices (4 tabs)
const int kHomeTab = 0;
const int kMoviesTab = 1;
const int kSeriesTab = 2;
const int kSettingsTab = 3;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = kHomeTab;

  // Global keys for tab pages to allow refresh
  final GlobalKey<State<MoviesPage>> _moviesKey = GlobalKey();
  final GlobalKey<State<SeriesPage>> _seriesKey = GlobalKey();

  // Tab pages - created once to preserve state across tab switches
  late final List<Widget> _bottomNavPages;

  // Double-back-to-exit: prevent accidental app exit from root route
  bool _canExit = false;
  Timer? _exitTimer;

  @override
  void initState() {
    super.initState();
    _bottomNavPages = [
      HomeScreen(onNavigateToTab: (index) {
        // Switch tab first
        setState(() => _currentIndex = index);
        // Trigger data refresh with skeleton loading when navigating via "More" button
        // This ensures skeleton shows first, then fresh data loads
        if (index == kMoviesTab) {
          // Use addPostFrameCallback to ensure the tab is visible before refreshing
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final state = _moviesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          });
        } else if (index == kSeriesTab) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final state = _seriesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          });
        }
      }),
      MoviesPage(key: _moviesKey),
      SeriesPage(key: _seriesKey),
      const SettingsPage(),
    ];
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    // Bottom Nav pages (4 main tabs: Home, Movies, Series, Settings)
    // Pages are created once in initState to preserve state across tab switches

    return PopScope(
      // Prevent accidental app exit: require double-back press
      canPop: _canExit,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_canExit) {
          // Second back press within 2 seconds → allow exit
          Navigator.of(context).pop();
        } else {
          // First back press → show toast and start 2-second window
          setState(() => _canExit = true);
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appConfig.translate('press_back_again_exit')),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFFE50914),
              behavior: SnackBarBehavior.floating,
            ),
          );
          _exitTimer?.cancel();
          _exitTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() => _canExit = false);
            }
          });
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          appConfig.translate('app_name'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: theme.colorScheme.onSurface),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SearchScreen()),
              );
            },
          ),
        ],
      ),
      drawer: _buildDrawer(appConfig, theme),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: _bottomNavPages,
          ),
          // Floating download progress indicator - shows when downloads are active
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DownloadMiniIndicator(
              downloadManager: DownloadManagerService.instance,
              onTap: () async {
                // Navigate to download page
                if (Platform.isAndroid) {
                  final hasPermission = await DownloadManagerService.instance.hasRuntimePermission();
                  if (!hasPermission) {
                    final granted = await DownloadManagerService.instance.requestRuntimePermission();
                    if (!granted) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(appConfig.translate('storage_permission_required')),
                            backgroundColor: Colors.redAccent,
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                      return;
                    }
                  }
                }
                if (mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DownloadPage()),
                  );
                }
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(appConfig, theme),
    ),
    );
  }

  Widget _buildBottomNav(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final unselectedColor = isDark ? Colors.grey.shade500 : Colors.grey.shade600;
    const selectedColor = Color(0xFFE50914);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : Colors.grey.shade300,
            blurRadius: 4,
            spreadRadius: 0,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
          indicatorColor: Colors.transparent,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          surfaceTintColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
            final isSelected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 24,
              color: isSelected ? selectedColor : unselectedColor,
            );
          }),
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? selectedColor : unselectedColor,
            );
          }),
        ),
        child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
          // Trigger data refresh when switching to Movies/Series tabs
          if (index == kMoviesTab) {
            final state = _moviesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          } else if (index == kSeriesTab) {
            final state = _seriesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: appConfig.translate('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.movie_outlined),
            selectedIcon: const Icon(Icons.movie),
            label: appConfig.translate('movies'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.tv_outlined),
            selectedIcon: const Icon(Icons.tv),
            label: appConfig.translate('series'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: appConfig.translate('settings'),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildDrawer(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final bgDrawer = isDark ? const Color(0xFF121212) : Colors.white;
    final bgHeader = isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100;

    return Drawer(
      backgroundColor: bgDrawer,
      child: DividerTheme(
        data: const DividerThemeData(color: Colors.transparent),
        child: SafeArea(
          child: Column(
            children: [
              // Drawer Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                decoration: BoxDecoration(
                  color: bgHeader,
                ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFE50914).withOpacity(0.15),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE50914).withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_circle_fill,
                      size: 40,
                      color: Color(0xFFE50914),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'KMM',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // Recent
                  _buildDrawerItem(
                    icon: Icons.history_outlined,
                    activeIcon: Icons.history,
                    title: appConfig.translate('recently_viewed'),
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const RecentPage()),
                      );
                    },
                  ),

                  // Genres/Tags/Collections
                  _buildDrawerItem(
                    icon: Icons.category_outlined,
                    activeIcon: Icons.category,
                    title: appConfig.translate('genres_tags_collections'),
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GenresTagsCollectionsPage()),
                      );
                    },
                  ),

                  // Downloads
                  _buildDrawerItem(
                    icon: Icons.download_outlined,
                    activeIcon: Icons.download,
                    title: appConfig.translate('downloads'),
                    isDark: isDark,
                    onTap: () async {
                      Navigator.pop(context); // Close drawer first

                      // Check if runtime storage permission has been granted
                      if (Platform.isAndroid) {
                        final downloadManager = DownloadManagerService.instance;
                        final hasPermission = await downloadManager.hasRuntimePermission();
                        if (!hasPermission) {
                          // Show native Android system permission dialog
                          final granted = await downloadManager.requestRuntimePermission();
                          if (!granted) {
                            // Permission denied — show message and don't navigate
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(appConfig.translate('storage_permission_required')),
                                  backgroundColor: Colors.redAccent,
                                  duration: const Duration(seconds: 3),
                                  action: SnackBarAction(
                                    label: appConfig.translate('settings'),
                                    textColor: Colors.white,
                                    onPressed: () => downloadManager.requestRuntimePermission(),
                                  ),
                                ),
                              );
                            }
                            return;
                          }
                        }
                      }

                      // Permission granted — navigate to Download page
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DownloadPage()),
                      );
                    },
                  ),

                  // Admin Panel (only for admin users)
                  if (appConfig.isCurrentUserAdmin) ...[
                    const SizedBox(height: 8),
                    _buildDrawerItem(
                      icon: Icons.admin_panel_settings_outlined,
                      activeIcon: Icons.admin_panel_settings,
                      title: 'Admin Panel',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const AdminPanelPage()),
                        );
                      },
                    ),
                    _buildDrawerItem(
                      icon: Icons.auto_awesome_outlined,
                      activeIcon: Icons.auto_awesome,
                      title: 'TMDB Generator',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TmdbGeneratorPage(),
                          ),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 8),

                  // Profile (if logged in)
                  if (appConfig.isLoggedIn)
                    _buildDrawerItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      title: appConfig.translate('profile'),
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ProfilePage()),
                        );
                      },
                    ),

                  // Login / Logout
                  if (appConfig.isLoggedIn)
                    _buildDrawerItem(
                      icon: Icons.logout,
                      activeIcon: Icons.logout,
                      title: appConfig.translate('logout'),
                      isDark: isDark,
                      onTap: () async {
                        Navigator.pop(context);
                        await appConfig.logoutUser();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(appConfig.translate('logout')),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        }
                      },
                    )
                  else
                    _buildDrawerItem(
                      icon: Icons.login,
                      activeIcon: Icons.login,
                      title: appConfig.translate('login'),
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                    ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'KMM v1.0.0',
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required IconData activeIcon,
    required String title,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isDark ? Colors.white70 : Colors.black54,
          size: 22,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 14,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        onTap: onTap,
      ),
    );
  }
}
