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

  final List<Widget> _pages = const [
    HomeScreen(),
    MoviesPage(),
    SeriesPage(),
    MovieBookmarkScreen(),
    GenresTagsCollectionsPage(),
    DownloadPage(),
    SettingsPage(),
    RegisterPage(),
  ];

  void _navigateTo(int index) {
    Navigator.pop(context); // Close drawer
    setState(() {
      _currentIndex = index;
    });
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
        index: _currentIndex,
        children: _pages,
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
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.play_circle_fill,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appConfig.translate('app_name'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${appConfig.translate("version")}: 1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final isSelected = _currentIndex == item.index;
                  return ListTile(
                    leading: Icon(
                      isSelected ? item.activeIcon : item.icon,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: isSelected,
                    selectedTileColor:
                        theme.colorScheme.primaryContainer.withOpacity(0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    onTap: () => _navigateTo(item.index),
                  );
                },
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'CM Movies v1.0.0',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.4),
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
