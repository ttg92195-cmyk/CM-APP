import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/category_page.dart';
import 'package:cm_movies/app/ui/home/home_page.dart' show kMoviesTab, kSeriesTab;
import 'package:cm_movies/app/core/services/recent_service.dart';

class HomeScreen extends StatefulWidget {
  final Function(int)? onNavigateToTab;

  const HomeScreen({super.key, this.onNavigateToTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final FirestoreContentService _contentService = FirestoreContentService();
  final RecentService _recentService = RecentService();
  // Banner PageController — created lazily once banner image count is known,
  // so initialPage can be set for the infinite-loop effect. Reused for the
  // lifetime of the State to avoid per-build memory leaks.
  PageController? _bannerController;
  // The ABSOLUTE page index the PageController is currently on (NOT the
  // modded real index). Used by the auto-scroll timer to advance the
  // carousel correctly — see _startAutoScroll for why this matters.
  int _currentAbsolutePage = 0;
  // The MODDED real banner index (0..length-1) currently displayed — used
  // only for the dots indicator below the banner.
  int _currentBannerIndex = 0;
  Timer? _autoScrollTimer;

  List<Movie> _trendingMovies = [];
  List<Movie> _trendingTvShows = [];
  List<Movie> _allMovies = [];
  List<Movie> _allSeries = [];

  // Banner images from Firestore admin config
  List<String> _bannerImageUrls = [];

  // Tag-based lists
  List<Movie> _kDramaMovies = [];
  List<Movie> _fourKMovies = [];
  List<Movie> _fourKSeries = [];
  List<Movie> _animationMovies = [];
  List<Movie> _animeMovies = [];
  List<Movie> _bollywoodMovies = [];

  bool _isLoading = true;
  bool _isLoadingTags = true;
  String? _error;

  static const int _homeLimit = 10; // Show 10 posts per section on Home

  // Whether the banner auto-scroll timer SHOULD be running. The actual
  // timer may be cancelled (e.g. during pull-to-refresh skeleton, or when
  // the app is backgrounded) but this flag remembers whether to restart
  // it once the interruption is over.
  bool _bannerAutoScrollEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    // NOTE: Auto-scroll timer is NOT started here. It is started only after
    // banner data actually arrives in _loadData() — see the call to
    // _startAutoScroll() inside the successful setState block. Starting the
    // timer here (while _bannerImageUrls is still empty) was the original
    // cause of the "initial rapid scroll" glitch: the timer would tick the
    // moment data arrived, before the PageController had been lazily created
    // and settled on its initialPage, causing a giant backward jump from
    // initialPage (= length * 1000) down to _currentBannerIndex + 1 (= 1).
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseAutoScroll();
    _bannerController?.dispose();
    _bannerController = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause the banner auto-scroll timer when the app goes to background,
    // and resume it (only if banner data is loaded) when the app returns
    // to the foreground. Without this, the timer keeps firing in the
    // background and ticks accumulate; on resume, the PageView tries to
    // animate to multiple pages in quick succession, producing the
    // "rapid banner scroll" glitch Bro reported when returning to the
    // app after backgrounding it.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pauseAutoScroll();
    } else if (state == AppLifecycleState.resumed) {
      // Only restart if banner data is present and we are not currently
      // loading (skeleton would replace the banner in the widget tree).
      if (_bannerAutoScrollEnabled &&
          _bannerImageUrls.isNotEmpty &&
          !_isLoading &&
          mounted) {
        // Defer to next frame so the PageController has a chance to
        // re-attach to the PageView after the app resumes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _bannerAutoScrollEnabled &&
              _bannerImageUrls.isNotEmpty &&
              !_isLoading) {
            _startAutoScroll();
          }
        });
      }
    }
  }

  /// Auto-scroll banner every 4 seconds.
  ///
  /// IMPORTANT: We track the ABSOLUTE page index (_currentAbsolutePage), not
  /// the modded realIndex, because animateToPage() needs the absolute page
  /// number the PageController is currently on. The previous implementation
  /// stored the modded realIndex in _currentBannerIndex and then called
  /// animateToPage(_currentBannerIndex + 1) — which is a tiny number like 1
  /// or 2 — causing the PageView to scroll backwards from initialPage
  /// (= length * 1000, e.g. 4000) all the way down to page 1 in a single
  /// 500ms animation. Visually this looked like a rapid auto-scroll burst
  /// on app launch. Storing the absolute page fixes it.
  ///
  /// This method is idempotent — it cancels any existing timer before
  /// starting a new one. It also sets _bannerAutoScrollEnabled = true so
  /// that didChangeAppLifecycleState knows whether to restart the timer
  /// when the app returns to the foreground.
  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _bannerAutoScrollEnabled = true;
    // Initialize absolute page tracker to the controller's actual current
    // page (the lazy initialPage). This prevents the first timer tick from
    // jumping backwards.
    if (_bannerController != null && _bannerController!.hasClients) {
      _currentAbsolutePage = _bannerController!.page?.round() ?? _currentAbsolutePage;
    }
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_bannerImageUrls.isNotEmpty && _bannerController != null && _bannerController!.hasClients) {
        _currentAbsolutePage = _currentAbsolutePage + 1;
        _bannerController!.animateToPage(
          _currentAbsolutePage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  /// Public refresh hook for external callers (e.g. home_page.dart after
  /// returning from TMDB Generator / Admin Panel where the user may have
  /// added or edited posts). Without this, Home shows stale data because
  /// IndexedStack keeps HomeScreen alive across tab switches.
  ///
  /// NOTE: We DO NOT set _isLoading = true here, because that would flash
  /// the skeleton loader every time the user returns from Admin Panel —
  /// very jarring. Instead we silently refetch in the background and
  /// update the lists in place. The existing skeleton only shows on
  /// initial load (initState → _loadData) and on pull-to-refresh.
  Future<void> refresh() => _refreshSilently();

  /// Stop the auto-scroll timer WITHOUT touching the PageController.
  /// Used during loading/refresh transitions so the timer doesn't keep
  /// firing animateToPage() against a controller that may be unmounted
  /// (because the skeleton replaces the banner in the widget tree).
  ///
  /// keepEnabledFlag: if true (default), preserves _bannerAutoScrollEnabled
  /// so didChangeAppLifecycleState can restart the timer on app resume.
  /// If false, clears the flag — used when we're tearing down the banner
  /// entirely (e.g. on dispose, or when the banner is hidden because no
  /// banner images are configured).
  void _pauseAutoScroll({bool keepEnabledFlag = true}) {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (!keepEnabledFlag) {
      _bannerAutoScrollEnabled = false;
    }
  }

  /// Tear down the banner PageController so a fresh one is created on the
  /// next _buildBannerSlider call. Used whenever the banner is about to
  /// disappear from the widget tree (e.g. skeleton loading appears during
  /// pull-to-refresh). Disposing the controller prevents the OLD detached
  /// controller from being animated by a lingering timer and keeps
  /// _currentAbsolutePage in sync with the new initialPage on rebuild.
  void _resetBannerController() {
    // Keep the enabled flag here — we'll restart the timer once banner
    // data arrives in _loadData's postFrame callback.
    _pauseAutoScroll(keepEnabledFlag: true);
    _bannerController?.dispose();
    _bannerController = null;
    // Reset to a safe default; _buildBannerSlider will set it to the
    // new initialPage once the controller is recreated.
    _currentAbsolutePage = 0;
    _currentBannerIndex = 0;
  }

  /// Silent background refresh — does NOT show skeleton loader. Used by
  /// refresh() above and by Navigator.push(...).then() callbacks in
  /// home_page.dart. Falls back to _loadData if lists are still empty.
  Future<void> _refreshSilently() async {
    if (_allMovies.isEmpty && _allSeries.isEmpty && _trendingMovies.isEmpty) {
      // Initial load never completed — fall back to full load with skeleton.
      return _loadData();
    }
    try {
      final results = await Future.wait([
        _contentService.getBannerConfig().catchError((e) => <String>[]),
        _contentService.getTrendingMovies().catchError((_) => <Movie>[]),
        _contentService.getTrendingTvShows().catchError((_) => <Movie>[]),
        _contentService.getMovies(limit: _homeLimit).catchError((_) => <Map<String, dynamic>>{}),
        _contentService.getSeries(limit: _homeLimit).catchError((_) => <Map<String, dynamic>>{}),
      ]);

      final bannerUrls = results[0] as List<String>;
      final trendingMovies = results[1] as List<Movie>;
      final trendingTvShows = results[2] as List<Movie>;
      final moviesResult = results[3];
      final seriesResult = results[4];

      List<Movie> allMovies = [];
      List<Movie> allSeries = [];
      if (moviesResult is Map<String, dynamic>) {
        allMovies = List<Movie>.from(moviesResult['movies'] ?? []);
      }
      if (seriesResult is Map<String, dynamic>) {
        allSeries = List<Movie>.from(seriesResult['movies'] ?? []);
      }

      if (mounted) {
        // Detect whether the banner image set actually changed. We compare
        // BOTH the length AND the contents, because the count alone can
        // miss the case where an image was replaced with a different URL
        // at the same position.
        final bannerChanged = !_listEquals(bannerUrls, _bannerImageUrls);

        // ALWAYS pause the timer before setState — even if bannerChanged
        // is false, the existing timer is now pointing at potentially stale
        // _currentAbsolutePage state (e.g. if the PageController was
        // recreated elsewhere). _startAutoScroll will re-sync it on restart.
        // We keep the enabled flag so that didChangeAppLifecycleState
        // can still resume correctly if the app gets backgrounded during
        // this refresh.
        _pauseAutoScroll(keepEnabledFlag: true);

        setState(() {
          _bannerImageUrls = bannerUrls;
          _trendingMovies = trendingMovies;
          _trendingTvShows = trendingTvShows;
          _allMovies = allMovies;
          _allSeries = allSeries;
        });

        // If the banner set changed, dispose the old PageController so a
        // fresh one (with a correct initialPage for the new image count)
        // is created on the next build. Without this, the existing
        // controller's initialPage (sized for the OLD image count) could
        // be misaligned with the new mod-loop, causing rapid backward
        // scroll glitches.
        if (bannerChanged) {
          _bannerController?.dispose();
          _bannerController = null;
          _currentAbsolutePage = 0;
          _currentBannerIndex = 0;
        }

        // Restart the auto-scroll timer on the next frame, AFTER the
        // setState above has been committed to the widget tree and the
        // lazy _bannerController has had a chance to recreate itself
        // with the correct initialPage for the (possibly new) image
        // count. Skipping this frame would cause _startAutoScroll to
        // read a stale/null controller.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _bannerImageUrls.isNotEmpty) {
            _startAutoScroll();
          } else if (mounted && _bannerImageUrls.isEmpty) {
            // No banner configured — make sure the enabled flag is cleared
            // so didChangeAppLifecycleState doesn't try to restart a
            // timer that has nothing to scroll.
            _bannerAutoScrollEnabled = false;
          }
        });

        // Reload tag-based sections in the background.
        _loadTagBasedData();
      }
    } catch (e) {
      debugPrint('Home silent refresh failed: $e');
      // Don't show error UI — keep the previously-loaded data visible.
    }
  }

  Future<void> _loadData() async {
    // PAUSE the auto-scroll timer and tear down the banner controller
    // BEFORE the skeleton replaces the banner in the widget tree. This
    // closes the 'banner glitches during pull-to-refresh' bug: previously
    // the timer kept ticking against the OLD (now-detached) controller
    // while the skeleton was visible, and on data arrival a NEW controller
    // was created with a fresh initialPage but the lingering timer was
    // still pointing at the stale _currentAbsolutePage — producing rapid
    // jumps/glitches.
    _resetBannerController();

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Load banner config and movie data in parallel.
      // Each future is wrapped with catchError so that one failure (e.g.
      // banner doc missing or temporarily failing) doesn't break the whole
      // home screen — the rest of the data still loads.
      final results = await Future.wait([
        _contentService.getBannerConfig().catchError((e) {
          debugPrint('Home: getBannerConfig failed, hiding banner: $e');
          return <String>[];
        }),
        _contentService.getTrendingMovies().catchError((_) => <Movie>[]),
        _contentService.getTrendingTvShows().catchError((_) => <Movie>[]),
        _contentService.getMovies(limit: _homeLimit).catchError((_) => <Map<String, dynamic>>{}),
        _contentService.getSeries(limit: _homeLimit).catchError((_) => <Map<String, dynamic>>{}),
      ]);

      final bannerUrls = results[0] as List<String>;
      final trendingMovies = results[1] as List<Movie>;
      final trendingTvShows = results[2] as List<Movie>;
      final moviesResult = results[3];
      final seriesResult = results[4];

      List<Movie> allMovies = [];
      List<Movie> allSeries = [];

      if (moviesResult is Map<String, dynamic>) {
        allMovies = List<Movie>.from(moviesResult['movies'] ?? []);
      }
      if (seriesResult is Map<String, dynamic>) {
        allSeries = List<Movie>.from(seriesResult['movies'] ?? []);
      }

      if (mounted) {
        setState(() {
          _bannerImageUrls = bannerUrls;
          _trendingMovies = trendingMovies;
          _trendingTvShows = trendingTvShows;
          _allMovies = allMovies;
          _allSeries = allSeries;
          _isLoading = false;
          _isLoadingTags = true;
        });

        // Start the auto-scroll timer ONLY AFTER banner data has actually
        // arrived AND the banner widget is back in the tree (i.e. we are
        // no longer showing the skeleton). We use addPostFrameCallback so
        // that the lazy _bannerController (created inside _buildBannerSlider
        // on the next frame) is fully attached to the PageView before we
        // read its initial page and start ticking the timer. This
        // guarantees the timer's first tick targets the correct absolute
        // page instead of jumping backwards from initialPage.
        //
        // Defensive: also cancel any stale timer that may have survived
        // from a previous load cycle — _startAutoScroll already does this,
        // but doing it here makes the intent explicit and protects against
        // future regressions. We keep the enabled flag so lifecycle
        // resume-after-pause knows to restart the timer.
        _pauseAutoScroll(keepEnabledFlag: true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _bannerImageUrls.isNotEmpty && !_isLoading) {
            _startAutoScroll();
          } else if (mounted && _bannerImageUrls.isEmpty) {
            // No banner configured — clear the enabled flag so that
            // didChangeAppLifecycleState doesn't try to restart a timer
            // that has nothing to scroll.
            _bannerAutoScrollEnabled = false;
          }
        });

        _loadTagBasedData();
      }
    } catch (e) {
      debugPrint('Error in _loadData: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// Shallow list equality helper for comparing two banner URL lists.
  /// Returns true if both lists have the same length and contain the
  /// same strings in the same order. Used by _refreshSilently to decide
  /// whether to dispose + recreate the PageController.
  bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _loadTagBasedData() async {
    // PARALLEL + PROGRESSIVE — Bro reported 5-10 minute waits on first
    // launch. Two root causes fixed here:
    //
    // 1. SEQUENTIAL → PARALLEL: previous implementation ran 6 Firestore
    //    queries sequentially via a for-loop with await. On slow
    //    networks each query can take 30-60s, so 6 × 60s = 6 minutes
    //    before the skeleton would disappear. Running all 6 in parallel
    //    cuts the total wait to roughly the slowest single query
    //    (~60s worst case) instead of 6 × slowest.
    //
    // 2. ALL-OR-NOTHING → PROGRESSIVE: instead of waiting for all 6
    //    tags before calling setState, we update each tag list the
    //    moment its query returns. Users see K Drama appear while
    //    4K Movies is still loading, etc. This makes the screen feel
    //    alive instead of frozen on a single skeleton.
    //
    // Each tag fetch is fire-and-forget — failures degrade to an
    // empty list for that tag (the section is hidden via the
    // `if (_xMovies.isNotEmpty)` guard in _buildContent), but other
    // tags still appear.

    Future<void> loadTag(
      String name,
      void Function(List<Movie>) setter,
    ) async {
      try {
        final movies = await _contentService.getMoviesByTagSimple(name, limit: _homeLimit);
        if (mounted) {
          setState(() {
            setter(movies);
          });
        }
      } catch (e) {
        debugPrint('Error loading tag $name: $e');
        // Leave the list at its current value (initially empty).
        // The section is hidden via `if (_xMovies.isNotEmpty)`.
      }
    }

    // Fire all 6 in parallel. Each one calls setState independently
    // as soon as it resolves.
    final futures = <Future<void>>[
      loadTag('K Drama', (m) => _kDramaMovies = m),
      loadTag('4K Movies', (m) => _fourKMovies = m),
      loadTag('4K Series', (m) => _fourKSeries = m),
      loadTag('Animation', (m) => _animationMovies = m),
      loadTag('Anime', (m) => _animeMovies = m),
      loadTag('Bollywood', (m) => _bollywoodMovies = m),
    ];

    // Wait for all to settle (success or caught failure), then clear
    // the loading flag so the bottom-of-screen skeleton (if any)
    // disappears.
    await Future.wait(futures).catchError((e) {
      debugPrint('_loadTagBasedData parallel fetch aggregate error: $e');
    });

    if (mounted) {
      setState(() => _isLoadingTags = false);
    }
  }

  void _navigateToDetail(Movie movie) async {
    final isSeries = movie.type == 'series';
    // Save to recent before navigating
    await _recentService.addRecent(movie);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isSeries
            ? SeriesDetailScreen(slug: movie.slug)
            : MovieDetailScreen(slug: movie.slug),
      ),
    );
  }

  void _navigateToCategory(CategoryPage page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        // NOTE: We only block on _isLoading (banner + movies + series +
        // trending). Tag-based sections (K Drama, 4K, Animation, etc.)
        // load in the background via _loadTagBasedData and appear
        // progressively as they arrive — Bro reported 5-10 minute
        // waits because the old code blocked the whole screen on
        // _isLoadingTags too. Now the user sees the main content
        // within ~1-2 seconds and tag sections fill in below.
        child: _isLoading
            ? _buildSkeletonLoading(theme, appConfig)
            : _error != null
                ? _buildErrorWidget(appConfig)
                : _buildContent(appConfig, theme),
      ),
    );
  }

  /// Skeleton loading matching expected number of sections
  Widget _buildSkeletonLoading(ThemeData theme, AppConfig appConfig) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner skeleton
          const BannerSkeleton(),
          const SizedBox(height: 8),
          // Movies section skeleton
          TrendingMovieSkeleton(title: appConfig.translate('movies'), count: 5),
          const SizedBox(height: 4),
          // Series section skeleton
          TrendingMovieSkeleton(title: appConfig.translate('series'), count: 5),
          const SizedBox(height: 4),
          // Trending Movies skeleton
          TrendingMovieSkeleton(title: appConfig.translate('trending_movies'), count: 5),
          const SizedBox(height: 4),
          // Trending TV Shows skeleton
          TrendingMovieSkeleton(title: appConfig.translate('trending_tv_shows'), count: 5),
          const SizedBox(height: 4),
          // K Drama skeleton
          TrendingMovieSkeleton(title: appConfig.translate('k_drama'), count: 5),
          const SizedBox(height: 4),
          // 4K Movies skeleton
          TrendingMovieSkeleton(title: appConfig.translate('4k_movies'), count: 5),
          const SizedBox(height: 4),
          // 4K Series skeleton
          TrendingMovieSkeleton(title: appConfig.translate('4k_series'), count: 5),
          const SizedBox(height: 4),
          // Animation skeleton
          TrendingMovieSkeleton(title: appConfig.translate('animation'), count: 5),
          const SizedBox(height: 4),
          // Anime skeleton
          TrendingMovieSkeleton(title: appConfig.translate('anime'), count: 5),
          const SizedBox(height: 4),
          // Bollywood skeleton
          TrendingMovieSkeleton(title: appConfig.translate('bollywood'), count: 5),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(AppConfig appConfig) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              appConfig.translate('error_occurred'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              _error != null ? _error! : '',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: Text(appConfig.translate('retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(AppConfig appConfig, ThemeData theme) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Slider (Admin-managed images)
          _buildBannerSlider(theme),

          const SizedBox(height: 8),
          // Movies Section
          if (_allMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('movies'),
              movies: _allMovies.length > _homeLimit ? _allMovies.sublist(0, _homeLimit) : _allMovies,
              onMovieTap: _navigateToDetail,
              onMore: () {
                widget.onNavigateToTab?.call(kMoviesTab);
              },
            ),

          const SizedBox(height: 4),

          // Series Section
          if (_allSeries.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('series'),
              movies: _allSeries.length > _homeLimit ? _allSeries.sublist(0, _homeLimit) : _allSeries,
              onMovieTap: _navigateToDetail,
              onMore: () {
                widget.onNavigateToTab?.call(kSeriesTab);
              },
            ),

          const SizedBox(height: 4),

          // Trending Movies
          if (_trendingMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('trending_movies'),
              movies: _trendingMovies.length > _homeLimit ? _trendingMovies.sublist(0, _homeLimit) : _trendingMovies,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('trending_movies'),
                  filterType: CategoryFilterType.trendingMovies,
                ));
              },
            ),

          const SizedBox(height: 4),

          // Trending Series
          if (_trendingTvShows.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('trending_tv_shows'),
              movies: _trendingTvShows.length > _homeLimit ? _trendingTvShows.sublist(0, _homeLimit) : _trendingTvShows,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('trending_tv_shows'),
                  filterType: CategoryFilterType.trendingSeries,
                ));
              },
            ),

          const SizedBox(height: 4),

          // K Drama
          if (_kDramaMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('k_drama'),
              movies: _kDramaMovies.length > _homeLimit ? _kDramaMovies.sublist(0, _homeLimit) : _kDramaMovies,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('k_drama'),
                  filterType: CategoryFilterType.tag,
                  filterValue: 'K Drama',
                ));
              },
            ),

          const SizedBox(height: 4),

          // 4K Movies
          if (_fourKMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('4k_movies'),
              movies: _fourKMovies.length > _homeLimit ? _fourKMovies.sublist(0, _homeLimit) : _fourKMovies,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('4k_movies'),
                  filterType: CategoryFilterType.tag,
                  filterValue: '4K Movies',
                ));
              },
            ),

          const SizedBox(height: 4),

          // 4K Series
          if (_fourKSeries.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('4k_series'),
              movies: _fourKSeries.length > _homeLimit ? _fourKSeries.sublist(0, _homeLimit) : _fourKSeries,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('4k_series'),
                  filterType: CategoryFilterType.tag,
                  filterValue: '4K Series',
                ));
              },
            ),

          const SizedBox(height: 4),

          // Animation
          if (_animationMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('animation'),
              movies: _animationMovies.length > _homeLimit ? _animationMovies.sublist(0, _homeLimit) : _animationMovies,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('animation'),
                  filterType: CategoryFilterType.tag,
                  filterValue: 'Animation',
                ));
              },
            ),

          const SizedBox(height: 4),

          // Anime
          if (_animeMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('anime'),
              movies: _animeMovies.length > _homeLimit ? _animeMovies.sublist(0, _homeLimit) : _animeMovies,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('anime'),
                  filterType: CategoryFilterType.tag,
                  filterValue: 'Anime',
                ));
              },
            ),

          const SizedBox(height: 4),

          // Bollywood
          if (_bollywoodMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('bollywood'),
              movies: _bollywoodMovies.length > _homeLimit ? _bollywoodMovies.sublist(0, _homeLimit) : _bollywoodMovies,
              onMovieTap: _navigateToDetail,
              onMore: () {
                _navigateToCategory(CategoryPage(
                  title: appConfig.translate('bollywood'),
                  filterType: CategoryFilterType.tag,
                  filterValue: 'Bollywood',
                ));
              },
            ),

          // Empty state
          if (_trendingMovies.isEmpty &&
              _trendingTvShows.isEmpty &&
              _allMovies.isEmpty &&
              _allSeries.isEmpty)
            SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  appConfig.translate('no_results'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Premium Banner Slider — Admin-managed pure image carousel
  /// Features: Card style with rounded corners, shadow, infinite loop, auto-scroll, dots indicator
  Widget _buildBannerSlider(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;

    // If no banner images configured, show nothing
    if (_bannerImageUrls.isEmpty) return const SizedBox.shrink();

    // Lazily create the banner PageController once we know the image count.
    // initialPage is set to a large multiple of the image count so the user
    // can scroll both backwards and forwards (infinite-loop effect).
    // The controller is reused across rebuilds and disposed in dispose().
    if (_bannerController == null) {
      final initialPage = _bannerImageUrls.length * 1000;
      _bannerController = PageController(initialPage: initialPage);
      // Keep the absolute-page tracker in sync with the controller's
      // initialPage so the auto-scroll timer advances from the correct
      // position instead of jumping backwards.
      _currentAbsolutePage = initialPage;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Banner card with rounded corners and shadow
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 180,
                child: Stack(
                  children: [
                    // Infinite loop PageView (reuse single _bannerController to avoid memory leak)
                    PageView.builder(
                      controller: _bannerController,
                      onPageChanged: (index) {
                        // Track BOTH the absolute page (for the auto-scroll
                        // timer's next animateToPage call) AND the modded
                        // real index (for the dots indicator).
                        _currentAbsolutePage = index;
                        final realIndex = index % _bannerImageUrls.length;
                        setState(() => _currentBannerIndex = realIndex);
                      },
                      itemBuilder: (context, index) {
                        final realIndex = index % _bannerImageUrls.length;
                        final imageUrl = _bannerImageUrls[realIndex];

                        return CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (context, url) => Container(
                            color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
                            child: Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: const Color(0xFFE50914),
                                ),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade300,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: isDark ? Colors.white24 : Colors.black12,
                              size: 48,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Dots indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_bannerImageUrls.length, (index) {
              final isActive = index == _currentBannerIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: isActive ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFE50914) : (isDark ? Colors.white38 : Colors.black26),
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
