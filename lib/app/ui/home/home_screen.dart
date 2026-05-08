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
      // Load core data first
      final results = await Future.wait([
        _contentService.getTrendingMovies(),
        _contentService.getTrendingTvShows(),
        _recentService.getRecentMovies(),
        _contentService.getMovies(limit: 20),
        _contentService.getSeries(limit: 20),
      ]);

      if (mounted) {
        setState(() {
          _trendingMovies = results[0] as List<Movie>;
          _trendingTvShows = results[1] as List<Movie>;
          _recentMovies = results[2] as List<Movie>;
          _allMovies = results[3] is Map<String, dynamic>
              ? (results[3] as Map<String, dynamic>)['movies'] as List<Movie>
              : <Movie>[];
          _allSeries = results[4] is Map<String, dynamic>
              ? (results[4] as Map<String, dynamic>)['movies'] as List<Movie>
              : <Movie>[];
          _isLoading = false;
        });

        // Now load tag-based data
        _loadTagBasedData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadTagBasedData() async {
    final tagSections = <String, Future<List<Movie>>>{
      'K Drama': _contentService.getMoviesByTagSimple('K Drama'),
      '4K': _contentService.getMoviesByTagSimple('4K'),
      'Animation': _contentService.getMoviesByTagSimple('Animation'),
      'Anime': _contentService.getMoviesByTagSimple('Anime'),
      'Bollywood': _contentService.getMoviesByTagSimple('Bollywood'),
      'Donghua': _contentService.getMoviesByTagSimple('Donghua'),
      'C Drama': _contentService.getMoviesByTagSimple('C Drama'),
    };

    final results = await Future.wait(tagSections.values.toList());
    final tagNames = tagSections.keys.toList();

    if (mounted) {
      setState(() {
        for (int i = 0; i < tagNames.length; i++) {
          final movies = results[i];
          switch (tagNames[i]) {
            case 'K Drama':
              _kDramaMovies = movies;
              break;
            case '4K':
              _fourKMovies = movies;
              // Derive 4K Series from 4K tag results filtered by type
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
        }
      });
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            appConfig.translate('error_occurred'),
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadData,
            child: Text(appConfig.translate('retry')),
          ),
        ],
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
