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
  final PageController _bannerController = PageController();
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
    _startAutoScroll();
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  /// Auto-scroll banner every 4 seconds
  void _startAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_bannerImageUrls.isNotEmpty && _bannerController.hasClients) {
        final nextIndex = _currentBannerIndex + 1;
        // Use a very large number for infinite loop effect
        _bannerController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Load banner config and movie data in parallel
      final results = await Future.wait([
        _contentService.getBannerConfig(),
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
      MapEntry('4K', _contentService.getMoviesByTagSimple('4K', limit: _homeLimit)),
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
          case '4K':
            fourKMovies = movies.where((m) => m.type == 'movie').toList();
            fourKSeries = movies.where((m) => m.type == 'series').toList();
            if (fourKMovies.isEmpty && movies.isNotEmpty) {
              fourKMovies = movies;
            }
            if (fourKSeries.isEmpty && movies.isNotEmpty) {
              fourKSeries = movies;
            }
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
          TrendingMovieSkeleton(title: appConfig.translate('movies'), count: 5),
          const SizedBox(height: 4),
          TrendingMovieSkeleton(title: appConfig.translate('series'), count: 5),
          const SizedBox(height: 4),
          TrendingMovieSkeleton(title: appConfig.translate('trending_movies'), count: 5),
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
                  filterValue: '4K',
                  typeFilter: 'movie',
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
                  filterValue: '4K',
                  typeFilter: 'series',
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

    // Use a very large initial page for infinite loop effect
    final initialPage = _bannerImageUrls.length * 1000;

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
                    // Infinite loop PageView
                    PageView.builder(
                      controller: PageController(initialPage: initialPage),
                      onPageChanged: (index) {
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
