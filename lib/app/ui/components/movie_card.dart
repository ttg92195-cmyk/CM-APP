import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/poster_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MovieCard extends StatefulWidget {
  final Movie movie;
  final VoidCallback onTap;
  final double? cardWidth; // Optional fixed width for horizontal lists

  const MovieCard({
    super.key,
    required this.movie,
    required this.onTap,
    this.cardWidth,
  });

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  double? _watchProgress; // 0.0 to 1.0, null = not watched

  // STATIC CACHE of SharedPreferences instance across ALL MovieCard
  // instances. Without this, every card calls
  // `SharedPreferences.getInstance()` independently — and although
  // getInstance() returns a cached Future after the first call, each
  // call still schedules a microtask on the event loop. With 100+
  // cards on a Movies/Series grid, that's 100+ microtasks queued
  // before any card can read its watch progress, delaying the
  // progress bar from appearing and adding to first-screen jank.
  //
  // By caching the resolved instance in a static field, only the
  // FIRST card ever awaits getInstance(); subsequent cards skip the
  // await entirely and go straight to the synchronous getInt() calls.
  // This is safe because SharedPreferences is a process-wide singleton
  // and the underlying map is in-memory after init.
  static SharedPreferences? _prefsCache;

  @override
  void initState() {
    super.initState();
    _loadWatchProgress();
  }

  Future<void> _loadWatchProgress() async {
    // Reuse the cached instance if available; otherwise await the
    // first init. Subsequent cards in the same grid build will hit
    // the cache and skip the await.
    final prefs = _prefsCache ??= await SharedPreferences.getInstance();
    final posMs = prefs.getInt('watch_pos_${widget.movie.id}');
    final durMs = prefs.getInt('watch_dur_${widget.movie.id}');
    if (posMs != null && durMs != null && posMs > 5000 && durMs > 0) {
      final progress = (posMs / durMs).clamp(0.0, 1.0);
      if (progress < 0.95 && mounted) {
        setState(() => _watchProgress = progress);
      }
    }
  }

  String _formatWatchPosition() {
    if (_watchProgress == null) return '';
    // We'll show percentage-based position
    final percent = (_watchProgress! * 100).round();
    return '$percent%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget cardContent = Column(
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
                    child: widget.movie.fullPosterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.movie.fullPosterUrl,
                            cacheManager: PosterCacheManager.instance,
                            cacheKey: widget.movie.id, // stable key per movie
                            fit: BoxFit.cover,
                            fadeInDuration: const Duration(milliseconds: 200),
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
                if (widget.movie.resolution != null && widget.movie.resolution!.isNotEmpty)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getQualityBadgeColor(widget.movie.resolution!),
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
                        _getQualityLabel(widget.movie.resolution!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                // IMDb Rating Badge - bottom right corner
                // Always shown. When the rating is null/empty/0.0, we display
                // "N/A" via _formatRating() instead of hiding the badge — Bro
                // reported that hiding it looked inconsistent across the grid
                // (some posters had the badge, some didn't, no obvious reason
                // why). Always-on with N/A fallback gives visual consistency.
                // The flame icon stays red regardless of the rating value so
                // the badge's visual weight doesn't change between real and
                // placeholder values.
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
                            Icons.local_fire_department,
                            size: 10,
                            color: Color(0xFFFF4444),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _formatRating(widget.movie.rating),
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

                // Feature 5: Watch Progress Bar — bottom of poster (YouTube-style)
                if (_watchProgress != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Thin progress bar at bottom of poster
                        ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                          child: Stack(
                            children: [
                              // Background
                              Container(
                                height: 3,
                                color: Colors.white24,
                              ),
                              // Progress fill
                              FractionallySizedBox(
                                widthFactor: _watchProgress!,
                                child: Container(
                                  height: 3,
                                  color: const Color(0xFFE50914),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                widget.movie.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  fontSize: 11,
                ),
              ),
            ),
            // Year + Duration/Season + Watch progress indicator below title
            if (widget.movie.year != null && widget.movie.year!.isNotEmpty ||
                _watchProgress != null ||
                (widget.movie.type == 'series' && widget.movie.seasons != null && widget.movie.seasons!.isNotEmpty) ||
                (widget.movie.type != 'series' && widget.movie.duration != null && widget.movie.duration!.isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.movie.year != null && widget.movie.year!.isNotEmpty)
                            Flexible(
                              child: Text(
                                widget.movie.year!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          // Show "Season X" for series, or duration for movies
                          if (widget.movie.type == 'series' && widget.movie.seasons != null && widget.movie.seasons!.isNotEmpty) ...[
                            if (widget.movie.year != null && widget.movie.year!.isNotEmpty)
                              const SizedBox(width: 4),
                            Icon(
                              Icons.tv,
                              size: 10,
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                'Season ${widget.movie.seasons}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ] else if (widget.movie.type != 'series' && widget.movie.duration != null && widget.movie.duration!.isNotEmpty) ...[
                            if (widget.movie.year != null && widget.movie.year!.isNotEmpty)
                              const SizedBox(width: 4),
                            Icon(
                              Icons.access_time,
                              size: 10,
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                '${widget.movie.duration} min',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_watchProgress != null) ...[
                      if (widget.movie.year != null && widget.movie.year!.isNotEmpty ||
                          (widget.movie.type == 'series' && widget.movie.seasons != null && widget.movie.seasons!.isNotEmpty) ||
                          (widget.movie.type != 'series' && widget.movie.duration != null && widget.movie.duration!.isNotEmpty))
                        const SizedBox(width: 4),
                      Icon(
                        Icons.play_circle_filled,
                        size: 10,
                        color: const Color(0xFFE50914).withOpacity(0.8),
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          _formatWatchPosition(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: const Color(0xFFE50914).withOpacity(0.8),
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );

    return GestureDetector(
      onTap: widget.onTap,
      child: widget.cardWidth != null
          ? SizedBox(
              width: widget.cardWidth,
              child: cardContent,
            )
          : cardContent,
    );
  }

  /// Format rating: show "N/A" if null, empty, or 0.0.
  /// Used for the always-on rating badge — Bro reported that hiding the
  /// badge when rating was missing looked inconsistent across the grid,
  /// so we now always show the badge and fall back to "N/A" when there
  /// is no real rating value.
  static String _formatRating(String? rating) {
    if (rating == null || rating.trim().isEmpty) return 'N/A';
    final parsed = double.tryParse(rating);
    if (parsed == null || parsed == 0.0) return 'N/A';
    return rating;
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
