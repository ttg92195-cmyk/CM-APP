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

  // Task 40 — poster load retry counter.
  // cached_network_image does NOT auto-retry on transient failures
  // (TMDB 429 rate-limit, brief 502, flaky mobile-data handoffs).
  // Once errorWidget fires, it stays fired forever — even after the
  // network recovers. We track a per-card attempt count and let the
  // user tap the error placeholder to retry (and also auto-retry once
  // the first time, since most TMDB failures are transient).
  int _posterRetryCount = 0;
  static const int _maxAutoRetries = 1;

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
    // Phase 4.38 — raised threshold from 5s → 30s. 5s was too low:
    // any accidental tap that briefly started playback (then closed)
    // would leave a progress bar artifact on the home grid forever.
    // 30s of deliberate watching is a much stronger signal that the
    // user actually wants to resume later.
    if (posMs != null && durMs != null && posMs > 30000 && durMs > 0) {
      final progress = (posMs / durMs).clamp(0.0, 1.0);
      if (progress < 0.95 && mounted) {
        setState(() => _watchProgress = progress);
      }
    }
  }

  // Task 40 — image URL with cache-busting retry suffix.
  // On retry, append `?retry=N` (or `&retry=N` if URL already has a
  // query string) so that CachedNetworkImage's URL-keyed in-memory
  // cache treats it as a new request. Combined with the cacheKey bump
  // (which handles the on-disk cache), this guarantees a fresh fetch
  // from the network on each retry attempt.
  String get _posterImageUrl {
    if (_posterRetryCount == 0) return widget.movie.fullPosterUrl;
    final sep = widget.movie.fullPosterUrl.contains('?') ? '&' : '?';
    return '${widget.movie.fullPosterUrl}${sep}retry=$_posterRetryCount';
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
            //
            // Task 38 Req 1: Wrap the poster in a Container with a subtle
            // boxShadow. In dark mode the poster sits on a 0xFF121212
            // scaffold background — without a shadow the poster's edges
            // blend into the background and the poster looks "dull" /
            // visually flat (Bro's complaint). The shadow gives the
            // poster a subtle lift off the page so it reads as a
            // distinct element. In light mode the shadow is barely
            // visible (low opacity) — posters already have good
            // contrast against the light scaffold.
            //
            // Performance: boxShadow on a Container is GPU-composited
            // and is cheap relative to the CachedNetworkImage decode
            // already happening on this card. With ~9-12 visible cards
            // in a 3-column grid, the cost is negligible.
            Stack(
              children: [
                // Poster Image (wrapped in shadow Container)
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.45 : 0.12),
                        blurRadius: isDark ? 4 : 2,
                        spreadRadius: 0,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: widget.movie.fullPosterUrl.isNotEmpty
                          ? CachedNetworkImage(
                              // Task 40 — append a cache-busting query param
                              // on retry so cached_network_image doesn't
                              // reuse the previously-failed cached entry.
                              // Without this, the "retry" would just read
                              // the same broken cache file and instantly
                              // fail again. The `_posterRetryCount` is
                              // also used by `cacheKey` below to force a
                              // fresh fetch from network.
                              imageUrl: _posterImageUrl,
                              cacheManager: PosterCacheManager.instance,
                              // Task 40 — cacheKey combines movie.id +
                              // retry count. When the user (or auto-retry)
                              // bumps the count, cacheKey changes, the
                              // cache manager treats it as a miss, and
                              // a fresh network fetch happens. Stable
                              // across rebuilds as long as retry count
                              // doesn't change.
                              cacheKey: '${widget.movie.id}_r$_posterRetryCount',
                              fit: BoxFit.cover,
                              // Task 40 — decode the poster at a smaller
                              // resolution in memory. A typical phone
                              // shows ~3 columns of posters at ~120-160px
                              // wide each; TMDB's original posters are
                              // 500-1000px wide. Decoding at full
                              // resolution wastes memory (each poster
                              // ~500KB-1MB in decoded form) and slows
                              // down the grid on devices with limited
                              // RAM — leading to posters appearing
                              // "stuck" or never loading when many are
                              // visible at once. memCacheWidth=400 keeps
                              // decoded size ~200KB per poster while
                              // remaining visually crisp on phones.
                              memCacheWidth: 400,
                              fadeInDuration: const Duration(milliseconds: 150),
                              // Task 40 — quieter placeholder. The old
                              // spinner was visually noisy in a 3-col
                              // grid (12+ spinners spinning at once is
                              // distracting). A flat skeleton-colored
                              // Container matches the MovieCardSkeleton
                              // shimmer look and feels less anxious.
                              placeholder: (context, url) => Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                              ),
                              errorWidget: (context, url, error) {
                                // Task 40 — auto-retry once on first
                                // failure (covers transient TMDB 429 /
                                // mobile-data handoff), then surface a
                                // tappable retry icon for subsequent
                                // failures. We use addPostFrameCallback
                                // to avoid calling setState during build.
                                if (_posterRetryCount < _maxAutoRetries) {
                                  _posterRetryCount++;
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (mounted) setState(() {});
                                  });
                                }
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _posterRetryCount++;
                                    });
                                  },
                                  child: Container(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.refresh,
                                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                                      size: 32,
                                    ),
                                  ),
                                );
                              },
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

                // Watch Progress — subtle dark gradient at poster bottom.
                // Phase 4.38 — placed BEFORE the IMDb rating badge in the
                // Stack so the rating badge draws on top of the gradient
                // (the badge has its own black75 background and doesn't
                // need extra darkening from the gradient). The gradient
                // provides contrast for the red progress fill in the
                // bottom-left/center area where the fill lives.
                if (_watchProgress != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.0),
                              Colors.black.withOpacity(0.45),
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
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

                // Feature 5: Watch Progress Bar — red fill at bottom of poster.
                //
                // Phase 4.38 redesign — Bro reported the previous version
                // looked like the poster was being "cut" by a horizontal
                // line ("ဖြတ်နေသလိုဖြစ်နေတယ်"). Root cause was the
                // `Colors.white24` track that spanned the full poster width
                // — it read as a stark white slice through the poster art,
                // especially on posters with light/saturated bottoms.
                //
                // New design (matches Netflix / Disney+ / Prime Video
                // mobile convention):
                //   1. NO white track. Only the red fill is shown.
                //   2. A subtle dark gradient overlay (transparent →
                //      black45) sits at the bottom 16px of the poster
                //      (declared above, before the rating badge, so the
                //      rating badge draws on top of it). The gradient
                //      gives the red fill consistent contrast regardless
                //      of the poster's bottom-edge color.
                //   3. The red fill is 3px tall, with its container
                //      ClipRRect being 8px tall (taller than the visible
                //      bar) so the 8px bottom-corner radius does NOT get
                //      clamped. Flutter clamps borderRadius to half the
                //      smaller dimension — an 8px radius on a 3px-tall
                //      rect gets clamped to 1.5px and doesn't match the
                //      poster's true 8px corners. By making the ClipRRect
                //      8px tall and placing the 3px red bar at its bottom,
                //      the bottom corners curve correctly and align with
                //      the poster's rounded bottom corners.
                //   4. LayoutBuilder is used to read the poster's actual
                //      rendered width so the red fill's width is exactly
                //      (progress × posterWidth).
                if (_watchProgress != null)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final barWidth =
                              constraints.maxWidth * _watchProgress!.clamp(0.02, 1.0);
                          return SizedBox(
                            height: 8,
                            child: Stack(
                              children: [
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  child: Container(
                                    width: barWidth,
                                    height: 3,
                                    color: const Color(0xFFE50914),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
            // Year + Duration/Season metadata below title.
            // Phase 4.38 — removed the inline watch-progress text block
            // (play icon + "X%") that used to live at the end of this Row.
            // The visual progress bar at the bottom of the poster is now
            // the single source of truth for watch progress — same
            // convention as Netflix / Disney+ / Prime Video mobile.
            // Removing the text also de-clutters the row (was 5 elements,
            // now 3) and avoids the "0%" artifact on freshly-started
            // titles.
            if (widget.movie.year != null && widget.movie.year!.isNotEmpty ||
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
