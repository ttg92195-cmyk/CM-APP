import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  List<Movie> _trendingMovies = [];
  List<Movie> _trendingTvShows = [];
  List<Movie> _allMovies = [];
  List<Movie> _allSeries = [];

  // Tag-based lists
  List<Movie> _kDramaMovies = [];
  List<Movie> _fourKMovies = [];
  List<Movie> _fourKSeries = [];
  List<Movie> _animationMovies = [];
  List<Movie> _animeMovies = [];
  List<Movie> _bollywoodMovies = [];

  bool _isLoading = true;
  String? _error;

  static const int _homeLimit = 10; // Show 10 posts per section on Home

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      List<Movie> trendingMovies = [];
      List<Movie> trendingTvShows = [];
      List<Movie> allMovies = [];
      List<Movie> allSeries = [];

      try {
        trendingMovies = await _contentService.getTrendingMovies();
      } catch (e) {
        debugPrint('Error loading trending movies: $e');
      }

      try {
        trendingTvShows = await _contentService.getTrendingTvShows();
      } catch (e) {
        debugPrint('Error loading trending TV shows: $e');
      }

      try {
        final moviesResult = await _contentService.getMovies(limit: _homeLimit);
        allMovies = List<Movie>.from(moviesResult['movies'] ?? []);
      } catch (e) {
        debugPrint('Error loading all movies: $e');
      }

      try {
        final seriesResult = await _contentService.getSeries(limit: _homeLimit);
        allSeries = List<Movie>.from(seriesResult['movies'] ?? []);
      } catch (e) {
        debugPrint('Error loading all series: $e');
      }

      if (mounted) {
        setState(() {
          _trendingMovies = trendingMovies;
          _trendingTvShows = trendingTvShows;
          _allMovies = allMovies;
          _allSeries = allSeries;
          _isLoading = false;
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

    for (final entry in tagEntries) {
      try {
        final movies = await entry.value;
        if (mounted) {
          setState(() {
            switch (entry.key) {
              case 'K Drama':
                _kDramaMovies = movies;
                break;
              case '4K':
                _fourKMovies = movies.where((m) => m.type == 'movie').toList();
                _fourKSeries = movies.where((m) => m.type == 'series').toList();
                if (_fourKMovies.isEmpty && movies.isNotEmpty) {
                  _fourKMovies = movies;
                }
                if (_fourKSeries.isEmpty && movies.isNotEmpty) {
                  _fourKSeries = movies;
                }
                break;
              case 'Animation':
                _animationMovies = movies;
                break;
              case 'Anime':
                _animeMovies = movies;
                break;
              case 'Bollywood':
                _bollywoodMovies = movies;
                break;
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading tag ${entry.key}: $e');
      }
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
        child: _isLoading
            ? _buildSkeletonLoading(theme, appConfig)
            : _error != null
                ? _buildErrorWidget(appConfig)
                : _buildContent(appConfig, theme),
      ),
    );
  }

  /// Skeleton loading with shimmer effect - one poster per section
  Widget _buildSkeletonLoading(ThemeData theme, AppConfig appConfig) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TrendingMovieSkeleton(title: 'Movies'),
          const SizedBox(height: 8),
          const TrendingMovieSkeleton(title: 'Series'),
          const SizedBox(height: 8),
          const TrendingMovieSkeleton(title: 'Trending'),
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
            const SizedBox(height: 8),
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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 8),

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

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
