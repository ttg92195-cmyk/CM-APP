import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/services/bookmark_service.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';

class MovieDetailScreen extends StatefulWidget {
  final String slug;

  const MovieDetailScreen({super.key, required this.slug});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final BookmarkService _bookmarkService = BookmarkService();
  final RecentService _recentService = RecentService();

  MovieDetail? _movieDetail;
  bool _isLoading = true;
  String? _error;
  bool _isBookmarked = false;
  bool _synopsisExpanded = false;

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

        setState(() {
          _movieDetail = detail;
          _isBookmarked = bookmarked;
          _isLoading = false;
        });
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
                ? Provider.of<AppConfig>(context, listen: false).translate('bookmark_added')
                : Provider.of<AppConfig>(context, listen: false).translate('bookmark_removed'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        // Fallback: try in-app web view mode
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Could not launch URL: $url - $e');
    }
  }

  // Glassmorphism icon button for back/bookmark
  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? iconColor,
    double size = 24,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor ?? Colors.white, size: size),
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
  }

  void _showDownloadModal() {
    if (_movieDetail == null) return;
    final detail = _movieDetail!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.download_rounded, color: isDark ? const Color(0xFFF5C518) : const Color(0xFFD4A817)),
                  const SizedBox(width: 8),
                  Text(
                    'All Download Links',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              child: Row(
                children: [
                  _tableCell('No', 40, isHeader: true, isDark: isDark),
                  _tableCell('Server', 80, isHeader: true, isDark: isDark),
                  _tableCell('Quality', 70, isHeader: true, isDark: isDark),
                  _tableCell('Size', 70, isHeader: true, isDark: isDark),
                  _tableCell('Link', 80, isHeader: true, isDark: isDark),
                ],
              ),
            ),
            Expanded(
              child: detail.downloadLinks.isEmpty
                  ? Center(
                      child: Text(
                        'No download links available',
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: detail.downloadLinks.length,
                      itemBuilder: (_, index) {
                        final link = detail.downloadLinks[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            children: [
                              _tableCell('${index + 1}', 40, isDark: isDark),
                              _tableCell(link.serverName, 80, isDark: isDark),
                              _tableCell(link.quality ?? '-', 70, isDark: isDark),
                              _tableCell(link.size ?? '-', 70, isDark: isDark),
                              SizedBox(
                                width: 80,
                                child: link.url.isNotEmpty
                                    ? InkWell(
                                        onTap: () => _launchUrl(link.url),
                                        child: Text(
                                          'Open',
                                          style: TextStyle(
                                            color: isDark ? const Color(0xFFF5C518) : const Color(0xFFD4A817),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      )
                                    : Text('-', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
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
    );
  }

  void _showWatchModal() {
    if (_movieDetail == null) return;
    final detail = _movieDetail!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.play_circle_filled, color: isDark ? const Color(0xFFF5C518) : const Color(0xFFD4A817)),
                  const SizedBox(width: 8),
                  Text(
                    'Watch Online',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: isDark ? Colors.white10 : Colors.grey.shade200,
              child: Row(
                children: [
                  _tableCell('No', 40, isHeader: true, isDark: isDark),
                  _tableCell('Server', 80, isHeader: true, isDark: isDark),
                  _tableCell('Quality', 70, isHeader: true, isDark: isDark),
                  _tableCell('Size', 70, isHeader: true, isDark: isDark),
                  _tableCell('Link', 80, isHeader: true, isDark: isDark),
                ],
              ),
            ),
            Expanded(
              child: detail.downloadLinks.isEmpty
                  ? Center(
                      child: Text(
                        'No watch links available',
                        style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: detail.downloadLinks.length,
                      itemBuilder: (_, index) {
                        final link = detail.downloadLinks[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200),
                            ),
                          ),
                          child: Row(
                            children: [
                              _tableCell('${index + 1}', 40, isDark: isDark),
                              _tableCell(link.serverName, 80, isDark: isDark),
                              _tableCell(link.quality ?? '-', 70, isDark: isDark),
                              _tableCell(link.size ?? '-', 70, isDark: isDark),
                              SizedBox(
                                width: 80,
                                child: link.url.isNotEmpty
                                    ? InkWell(
                                        onTap: () => _launchUrl(link.url),
                                        child: Text(
                                          'Watch',
                                          style: TextStyle(
                                            color: isDark ? const Color(0xFFF5C518) : const Color(0xFFD4A817),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      )
                                    : Text('-', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black45)),
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
    );
  }

  Widget _tableCell(String text, double width, {bool isHeader = false, bool isDark = true}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader
              ? (isDark ? Colors.white : Colors.black87)
              : (isDark ? Colors.white70 : Colors.black87),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
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

    // Adaptive colors
    final sectionHeaderColor = isDark ? const Color(0xFFF5C518) : const Color(0xFFB8960F);
    final bodyTextColor = isDark ? Colors.white70 : Colors.black87;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final tagBorderColor = isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    final tagTextColor = isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFF5F5F5),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== Header: Backdrop + Poster + Info =====
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Backdrop image (shorter height, ~200px)
                SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: (detail.fullBackdropUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: detail.fullBackdropUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  detail.fullPosterUrl.isNotEmpty
                                      ? CachedNetworkImage(imageUrl: detail.fullPosterUrl, fit: BoxFit.cover)
                                      : Container(
                                          color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade400,
                                        ),
                            )
                          : detail.fullPosterUrl.isNotEmpty
                              ? CachedNetworkImage(imageUrl: detail.fullPosterUrl, fit: BoxFit.cover)
                              : Container(color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade400)
                      ),
                ),

                // Dark overlay on backdrop (0.7 opacity)
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                  ),
                ),

                // Back button and bookmark - with glassmorphism
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildGlassIconButton(
                            icon: Icons.arrow_back,
                            onPressed: () => Navigator.pop(context),
                          ),
                          _buildGlassIconButton(
                            icon: _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                            onPressed: _toggleBookmark,
                            iconColor: _isBookmarked ? Colors.amber : Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // Poster + Title/Info row (overlaps up into backdrop)
            Transform.translate(
              offset: const Offset(0, -60),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Poster thumbnail
                    Container(
                      width: 110,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: detail.fullPosterUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: detail.fullPosterUrl,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                                  child: Icon(Icons.movie, size: 40, color: isDark ? Colors.white24 : Colors.black12),
                                ),
                              )
                            : Container(
                                color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                                child: Icon(Icons.movie, size: 40, color: isDark ? Colors.white24 : Colors.black12),
                              ),
                      ),
                    ),

                    const SizedBox(width: 14),

                    // Title + Meta info
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
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
                            const SizedBox(height: 8),

                            // Rating + Year + Duration row
                            Row(
                              children: [
                                if (detail.rating != null && detail.rating!.isNotEmpty) ...[
                                  const Icon(Icons.star, size: 16, color: Colors.amber),
                                  const SizedBox(width: 3),
                                  Text(
                                    detail.rating!,
                                    style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                if (detail.year != null && detail.year!.isNotEmpty) ...[
                                  Text(detail.year!, style: TextStyle(color: metaTextColor, fontSize: 13)),
                                  const SizedBox(width: 12),
                                ],
                                if (detail.duration != null && detail.duration!.isNotEmpty) ...[
                                  Text('${detail.duration} min', style: TextStyle(color: metaTextColor, fontSize: 13)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Type badge
                            if (detail.type != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE50914).withOpacity(0.85),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  detail.type == 'series' ? 'Series' : 'Movie',
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Categories - outline style tags
            if (detail.categories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: detail.categories.take(5).map((cat) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tagBorderColor, width: 1),
                    ),
                    child: Text(cat, style: TextStyle(color: tagTextColor, fontSize: 11)),
                  )).toList(),
                ),
              ),

            const SizedBox(height: 16),

            // ===== Action Buttons =====
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: detail.downloadLinks.isNotEmpty ? _showWatchModal : null,
                      icon: const Icon(Icons.play_arrow, size: 20),
                      label: const Text('Watch Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5C518),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                        disabledForegroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: detail.downloadLinks.isNotEmpty ? _showDownloadModal : null,
                      icon: const Icon(Icons.download, size: 20),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5C518),
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: isDark ? Colors.grey.shade700 : Colors.grey.shade400,
                        disabledForegroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tags row - outline style
            if (detail.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: detail.tags.take(6).map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: tagBorderColor, width: 1),
                    ),
                    child: Text(tag, style: TextStyle(color: tagTextColor, fontSize: 11)),
                  )).toList(),
                ),
              ),

            const SizedBox(height: 16),

            // ===== Synopsis Section =====
            if (detail.overview != null && detail.overview!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Synopsis', style: TextStyle(color: sectionHeaderColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textSpan = TextSpan(
                          text: detail.overview!,
                          style: TextStyle(fontSize: 14, height: 1.6, color: bodyTextColor),
                        );
                        final textPainter = TextPainter(
                          text: textSpan,
                          maxLines: 3,
                          textDirection: TextDirection.ltr,
                        );
                        textPainter.layout(maxWidth: constraints.maxWidth);
                        final isOverflow = textPainter.didExceedMaxLines;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              detail.overview!,
                              maxLines: _synopsisExpanded ? null : 3,
                              overflow: _synopsisExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, height: 1.6, color: bodyTextColor),
                            ),
                            if (isOverflow)
                              GestureDetector(
                                onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _synopsisExpanded ? 'read less' : '...read more',
                                    style: TextStyle(
                                      color: sectionHeaderColor,
                                      fontSize: 13,
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

            // ===== Directors Section =====
            if (detail.directors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Director', style: TextStyle(color: sectionHeaderColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: detail.directors.map((d) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? Colors.white12 : Colors.grey.shade400,
                            width: 0.5,
                          ),
                        ),
                        child: Text(d, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
                      )).toList(),
                    ),
                  ],
                ),
              ),

            if (detail.directors.isNotEmpty) const SizedBox(height: 20),

            // ===== Cast Section =====
            if (detail.casts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Cast', style: TextStyle(color: sectionHeaderColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: detail.casts.length,
                        itemBuilder: (context, index) {
                          final cast = detail.casts[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                                  child: ClipOval(
                                    child: cast.fullProfileUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: cast.fullProfileUrl,
                                            fit: BoxFit.cover,
                                            width: 64,
                                            height: 64,
                                            placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                            errorWidget: (context, url, error) => Center(
                                              child: Text(
                                                cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?',
                                                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 22, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Text(
                                              cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?',
                                              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 22, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 72,
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
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            if (detail.casts.isNotEmpty) const SizedBox(height: 20),

            // ===== Download Links Section (inline) =====
            if (detail.downloadLinks.isNotEmpty && appConfig.downloadEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Download', style: TextStyle(color: sectionHeaderColor, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...detail.downloadLinks.map((link) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        margin: EdgeInsets.zero,
                        color: cardBgColor,
                        child: InkWell(
                          onTap: link.url.isNotEmpty ? () => _launchUrl(link.url) : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(Icons.download_rounded, color: isDark ? theme.colorScheme.primary : const Color(0xFFB8960F), size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(link.serverName, style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (link.quality != null) ...[
                                            _buildInfoChip('Quality', link.quality!, theme, isDark),
                                            const SizedBox(width: 8),
                                          ],
                                          if (link.resolution != null) ...[
                                            _buildInfoChip('Resolution', link.resolution!, theme, isDark),
                                            const SizedBox(width: 8),
                                          ],
                                          if (link.size != null)
                                            _buildInfoChip('Size', link.size!, theme, isDark),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.open_in_new, color: isDark ? theme.colorScheme.primary : const Color(0xFFB8960F), size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )),
                  ],
                ),
              ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.primaryContainer : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: isDark ? theme.colorScheme.onPrimaryContainer : Colors.black87,
          fontSize: 10,
        ),
      ),
    );
  }
}
