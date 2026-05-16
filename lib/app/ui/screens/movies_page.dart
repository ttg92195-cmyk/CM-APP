import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';

class MoviesPage extends StatefulWidget {
  const MoviesPage({super.key});

  @override
  State<MoviesPage> createState() => _MoviesPageState();
}

class _MoviesPageState extends State<MoviesPage> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final ScrollController _scrollController = ScrollController();

  List<Movie> _movies = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final Set<String> _seenIds = {};
  bool _isFirstLoad = true;

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

  /// Called when this tab becomes active (from HomePage)
  /// Refreshes data to show newly added posts
  void onTabSelected() {
    if (_isFirstLoad) {
      _isFirstLoad = false;
      return; // initState already loads on first time
    }
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _seenIds.clear();
      _lastDoc = null;
      _hasMore = true;
    });
    await _loadMovies();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadMovies() async {
    setState(() => _isLoading = true);
    try {
      final stopwatch = Stopwatch()..start();
      final result = await _contentService.getMovies(limit: 20);
      // Ensure skeleton shows for at least 600ms so it doesn't flash too fast
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsed));
      }
      if (mounted) {
        final movies = result['movies'] as List<Movie>;
        for (final m in movies) {
          _seenIds.add(m.id);
        }
        setState(() {
          _movies = movies;
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
      final result = await _contentService.getMovies(
        limit: 20,
        startAfter: _lastDoc,
      );
      if (mounted) {
        final incoming = result['movies'] as List<Movie>;
        // Deduplicate by ID to prevent duplicates
        final newMovies = <Movie>[];
        for (final m in incoming) {
          if (!_seenIds.contains(m.id)) {
            _seenIds.add(m.id);
            newMovies.add(m);
          }
        }
        setState(() {
          _movies.addAll(newMovies);
          _hasMore = result['hasMore'] as bool && incoming.isNotEmpty;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _isLoading
          ? _buildSkeletonLoading()
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
                          final movie = _movies[index];
                          return MovieCard(
                            movie: movie,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => movie.type == 'series'
                                      ? SeriesDetailScreen(slug: movie.slug)
                                      : MovieDetailScreen(slug: movie.slug),
                                ),
                              );
                            },
                          );
                        },
                        childCount: _movies.length,
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
                  if (!_isLoading && _movies.isEmpty)
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
                                'No movies yet',
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

  Widget _buildSkeletonLoading() {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.53,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return const MovieCardSkeleton();
      },
    );
  }
}
