import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_screen.dart';
import 'package:cm_movies/app/ui/screens/movies_page.dart';
import 'package:cm_movies/app/ui/screens/series_page.dart';
import 'package:cm_movies/app/ui/screens/movie_bookmark_screen.dart';
import 'package:cm_movies/app/ui/screens/genres_tags_collections_page.dart';
import 'package:cm_movies/app/ui/screens/download_page.dart';
import 'package:cm_movies/app/ui/screens/settings_page.dart';
import 'package:cm_movies/app/ui/screens/register_page.dart';
import 'package:cm_movies/app/ui/screens/search_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  // Bottom Nav pages (5 tabs)
  final List<Widget> _bottomNavPages = const [
    HomeScreen(),
    MoviesPage(),
    SeriesPage(),
    MovieBookmarkScreen(),
    SettingsPage(),
  ];

  // All menu pages for drawer navigation
  final List<Widget> _allPages = const [
    HomeScreen(),         // 0
    MoviesPage(),         // 1
    SeriesPage(),         // 2
    MovieBookmarkScreen(), // 3
    GenresTagsCollectionsPage(), // 4
    DownloadPage(),       // 5
    SettingsPage(),       // 6
    RegisterPage(),       // 7
  ];

  // Map drawer index to actual page
  void _navigateDrawerTo(int drawerIndex) {
    Navigator.pop(context); // Close drawer
    // Find matching bottom nav index or switch to drawer page
    setState(() {
      _currentIndex = drawerIndex;
    });
  }

  // Get the current pages list based on mode
  List<Widget> get _currentPages {
    // If index < 5, show from bottom nav pages
    // If index >= 5, show from all pages
    if (_currentIndex < 5) {
      return _bottomNavPages;
    }
    return _allPages;
  }

  int get _effectiveIndex {
    if (_currentIndex < 5) return _currentIndex;
    return _currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

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
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
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
        index: _currentIndex < 5 ? _currentIndex : _currentIndex,
        children: _currentIndex < 5
            ? _bottomNavPages
            : _allPages.sublist(0, _currentIndex + 1),
      ),
      bottomNavigationBar: _buildBottomNav(appConfig, theme),
    );
  }

  Widget _buildBottomNav(AppConfig appConfig, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.15),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: _currentIndex < 5 ? _currentIndex : -1,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: const Color(0xFF121212),
        indicatorColor: const Color(0xFF00E5FF).withOpacity(0.15),
        height: 64,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined, color: Colors.grey),
            selectedIcon: const Icon(Icons.home, color: Color(0xFF00E5FF)),
            label: appConfig.translate('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.movie_outlined, color: Colors.grey),
            selectedIcon: const Icon(Icons.movie, color: Color(0xFF00E5FF)),
            label: appConfig.translate('movies'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.tv_outlined, color: Colors.grey),
            selectedIcon: const Icon(Icons.tv, color: Color(0xFF00E5FF)),
            label: appConfig.translate('series'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_outline, color: Colors.grey),
            selectedIcon: const Icon(Icons.bookmark, color: Color(0xFF00E5FF)),
            label: appConfig.translate('bookmarks'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined, color: Colors.grey),
            selectedIcon: const Icon(Icons.settings, color: Color(0xFF00E5FF)),
            label: appConfig.translate('settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(AppConfig appConfig, ThemeData theme) {
    final menuItems = [
      _MenuItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home,
        title: appConfig.translate('home'),
        index: 0,
      ),
      _MenuItem(
        icon: Icons.movie_outlined,
        activeIcon: Icons.movie,
        title: appConfig.translate('movies'),
        index: 1,
      ),
      _MenuItem(
        icon: Icons.tv_outlined,
        activeIcon: Icons.tv,
        title: appConfig.translate('series'),
        index: 2,
      ),
      _MenuItem(
        icon: Icons.bookmark_outline,
        activeIcon: Icons.bookmark,
        title: appConfig.translate('bookmarks'),
        index: 3,
      ),
      _MenuItem(
        icon: Icons.category_outlined,
        activeIcon: Icons.category,
        title: appConfig.translate('genres_tags_collections'),
        index: 4,
      ),
      _MenuItem(
        icon: Icons.download_outlined,
        activeIcon: Icons.download,
        title: appConfig.translate('downloads'),
        index: 5,
      ),
      _MenuItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        title: appConfig.translate('settings'),
        index: 6,
      ),
      _MenuItem(
        icon: Icons.person_outline,
        activeIcon: Icons.person,
        title: appConfig.translate('register'),
        index: 7,
      ),
    ];

    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with neon accent
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF00E5FF).withOpacity(0.3),
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
                      color: const Color(0xFF00E5FF).withOpacity(0.15),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_circle_fill,
                      size: 40,
                      color: Color(0xFF00E5FF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'CM Movies',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final isSelected = _currentIndex == item.index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        isSelected ? item.activeIcon : item.icon,
                        color: isSelected
                            ? const Color(0xFF00E5FF)
                            : Colors.white70,
                        size: 22,
                      ),
                      title: Text(
                        item.title,
                        style: TextStyle(
                          color: isSelected
                              ? const Color(0xFF00E5FF)
                              : Colors.white,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor:
                          const Color(0xFF00E5FF).withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: isSelected
                            ? BorderSide(
                                color: const Color(0xFF00E5FF).withOpacity(0.3),
                                width: 1,
                              )
                            : BorderSide.none,
                      ),
                      onTap: () => _navigateDrawerTo(item.index),
                    ),
                  );
                },
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'CM Movies v1.0.0',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final IconData activeIcon;
  final String title;
  final int index;

  _MenuItem({
    required this.icon,
    required this.activeIcon,
    required this.title,
    required this.index,
  });
}
