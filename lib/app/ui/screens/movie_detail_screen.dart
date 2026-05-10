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
import 'package:cm_movies/app/ui/components/age_rating_gate.dart';

class MovieDetailScreen extends StatefulWidget {
  final String slug;

  const MovieDetailScreen({super.key, required this.slug});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen>
    with SingleTickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  final BookmarkService _bookmarkService = BookmarkService();
  final WatchlistService _watchlistService = WatchlistService();
  final RecentService _recentService = RecentService();
  final DownloadManagerService _downloadManager = DownloadManagerService.instance;

  MovieDetail? _movieDetail;
  bool _isLoading = true;
  String? _error;
  bool _isBookmarked = false;
  bool _isInWatchlist = false;
  bool _ageVerified = false;
  bool _overviewExpanded = false;

  late TabController _tabController;
  List<Movie> _relatedMovies = [];
  bool _isLoadingRelated = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _downloadManager.init(); // Ensure download state is loaded (singleton: only runs once)
    _loadMovieDetail();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMovieDetail() async {
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
        final result = await _contentService.getTrendingMovies();
        related = result.where((m) => m.id != detail.id).take(9).toList();
      }
      if (mounted) {
        setState(() {
          _relatedMovies = related;
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
    if (_movieDetail == null) return;
    final movie = Movie(
      id: _movieDetail!.id,
      title: _movieDetail!.title,
      slug: _movieDetail!.slug,
      year: _movieDetail!.year,
      poster: _movieDetail!.poster,
      type: _movieDetail!.type,
      isTrending: _movieDetail!.isTrending,
    );
    await _bookmarkService.toggleBookmark(movie);
    final bookmarked = await _bookmarkService.isBookmarked(_movieDetail!.id);
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
    if (_movieDetail == null) return;
    final movie = Movie(
      id: _movieDetail!.id,
      title: _movieDetail!.title,
      slug: _movieDetail!.slug,
      year: _movieDetail!.year,
      poster: _movieDetail!.poster,
      type: _movieDetail!.type,
      isTrending: _movieDetail!.isTrending,
    );
    await _watchlistService.toggleWatchlist(movie);
    final inWatchlist = await _watchlistService.isInWatchlist(_movieDetail!.id);
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
    if (_movieDetail == null) return;
    await _downloadManager.addTask(
      movieId: _movieDetail!.id,
      movieTitle: _movieDetail!.title,
      moviePoster: _movieDetail!.poster,
      url: link.url,
      quality: link.quality ?? link.resolution ?? 'Standard',
      size: link.size,
      serverName: link.serverName,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Provider.of<AppConfig>(context, listen: false)
              .translate('downloading')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(Icons.arrow_back,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 18),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            actions: [
              // Watchlist button
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 32,
                  height: 32,
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
                      size: 18,
                    ),
                    onPressed: _toggleWatchlist,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ),
              ),
              // Bookmark button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  width: 32,
                  height: 32,
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
                      size: 18,
                    ),
                    onPressed: _toggleBookmark,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
            delegate: _TabBarDelegate(
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
      padding: const EdgeInsets.only(bottom: 8),
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
                                      color: accentColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Icon(
                                    _overviewExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: accentColor,
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
    if (detail.downloadLinks.isEmpty) {
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

    // Group download links by server
    final Map<String, List<MovieDownloadLink>> serverGroups = {};
    for (final link in detail.downloadLinks) {
      final serverName = link.serverName.isNotEmpty ? link.serverName : 'Server';
      serverGroups.putIfAbsent(serverName, () => []).add(link);
    }

    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      children: [
        Text('Download Options',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...serverGroups.entries.map((entry) {
          final serverName = entry.key;
          final links = entry.value;
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
                dividerColor: Colors.transparent,
                shape: const RoundedRectangleBorder(side: BorderSide.none),
                collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.dns_outlined,
                      color: accentColor, size: 22),
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
                      links
                          .map((l) => l.quality ?? l.resolution ?? 'Link')
                          .join(', '),
                      style: TextStyle(
                          color: metaTextColor, fontSize: 11),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: qualityBadgeColor,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    qualityLabel,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getQualityDescription(qualityLabel),
                                  style: TextStyle(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'MKV · Myanmar Subtitle (Hardsub)${link.size != null ? ' · ${link.size}' : ''}',
                              style: TextStyle(
                                  color: metaTextColor, fontSize: 11),
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
                                      disabledBackgroundColor:
                                          isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                                      disabledForegroundColor:
                                          isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8)),
                                      textStyle: const TextStyle(
                                          fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // External download
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: link.url.isNotEmpty
                                        ? () => _launchUrl(link.url)
                                        : null,
                                    icon: const Icon(Icons.open_in_new, size: 16),
                                    label: Text('Open $qualityLabel'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: accentColor,
                                      disabledForegroundColor:
                                          isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8)),
                                      side: BorderSide(
                                          color: link.url.isNotEmpty
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
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          );
        }),
      ],
    );
  }

  Color _getQualityBadgeColor(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd')) {
      return const Color(0xFFE50914); // Red for 4K
    } else if (q.contains('1080')) {
      return const Color(0xFFFF6D00); // Orange for 1080p
    } else if (q.contains('720')) {
      return const Color(0xFFFFAB00); // Yellow/amber for 720p
    }
    return const Color(0xFF4CAF50); // Green for others
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
            : _relatedMovies.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.movie_outlined,
                              size: 56,
                              color: isDark ? Colors.white24 : Colors.black12),
                          const SizedBox(height: 12),
                          Text('No related movies found',
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
                    itemCount: _relatedMovies.length,
                    itemBuilder: (context, index) {
                      final movie = _relatedMovies[index];
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MovieDetailScreen(
                                  slug: movie.slug),
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
                                      child: movie.fullPosterUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: movie.fullPosterUrl,
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
                                                child: Icon(Icons.movie,
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
                                              child: Icon(Icons.movie,
                                                  size: 30,
                                                  color: isDark
                                                      ? Colors.white24
                                                      : Colors.black12),
                                            ),
                                    ),
                                  ),
                                  // Quality badge - top left
                                  if (movie.poster != null &&
                                      movie.poster!.isNotEmpty)
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
                                            movie.rating ?? '7.0',
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
                              movie.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // Year
                            if (movie.year != null && movie.year!.isNotEmpty)
                              Text(
                                movie.year!,
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
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final Color accentColor;
  final bool isDark;

  _TabBarDelegate({
    required this.tabController,
    required this.accentColor,
    required this.isDark,
  });

  @override
  double get minExtent => 52;

  @override
  double get maxExtent => 52;

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) {
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
