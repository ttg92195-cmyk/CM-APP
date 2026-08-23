import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
import 'package:cm_movies/app/ui/screens/reels_page.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';
import 'package:cm_movies/app/ui/screens/tmdb_generator_page.dart';
import 'package:cm_movies/app/ui/screens/vip_page.dart';
import 'package:cm_movies/app/ui/components/download_notification_banner.dart';
import 'package:cm_movies/app/ui/components/premium_snackbar.dart';

// Bottom nav tab indices (5 tabs).
// Phase 4 Step C — added kReelsTab between Series and Settings. The
// index shift (Settings moved from 3 → 4) is a breaking change for any
// persisted tab index, but we don't persist tab state to disk anywhere,
// so the change is safe.
const int kHomeTab = 0;
const int kMoviesTab = 1;
const int kSeriesTab = 2;
const int kReelsTab = 3;
const int kSettingsTab = 4;

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
  // Home has its own key so we can call its public refresh() method after
  // returning from content-modifying screens (TMDB Generator, Admin Panel,
  // Add Movie, Edit Movie, Batch Import). Without this, Home keeps showing
  // stale data because IndexedStack keeps HomeScreen alive across tab
  // switches and does NOT auto-reload on Navigator.pop().
  final GlobalKey<State<HomeScreen>> _homeKey = GlobalKey();

  // Tab pages - created once to preserve state across tab switches
  late final List<Widget> _bottomNavPages;

  // Double-back-to-exit: prevent accidental app exit from root route
  bool _canExit = false;
  Timer? _exitTimer;

  // Real app version (fetched from package_info_plus)
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _bottomNavPages = [
      HomeScreen(
        key: _homeKey,
        onNavigateToTab: (index) {
          // Phase 3.1 — capture previous tab index BEFORE setState so
          // we can detect tab-switch direction. This callback is
          // invoked from HomeScreen's "More" button (which always
          // navigates AWAY from Home to Movies or Series), so in
          // practice isLeavingHome is always true and isEnteringHome
          // is always false. But we keep the symmetric pattern for
          // safety and consistency with onDestinationSelected.
          final previousIndex = _currentIndex;
          final isLeavingHome = (previousIndex == kHomeTab && index != kHomeTab);
          final isEnteringHome = (previousIndex != kHomeTab && index == kHomeTab);

          // Pause banner auto-scroll BEFORE setState so the timer is
          // cancelled before the IndexedStack re-renders with Home
          // hidden. IndexedStack keeps HomeScreen mounted, so without
          // this the timer keeps firing and _currentAbsolutePage drifts
          // while the user is on another tab.
          if (isLeavingHome) {
            _pauseHomeBannerAutoScroll();
          }

          // Switch tab first
          setState(() => _currentIndex = index);

          // Resume banner auto-scroll AFTER setState, deferred to
          // addPostFrameCallback (inside _resumeHomeBannerAutoScroll)
          // so the PageController has re-attached to the (now-visible)
          // PageView before we read its .page to re-sync
          // _currentAbsolutePage.
          if (isEnteringHome) {
            _resumeHomeBannerAutoScroll();
          }

          // Trigger data refresh with skeleton loading when navigating via "More" button.
          //
          // Phase 4.42 — call onTabSelected() SYNCHRONOUSLY (no addPostFrameCallback).
          // Why: IndexedStack keeps MoviesPage/SeriesPage mounted at all times, so
          // _moviesKey.currentState / _seriesKey.currentState are always available
          // immediately — we don't need to wait for the tab to become visible.
          // Calling onTabSelected() synchronously here means the setState inside
          // _refreshData() (which clears _movies and sets _isLoading=true) batches
          // with the setState(() => _currentIndex = index) above, so Flutter
          // rebuilds both _HomePageState and MoviesPageState in the SAME frame.
          // The user sees the skeleton the instant the Movies tab becomes visible.
          //
          // The previous implementation wrapped onTabSelected() in
          // addPostFrameCallback, which caused a 1-frame delay between the tab
          // becoming visible (showing STALE movies data) and the skeleton
          // appearing. Bro reported this as "Skeleton Loading ပေါ်လာတာ မြန်ဆန်
          // တာတောင်မဟုတ်" (skeleton doesn't appear fast enough when tapping More).
          //
          // This matches the pattern already used by onDestinationSelected
          // (bottom nav tap) — see lines ~440-445.
          if (index == kMoviesTab) {
            final state = _moviesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          } else if (index == kSeriesTab) {
            final state = _seriesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          }
        },
      ),
      MoviesPage(key: _moviesKey),
      SeriesPage(key: _seriesKey),
      // Phase 4 Step C — Reels tab (placeholder page; grid UI comes in Step D).
      const ReelsPage(),
      const SettingsPage(),
    ];
  }

  @override
  void dispose() {
    _exitTimer?.cancel();
    super.dispose();
  }

  // Fetch the real app version (e.g. "1.9.0+15") from pubspec at runtime
  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version;
      final build = info.buildNumber;
      final formatted = build.isEmpty ? version : '$version+$build';
      if (mounted) {
        setState(() => _appVersion = formatted);
      }
    } catch (_) {
      // Fallback: leave empty so UI can fall back to a static label
    }
  }

  /// Silently refresh the Home tab's data. Called after returning from
  /// content-modifying screens (TMDB Generator, Admin Panel, etc.) so that
  /// newly-added or edited posts appear at the top of the Home feed
  /// without requiring the user to pull-to-refresh.
  ///
  /// Safe to call when Home is not the current tab — IndexedStack keeps
  /// HomeScreen alive, so the GlobalKey state is always available.
  void _refreshHomeIfMounted() {
    final state = _homeKey.currentState;
    if (state != null) {
      // ignore: avoid_dynamic_calls — HomeScreen.refresh() is a public API
      (state as dynamic).refresh();
    }
  }

  // ======================================================================
  // Phase 3.1 — Banner auto-scroll pause/resume on tab switch.
  //
  // HomeScreen exposes pauseAutoScroll() and resumeAutoScroll() as
  // public methods. We call them via the _homeKey GlobalKey whenever
  // the user leaves or enters the Home tab, so the auto-scroll timer
  // doesn't keep firing while Home is hidden inside IndexedStack.
  //
  // Why this matters: IndexedStack keeps all 4 tab pages mounted, so
  // the HomeScreen's Timer.periodic keeps ticking while the user is
  // on Movies/Series/Settings. Each tick increments
  // _currentAbsolutePage and calls animateToPage() on a hidden
  // PageView. Flutter throttles offscreen animation frames, so the
  // animation may not execute visually — but _currentAbsolutePage
  // keeps drifting ahead. On return to Home, the next tick fires
  // animateToPage(driftedAbsolutePage) on a now-visible PageView,
  // producing the "fast-forward" glitch.
  //
  // Fix: pause the timer when leaving Home, resume (with re-sync)
  // when entering Home. The resume path MUST use addPostFrameCallback
  // so the PageController has re-attached to the (now-visible)
  // PageView before we read its .page.
  // ======================================================================

  /// Pause HomeScreen's banner auto-scroll timer. Called when the
  /// user leaves the Home tab (either via bottom nav tap or via the
  /// "More" button on Home that switches to another tab). Safe to
  /// call when Home is not the current tab — IndexedStack keeps
  /// HomeScreen alive, so the GlobalKey state is always available.
  void _pauseHomeBannerAutoScroll() {
    final state = _homeKey.currentState;
    if (state != null) {
      // ignore: avoid_dynamic_calls — HomeScreen.pauseAutoScroll() is a public API
      (state as dynamic).pauseAutoScroll();
    }
  }

  /// Resume HomeScreen's banner auto-scroll timer. Called when the
  /// user enters the Home tab. Uses addPostFrameCallback to ensure
  /// the PageController has re-attached to the (now-visible) PageView
  /// before HomeScreen reads its .page to re-sync _currentAbsolutePage.
  void _resumeHomeBannerAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _homeKey.currentState;
      if (state != null) {
        // ignore: avoid_dynamic_calls — HomeScreen.resumeAutoScroll() is a public API
        (state as dynamic).resumeAutoScroll();
      }
    });
  }

  /// Push a new route from the HomePage, pausing HomeScreen's banner
  /// auto-scroll while the pushed route is visible and resuming it
  /// when the route is popped.
  ///
  /// This is needed because IndexedStack keeps HomeScreen mounted even
  /// when a route is pushed on top of HomePage. Without pause/resume,
  /// the auto-scroll timer keeps firing against the hidden PageView,
  /// causing _currentAbsolutePage to drift. When the user pops back to
  /// Home, the next tick fires animateToPage(driftedAbsolutePage) on a
  /// now-visible PageView, producing the "fast-forward" glitch.
  ///
  /// Only pauses if Home is the current tab (if we're on Movies/Series/
  /// Settings, Home's auto-scroll is already paused from the tab switch).
  /// Only resumes if Home is still the current tab when the route is
  /// popped (the user can't switch tabs while the pushed route is
  /// visible because it covers the bottom nav, but we check defensively).
  ///
  /// Set [refreshOnReturn] to true if Home should silently refresh its
  /// data when the route is popped (e.g., after returning from TMDB
  /// Generator or Admin Panel where the user may have added/edited
  /// content).
  Future<T?> _pushRouteWithBannerPause<T>(
    WidgetBuilder builder, {
    bool refreshOnReturn = false,
  }) {
    if (_currentIndex == kHomeTab) {
      _pauseHomeBannerAutoScroll();
    }
    return Navigator.push<T>(context, MaterialPageRoute(builder: builder))
        .then((result) {
      if (refreshOnReturn) _refreshHomeIfMounted();
      if (_currentIndex == kHomeTab) {
        _resumeHomeBannerAutoScroll();
      }
      return result;
    });
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
              _pushRouteWithBannerPause((_) => const SearchScreen());
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
                  _pushRouteWithBannerPause((_) => const DownloadPage());
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
          // If user taps Home tab while already on Home, treat it as a
          // refresh trigger (silently — no skeleton). This mirrors the
          // common "tap the active tab to refresh" pattern in apps like
          // Twitter / Instagram. Otherwise just switch tabs.
          if (index == _currentIndex && index == kHomeTab) {
            _refreshHomeIfMounted();
            return;
          }
          // Phase 3.1 — capture previous tab index BEFORE setState so
          // we can detect tab-switch direction (Home→other vs other→Home).
          // This is critical: after setState, _currentIndex is already
          // updated to the new value, so we can't use it to detect the
          // "leaving Home" vs "entering Home" case.
          final previousIndex = _currentIndex;
          final isLeavingHome = (previousIndex == kHomeTab && index != kHomeTab);
          final isEnteringHome = (previousIndex != kHomeTab && index == kHomeTab);

          // Pause banner auto-scroll BEFORE setState so the timer is
          // cancelled before the IndexedStack re-renders with Home
          // hidden. Otherwise the timer could tick one more time
          // between setState and the next frame, causing a single
          // spurious animateToPage() call.
          if (isLeavingHome) {
            _pauseHomeBannerAutoScroll();
          }

          setState(() {
            _currentIndex = index;
          });

          // Resume banner auto-scroll AFTER setState, but defer the
          // actual work to addPostFrameCallback (inside
          // _resumeHomeBannerAutoScroll) so the PageController has
          // re-attached to the (now-visible) PageView before we read
          // its .page to re-sync _currentAbsolutePage.
          if (isEnteringHome) {
            _resumeHomeBannerAutoScroll();
          }

          // Trigger data refresh when switching to Movies/Series tabs
          if (index == kMoviesTab) {
            final state = _moviesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          } else if (index == kSeriesTab) {
            final state = _seriesKey.currentState;
            if (state != null) (state as dynamic).onTabSelected();
          } else if (index == kHomeTab) {
            // Returning to Home — silently refresh in case the user
            // added/edited content elsewhere since Home was last visible.
            _refreshHomeIfMounted();
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
          // Phase 4 Step C — Reels 5th tab between Series and Settings.
          NavigationDestination(
            icon: const Icon(Icons.video_collection_outlined),
            selectedIcon: const Icon(Icons.video_collection),
            label: appConfig.translate('reels'),
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
                    _appVersion.isEmpty
                        ? appConfig.translate('version')
                        : '${appConfig.translate('version')} $_appVersion',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // VIP Status Card — shows active VIP (red badge) or "not purchased yet"
                  _buildVipStatusCard(appConfig, isDark),
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
                      _pushRouteWithBannerPause((_) => const RecentPage());
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
                      _pushRouteWithBannerPause((_) => const GenresTagsCollectionsPage());
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
                      _pushRouteWithBannerPause((_) => const DownloadPage());
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
                        _pushRouteWithBannerPause(
                          (_) => const AdminPanelPage(),
                          refreshOnReturn: true,
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
                        _pushRouteWithBannerPause(
                          (_) => const TmdbGeneratorPage(),
                          refreshOnReturn: true,
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
                        _pushRouteWithBannerPause((_) => const ProfilePage());
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
                          // Phase 4.35: Premium styled SnackBar replaces
                          // the old plain orange bar. Dark gradient card
                          // with red accent icon, bilingual title +
                          // subtitle, floating with rounded corners.
                          final isMy = appConfig.languageCode == 'my';
                          ScaffoldMessenger.of(context).showSnackBar(
                            PremiumSnackBar(
                              context: context,
                              icon: Icons.logout_rounded,
                              title: isMy
                                  ? 'ထွက်ပြီးပါပြီ'
                                  : 'Logged out',
                              subtitle: isMy
                                  ? 'သင် sign out လုပ်ပြီးပါပြီ။'
                                  : 'You have been signed out.',
                              accentColor: const Color(0xFFE50914),
                              duration: const Duration(seconds: 3),
                            ).build(),
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
                        _pushRouteWithBannerPause((_) => const LoginPage());
                      },
                    ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _appVersion.isEmpty ? 'KMM' : 'KMM v$_appVersion',
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

  /// VIP status card shown inside the drawer header.
  /// - VIP users → red gradient badge with crown + "VIP Active" + expiry date
  /// - Non-VIP users → outlined grey/orange card with "VIP Not Active" + "Tap to upgrade"
  ///   (tapping opens the VipPage where they can purchase VIP via Telegram)
  Widget _buildVipStatusCard(AppConfig appConfig, bool isDark) {
    final isVip = appConfig.isCurrentUserVip;
    final isAdmin = appConfig.isCurrentUserAdmin;
    // Admins implicitly have all VIP perks — show VIP-style badge for them too
    final showAsVip = isVip || isAdmin;

    if (showAsVip) {
      // Format the VIP expiry date for display (if available)
      String expiryDisplay = '';
      final rawExpiry = appConfig.currentUser?['vipExpiry'] as String?;
      if (rawExpiry != null && rawExpiry.isNotEmpty) {
        final dt = DateTime.tryParse(rawExpiry);
        if (dt != null) {
          expiryDisplay =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFFE50914), Color(0xFFB20710)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE50914).withOpacity(0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAdmin
                        ? '${appConfig.translate('vip_active')} · Admin'
                        : appConfig.translate('vip_active'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expiryDisplay.isEmpty
                        ? appConfig.translate('vip_active_desc')
                        : appConfig
                            .translate('vip_expires_on')
                            .replaceAll('{date}', expiryDisplay),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Non-VIP card — tap to open VipPage and purchase VIP
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pop(context); // close drawer
          _pushRouteWithBannerPause((_) => const VipPage());
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.04),
            border: Border.all(
              color: const Color(0xFFE50914).withOpacity(0.5),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline,
                color: const Color(0xFFE50914).withOpacity(0.9),
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      appConfig.translate('vip_inactive'),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      appConfig.translate('vip_inactive_desc'),
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  appConfig.translate('vip_get_now'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
