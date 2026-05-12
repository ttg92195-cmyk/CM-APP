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
import 'package:cm_movies/app/core/services/download_manager_service.dart';
import 'package:cm_movies/app/ui/screens/category_page.dart';
import 'package:cm_movies/app/ui/screens/download_page.dart';
import 'package:cm_movies/app/ui/screens/video_player_screen.dart';
import 'package:cm_movies/app/ui/components/age_rating_gate.dart';

class SeriesDetailScreen extends StatefulWidget {
  final String slug;

  const SeriesDetailScreen({super.key, required this.slug});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  final BookmarkService _bookmarkService = BookmarkService();
  final WatchlistService _watchlistService = WatchlistService();
  final RecentService _recentService = RecentService();
  final DownloadManagerService _downloadManager = DownloadManagerService.instance;

  MovieDetail? _seriesDetail;
  bool _isLoading = true;
  String? _error;
  bool _isBookmarked = false;
  bool _isInWatchlist = false;
  bool _ageVerified = false;
  bool _overviewExpanded = false;

  late TabController _tabController;
  List<Movie> _relatedSeries = [];
  bool _isLoadingRelated = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _downloadManager.init(); // Ensure download state is loaded (singleton: only runs once)
    _loadSeriesDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSeriesDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await _contentService.getMovieBySlug(widget.slug);
      if (detail != null && mounted) {
        // Age gate check for adult content
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
          limit: 9,
        );
        related = (result['movies'] as List<Movie>)
            .where((m) => m.id != detail.id)
            .toList();
      }
      if (related.length < 6 && detail.tags.isNotEmpty) {
        final tagResult = await _contentService.getMoviesByTagSimple(
          detail.tags.first,
          limit: 9,
        );
        for (final m in tagResult) {
          if (m.id != detail.id && !related.any((r) => r.id == m.id)) {
            related.add(m);
          }
          if (related.length >= 9) break;
        }
      }
      if (related.isEmpty) {
        final result = await _contentService.getTrendingTvShows();
        related = result.where((m) => m.id != detail.id).take(9).toList();
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
                ? Provider.of<AppConfig>(context, listen: false)
                    .translate('bookmark_added')
                : Provider.of<AppConfig>(context, listen: false)
                    .translate('bookmark_removed'),
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
                ? Provider.of<AppConfig>(context, listen: false)
                    .translate('watchlist_added')
                : Provider.of<AppConfig>(context, listen: false)
                    .translate('watchlist_removed'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _startInAppDownload(MovieDownloadLink link) async {
    if (_seriesDetail == null) return;

    // Validate URL before starting download
    if (link.url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download link is not available'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Check if download is enabled
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    if (!appConfig.downloadEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('download_disabled_msg')),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final result = await _downloadManager.addTaskWithResult(
      movieId: _seriesDetail!.id,
      movieTitle: _seriesDetail!.title,
      moviePoster: _seriesDetail!.fullPosterUrl.isNotEmpty ? _seriesDetail!.fullPosterUrl : _seriesDetail!.poster,
      url: link.url,
      quality: link.quality ?? link.resolution ?? 'Standard',
      size: link.size,
      serverName: link.serverName,
    );
    if (mounted) {
      String message;
      Color bgColor;
      switch (result) {
        case AddTaskResult.success:
          message = '${appConfig.translate('downloading')} — ${link.quality ?? link.resolution ?? 'Standard'}';
          bgColor = const Color(0xFF4CAF50);
          break;
        case AddTaskResult.blockedDomain:
          message = 'Download blocked: domain not allowed';
          bgColor = Colors.redAccent;
          break;
        case AddTaskResult.emptyUrl:
          message = 'Download URL is empty';
          bgColor = Colors.redAccent;
          break;
        case AddTaskResult.alreadyExists:
          message = 'Already downloading ${link.quality ?? link.resolution ?? 'Standard'}';
          bgColor = Colors.orange;
          break;
        case AddTaskResult.permissionDenied:
          message = 'Storage permission required. Grant permission in Download Settings.';
          bgColor = Colors.redAccent;
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 3),
          action: result == AddTaskResult.success
              ? SnackBarAction(
                  label: 'View',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DownloadPage()),
                    );
                  },
                )
              : null,
        ),
      );
    }
  }

  void _openVideoPlayer(String url, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(videoUrl: url, title: title),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Could not launch URL: $url - $e');
    }
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
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5);
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: bgColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // Header: Poster + Title info (no backdrop)
          SliverAppBar(
            expandedHeight: MediaQuery.of(context).padding.top + kToolbarHeight + 172,
            pinned: true,
            floating: false,
            leadingWidth: 46,
            backgroundColor: isDark ? const Color(0xFF0A0A0A) : bgColor,
            centerTitle: true,
            title: AnimatedOpacity(
              opacity: innerBoxIsScrolled ? 1.0 : 0.0,
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
            leading: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 16),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ),
            actions: [
              // Watchlist button
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isInWatchlist
                          ? Icons.watch_later
                          : Icons.watch_later_outlined,
                      color: _isInWatchlist
                          ? const Color(0xFF4CAF50)
                          : (isDark ? Colors.white : Colors.black54),
                      size: 16,
                    ),
                    onPressed: _toggleWatchlist,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ),
              ),
              // Bookmark button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isBookmarked
                          ? Icons.bookmark
                          : Icons.bookmark_outline,
                      color: _isBookmarked
                          ? accentColor
                          : (isDark ? Colors.white : Colors.black54),
                      size: 16,
                    ),
                    onPressed: _toggleBookmark,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: bgColor,
                child: Padding(
                  padding: EdgeInsets.only(
                      left: 16, right: 16, top: MediaQuery.of(context).padding.top + kToolbarHeight + 8, bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Poster thumbnail
                      Container(
                        width: 110,
                        height: 155,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: detail.fullPosterUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: detail.fullPosterUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      Container(
                                    color: isDark
                                        ? const Color(0xFF1E1E1E)
                                        : Colors.grey.shade300,
                                    child: Icon(Icons.tv,
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
                                  child: Icon(Icons.tv,
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
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detail.title,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (detail.year != null &&
                                      detail.year!.isNotEmpty) ...[
                                    Icon(Icons.calendar_today,
                                        size: 13, color: metaTextColor),
                                    const SizedBox(width: 4),
                                    Text(detail.year!,
                                        style: TextStyle(
                                            color: metaTextColor,
                                            fontSize: 12)),
                                    const SizedBox(width: 10),
                                  ],
                                  if (detail.rating != null &&
                                      detail.rating!.isNotEmpty) ...[
                                    const Icon(Icons.star,
                                        size: 14, color: Colors.amber),
                                    const SizedBox(width: 3),
                                    Text(detail.rating!,
                                        style: const TextStyle(
                                            color: Colors.amber,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 10),
                                  ],
                                  // Duration instead of Series badge
                                  if (detail.duration != null &&
                                      detail.duration!.isNotEmpty) ...[
                                    Icon(Icons.access_time,
                                        size: 13, color: metaTextColor),
                                    const SizedBox(width: 4),
                                    Text('${detail.duration} min',
                                        style: TextStyle(
                                            color: metaTextColor,
                                            fontSize: 12)),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Category tags - tappable pill chips
                              if (detail.categories.isNotEmpty)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: detail.categories.take(3).map((cat) {
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
              ),
            ),
          ),
          // Tab bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SeriesTabBarDelegate(
              tabController: _tabController,
              accentColor: accentColor,
              isDark: isDark,
            ),
          ),
        ],
        body: Container(
          color: bgColor,
          child: TabBarView(
            controller: _tabController,
            children: [
              // ===== Detail Tab =====
              _buildDetailTab(
                  detail, isDark, bodyTextColor, metaTextColor, accentColor),
              // ===== Download Tab =====
              _buildDownloadTab(
                  detail, isDark, accentColor, cardBgColor, metaTextColor, bodyTextColor),
              // ===== Explore Tab =====
              _buildExploreTab(
                  isDark, accentColor, metaTextColor, cardBgColor),
            ],
          ),
        ),
      ),
    );
  }

  // ===== DETAIL TAB =====
  Widget _buildDetailTab(
    MovieDetail detail,
    bool isDark,
    Color bodyTextColor,
    Color metaTextColor,
    Color accentColor,
  ) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 4),
      children: [
        // Overview Section
        if (detail.overview != null && detail.overview!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overview',
                    style: TextStyle(
                        color: bodyTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final textSpan = TextSpan(
                      text: detail.overview!,
                      style:
                          TextStyle(fontSize: 13, height: 1.5, color: bodyTextColor),
                    );
                    final textPainter = TextPainter(
                      text: textSpan,
                      maxLines: 10,
                      textDirection: TextDirection.ltr,
                    );
                    textPainter.layout(maxWidth: constraints.maxWidth);
                    final isOverflow = textPainter.didExceedMaxLines;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.overview!,
                          maxLines: _overviewExpanded ? null : 10,
                          overflow: _overviewExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, height: 1.5, color: bodyTextColor),
                        ),
                        if (isOverflow)
                          GestureDetector(
                            onTap: () => setState(
                                () => _overviewExpanded = !_overviewExpanded),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _overviewExpanded
                                        ? 'View Less'
                                        : 'View More',
                                    style: TextStyle(
                                      color: const Color(0xFFE50914),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Icon(
                                    _overviewExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: const Color(0xFFE50914),
                                    size: 16,
                                  ),
                                ],
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

        const SizedBox(height: 6),

        // Cast Section
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
                SizedBox(
                  height: 110,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: detail.casts.length,
                    itemBuilder: (context, index) {
                      final cast = detail.casts[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: isDark
                                  ? const Color(0xFF1E1E1E)
                                  : Colors.grey.shade300,
                              child: ClipOval(
                                child: cast.fullProfileUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: cast.fullProfileUrl,
                                        fit: BoxFit.cover,
                                        width: 68,
                                        height: 68,
                                        placeholder: (context, url) =>
                                            const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)),
                                        errorWidget: (context, url, error) =>
                                            Center(
                                          child: Text(
                                            cast.name.isNotEmpty
                                                ? cast.name[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                                color: isDark
                                                    ? Colors.white54
                                                    : Colors.black54,
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          cast.name.isNotEmpty
                                              ? cast.name[0].toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black54,
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold),
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
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: bodyTextColor),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ===== DOWNLOAD TAB =====
  Widget _buildDownloadTab(
    MovieDetail detail,
    bool isDark,
    Color accentColor,
    Color cardBgColor,
    Color metaTextColor,
    Color bodyTextColor,
  ) {
    final hasSeasons = detail.seasons.isNotEmpty;
    final hasDirectLinks = detail.downloadLinks.isNotEmpty;

    if (!hasSeasons && !hasDirectLinks) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 48, color: isDark ? Colors.white24 : Colors.black12),
            const SizedBox(height: 12),
            Text('No download links available',
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 14)),
          ],
        ),
      );
    }

    return DividerTheme(
      data: const DividerThemeData(color: Colors.transparent),
      child: ListView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        children: [
          Text('Download Options',
              style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Season-based downloads
          if (hasSeasons)
            ...detail.seasons.map((season) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ExpansionTile(
                    tilePadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    childrenPadding:
                        const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    collapsedIconColor: metaTextColor,
                    iconColor: accentColor,
                    collapsedBackgroundColor: Colors.transparent,
                    backgroundColor: Colors.transparent,
                  shape: const RoundedRectangleBorder(side: BorderSide.none),
                  collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.video_library,
                        color: accentColor, size: 22),
                  ),
                  title: Text(season.name,
                      style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${season.episodes.length} ${season.episodes.length == 1 ? 'episode' : 'episodes'}',
                        style: TextStyle(
                            color: isDark ? Colors.blue.shade300 : Colors.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                  children: season.episodes.map((episode) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 2),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          collapsedIconColor: metaTextColor,
                          iconColor: accentColor,
                          collapsedBackgroundColor: Colors.transparent,
                          backgroundColor: Colors.transparent,
                          shape: const RoundedRectangleBorder(side: BorderSide.none),
                          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                          leading: Icon(Icons.play_circle_outline,
                              color: isDark ? Colors.white54 : Colors.black54,
                              size: 20),
                          title: Text(episode.name,
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                          children: episode.downloadLinks.isEmpty
                              ? [
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Text('No links available',
                                        style: TextStyle(
                                            color: isDark
                                                ? Colors.white38
                                                : Colors.black38,
                                            fontSize: 12)),
                                  )
                                ]
                              : episode.downloadLinks.map((link) {
                                  final qualityLabel =
                                      link.quality ?? link.resolution ?? 'Standard';
                                  final qualityBadgeColor =
                                      _getQualityBadgeColor(qualityLabel);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: qualityBadgeColor,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(qualityLabel,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _getQualityDescription(
                                                  qualityLabel),
                                              style: TextStyle(
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        // Download buttons row
                                        Row(
                                          children: [
                                            // In-app download
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: link.url.isNotEmpty
                                                    ? () => _startInAppDownload(link)
                                                    : null,
                                                icon: const Icon(Icons.downloading, size: 16),
                                                label: Text('Save $qualityLabel'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF4CAF50),
                                                  foregroundColor: Colors.white,
                                                  disabledBackgroundColor: isDark
                                                      ? Colors.grey.shade700 : Colors.grey.shade400,
                                                  disabledForegroundColor: isDark
                                                      ? Colors.grey.shade500 : Colors.grey.shade600,
                                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(8)),
                                                  textStyle: const TextStyle(
                                                      fontWeight: FontWeight.w600, fontSize: 12),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            // Watch button
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: link.watchUrl != null && link.watchUrl!.isNotEmpty
                                                    ? () => _openVideoPlayer(link.watchUrl!, link.watchName ?? qualityLabel)
                                                    : null,
                                                icon: const Icon(Icons.play_circle_outline, size: 16),
                                                label: const Text('Watch'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: accentColor,
                                                  disabledForegroundColor: isDark
                                                      ? Colors.grey.shade500 : Colors.grey.shade600,
                                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(8)),
                                                  side: BorderSide(
                                                      color: link.watchUrl != null && link.watchUrl!.isNotEmpty
                                                          ? accentColor
                                                          : (isDark ? Colors.grey.shade700 : Colors.grey.shade400)),
                                                  textStyle: const TextStyle(
                                                      fontWeight: FontWeight.w600, fontSize: 12),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            );
          }),

        // Direct download links (without seasons)
        if (hasDirectLinks && !hasSeasons)
          ..._buildServerGroupWidgets(detail.downloadLinks, isDark, accentColor, metaTextColor),
      ],
    ),
    );
  }

  // Helper: Build server group widgets for download tab
  List<Widget> _buildServerGroupWidgets(
    List<MovieDownloadLink> downloadLinks,
    bool isDark,
    Color accentColor,
    Color metaTextColor,
  ) {
    final Map<String, List<MovieDownloadLink>> serverGroups = {};
    for (final link in downloadLinks) {
      final serverName = link.serverName.isNotEmpty ? link.serverName : 'Server';
      serverGroups.putIfAbsent(serverName, () => []).add(link);
    }
    return serverGroups.entries.map((entry) {
      final serverName = entry.key;
      final links = entry.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.white12 : Colors.grey.shade300,
              width: 0.5,
            ),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            collapsedIconColor: metaTextColor,
            iconColor: accentColor,
            collapsedBackgroundColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.dns_outlined, color: accentColor, size: 22),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(serverName,
                    style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  links.map((l) => l.quality ?? l.resolution ?? 'Link').join(', '),
                  style: TextStyle(color: metaTextColor, fontSize: 11),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${links.length} ${links.length == 1 ? 'quality' : 'qualities'}',
                  style: TextStyle(
                      color: isDark ? Colors.blue.shade300 : Colors.blue,
                      fontSize: 10,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
            children: links.map((link) {
              final qualityLabel = link.quality ?? link.resolution ?? 'Standard';
              final qualityBadgeColor = _getQualityBadgeColor(qualityLabel);
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade200,
                      width: 0.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: qualityBadgeColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(qualityLabel,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getQualityDescription(qualityLabel),
                              style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'MKV · Myanmar Subtitle (Hardsub)${link.size != null ? ' · ${link.size}' : ''}',
                          style: TextStyle(color: metaTextColor, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                        // Download buttons row
                        Row(
                          children: [
                            // In-app download
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: link.url.isNotEmpty
                                    ? () => _startInAppDownload(link)
                                    : null,
                                icon: const Icon(Icons.downloading, size: 16),
                                label: Text('Save $qualityLabel'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4CAF50),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: isDark
                                      ? Colors.grey.shade700 : Colors.grey.shade400,
                                  disabledForegroundColor: isDark
                                      ? Colors.grey.shade500 : Colors.grey.shade600,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Watch button
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: link.watchUrl != null && link.watchUrl!.isNotEmpty
                                    ? () => _openVideoPlayer(link.watchUrl!, link.watchName ?? qualityLabel)
                                    : null,
                                icon: const Icon(Icons.play_circle_outline, size: 16),
                                label: const Text('Watch'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: accentColor,
                                  disabledForegroundColor: isDark
                                      ? Colors.grey.shade500 : Colors.grey.shade600,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(
                                      color: link.watchUrl != null && link.watchUrl!.isNotEmpty
                                          ? accentColor
                                          : (isDark ? Colors.grey.shade700 : Colors.grey.shade400)),
                                  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }).toList();
  }

  Color _getQualityBadgeColor(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd')) {
      return const Color(0xFFE50914);
    } else if (q.contains('1080')) {
      return const Color(0xFFFF6D00);
    } else if (q.contains('720')) {
      return const Color(0xFFFFAB00);
    }
    return const Color(0xFF4CAF50);
  }

  String _getQualityDescription(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd')) return 'Ultra HD';
    if (q.contains('1080')) return 'Full HD';
    if (q.contains('720')) return 'HD';
    if (q.contains('480')) return 'Standard';
    return 'Standard';
  }

  // ===== EXPLORE TAB =====
  Widget _buildExploreTab(
    bool isDark,
    Color accentColor,
    Color metaTextColor,
    Color cardBgColor,
  ) {
    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Text('You may also like',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _isLoadingRelated
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: CircularProgressIndicator(),
                ),
              )
            : _relatedSeries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.tv_outlined,
                              size: 56,
                              color: isDark ? Colors.white24 : Colors.black12),
                          const SizedBox(height: 12),
                          Text('No related series found',
                              style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.black45,
                                  fontSize: 14)),
                        ],
                      ),
                    ),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.52,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _relatedSeries.length,
                    itemBuilder: (context, index) {
                      final series = _relatedSeries[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SeriesDetailScreen(
                                  slug: series.slug),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Poster with badges
                            Expanded(
                              child: Stack(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: series.fullPosterUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: series.fullPosterUrl,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) =>
                                                  Container(
                                                color: isDark
                                                    ? const Color(0xFF1E1E1E)
                                                    : Colors.grey.shade300,
                                                child: const Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2)),
                                              ),
                                              errorWidget:
                                                  (context, url, error) =>
                                                      Container(
                                                color: isDark
                                                    ? const Color(0xFF1E1E1E)
                                                    : Colors.grey.shade300,
                                                child: Icon(Icons.tv,
                                                    size: 30,
                                                    color: isDark
                                                        ? Colors.white24
                                                        : Colors.black12),
                                              ),
                                            )
                                          : Container(
                                              color: isDark
                                                  ? const Color(0xFF1E1E1E)
                                                  : Colors.grey.shade300,
                                              child: Icon(Icons.tv,
                                                  size: 30,
                                                  color: isDark
                                                      ? Colors.white24
                                                      : Colors.black12),
                                            ),
                                    ),
                                  ),
                                  // Quality badge - top left
                                  if (series.poster != null &&
                                      series.poster!.isNotEmpty)
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: accentColor,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text('1080p',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                  // Rating badge - top right
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade700,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star,
                                              size: 9, color: Colors.white),
                                          const SizedBox(width: 2),
                                          Text(
                                            series.rating ?? '7.0',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Title
                            Text(
                              series.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // Year
                            if (series.year != null && series.year!.isNotEmpty)
                              Text(
                                series.year!,
                                style: TextStyle(
                                    color: metaTextColor, fontSize: 10),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
      ],
    );
  }
}

// Custom TabBar SliverPersistentHeaderDelegate
class _SeriesTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final Color accentColor;
  final bool isDark;

  _SeriesTabBarDelegate({
    required this.tabController,
    required this.accentColor,
    required this.isDark,
  });

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  bool shouldRebuild(covariant _SeriesTabBarDelegate oldDelegate) {
    return oldDelegate.isDark != isDark ||
        oldDelegate.accentColor != accentColor;
  }

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
      child: TabBar(
        controller: tabController,
        labelColor: accentColor,
        unselectedLabelColor: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
        indicator: const BoxDecoration(),
        dividerColor: Colors.transparent,
        labelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
        tabs: const [
          Tab(icon: Icon(Icons.info_outline, size: 20), text: 'Detail'),
          Tab(icon: Icon(Icons.file_download_outlined, size: 20), text: 'Download'),
          Tab(icon: Icon(Icons.explore_outlined, size: 20), text: 'Explore'),
        ],
      ),
    );
  }
}
