import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';

/// Enum for different category filter types
enum CategoryFilterType {
  tag, // Filter by tag (e.g., K Drama, Animation, Anime, Bollywood, 4K)
  trendingMovies, // Filter: type=movie + isTrending=true
  trendingSeries, // Filter: type=series + isTrending=true
  genre, // Filter by genre/category
}

/// A reusable page for displaying filtered movie/series lists with pagination
class CategoryPage extends StatefulWidget {
  final String title;
  final CategoryFilterType filterType;
  final String? filterValue; // tag name or genre name
  final String? typeFilter; // optional 'movie' or 'series' to further filter

  const CategoryPage({
    super.key,
    required this.title,
    required this.filterType,
    this.filterValue,
    this.typeFilter,
  });

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final ScrollController _scrollController = ScrollController();

  List<Movie> _movies = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  // Track seen IDs to prevent duplicates
  final Set<String> _seenIds = {};

  @override
  void initState() {
    super.initState();
    _loadMovies();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  /// Add movies while deduplicating by ID
  List<Movie> _deduplicate(List<Movie> existing, List<Movie> incoming) {
    final result = <Movie>[...existing];
    for (final movie in incoming) {
      if (!_seenIds.contains(movie.id)) {
        _seenIds.add(movie.id);
        result.add(movie);
      }
    }
    return result;
  }

  Future<void> _loadMovies() async {
    setState(() => _isLoading = true);
    _seenIds.clear();
    try {
      Map<String, dynamic> result;

      switch (widget.filterType) {
        case CategoryFilterType.tag:
          result = await _contentService.getMoviesByTag(
            widget.filterValue!,
            limit: 20,
          );
          break;
        case CategoryFilterType.genre:
          result = await _contentService.getMoviesByGenre(
            widget.filterValue!,
            limit: 20,
          );
          break;
        case CategoryFilterType.trendingMovies:
          // Get all trending movies
          final trendingList = await _contentService.getTrendingMovies();
          if (mounted) {
            setState(() {
              _movies = trendingList;
              for (final m in trendingList) {
                _seenIds.add(m.id);
              }
              _hasMore = false;
              _isLoading = false;
            });
          }
          return;
        case CategoryFilterType.trendingSeries:
          // Get all trending series
          final trendingList = await _contentService.getTrendingTvShows();
          if (mounted) {
            setState(() {
              _movies = trendingList;
              for (final m in trendingList) {
                _seenIds.add(m.id);
              }
              _hasMore = false;
              _isLoading = false;
            });
          }
          return;
      }

      final newMovies = result['movies'] as List<Movie>;
      for (final m in newMovies) {
        _seenIds.add(m.id);
      }

      if (mounted) {
        setState(() {
          _movies = newMovies;
          _hasMore = result['hasMore'] as bool;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      Map<String, dynamic> result;

      switch (widget.filterType) {
        case CategoryFilterType.tag:
          result = await _contentService.getMoviesByTag(
            widget.filterValue!,
            limit: 20,
            startAfter: _lastDoc,
          );
          break;
        case CategoryFilterType.genre:
          result = await _contentService.getMoviesByGenre(
            widget.filterValue!,
            limit: 20,
            startAfter: _lastDoc,
          );
          break;
        default:
          // trending types don't paginate
          setState(() => _isLoadingMore = false);
          return;
      }

      final incomingMovies = result['movies'] as List<Movie>;
      final deduped = _deduplicate(_movies, incomingMovies);

      if (mounted) {
        setState(() {
          _movies = deduped;
          _hasMore = result['hasMore'] as bool && incomingMovies.isNotEmpty;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Apply type filter if specified (e.g., show only 'movie' or 'series' from tag results)
    List<Movie> displayedMovies = _movies;
    if (widget.typeFilter != null) {
      displayedMovies = _movies
          .where((m) => m.type == widget.typeFilter)
          .toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMovies,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Movie grid (3 columns)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.53,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final movie = displayedMovies[index];
                          return MovieCard(
                            movie: movie,
                            onTap: () => _navigateToDetail(movie),
                          );
                        },
                        childCount: displayedMovies.length,
                      ),
                    ),
                  ),

                  // Loading more indicator
                  if (_isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),

                  // Empty state
                  if (!_isLoading && displayedMovies.isEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 300,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.movie_filter_outlined,
                                size: 64,
                                color: theme.colorScheme.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No ${widget.title} yet',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Bottom spacing
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 16),
                  ),
                ],
              ),
            ),
    );
  }
}
