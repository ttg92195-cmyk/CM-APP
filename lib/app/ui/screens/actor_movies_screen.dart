import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';

/// Screen showing movies/series from Firestore that feature a specific actor.
/// Only shows items already in the library — no TMDB results.
class ActorMoviesScreen extends StatefulWidget {
  final String actorName;

  const ActorMoviesScreen({super.key, required this.actorName});

  @override
  State<ActorMoviesScreen> createState() => _ActorMoviesScreenState();
}

class _ActorMoviesScreenState extends State<ActorMoviesScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();

  List<Movie> _movies = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadActorMovies();
  }

  Future<void> _loadActorMovies() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Search Firestore for movies/series that have this actor in their casts array
      final movies = await _contentService.getMoviesByActor(widget.actorName);
      if (mounted) {
        setState(() {
          _movies = movies;
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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.actorName),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 48,
                          color: isDark ? Colors.white24 : Colors.black12),
                      const SizedBox(height: 12),
                      Text('Failed to load movies',
                          style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontSize: 14)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadActorMovies,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _movies.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.movie_filter_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.3)),
                          const SizedBox(height: 16),
                          Text(
                            'No movies found for ${widget.actorName}',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
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
                                  onTap: () => _navigateToDetail(movie),
                                );
                              },
                              childCount: _movies.length,
                            ),
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: 16),
                        ),
                      ],
                    ),
    );
  }
}
