import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/poster_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 4.28 — Shimmer placeholder shown while a poster image is
/// being fetched from the network. Replaces the previous flat-colored
/// Container which looked visually flat and gave no indication that
/// the image was actually loading. The shimmer is a subtle horizontal
/// gradient sweep (1.2s loop) that matches the MovieCardSkeleton used
/// elsewhere in the app — so the loading state visually matches the
/// grid skeleton state the user already sees on first page load.
///
/// Performance: one AnimationController per visible card. Cards that
/// scroll off-screen dispose their State (and therefore their
/// AnimationController), so the cost scales with the number of
/// visible cards (~9-12 in a 3-col grid). Animation is GPU-composited
/// so it adds negligible CPU load.
class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
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
    // Two-tone palette for the gradient sweep. The 'highlight' color
    // is the light band that sweeps across; the 'base' is the resting
    // color. We use the same color tokens as MovieCardSkeleton so the
    // placeholder matches the surrounding grid skeleton look.
    final baseColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF3D3D3D) : const Color(0xFFF5F5F5);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          // Linear gradient with three stops — middle stop is the
          // 'highlight' band. The gradient is twice as wide as the
          // box so the highlight band sweeps from off-screen left to
          // off-screen right; `begin` and `end` are animated from
          // -1.0 → 2.0 over the animation duration.
          shaderCallback: (bounds) {
            final t = _controller.value;
            return LinearGradient(
              begin: Alignment(t * 3 - 1, 0),
              end: Alignment(t * 3 + 0.5, 0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: Container(
            color: baseColor,
          ),
        );
      },
    );
  }
}

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
                              // visible at once.
                              //
                              // Phase 4.28 — bumped from 400 → 500. On a
                              // 3x device pixel ratio phone showing a 3-col
                              // grid at ~140px logical width, each poster
                              // is rendered at ~420px device pixels. The old
                              // 400 value was just under that threshold and
                              // caused slight softness on high-DPI screens.
                              // 500 gives us headroom for 4x DPR phones and
                              // horizontal scrollers (where cards are wider)
                              // while still keeping decoded size ~300KB per
                              // poster. With the 2000-object cache limit,
                              // worst case is ~600MB on disk — within
                              // reason for an image-heavy app.
                              memCacheWidth: 500,
                              // Phase 4.28 — high filter quality for sharper
                              // downscaling. CachedNetworkImage defaults to
                              // FilterQuality.low (nearest-neighbor) which
                              // produces visible aliasing on diagonal edges
                              // (poster text, faces) when the source image
                              // is much larger than the display size. High
                              // uses bicubic interpolation — slightly more
                              // CPU on first decode but the result is cached
                              // in the poster cache so subsequent renders
                              // are free.
                              filterQuality: FilterQuality.high,
                              // Phase 4.28 — smoother fade-in. Old 150ms was
                              // a bit jarring (too quick). 300ms feels more
                              // polished and matches Material's standard
                              // motion duration for content appearance.
                              //
                              // Note: cached_network_image v3.4.1 (current
                              // pinned version) does NOT expose a separate
                              // `fadeInDurationOnRebuild` parameter. However,
                              // the default behavior in v3.4.1 is exactly
                              // what we want: the fade-in animation only
                              // fires on the FIRST load from network/disk —
                              // when the parent widget rebuilds and the
                              // image is still in the in-memory cache, the
                              // image is shown instantly with no fade. So
                              // we do not need to override anything here.
                              fadeInDuration: const Duration(milliseconds: 300),
                              // Phase 4.28 — shimmer placeholder. Replaces
                              // the old flat Container — gives the user a
                              // subtle visual indication that the image is
                              // loading, matching the MovieCardSkeleton used
                              // elsewhere in the app.
                              placeholder: (context, url) =>
                                  const _ShimmerPlaceholder(),
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
                                // Phase 4.28 — improved error state. Old
                                // version was a bare Icon on a flat color
                                // (looked unfinished). Now we add a small
                                // caption below the icon ('Tap to retry')
                                // so the user knows the placeholder is
                                // interactive, and use a slightly larger
                                // icon for better tap-target affordance.
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _posterRetryCount++;
                                    });
                                  },
                                  child: Container(
                                    color: theme.colorScheme.surfaceContainerHighest,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.broken_image_outlined,
                                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                                          size: 32,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Tap to retry',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurface.withOpacity(0.4),
                                            fontSize: 9,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
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
