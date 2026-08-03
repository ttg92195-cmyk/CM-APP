import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/services/bookmark_service.dart';
import 'package:cm_movies/app/core/services/watchlist_service.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';
import 'package:cm_movies/app/ui/screens/category_page.dart';
import 'package:cm_movies/app/ui/components/age_rating_gate.dart';
import 'package:cm_movies/app/ui/screens/actor_movies_screen.dart';
import 'package:cm_movies/app/ui/screens/movie_watch_screen.dart';
import 'package:cm_movies/app/ui/screens/movie_download_screen.dart';
import 'package:cm_movies/app/ui/screens/vip_page.dart';

class MovieDetailScreen extends StatefulWidget {
  final String slug;

  const MovieDetailScreen({super.key, required this.slug});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final BookmarkService _bookmarkService = BookmarkService();
  final WatchlistService _watchlistService = WatchlistService();
  final RecentService _recentService = RecentService();

  MovieDetail? _movieDetail;
  bool _isLoading = true;
  String? _error;
  bool _isBookmarked = false;
  bool _isInWatchlist = false;
  bool _ageVerified = false;
  bool _overviewExpanded = false;

  List<Movie> _relatedMovies = [];
  bool _isLoadingRelated = true;

  @override
  void initState() {
    super.initState();
    _loadMovieDetail();
  }

