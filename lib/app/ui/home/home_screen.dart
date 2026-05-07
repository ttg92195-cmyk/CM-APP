import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/api_service.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';
import 'package:cm_movies/app/ui/components/movie_list_tile.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  final RecentService _recentService = RecentService();

  List<Movie> _trendingMovies = [];
  List<Movie> _trendingTvShows = [];
  List<Movie> _recentMovies = [];
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
      final results = await Future.wait([
        _apiService.getTrendingMovies(),
        _apiService.getTrendingTvShows(),
        _recentService.getRecentMovies(),
      ]);
      if (mounted) {
        setState(() {
          _trendingMovies = results[0] as List<Movie>;
          _trendingTvShows = results[1] as List<Movie>;
          _recentMovies = results[2] as List<Movie>;
          _isLoading = false;
        });
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

  void _navigateToDetail(Movie movie) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MovieDetailScreen(slug: movie.slug),
      ),
    ).then((_) {
      // Refresh recent list when returning
      _recentService.getRecentMovies().then((recents) {
        if (mounted) {
          setState(() {
            _recentMovies = recents;
          });
        }
      });
    });
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
          // Trending Movies
          if (_trendingMovies.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('trending_movies'),
              movies: _trendingMovies,
              onMovieTap: _navigateToDetail,
            ),

          const SizedBox(height: 16),

          // Trending TV Shows
          if (_trendingTvShows.isNotEmpty)
            TrendingMovieComponent(
              title: appConfig.translate('trending_tv_shows'),
              movies: _trendingTvShows,
              onMovieTap: _navigateToDetail,
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
