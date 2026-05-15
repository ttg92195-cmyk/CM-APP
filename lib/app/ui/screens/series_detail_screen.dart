import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:cm_movies/app/ui/screens/series_watch_screen.dart';
import 'package:cm_movies/app/ui/screens/series_download_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final String slug;

  const SeriesDetailScreen({super.key, required this.slug});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final BookmarkService _bookmarkService = BookmarkService();
  final WatchlistService _watchlistService = WatchlistService();
  final RecentService _recentService = RecentService();

  MovieDetail? _seriesDetail;
  bool _isLoading = true;
  String? _error;
  bool _isBookmarked = false;
  bool _isInWatchlist = false;
  bool _ageVerified = false;
  bool _overviewExpanded = false;

  List<Movie> _relatedSeries = [];
  bool _isLoadingRelated = true;

  @override
  void initState() {
    super.initState();
    _loadSeriesDetail();
  }

  Future<void> _loadSeriesDetail() async {
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
          _seriesDetail = detail;
          _isBookmarked = bookmarked;
          _isInWatchlist = inWatchlist;
          _isLoading = false;
        });

        _loadRelatedSeries(detail);
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Series not found';
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

  Future<void> _loadRelatedSeries(MovieDetail detail) async {
    try {
      List<Movie> related = [];
      if (detail.categories.isNotEmpty) {
        final result = await _contentService.getMoviesByGenre(
          detail.categories.first,
          limit: 11,
        );
        related = (result['movies'] as List<Movie>)
            .where((m) => m.id != detail.id)
            .toList();
      }
      if (related.length < 10 && detail.tags.isNotEmpty) {
        final tagResult = await _contentService.getMoviesByTagSimple(
          detail.tags.first,
          limit: 11,
        );
        for (final m in tagResult) {
          if (m.id != detail.id && !related.any((r) => r.id == m.id)) {
            related.add(m);
          }
          if (related.length >= 10) break;
        }
      }
      if (related.isEmpty) {
        final result = await _contentService.getTrendingTvShows();
        related = result.where((m) => m.id != detail.id).take(10).toList();
      }
      if (mounted) {
        setState(() {
          _relatedSeries = related;
          _isLoadingRelated = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRelated = false);
      }
    }
  }

  Future<void> _toggleBookmark() async {
    if (_seriesDetail == null) return;
    final movie = Movie(
      id: _seriesDetail!.id,
      title: _seriesDetail!.title,
      slug: _seriesDetail!.slug,
      year: _seriesDetail!.year,
      poster: _seriesDetail!.poster,
      type: _seriesDetail!.type,
      isTrending: _seriesDetail!.isTrending,
    );
    await _bookmarkService.toggleBookmark(movie);
    final bookmarked = await _bookmarkService.isBookmarked(_seriesDetail!.id);
    if (mounted) {
      setState(() => _isBookmarked = bookmarked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bookmarked
                ? Provider.of<AppConfig>(context, listen: false).translate('bookmark_added')
                : Provider.of<AppConfig>(context, listen: false).translate('bookmark_removed'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleWatchlist() async {
    if (_seriesDetail == null) return;
    final movie = Movie(
      id: _seriesDetail!.id,
      title: _seriesDetail!.title,
      slug: _seriesDetail!.slug,
      year: _seriesDetail!.year,
      poster: _seriesDetail!.poster,
      type: _seriesDetail!.type,
      isTrending: _seriesDetail!.isTrending,
    );
    await _watchlistService.toggleWatchlist(movie);
    final inWatchlist = await _watchlistService.isInWatchlist(_seriesDetail!.id);
    if (mounted) {
      setState(() => _isInWatchlist = inWatchlist);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inWatchlist
                ? Provider.of<AppConfig>(context, listen: false).translate('watchlist_added')
                : Provider.of<AppConfig>(context, listen: false).translate('watchlist_removed'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M';
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K';
    return views.toString();
  }

  /// Dynamic Country Flag + Language mapping
  static String _getCountryLanguage(String? country) {
    if (country == null || country.isEmpty) return '🇺🇸 English';
    final normalized = country.trim().toUpperCase();
    const Map<String, String> countryMap = {
      'US': '🇺🇸 English', 'JP': '🇯🇵 Japanese', 'KR': '🇰🇷 Korean',
      'TH': '🇹🇭 Thai', 'CN': '🇨🇳 Chinese', 'HK': '🇭🇰 Cantonese',
      'TW': '🇹🇼 Mandarin', 'IN': '🇮🇳 Hindi', 'GB': '🇬🇧 English',
      'UK': '🇬🇧 English', 'FR': '🇫🇷 French', 'DE': '🇩🇪 German',
      'ES': '🇪🇸 Spanish', 'IT': '🇮🇹 Italian', 'PH': '🇵🇭 Filipino',
      'TR': '🇹🇷 Turkish', 'BR': '🇧🇷 Portuguese', 'RU': '🇷🇺 Russian',
      'ID': '🇮🇩 Indonesian', 'MY': '🇲🇾 Malay', 'MM': '🇲🇲 Myanmar',
      'UNITED STATES': '🇺🇸 English', 'JAPAN': '🇯🇵 Japanese',
      'KOREA': '🇰🇷 Korean', 'SOUTH KOREA': '🇰🇷 Korean',
      'THAILAND': '🇹🇭 Thai', 'CHINA': '🇨🇳 Chinese', 'INDIA': '🇮🇳 Hindi',
      'ENGLISH': '🇺🇸 English', 'JAPANESE': '🇯🇵 Japanese',
      'KOREAN': '🇰🇷 Korean', 'THAI': '🇹🇭 Thai', 'CHINESE': '🇨🇳 Chinese',
      'HINDI': '🇮🇳 Hindi', 'CANTONESE': '🇭🇰 Cantonese',
      'MANDARIN': '🇨🇳 Chinese', 'FRENCH': '🇫🇷 French',
      'SPANISH': '🇪🇸 Spanish', 'GERMAN': '🇩🇪 German',
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
                      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 16),
                      Text(appConfig.translate('error_occurred')),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSeriesDetail,
                        child: Text(appConfig.translate('retry')),
                      ),
                    ],
                  ),
                )
              : _buildDetail(appConfig, theme),
    );
  }

  Widget _buildDetail(AppConfig appConfig, ThemeData theme) {
    if (_seriesDetail == null) return const SizedBox.shrink();
    final detail = _seriesDetail!;
    final isDark = theme.brightness == Brightness.dark;

    final accentColor = const Color(0xFFE50914);
    final bodyTextColor = isDark ? Colors.white70 : Colors.black87;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);

    // Calculate total seasons and episodes
    final totalSeasons = detail.seasons.length;
    final totalEpisodes = detail.seasons.fold<int>(0, (sum, s) => sum + s.episodes.length);

    // Check if any watch/download links exist
    final hasWatchLinks = detail.seasons.any((s) => s.episodes.any((e) => e.watchLinks.isNotEmpty));
    final hasDownloadLinks = detail.seasons.any((s) => s.episodes.any((e) => e.downloadLinks.isNotEmpty));

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ===== App Bar =====
          SliverAppBar(
            pinned: true,
            floating: false,
            leadingWidth: 46,
            backgroundColor: isDark ? const Color(0xFF121212) : bgColor,
            centerTitle: true,
            title: Text(
              detail.title,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black87, size: 24),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: Icon(
                  _isInWatchlist ? Icons.watch_later : Icons.watch_later_outlined,
                  color: _isInWatchlist ? const Color(0xFF4CAF50) : (isDark ? Colors.white : Colors.black54),
                  size: 24,
                ),
                onPressed: _toggleWatchlist,
              ),
              IconButton(
                icon: Icon(
                  _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                  color: _isBookmarked ? accentColor : (isDark ? Colors.white : Colors.black54),
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
                      // Poster
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
                                  errorWidget: (context, url, error) => Container(
                                    color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade300,
                                    child: Icon(Icons.tv, size: 36, color: isDark ? Colors.white24 : Colors.black12),
                                  ),
                                )
                              : Container(
                                  color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade300,
                                  child: Icon(Icons.tv, size: 36, color: isDark ? Colors.white24 : Colors.black12),
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
                              const SizedBox(height: 8),
                              // Meta: Year ⭐ Rating Season X 🇺🇸 English
                              Row(
                                children: [
                                  if (detail.year != null && detail.year!.isNotEmpty) ...[
                                    Text(detail.year!,
                                        style: TextStyle(color: metaTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                                    const SizedBox(width: 8),
                                    Text('·', style: TextStyle(color: metaTextColor, fontSize: 13)),
                                    const SizedBox(width: 8),
                                  ],
                                  if (detail.rating != null && detail.rating!.isNotEmpty) ...[
                                    Icon(Icons.star, size: 16, color: accentColor),
                                    const SizedBox(width: 3),
                                    Text(detail.rating!,
                                        style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 8),
                                    Text('·', style: TextStyle(color: metaTextColor, fontSize: 13)),
                                    const SizedBox(width: 8),
                                  ],
                                  if (totalSeasons > 0) ...[
                                    Text('Season $totalSeasons',
                                        style: TextStyle(color: metaTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
                                    const SizedBox(width: 8),
                                    Text('·', style: TextStyle(color: metaTextColor, fontSize: 13)),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(_getCountryLanguage(detail.country), style: const TextStyle(fontSize: 12)),
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
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isDark ? Colors.white12 : Colors.grey.shade300,
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(cat,
                                            style: TextStyle(
                                              color: isDark ? Colors.white70 : Colors.black87,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                            )),
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
                          style: TextStyle(color: bodyTextColor, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (totalSeasons > 0)
                        _detailRow('Seasons', '$totalSeasons', bodyTextColor, metaTextColor),
                      if (totalEpisodes > 0)
                        _detailRow('Episodes', '$totalEpisodes', bodyTextColor, metaTextColor),
                      if (detail.categories.isNotEmpty)
                        _detailRow('Genre', detail.categories.join('  '), bodyTextColor, metaTextColor),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ===== 3. ACTION BUTTONS =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: hasWatchLinks
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SeriesWatchScreen(seriesDetail: detail),
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
                            disabledBackgroundColor: isDark ? Colors.white12 : Colors.grey.shade300,
                            disabledForegroundColor: isDark ? Colors.white38 : Colors.black38,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Download Button (controlled by Show Download toggle)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (hasDownloadLinks && appConfig.downloadEnabled)
                              ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SeriesDownloadScreen(seriesDetail: detail),
                                    ),
                                  );
                                }
                              : null,
                          icon: const Icon(Icons.download, size: 20),
                          label: const Text('Download',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appConfig.downloadEnabled ? accentColor : (isDark ? Colors.white12 : Colors.grey.shade400),
                            foregroundColor: appConfig.downloadEnabled ? Colors.white : (isDark ? Colors.white38 : Colors.black38),
                            disabledBackgroundColor: isDark ? Colors.white12 : Colors.grey.shade300,
                            disabledForegroundColor: isDark ? Colors.white38 : Colors.black38,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ===== 4. OVERVIEW =====
                if (detail.overview != null && detail.overview!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Overview',
                            style: TextStyle(color: accentColor, fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final textSpan = TextSpan(
                              text: detail.overview!,
                              style: TextStyle(fontSize: 13, height: 1.6, color: bodyTextColor),
                            );
                            final textPainter = TextPainter(
                              text: textSpan,
                              maxLines: 4,
                              textDirection: TextDirection.ltr,
                            );
                            textPainter.layout(maxWidth: constraints.maxWidth);
                            final isOverflow = textPainter.didExceedMaxLines;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  detail.overview!,
                                  maxLines: _overviewExpanded ? null : 4,
                                  overflow: _overviewExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, height: 1.6, color: bodyTextColor),
                                ),
                                if (isOverflow)
                                  GestureDetector(
                                    onTap: () => setState(() => _overviewExpanded = !_overviewExpanded),
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        _overviewExpanded ? 'View Less' : 'View More',
                                        style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.w500),
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
                            style: TextStyle(color: bodyTextColor, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 110,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: detail.casts.length,
                            itemBuilder: (context, index) {
                              final cast = detail.casts[index];
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
                                      CircleAvatar(
                                        radius: 34,
                                        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade300,
                                        child: ClipOval(
                                          child: cast.fullProfileUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: cast.fullProfileUrl,
                                                  fit: BoxFit.cover,
                                                  width: 68,
                                                  height: 68,
                                                  placeholder: (context, url) =>
                                                      const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                                  errorWidget: (context, url, error) => Center(
                                                    child: Text(
                                                      cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?',
                                                      style: TextStyle(
                                                        color: isDark ? Colors.white54 : Colors.black54,
                                                        fontSize: 24,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                )
                                              : Center(
                                                  child: Text(
                                                    cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?',
                                                    style: TextStyle(
                                                      color: isDark ? Colors.white54 : Colors.black54,
                                                      fontSize: 24,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
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
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: bodyTextColor),
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

                const SizedBox(height: 20),

                // ===== 6. YOU MAY ALSO LIKE =====
                if (_relatedSeries.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('You May Also Like',
                            style: TextStyle(color: bodyTextColor, fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 200,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _relatedSeries.length,
                            itemBuilder: (context, index) {
                              final series = _relatedSeries[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => SeriesDetailScreen(slug: series.slug),
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
                                          child: series.fullPosterUrl.isNotEmpty
                                              ? CachedNetworkImage(
                                                  imageUrl: series.fullPosterUrl,
                                                  fit: BoxFit.cover,
                                                  errorWidget: (_, __, ___) => const Icon(Icons.tv, size: 30),
                                                )
                                              : const Icon(Icons.tv, size: 30),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        series.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: bodyTextColor),
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

  Widget _detailRow(String label, String value, Color bodyTextColor, Color metaTextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: metaTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value, style: TextStyle(color: bodyTextColor, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
