import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/components/safe_text.dart';

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

    // Show 10 movies max for horizontal scroll
    final displayMovies = movies.length > 10 ? movies.sublist(0, 10) : movies;
    const cardWidth = 120.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: SafeText(
                  title,
                  maxLines: 1,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (onMore != null)
                TextButton.icon(
                  onPressed: onMore,
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: SafeText(
                    appConfig.translate('more'),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFE50914),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: Colors.transparent,
                  ),
                ),
            ],
          ),
        ),
        // Horizontal scrollable list
        SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: displayMovies.length,
            itemBuilder: (context, index) {
              final movie = displayMovies[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: MovieCard(
                  movie: movie,
                  cardWidth: cardWidth,
                  onTap: () => onMovieTap(movie),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Skeleton loading widget for a single movie card with shimmer pulse
class MovieCardSkeleton extends StatefulWidget {
  final double? cardWidth; // Optional fixed width for horizontal lists

  const MovieCardSkeleton({super.key, this.cardWidth});

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
    )..repeat(reverse: true);
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

    Widget skeletonContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poster skeleton
            Container(
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 4),
            // Title skeleton
            Container(
              height: 12,
              width: double.infinity,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            // Year skeleton
            Container(
              height: 10,
              width: 50,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        );

    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
      child: widget.cardWidth != null
          ? Container(
              width: widget.cardWidth,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: skeletonContent,
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: skeletonContent,
            ),
    );
  }
}

/// Skeleton loading for a horizontal section (one row with multiple posters)
class TrendingMovieSkeleton extends StatelessWidget {
  final String title;
  final int count;

  const TrendingMovieSkeleton({super.key, required this.title, this.count = 5});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: count,
            itemBuilder: (context, index) {
              return const MovieCardSkeleton(cardWidth: 130);
            },
          ),
        ),
      ],
    );
  }
}

/// Skeleton loading for the banner slider
class BannerSkeleton extends StatefulWidget {
  const BannerSkeleton({super.key});

  @override
  State<BannerSkeleton> createState() => _BannerSkeletonState();
}

class _BannerSkeletonState extends State<BannerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.4, end: 1.0).animate(_controller),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Dots indicator skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: index == 0 ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(3),
              ),
            )),
          ),
        ],
      ),
    );
  }
}
