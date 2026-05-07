import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/home/home_screen.dart';
import 'package:cm_movies/app/ui/home/library_page.dart';
import 'package:cm_movies/app/ui/screens/search_screen.dart';
import 'package:cm_movies/app/ui/screens/movie_bookmark_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomeScreen(),
    LibraryPage(),
    SearchScreen(),
    MovieBookmarkScreen(),
    _SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: Theme.of(context).colorScheme.surface,
        indicatorColor: Theme.of(context).colorScheme.primaryContainer,
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
            icon: const Icon(Icons.search_outlined),
            selectedIcon: const Icon(Icons.search),
            label: appConfig.translate('search'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmark_outline),
            selectedIcon: const Icon(Icons.bookmark),
            label: appConfig.translate('bookmarks'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: appConfig.translate('settings'),
          ),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage();

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('settings')),
      ),
      body: ListView(
        children: [
          // Theme Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              appConfig.translate('theme'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              appConfig.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            ),
            title: Text(appConfig.translate('dark_mode')),
            value: appConfig.isDarkMode,
            onChanged: (val) {
              appConfig.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
            },
          ),
          const Divider(),

          // Language Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              appConfig.translate('language'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          RadioListTile<String>(
            title: const Text('မြန်မာ'),
            subtitle: const Text('Myanmar'),
            value: 'my',
            groupValue: appConfig.languageCode,
            onChanged: (val) {
              if (val != null) appConfig.setLanguage(val);
            },
          ),
          RadioListTile<String>(
            title: const Text('English'),
            subtitle: const Text('English'),
            value: 'en',
            groupValue: appConfig.languageCode,
            onChanged: (val) {
              if (val != null) appConfig.setLanguage(val);
            },
          ),
          const Divider(),

          // About Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              appConfig.translate('about_app'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(appConfig.translate('app_name')),
            subtitle: Text('${appConfig.translate('version')}: 1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.tv),
            title: const Text('HomieTV'),
            subtitle: const Text('www.homietv.com'),
          ),
        ],
      ),
    );
  }
}
