import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';

class RecentPage extends StatefulWidget {
  const RecentPage({super.key});

  @override
  State<RecentPage> createState() => _RecentPageState();
}

class _RecentPageState extends State<RecentPage> {
  final RecentService _recentService = RecentService();
  List<Movie> _recentMovies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecents();
  }

  Future<void> _loadRecents() async {
    final recents = await _recentService.getRecentMovies();
    if (mounted) {
      setState(() {
        _recentMovies = recents;
        _isLoading = false;
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
    ).then((_) => _loadRecents());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recent'),
      ),
      body: _isLoading
          ? _buildSkeletonLoading()
          : _recentMovies.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No recently viewed',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    setState(() => _isLoading = true);
                    await _loadRecents();
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
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
                              final movie = _recentMovies[index];
                              return MovieCard(
                                movie: movie,
                                onTap: () => _navigateToDetail(movie),
                              );
                            },
                            childCount: _recentMovies.length,
                          ),
                        ),
                      ),

                      // Clear button
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: TextButton.icon(
                              onPressed: () async {
                                await _recentService.clearRecents();
                                _loadRecents();
                              },
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Clear History'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                              ),
                            ),
                          ),
                        ),
                      ),

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
      itemCount: 6,
      itemBuilder: (context, index) {
        return const MovieCardSkeleton();
      },
    );
  }
}
