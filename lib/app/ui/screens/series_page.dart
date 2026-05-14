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
      final result = await _contentService.getSeries(limit: 20);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _contentService.getSeries(
        limit: 20,
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
              onRefresh: _loadSeries,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Series grid (3 columns)
                  SliverPadding(
                    padding: const EdgeInsets.all(8),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.55,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
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
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return const MovieCardSkeleton();
      },
    );
  }
}
