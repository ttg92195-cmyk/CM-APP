import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/api_service.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';
import 'package:cm_movies/app/ui/components/movie_list_tile.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/genres_tags_collections_page.dart';

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

  List<TagAndGenres> _apiTags = [];

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
        _apiService.getTrendingMovies(),
        _apiService.getTrendingTvShows(),
        _recentService.getRecentMovies(),
        _apiService.getMovies(page: 1),
        _apiService.getTvShows(page: 1),
        _apiService.getMovieTags(),
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
          _apiTags = results[5] as List<TagAndGenres>;
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
    // Map tag names to their API IDs
    final tagMap = <String, int>{};
    for (final tag in _apiTags) {
      tagMap[tag.name.toLowerCase()] = tag.id;
    }

    // Load each tag-based section
    final futures = <Future<void>>[];

    final tagSections = {
      'k drama': () async {
        final id = tagMap['k drama'];
        if (id != null) {
          try {
            final result = await _apiService.getMoviesByTag(id, page: 1);
            if (mounted) {
              setState(() => _kDramaMovies = result['movies'] as List<Movie>);
            }
          } catch (_) {}
        }
      },
      '4k': () async {
        final id = tagMap['4k'];
        if (id != null) {
          try {
            final result = await _apiService.getMoviesByTag(id, page: 1);
            if (mounted) {
              setState(() {
                _fourKMovies = result['movies'] as List<Movie>;
              });
            }
          } catch (_) {}
        }
      },
      'animation': () async {
        final id = tagMap['animation'];
        if (id != null) {
          try {
            final result = await _apiService.getMoviesByTag(id, page: 1);
            if (mounted) {
              setState(() {
                _animationMovies = result['movies'] as List<Movie>;
              });
            }
          } catch (_) {}
        }
      },
      'anime': () async {
        final id = tagMap['anime'];
        if (id != null) {
          try {
            final result = await _apiService.getMoviesByTag(id, page: 1);
            if (mounted) {
              setState(() => _animeMovies = result['movies'] as List<Movie>);
            }
          } catch (_) {}
        }
      },
      'bollywood': () async {
        final id = tagMap['bollywood'];
        if (id != null) {
          try {
            final result = await _apiService.getMoviesByTag(id, page: 1);
            if (mounted) {
              setState(() => _bollywoodMovies = result['movies'] as List<Movie>);
            }
          } catch (_) {}
        }
      },
      'donghua': () async {
        final id = tagMap['donghua'];
        if (id != null) {
          try {
            final result = await _apiService.getMoviesByTag(id, page: 1);
            if (mounted) {
              setState(() => _donghuaMovies = result['movies'] as List<Movie>);
            }
          } catch (_) {}
        }
      },
      'c drama': () async {
        final id = tagMap['c drama'];
        if (id != null) {
          try {
            final result = await _apiService.getMoviesByTag(id, page: 1);
            if (mounted) {
              setState(() => _cDramaMovies = result['movies'] as List<Movie>);
            }
          } catch (_) {}
        }
      },
    };

    for (final entry in tagSections.entries) {
      futures.add(entry.value());
    }

    await Future.wait(futures);

    // Derive 4K Series from 4K tag results (we'll just use the 4K movies list)
    if (_fourKMovies.isNotEmpty) {
      // The API returns all items with 4K tag - some might be series
      // We'll show the same list for now
      if (mounted) {
        setState(() => _fourKSeries = _fourKMovies);
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
    final match = _apiTags.where(
      (t) => t.name.toLowerCase() == tagName.toLowerCase(),
    ).toList();

    if (match.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FilterResultPage(
            title: tagName,
            fetchFn: (page) =>
                _apiService.getMoviesByTag(match.first.id, page: page),
          ),
        ),
      );
    }
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
