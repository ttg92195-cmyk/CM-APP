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

class _HomeScreenState extends State<HomeScreen> {
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

  @override
  void initState() {
    super.initState();
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
    _autoScrollTimer?.cancel();
    _bannerController?.dispose();
    super.dispose();
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
  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
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
  void _pauseAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  /// Tear down the banner PageController so a fresh one is created on the
  /// next _buildBannerSlider call. Used whenever the banner is about to
  /// disappear from the widget tree (e.g. skeleton loading appears during
  /// pull-to-refresh). Disposing the controller prevents the OLD detached
  /// controller from being animated by a lingering timer and keeps
  /// _currentAbsolutePage in sync with the new initialPage on rebuild.
  void _resetBannerController() {
    _pauseAutoScroll();
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
        // Restart the auto-scroll timer if banner count changed.
        final bannerChanged = bannerUrls.length != _bannerImageUrls.length;
        setState(() {
          _bannerImageUrls = bannerUrls;
          _trendingMovies = trendingMovies;
          _trendingTvShows = trendingTvShows;
          _allMovies = allMovies;
          _allSeries = allSeries;
        });
        if (bannerChanged) {
          _autoScrollTimer?.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _bannerImageUrls.isNotEmpty) {
              _startAutoScroll();
            }
          });
        }
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
        // future regressions.
        _pauseAutoScroll();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _bannerImageUrls.isNotEmpty && !_isLoading) {
            _startAutoScroll();
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

  Future<void> _loadTagBasedData() async {
    final tagEntries = <MapEntry<String, Future<List<Movie>>>>[
      MapEntry('K Drama', _contentService.getMoviesByTagSimple('K Drama', limit: _homeLimit)),
      MapEntry('4K Movies', _contentService.getMoviesByTagSimple('4K Movies', limit: _homeLimit)),
      MapEntry('4K Series', _contentService.getMoviesByTagSimple('4K Series', limit: _homeLimit)),
      MapEntry('Animation', _contentService.getMoviesByTagSimple('Animation', limit: _homeLimit)),
      MapEntry('Anime', _contentService.getMoviesByTagSimple('Anime', limit: _homeLimit)),
      MapEntry('Bollywood', _contentService.getMoviesByTagSimple('Bollywood', limit: _homeLimit)),
    ];

    // Accumulate results locally, then call setState once after all are done
    List<Movie> kDramaMovies = _kDramaMovies;
    List<Movie> fourKMovies = _fourKMovies;
    List<Movie> fourKSeries = _fourKSeries;
    List<Movie> animationMovies = _animationMovies;
    List<Movie> animeMovies = _animeMovies;
    List<Movie> bollywoodMovies = _bollywoodMovies;

    for (final entry in tagEntries) {
      try {
        final movies = await entry.value;
        switch (entry.key) {
          case 'K Drama':
            kDramaMovies = movies;
            break;
          case '4K Movies':
            fourKMovies = movies;
            break;
          case '4K Series':
            fourKSeries = movies;
            break;
          case 'Animation':
            animationMovies = movies;
            break;
          case 'Anime':
            animeMovies = movies;
            break;
          case 'Bollywood':
            bollywoodMovies = movies;
            break;
        }
      } catch (e) {
        debugPrint('Error loading tag ${entry.key}: $e');
      }
    }

    // Single setState after all tag data is loaded
    if (mounted) {
      setState(() {
        _kDramaMovies = kDramaMovies;
        _fourKMovies = fourKMovies;
        _fourKSeries = fourKSeries;
        _animationMovies = animationMovies;
        _animeMovies = animeMovies;
        _bollywoodMovies = bollywoodMovies;
        _isLoadingTags = false;
      });
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
        child: (_isLoading || _isLoadingTags)
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
