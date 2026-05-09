import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_screen.dart';
import 'package:cm_movies/app/ui/screens/movies_page.dart';
import 'package:cm_movies/app/ui/screens/series_page.dart';
import 'package:cm_movies/app/ui/screens/recent_page.dart';
import 'package:cm_movies/app/ui/screens/movie_bookmark_screen.dart';
import 'package:cm_movies/app/ui/screens/genres_tags_collections_page.dart';
import 'package:cm_movies/app/ui/screens/download_page.dart';
import 'package:cm_movies/app/ui/screens/settings_page.dart';
import 'package:cm_movies/app/ui/screens/login_page.dart';
import 'package:cm_movies/app/ui/screens/profile_page.dart';
import 'package:cm_movies/app/ui/screens/search_screen.dart';
import 'package:cm_movies/app/ui/screens/admin_panel_page.dart';
import 'package:cm_movies/app/ui/screens/watchlist_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    // Bottom Nav pages (4 main tabs: Home, Movies, Series, Settings)
    final List<Widget> bottomNavPages = [
      HomeScreen(onNavigateToTab: (index) {
        setState(() => _currentIndex = index);
      }),
      MoviesPage(key: _moviesKey),
      SeriesPage(key: _seriesKey),
      const SettingsPage(),
    ];

    return Scaffold(
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
      body: IndexedStack(
        index: _currentIndex,
        children: bottomNavPages,
      ),
      bottomNavigationBar: _buildBottomNav(appConfig, theme),
    );
  }

  Widget _buildBottomNav(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE50914).withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        indicatorColor: const Color(0xFFE50914).withOpacity(0.12),
        height: 64,
        destinations: [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: isDark ? Colors.grey : Colors.grey.shade600),
            selectedIcon: const Icon(Icons.home, color: Color(0xFFE50914)),
            label: appConfig.translate('home'),
          ),
          NavigationDestination(
            icon: Icon(Icons.movie_outlined, color: isDark ? Colors.grey : Colors.grey.shade600),
            selectedIcon: const Icon(Icons.movie, color: Color(0xFFE50914)),
            label: appConfig.translate('movies'),
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined, color: isDark ? Colors.grey : Colors.grey.shade600),
            selectedIcon: const Icon(Icons.tv, color: Color(0xFFE50914)),
            label: appConfig.translate('series'),
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined, color: isDark ? Colors.grey : Colors.grey.shade600),
            selectedIcon: const Icon(Icons.settings, color: Color(0xFFE50914)),
            label: appConfig.translate('settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;
    final bgDrawer = isDark ? const Color(0xFF121212) : Colors.white;
    final bgHeader = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;

    return Drawer(
      backgroundColor: bgDrawer,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: BoxDecoration(
                color: bgHeader,
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFFE50914).withOpacity(0.3),
                    width: 1,
                  ),
                ),
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
                    'CM Movies',
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
                  // Bookmark
                  _buildDrawerItem(
                    icon: Icons.bookmark_outline,
                    activeIcon: Icons.bookmark,
                    title: appConfig.translate('bookmarks'),
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const MovieBookmarkScreen()),
                      );
                    },
                  ),

                  // Watchlist
                  _buildDrawerItem(
                    icon: Icons.watch_later_outlined,
                    activeIcon: Icons.watch_later,
                    title: appConfig.translate('watchlist'),
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WatchlistScreen()),
                      );
                    },
                  ),

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
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DownloadPage()),
                      );
                    },
                  ),

                  // Admin Panel (only for admin users)
                  if (appConfig.isCurrentUserAdmin) ...[
                    const Divider(height: 24),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('TMDB Generator - Coming Soon!'),
                            backgroundColor: Color(0xFFE50914),
                          ),
                        );
                      },
                    ),
                  ],

                  const Divider(height: 24),

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
                'CM Movies v1.0.0',
                style: TextStyle(
                  color: subTextColor,
                  fontSize: 11,
                ),
              ),
            ),
          ],
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
          side: BorderSide(
            color: const Color(0xFFE50914).withOpacity(0.1),
            width: 1,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
