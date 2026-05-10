import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/app/core/models/movie.dart';

class MovieCard extends StatelessWidget {
  final Movie movie;
  final VoidCallback onTap;

  const MovieCard({
    super.key,
    required this.movie,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Poster with overlays
            Stack(
              children: [
                // Poster Image
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: movie.fullPosterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: movie.fullPosterUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.movie,
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                                size: 40,
                              ),
                            ),
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.movie,
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                              size: 40,
                            ),
                          ),
                  ),
                ),

                // Quality Badge - top left corner
                if (movie.resolution != null && movie.resolution!.isNotEmpty)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getQualityBadgeColor(movie.resolution!),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        _getQualityLabel(movie.resolution!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // IMDb Rating Badge - bottom right corner
                if (movie.rating != null && movie.rating!.isNotEmpty)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star,
                            size: 10,
                            color: Color(0xFFFFC107),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            movie.rating!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontSize: 11,
                ),
              ),
            ),
            // Year below title
            if (movie.year != null && movie.year!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  movie.year!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Get standardized quality label from resolution string
  static String _getQualityLabel(String resolution) {
    final r = resolution.toLowerCase();
    if (r.contains('4k') || r.contains('uhd')) return '4K';
    if (r.contains('1080')) return '1080p';
    if (r.contains('720')) return '720p';
    if (r.contains('480')) return '480p';
    if (r.contains('hd') && !r.contains('fhd')) return '720p';
    if (r.contains('fhd')) return '1080p';
    return resolution;
  }

  /// Get badge color based on quality
  static Color _getQualityBadgeColor(String resolution) {
    final r = resolution.toLowerCase();
    if (r.contains('4k') || r.contains('uhd')) return const Color(0xFFE50914); // Red
    if (r.contains('1080') || r.contains('fhd')) return const Color(0xFFFF6D00); // Orange
    if (r.contains('720') || r.contains('hd')) return const Color(0xFFFFAB00); // Amber
    return const Color(0xFF4CAF50); // Green for others
  }
}