  Future<void> _loadMovieDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await _contentService.getMovieBySlug(widget.slug);
      if (detail != null && mounted) {
        if (detail.isAdult != null && detail.isAdult != 0) {
          final verified = await AgeRatingGate.checkAndShowGate(
            context,
            isAdult: detail.isAdult,
            movieTitle: detail.title,
          );
          if (!verified) {
            if (mounted) Navigator.pop(context);
            return;
          }
          _ageVerified = true;
        }

        final movie = Movie(
          id: detail.id,
          title: detail.title,
          titleLowercase: detail.title.toLowerCase(),
          slug: detail.slug,
          year: detail.year,
          poster: detail.poster,
          type: detail.type,
          isTrending: detail.isTrending,
        );
        await _recentService.addRecent(movie);
        final bookmarked = await _bookmarkService.isBookmarked(detail.id);
        final inWatchlist = await _watchlistService.isInWatchlist(detail.id);

        setState(() {
          _movieDetail = detail;
          _isBookmarked = bookmarked;
          _isInWatchlist = inWatchlist;
          _isLoading = false;
        });

        _loadRelatedMovies(detail);
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Movie not found';
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

  Future<void> _loadRelatedMovies(MovieDetail detail) async {
    try {
      // Task 42#2: rewritten to show genuinely related posts.
      //
      // OLD behavior: queried only the FIRST category, fell back to
      // trending (unrelated) when genre returned < 10 results. User saw
      // "new" movies instead of related ones.
      //
      // NEW behavior:
      //   1. Query movies by EACH category (capped at 3) — type-filtered
      //      to 'movie' so series don't leak in.
      //   2. Query movies by EACH tag (capped at 2) for more candidates.
      //   3. Score each candidate by # of shared categories (each shared
      //      category = +2 points).
      //   4. Sort by score desc, then createdAt desc as tiebreaker.
      //   5. Take top 10.
      //   6. NO trending fallback — if no related found, the section is
      //      hidden (cleaner than showing unrelated posts).
      final Map<String, Movie> candidates = {};

      // Cap categories to avoid excessive Firestore reads.
      final catsToQuery = detail.categories.take(3).toList();
      for (final category in catsToQuery) {
        try {
          final result = await _contentService.getMoviesByGenre(
            category,
            limit: 30,
            typeFilter: 'movie',
          );
          for (final m in (result['movies'] as List<Movie>)) {
            if (m.id != detail.id) candidates[m.id] = m;
          }
        } catch (_) {
          // Single-category failure shouldn't abort the whole load.
        }
      }

      // Tags as secondary signal — only used to FIND more candidates,
      // not for scoring (tags not available on Movie model).
      final tagsToQuery = detail.tags.take(2).toList();
      for (final tag in tagsToQuery) {
        try {
          final tagResult = await _contentService.getMoviesByTagSimple(
            tag,
            limit: 20,
          );
          for (final m in tagResult) {
            if (m.id != detail.id) {
              candidates.putIfAbsent(m.id, () => m);
            }
          }
        } catch (_) {
          // Single-tag failure shouldn't abort the whole load.
        }
      }

      // Score by category overlap.
      final detailCatsLower = detail.categories
          .map((c) => c.toLowerCase())
          .toSet();

      final scored = candidates.values.map((m) {
        int score = 0;
        for (final c in m.categories) {
          if (detailCatsLower.contains(c.toLowerCase())) score += 2;
        }
        return (movie: m, score: score);
      }).toList();

      // Sort: score desc, then createdAt desc as tiebreaker.
      scored.sort((a, b) {
        final scoreCmp = b.score.compareTo(a.score);
        if (scoreCmp != 0) return scoreCmp;
        return (b.movie.createdAt ?? DateTime(2000))
            .compareTo(a.movie.createdAt ?? DateTime(2000));
      });

      final related = scored.take(10).map((e) => e.movie).toList();

      debugPrint('LOAD_RELATED_MOVIES: "${detail.title}" '
          'categories=${detail.categories} tags=${detail.tags} '
          'candidates=${candidates.length} '
          '→ ${related.length} related '
          '(top score=${scored.isEmpty ? 0 : scored.first.score})');

      if (mounted) {
        setState(() {
          _relatedMovies = related;
          _isLoadingRelated = false;
        });
      }
    } catch (e) {
      debugPrint('_loadRelatedMovies failed: $e');
      if (mounted) {
        setState(() => _isLoadingRelated = false);
      }
    }
  }

  Future<void> _toggleBookmark() async {
    if (_movieDetail == null) return;
    final movie = Movie(
      id: _movieDetail!.id,
      title: _movieDetail!.title,
      titleLowercase: _movieDetail!.title.toLowerCase(),
      slug: _movieDetail!.slug,
      year: _movieDetail!.year,
      poster: _movieDetail!.poster,
      type: _movieDetail!.type,
      isTrending: _movieDetail!.isTrending,
    );
    final primaryOk = await _bookmarkService.toggleBookmark(movie);
    final bookmarked = await _bookmarkService.isBookmarked(_movieDetail!.id);
    if (mounted) {
      setState(() => _isBookmarked = bookmarked);
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      // H7: surface silent Firestore failures to the user. If primaryOk
      // is false, the write fell back to local storage — warn the user
      // that the change isn't synced to the cloud yet.
      final message = !primaryOk
          ? appConfig.translate('saved_locally')
          : bookmarked
              ? appConfig.translate('bookmark_added')
              : appConfig.translate('bookmark_removed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleWatchlist() async {
    if (_movieDetail == null) return;
    final movie = Movie(
      id: _movieDetail!.id,
      title: _movieDetail!.title,
      titleLowercase: _movieDetail!.title.toLowerCase(),
      slug: _movieDetail!.slug,
      year: _movieDetail!.year,
      poster: _movieDetail!.poster,
      type: _movieDetail!.type,
      isTrending: _movieDetail!.isTrending,
    );
    final primaryOk = await _watchlistService.toggleWatchlist(movie);
    final inWatchlist = await _watchlistService.isInWatchlist(_movieDetail!.id);
    if (mounted) {
      setState(() => _isInWatchlist = inWatchlist);
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      // H7: same surface-failure pattern as _toggleBookmark above.
      final message = !primaryOk
          ? appConfig.translate('saved_locally')
          : inWatchlist
              ? appConfig.translate('watchlist_added')
              : appConfig.translate('watchlist_removed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}K';
    }
    return views.toString();
  }

  String _formatDuration(String? duration) {
    if (duration == null || duration.isEmpty) return '';
    final mins = int.tryParse(duration.replaceAll(RegExp(r'[^\d]'), ''));
    if (mins != null && mins > 0) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return h > 0 ? '${h}h ${m}m' : '${m}m';
    }
    return duration;
  }

  /// Dynamic Country Flag + Language mapping
  /// Maps country code/name to emoji flag + language name
  static String _getCountryLanguage(String? country) {
    if (country == null || country.isEmpty) return '🇺🇸 English';

    final normalized = country.trim().toUpperCase();

    // Map of country codes/names → flag + language
    const Map<String, String> countryMap = {
      // Country codes
      'US': '🇺🇸 English',
      'JP': '🇯🇵 Japanese',
      'KR': '🇰🇷 Korean',
      'TH': '🇹🇭 Thai',
      'CN': '🇨🇳 Chinese',
      'HK': '🇭🇰 Cantonese',
      'TW': '🇹🇼 Mandarin',
      'IN': '🇮🇳 Hindi',
      'GB': '🇬🇧 English',
      'UK': '🇬🇧 English',
      'FR': '🇫🇷 French',
      'DE': '🇩🇪 German',
      'ES': '🇪🇸 Spanish',
      'IT': '🇮🇹 Italian',
      'PH': '🇵🇭 Filipino',
      'TR': '🇹🇷 Turkish',
      'BR': '🇧🇷 Portuguese',
      'RU': '🇷🇺 Russian',
      'ID': '🇮🇩 Indonesian',
      'MY': '🇲🇾 Malay',
      'MM': '🇲🇲 Myanmar',
      // Full names (common)
      'UNITED STATES': '🇺🇸 English',
      'JAPAN': '🇯🇵 Japanese',
      'KOREA': '🇰🇷 Korean',
      'SOUTH KOREA': '🇰🇷 Korean',
      'THAILAND': '🇹🇭 Thai',
      'CHINA': '🇨🇳 Chinese',
      'INDIA': '🇮🇳 Hindi',
      'ENGLISH': '🇺🇸 English',
      'JAPANESE': '🇯🇵 Japanese',
      'KOREAN': '🇰🇷 Korean',
      'THAI': '🇹🇭 Thai',
      'CHINESE': '🇨🇳 Chinese',
      'HINDI': '🇮🇳 Hindi',
      'CANTONESE': '🇭🇰 Cantonese',
      'MANDARIN': '🇨🇳 Chinese',
      'FRENCH': '🇫🇷 French',
      'SPANISH': '🇪🇸 Spanish',
      'GERMAN': '🇩🇪 German',
    };

    return countryMap[normalized] ?? '🇺🇸 English';
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 48, color: Colors.redAccent),
                      const SizedBox(height: 16),
                      Text(appConfig.translate('error_occurred')),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadMovieDetail,
                        child: Text(appConfig.translate('retry')),
                      ),
                    ],
                  ),
                )
              : _buildDetail(appConfig, theme),
    );
  }

  Widget _buildDetail(AppConfig appConfig, ThemeData theme) {
    if (_movieDetail == null) return const SizedBox.shrink();
    final detail = _movieDetail!;
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = theme.colorScheme.primary;
    final bodyTextColor = isDark ? Colors.white70 : Colors.black87;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ===== App Bar with poster and action icons =====
          SliverAppBar(
            pinned: true,
            floating: false,
            // Phase 2 — Restored default leadingWidth (56). Was 46,
            // which clipped the back-button IconButton's 48×48 circular
            // ripple to 46 wide. The global iconButtonTheme now locks
            // the IconButton to 48×48, so the slot needs to be at least
            // 48 wide — using the Material default (56) gives the
            // standard AppBar back-button spacing.
            leadingWidth: 56,
            backgroundColor: isDark ? const Color(0xFF121212) : bgColor,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            title: AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                detail.title,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back,
                  color: isDark ? Colors.white : Colors.black87, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // Task 38 Req 2: Trailer icon — opens the YouTube trailer URL
              // saved from TMDB. Only shown if the field is non-empty (older
              // docs / non-TMDB movies won't have it). Uses url_launcher's
              // external-app mode so the user is taken to the YouTube app
              // (or browser fallback) instead of an in-app webview.
              //
              // Task 42#3: removed `canLaunchUrl` guard. On Android 11+
              // canLaunchUrl returns false for any URL not declared in
              // AndroidManifest <queries>, EVEN after we added the
              // http/https scheme there — the check is unreliable in
              // practice and was silently killing the trailer tap.
              // We now call launchUrl directly and surface any failure
              // via a SnackBar so the user knows the launch failed
              // (rather than the button appearing dead).
              if (detail.trailerUrl != null &&
                  detail.trailerUrl!.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.play_circle_outline,
                    color: isDark ? Colors.white : Colors.black54,
                    size: 24,
                  ),
                  tooltip: 'Trailer',
                  onPressed: () async {
                    final uri = Uri.parse(detail.trailerUrl!);
                    try {
                      final ok = await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open trailer'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not open trailer: $e'),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                ),
              // Watchlist button
              IconButton(
                icon: Icon(
                  _isInWatchlist ? Icons.watch_later : Icons.watch_later_outlined,
                  color: _isInWatchlist
                      ? const Color(0xFF4CAF50)
                      : (isDark ? Colors.white : Colors.black54),
                  size: 24,
                ),
                onPressed: _toggleWatchlist,
              ),
              // Bookmark button
              IconButton(
                icon: Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                  color: _isBookmarked
                      ? accentColor
                      : (isDark ? Colors.white : Colors.black54),
                  size: 24,
                ),
                onPressed: _toggleBookmark,
              ),
              const SizedBox(width: 4),
            ],
          ),

          // ===== Main Content =====
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== 1. INFO SECTION (Hero Row) =====
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Small Poster with rounded corners
                      Container(
                        width: 110,
                        height: 155,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: detail.fullPosterUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: detail.fullPosterUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    color: isDark
                                        ? const Color(0xFF1E1E1E)
                                        : Colors.grey.shade300,
                                    child: Icon(Icons.movie,
                                        size: 36,
                                        color: isDark
                                            ? Colors.white24
                                            : Colors.black12),
                                  ),
                                )
                              : Container(
                                  color: isDark
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.grey.shade300,
                                  child: Icon(Icons.movie,
                                      size: 36,
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.black12),
                                ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Title + Meta
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Title
                              Text(
                                detail.title,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              // Task 38 Req 2: Tagline — short marketing line
                              // from TMDB (e.g. "The world's greatest villain
                              // meets his match."). Shown italic + muted under
                              // the title. Older docs without tagline just skip.
                              if (detail.tagline != null &&
                                  detail.tagline!.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  detail.tagline!,
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 8),
                              // MetaData: Year ⭐ Rating Duration 🇺🇸 English
                              // Use Wrap to gracefully handle overflow on narrow screens
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (detail.year != null &&
                                      detail.year!.isNotEmpty)
                                    Text(detail.year!,
                                        style: TextStyle(
                                            color: metaTextColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                  if (detail.year != null &&
                                      detail.year!.isNotEmpty)
                                    Text('·',
                                        style: TextStyle(
                                            color: metaTextColor,
                                            fontSize: 13)),
                                  // Task 38 Req 2: Certification badge —
                                  // TMDB age rating (e.g. PG-13, R, TV-MA).
                                  // Rendered as a tiny outlined chip so it
                                  // reads as a discrete badge rather than
                                  // inline text. Older docs without
                                  // certification are skipped silently.
                                  if (detail.certification != null &&
                                      detail.certification!.trim().isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black45,
                                          width: 0.6,
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(
                                        detail.certification!,
                                        style: TextStyle(
                                          color: metaTextColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (detail.certification != null &&
                                      detail.certification!.trim().isNotEmpty)
                                    Text('·',
                                        style: TextStyle(
                                            color: metaTextColor,
                                            fontSize: 13)),
                                  // Rating: flame icon + rating text packed into a
                                  // single Row so the Wrap's `spacing: 8` doesn't
                                  // push them apart. Previously these were three
                                  // separate Wrap children (icon, SizedBox(2),
                                  // text) and the Wrap applied 8px of space
                                  // between every pair — so the icon and its
                                  // number ended up ~10px apart instead of the
                                  // intended 4px. See Bro's '🔥       6.0' report.
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.local_fire_department,
                                          size: 16, color: accentColor),
                                      const SizedBox(width: 4),
                                      Text(_formatRating(detail.rating),
                                          style: TextStyle(
                                              color: accentColor,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  Text('·',
                                      style: TextStyle(
                                          color: metaTextColor,
                                          fontSize: 13)),
                                  if (detail.duration != null &&
                                      detail.duration!.isNotEmpty)
                                    Text(_formatDuration(detail.duration),
                                        style: TextStyle(
                                            color: metaTextColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                  if (detail.duration != null &&
                                      detail.duration!.isNotEmpty)
                                    Text('·',
                                        style: TextStyle(
                                            color: metaTextColor,
                                            fontSize: 13)),
                                  Text(_getCountryLanguage(detail.country),
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // Category Tags (up to 6)
                              if (detail.categories.isNotEmpty)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: detail.categories.take(6).map((cat) {
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CategoryPage(
                                              title: cat,
                                              filterType: CategoryFilterType.genre,
                                              filterValue: cat,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white.withOpacity(0.08)
                                              : Colors.black.withOpacity(0.06),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white12
                                                : Colors.grey.shade300,
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(
                                          cat,
                                          style: TextStyle(
                                            color: isDark ? Colors.white70 : Colors.black87,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ===== 2. DETAILS SECTION =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Details',
                          style: TextStyle(
                              color: bodyTextColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (detail.fileSize != null && detail.fileSize!.isNotEmpty)
                        _detailRow('File Size', detail.fileSize!, bodyTextColor, metaTextColor),
                      if (detail.resolution != null && detail.resolution!.isNotEmpty)
                        _detailRow('Quality', detail.resolution!, bodyTextColor, metaTextColor),
                      if (detail.format != null && detail.format!.isNotEmpty)
                        _detailRow('Format', detail.format!, bodyTextColor, metaTextColor),
                      if (detail.categories.isNotEmpty)
                        _detailRow('Genre', detail.categories.join('  '), bodyTextColor, metaTextColor),
                      if (detail.duration != null && detail.duration!.isNotEmpty)
                        _detailRow('Duration', _formatDuration(detail.duration), bodyTextColor, metaTextColor),
                      if (detail.directors.isNotEmpty)
                        _detailRow('Director', detail.directors.join(', '), bodyTextColor, metaTextColor),
                      // Task 38 Req 2: Status row — only shown when non-empty.
                      // For movies: "Released", "Rumored", "Post Production".
                      // For series: "Returning Series", "Ended", "Canceled".
                      // Older docs without status are skipped silently.
                      if (detail.status != null &&
                          detail.status!.trim().isNotEmpty)
                        _detailRow('Status', detail.status!, bodyTextColor, metaTextColor),
                      // Task 38 Req 2: Vote count — "X votes" on TMDB.
                      // Helps the user gauge how reliable the rating is.
                      if (detail.voteCount != null && detail.voteCount! > 0)
                        _detailRow('Votes', '${detail.voteCount} votes', bodyTextColor, metaTextColor),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ===== 3. ACTION BUTTONS =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Watch Now Button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: detail.watchLinks.isNotEmpty
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MovieWatchScreen(movieDetail: detail),
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.play_arrow, size: 20),
                          label: const Text('Watch Now',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: isDark
                                ? Colors.white12
                                : Colors.grey.shade300,
                            disabledForegroundColor: isDark
                                ? Colors.white38
                                : Colors.black38,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Download Button — VIP/Admin only.
                      // Non-VIP: button is greyed; tapping prompts VIP upgrade.
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: detail.downloadLinks.isEmpty
                              ? null
                              : () {
                                  if (!appConfig.isDownloadAllowedForUser) {
                                    // Non-VIP → prompt to buy VIP
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          appConfig.languageCode == 'my'
                                              ? 'Download ကို အသုံးပြုရန် VIP ဝယ်ယူရပါမည်'
                                              : 'VIP membership required to download. Please upgrade to VIP.',
                                        ),
                                        backgroundColor: Colors.orange,
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const VipPage()),
                                    );
                                    return;
                                  }
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MovieDownloadScreen(movieDetail: detail),
                                    ),
                                  );
                                },
                          icon: Icon(
                            appConfig.isDownloadAllowedForUser
                                ? Icons.download
                                : Icons.lock_outline,
                            size: 20,
                          ),
                          label: const Text('Download',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appConfig.isDownloadAllowedForUser
                                ? accentColor
                                : (isDark ? Colors.white12 : Colors.grey.shade400),
                            foregroundColor: appConfig.isDownloadAllowedForUser
                                ? Colors.white
                                : (isDark ? Colors.white38 : Colors.black38),
                            disabledBackgroundColor: isDark
                                ? Colors.white12
                                : Colors.grey.shade300,
                            disabledForegroundColor: isDark
                                ? Colors.white38
                                : Colors.black38,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ===== 4. CONTENT SECTION (Synopsis/Overview) =====
                if (detail.overview != null && detail.overview!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Overview',
                            style: TextStyle(
                                color: accentColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final textSpan = TextSpan(
                              text: detail.overview!,
                              style: TextStyle(fontSize: 13, height: 1.6, color: bodyTextColor),
                            );
                            // Task 38 #4 — collapsed preview shows up to 15
                            // lines (was 4). Most TMDB overviews are 6-12
                            // lines on a typical phone width, so 15 covers
                            // ~95% of cases without needing "View More".
                            // The remaining ~5% (very long overviews) still
                            // get the "View More" tap-to-expand affordance.
                            const kCollapsedLines = 15;
                            final textPainter = TextPainter(
                              text: textSpan,
                              maxLines: kCollapsedLines,
                              textDirection: TextDirection.ltr,
                            );
                            textPainter.layout(maxWidth: constraints.maxWidth);
                            final isOverflow = textPainter.didExceedMaxLines;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detail.overview!,
                                  maxLines: _overviewExpanded ? null : kCollapsedLines,
                                  overflow: _overviewExpanded
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13, height: 1.6, color: bodyTextColor),
                                ),
                                if (isOverflow)
                                  GestureDetector(
                                    onTap: () => setState(
                                        () => _overviewExpanded = !_overviewExpanded),
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _overviewExpanded ? 'View Less' : 'View More',
                                        style: TextStyle(
                                          color: accentColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // ===== 5. CAST SECTION =====
                if (detail.casts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Casts',
                            style: TextStyle(
                                color: bodyTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        // Task 42#2: height tightened 140 → 116. Cast item
                        // content max = avatar(68) + gap(6) + name 2-line(~28)
                        // + char gap(2) + char 1-line(~12) = 116. The old 140
                        // left ~24px of empty space below each cast row.
                        SizedBox(
                          height: 116,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            itemCount: detail.casts.length,
                            itemBuilder: (context, index) {
                              final cast = detail.casts[index];
                              final hasProfile = cast.fullProfileUrl.isNotEmpty;
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ActorMoviesScreen(actorName: cast.name),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 14),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 68,
                                        height: 68,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: hasProfile
                                              ? null
                                              : LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: isDark
                                                      ? [const Color(0xFF3A3A3A), const Color(0xFF2A2A2A)]
                                                      : [Colors.grey.shade400, Colors.grey.shade300],
                                                ),
                                          color: hasProfile
                                              ? (isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade300)
                                              : null,
                                        ),
                                        child: ClipOval(
                                          child: hasProfile
                                              ? CachedNetworkImage(
                                                  imageUrl: cast.fullProfileUrl,
                                                  fit: BoxFit.cover,
                                                  width: 68,
                                                  height: 68,
                                                  placeholder: (context, url) =>
                                                      Center(
                                                        child: SizedBox(
                                                          width: 20,
                                                          height: 20,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            valueColor: AlwaysStoppedAnimation<Color>(
                                                              const Color(0xFFE50914).withOpacity(0.6),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                  errorWidget: (context, url, error) =>
                                                      _buildFallbackAvatar(cast.name, isDark),
                                                )
                                              : _buildFallbackAvatar(cast.name, isDark),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        width: 76,
                                        child: Text(
                                          cast.name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: bodyTextColor),
                                        ),
                                      ),
                                      // Task 38 Req 2: Character (role) name
                                      // shown as a tiny muted subtitle under
                                      // the actor name. Older docs without
                                      // `character` skip silently.
                                      if (cast.character != null &&
                                          cast.character!.trim().isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        SizedBox(
                                          width: 76,
                                          child: Text(
                                            cast.character!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontStyle: FontStyle.italic,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black45,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // ===== 6. YOU MAY ALSO LIKE =====
                if (_relatedMovies.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('You May Also Like',
                            style: TextStyle(
                                color: bodyTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _relatedMovies.length,
                            itemBuilder: (context, index) {
                              final movie = _relatedMovies[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MovieDetailScreen(slug: movie.slug),
                                    ),
                                  );
                                },
                                child: Container(
                                  width: 110,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 110,
                                        height: 155,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: movie.fullPosterUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: movie.fullPosterUrl,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 30),
                                                )
                                              : const Icon(Icons.movie, size: 30),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        movie.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: bodyTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Format rating: show "N/A" if null, empty, or 0.0
  String _formatRating(String? rating) {
    if (rating == null || rating.trim().isEmpty) return 'N/A';
    final parsed = double.tryParse(rating);
    if (parsed == null || parsed == 0.0) return 'N/A';
    return rating;
  }

  Widget _detailRow(String label, String value, Color bodyTextColor, Color metaTextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: metaTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: bodyTextColor,
                    fontSize: 13,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }

  /// Beautiful fallback avatar for cast members without profile photos
  /// Shows a gradient circle with a person silhouette icon + initial letter
  Widget _buildFallbackAvatar(String name, bool isDark) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [const Color(0xFF3A3A3A), const Color(0xFF252525)]
              : [Colors.grey.shade400, Colors.grey.shade300],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Person silhouette icon (subtle background)
          Icon(
            Icons.person,
            size: 36,
            color: isDark
                ? Colors.white.withOpacity(0.15)
                : Colors.white.withOpacity(0.5),
          ),
          // Initial letter overlay
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFE50914).withOpacity(isDark ? 0.85 : 0.9),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
