import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';

class TrendingMovieComponent extends StatelessWidget {
  final String title;
  final List<Movie> movies;
  final Function(Movie) onMovieTap;
  final VoidCallback? onMore;

  const TrendingMovieComponent({
    super.key,
    required this.title,
    required this.movies,
    required this.onMovieTap,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onMore != null)
                TextButton.icon(
                  onPressed: onMore,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(
                    appConfig.translate('more'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              final movie = movies[index];
              return MovieCard(
                movie: movie,
                onTap: () => onMovieTap(movie),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Skeleton loading widget for a single movie card
class MovieCardSkeleton extends StatefulWidget {
  const MovieCardSkeleton({super.key});

  @override
  State<MovieCardSkeleton> createState() => _MovieCardSkeletonState();
}

class _MovieCardSkeletonState extends State<MovieCardSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0);
    final highlightColor = isDark ? const Color(0xFF3A3A3A) : const Color(0xFFF5F5F5);

    return Container(
      width: 130,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poster skeleton
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: LinearGradient(
                    begin: Alignment(-1.0 + (_controller.value * 2.0), 0),
                    end: Alignment(1.0 + (_controller.value * 2.0), 0),
                    colors: [
                      baseColor,
                      highlightColor,
                      baseColor,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: Container(),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // Title skeleton
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Container(
                height: 12,
                width: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: Alignment(-1.0 + (_controller.value * 2.0), 0),
                    end: Alignment(1.0 + (_controller.value * 2.0), 0),
                    colors: [
                      baseColor,
                      highlightColor,
                      baseColor,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // Year skeleton
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Container(
                height: 10,
                width: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: Alignment(-1.0 + (_controller.value * 2.0), 0),
                    end: Alignment(1.0 + (_controller.value * 2.0), 0),
                    colors: [
                      baseColor,
                      highlightColor,
                      baseColor,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Skeleton loading for a horizontal section (one row)
class TrendingMovieSkeleton extends StatelessWidget {
  final String title;

  const TrendingMovieSkeleton({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 250,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: const [
              MovieCardSkeleton(),
            ],
          ),
        ),
      ],
    );
  }
}
