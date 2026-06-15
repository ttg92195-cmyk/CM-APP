import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';

class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key});

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final ScrollController _scrollController = ScrollController();

  List<Movie> _series = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  final Set<String> _seenIds = {};
  bool _isFirstLoad = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSeries();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Called when this tab becomes active (from HomePage)
  /// Always refreshes to show skeleton loading first, then fresh data.
  /// This ensures users see the skeleton shimmer effect when navigating
  /// from Home via the "More" button, rather than stale data.
  void onTabSelected() {
    _isFirstLoad = false;
    _refreshData();
  }

  Future<void> _refreshData() async {
    setState(() {
      _series = [];  // Clear series so skeleton shows during refresh
      _seenIds.clear();
      _lastDoc = null;
      _hasMore = true;
      _errorMessage = null;
    });
    await _loadSeries();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadSeries() async {
    setState(() => _isLoading = true);
    try {
      final stopwatch = Stopwatch()..start();
      final result = await _contentService.getSeries(limit: 50);
      // Ensure skeleton shows for at least 600ms so it doesn't flash too fast
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 600) {
        await Future.delayed(Duration(milliseconds: 600 - elapsed));
      }
      if (mounted) {
        final seriesList = result['movies'] as List<Movie>;
        for (final m in seriesList) {
          _seenIds.add(m.id);
        }
        setState(() {
          _series = seriesList;
          _hasMore = result['hasMore'] as bool;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading series: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _contentService.getSeries(
        limit: 50,
        startAfter: _lastDoc,
      );
      if (mounted) {
        final incoming = result['movies'] as List<Movie>;
        // Deduplicate by ID to prevent duplicates
        final newSeries = <Movie>[];
        for (final m in incoming) {
          if (!_seenIds.contains(m.id)) {
            _seenIds.add(m.id);
            newSeries.add(m);
          }
        }
        setState(() {
          _series.addAll(newSeries);
          _hasMore = result['hasMore'] as bool && incoming.isNotEmpty;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading more series: $e');
      if (mounted) setState(() => _isLoadingMore = false);
      // Don't block UI — user can keep scrolling, next load more will retry
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: _isLoading
          ? _buildSkeletonLoading()
          : RefreshIndicator(
              onRefresh: _loadSeries,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Series grid (3 columns)
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
                          final series = _series[index];
                          return MovieCard(
                            movie: series,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SeriesDetailScreen(slug: series.slug),
                                ),
                              );
                            },
                          );
                        },
                        childCount: _series.length,
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
                  if (!_isLoading && _series.isEmpty)
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 300,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.tv_outlined,
                                size: 64,
                                color: theme.colorScheme.onSurface.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No series yet',
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
