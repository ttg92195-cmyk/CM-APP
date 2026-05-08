import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';
import 'package:cm_movies/app/ui/components/movie_list_tile.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/genres_tags_collections_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final RecentService _recentService = RecentService();

  List<Movie> _trendingMovies = [];
  List<Movie> _trendingTvShows = [];
  List<Movie> _recentMovies = [];
  List<Movie> _allMovies = [];
  List<Movie> _allSeries = [];

  // Tag-based lists
  List<Movie> _kDramaMovies = [];
  List<Movie> _fourKMovies = [];
  List<Movie> _fourKSeries = [];
  List<Movie> _animationMovies = [];
  List<Movie> _animeMovies = [];
  List<Movie> _bollywoodMovies = [];
  List<Movie> _donghuaMovies = [];
  List<Movie> _cDramaMovies = [];

  bool _isLoading = true;
  String? _error;

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
      // Load each query independently to avoid one failure blocking all
      List<Movie> trendingMovies = [];
      List<Movie> trendingTvShows = [];
      List<Movie> recentMovies = [];
      List<Movie> allMovies = [];
      List<Movie> allSeries = [];

      // Load core data with individual error handling
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
        recentMovies = await _recentService.getRecentMovies();
      } catch (e) {
        debugPrint('Error loading recent movies: $e');
      }

      try {
        final moviesResult = await _contentService.getMovies(limit: 20);
        allMovies = List<Movie>.from(moviesResult['movies'] ?? []);
      } catch (e) {
        debugPrint('Error loading all movies: $e');
      }

      try {
        final seriesResult = await _contentService.getSeries(limit: 20);
        allSeries = List<Movie>.from(seriesResult['movies'] ?? []);
      } catch (e) {
        debugPrint('Error loading all series: $e');
      }

      if (mounted) {
        setState(() {
          _trendingMovies = trendingMovies;
          _trendingTvShows = trendingTvShows;
          _recentMovies = recentMovies;
          _allMovies = allMovies;
          _allSeries = allSeries;
          _isLoading = false;
        });

        // Now load tag-based data
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
      MapEntry('K Drama', _contentService.getMoviesByTagSimple('K Drama')),
      MapEntry('4K', _contentService.getMoviesByTagSimple('4K')),
      MapEntry('Animation', _contentService.getMoviesByTagSimple('Animation')),
      MapEntry('Anime', _contentService.getMoviesByTagSimple('Anime')),
      MapEntry('Bollywood', _contentService.getMoviesByTagSimple('Bollywood')),
      MapEntry('Donghua', _contentService.getMoviesByTagSimple('Donghua')),
      MapEntry('C Drama', _contentService.getMoviesByTagSimple('C Drama')),
    ];

    // Load each tag query independently to avoid one failure blocking all
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
                _fourKMovies = movies;
                _fourKSeries = movies.where((m) => m.type == 'series').toList();
                if (_fourKSeries.isEmpty) _fourKSeries = movies;
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
              case 'Donghua':
                _donghuaMovies = movies;
                break;
              case 'C Drama':
                _cDramaMovies = movies;
                break;
            }
          });
        }
      } catch (e) {
        debugPrint('Error loading tag ${entry.key}: $e');
      }
    }
  }

  void _navigateToDetail(Movie movie) {
    final isSeries = movie.type == 'series';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isSeries
            ? SeriesDetailScreen(slug: movie.slug)
            : MovieDetailScreen(slug: movie.slug),
      ),
    ).then((_) {
      _recentService.getRecentMovies().then((recents) {
        if (mounted) {
          setState(() {
            _recentMovies = recents;
          });
        }
      });
    });
  }

  void _navigateToMoreByTag(String tagName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FilterResultPage(
          title: tagName,
          tagName: tagName,
        ),
      ),
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
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorWidget(appConfig)
                : _buildContent(appConfig, theme),
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
              movies: _allMovies.length > 20 ? _allMovies.sublist(0, 20) : _allMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('Featured Movies'),
            ),

          const SizedBox(height: 8),

          // Series Section
          if (_allSeries.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('series'),
              movies: _allSeries.length > 20 ? _allSeries.sublist(0, 20) : _allSeries,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('Trending'),
            ),

          const SizedBox(height: 8),

          // Trending Movies
          if (_trendingMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('trending_movies'),
              movies: _trendingMovies,
              onMovieTap: _navigateToDetail,
            ),

          const SizedBox(height: 8),

          // Trending TV Shows
          if (_trendingTvShows.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('trending_tv_shows'),
              movies: _trendingTvShows,
              onMovieTap: _navigateToDetail,
            ),

          const SizedBox(height: 8),

          // K Drama
          if (_kDramaMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('k_drama'),
              movies: _kDramaMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('K Drama'),
            ),

          const SizedBox(height: 8),

          // 4K Movies
          if (_fourKMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('4k_movies'),
              movies: _fourKMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('4K'),
            ),

          const SizedBox(height: 8),

          // 4K Series
          if (_fourKSeries.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('4k_series'),
              movies: _fourKSeries,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('4K'),
            ),

          const SizedBox(height: 8),

          // Animation
          if (_animationMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('animation'),
              movies: _animationMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('Animation'),
            ),

          const SizedBox(height: 8),

          // Anime
          if (_animeMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('anime'),
              movies: _animeMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('Anime'),
            ),

          const SizedBox(height: 8),

          // Bollywood
          if (_bollywoodMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('bollywood'),
              movies: _bollywoodMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('Bollywood'),
            ),

          const SizedBox(height: 8),

          // Donghua
          if (_donghuaMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('donghua'),
              movies: _donghuaMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('Donghua'),
            ),

          const SizedBox(height: 8),

          // C Drama
          if (_cDramaMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('c_drama'),
              movies: _cDramaMovies,
              onMovieTap: _navigateToDetail,
              onMore: () => _navigateToMoreByTag('C Drama'),
            ),

          const SizedBox(height: 16),

          // Recently Viewed
          if (_recentMovies.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    appConfig.translate('recently_viewed'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await _recentService.clearRecents();
                      setState(() {
                        _recentMovies = [];
                      });
                    },
                    child: Text(
                      appConfig.translate('clear_history'),
                      style: TextStyle(color: Colors.redAccent.shade200),
                    ),
                  ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentMovies.length > 10 ? 10 : _recentMovies.length,
              itemBuilder: (context, index) {
                final movie = _recentMovies[index];
                return MovieListTile(
                  movie: movie,
                  onTap: () => _navigateToDetail(movie),
                );
              },
            ),
          ],

          // Empty state
          if (_trendingMovies.isEmpty &&
              _trendingTvShows.isEmpty &&
              _allMovies.isEmpty &&
              _allSeries.isEmpty &&
              _recentMovies.isEmpty)
            SizedBox(
              height: 300,
              child: Center(
                child: Text(
                  appConfig.translate('no_results'),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ),

          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
