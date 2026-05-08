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

class SeriesDetailScreen extends StatefulWidget {
  final String slug;

  const SeriesDetailScreen({super.key, required this.slug});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final BookmarkService _bookmarkService = BookmarkService();
  final RecentService _recentService = RecentService();

  MovieDetail? _seriesDetail;
  bool _isLoading = true;
  String? _error;
  bool _isBookmarked = false;
  bool _synopsisExpanded = false;

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
          _seriesDetail = detail;
          _isBookmarked = bookmarked;
          _isLoading = false;
        });
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  void _showSeriesDownloadModal() {
    if (_seriesDetail == null) return;
    final detail = _seriesDetail!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SeriesDownloadSheet(
        detail: detail,
        isDark: isDark,
        theme: theme,
        onLaunchUrl: _launchUrl,
      ),
    );
  }

  void _showSeriesWatchModal() {
    if (_seriesDetail == null) return;
    final detail = _seriesDetail!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SeriesWatchSheet(
        detail: detail,
        isDark: isDark,
        theme: theme,
        onLaunchUrl: _launchUrl,
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

    // Adaptive colors
    final sectionHeaderColor = isDark ? const Color(0xFFF5C518) : const Color(0xFFB8960F);
    final bodyTextColor = isDark ? Colors.white70 : Colors.black87;
    final chipBgColor = isDark ? Colors.white12 : const Color(0xFFE8E8E8);
    final chipTextColor = isDark ? Colors.white70 : const Color(0xFF333333);

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ===== Poster Backdrop Section =====
            Stack(
              children: [
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: (detail.fullBackdropUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: detail.fullBackdropUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  detail.fullPosterUrl.isNotEmpty
                                      ? CachedNetworkImage(imageUrl: detail.fullPosterUrl, fit: BoxFit.cover)
                                      : Container(
                                          color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                                          child: Icon(Icons.tv, size: 64, color: isDark ? Colors.white24 : Colors.black12),
                                        ),
                            )
                          : detail.fullPosterUrl.isNotEmpty
                              ? CachedNetworkImage(imageUrl: detail.fullPosterUrl, fit: BoxFit.cover)
                              : Container(
                                  color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                                  child: Icon(Icons.tv, size: 64, color: isDark ? Colors.white24 : Colors.black12),
                                )
                      ),
                ),
                // Stronger gradient overlay for text readability
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.5),
                        Colors.black.withOpacity(0.95),
                      ],
                    ),
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
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detail.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          shadows: [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black87)],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (detail.rating != null && detail.rating!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, size: 14, color: Colors.amber),
                                  const SizedBox(width: 3),
                                  Text(detail.rating!, style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          if (detail.rating != null && detail.rating!.isNotEmpty) const SizedBox(width: 10),
                          if (detail.year != null && detail.year!.isNotEmpty)
                            Text(detail.year!, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                          if (detail.year != null && detail.year!.isNotEmpty) const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914).withOpacity(0.85),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('Series', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (detail.categories.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: detail.categories.take(4).map((cat) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white38, width: 0.5),
                            ),
                            child: Text(cat, style: const TextStyle(color: Colors.white, fontSize: 11)),
                          )).toList(),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            // ===== Action Buttons =====
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: detail.seasons.isNotEmpty || detail.downloadLinks.isNotEmpty ? _showSeriesWatchModal : null,
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
                      onPressed: detail.seasons.isNotEmpty || detail.downloadLinks.isNotEmpty ? _showSeriesDownloadModal : null,
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

            // Tags row - improved contrast for light mode
            if (detail.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: detail.tags.take(6).map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: chipBgColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.grey.shade400,
                        width: 0.5,
                      ),
                    ),
                    child: Text(tag, style: TextStyle(color: chipTextColor, fontSize: 11)),
                  )).toList(),
                ),
              ),

            const SizedBox(height: 16),

            // Synopsis
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
                        final textPainter = TextPainter(text: textSpan, maxLines: 3, textDirection: TextDirection.ltr);
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

            // Directors
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
                          color: chipBgColor,
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

            // Cast
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
                                            imageUrl: cast.fullProfileUrl, fit: BoxFit.cover, width: 64, height: 64,
                                            placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                            errorWidget: (context, url, error) => Center(
                                              child: Text(cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?',
                                                style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 22, fontWeight: FontWeight.bold)),
                                            ),
                                          )
                                        : Center(
                                            child: Text(cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?',
                                              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 22, fontWeight: FontWeight.bold)),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                SizedBox(
                                  width: 72,
                                  child: Text(cast.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: bodyTextColor)),
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

            // NOTE: "Seasons & Episodes" inline section REMOVED
            // Season/Episode selection is now only available via Watch/Download modal bottom sheets

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ===== Series Download Modal (Season -> Episode -> Links) =====
class _SeriesDownloadSheet extends StatefulWidget {
  final MovieDetail detail;
  final bool isDark;
  final ThemeData theme;
  final Function(String) onLaunchUrl;

  const _SeriesDownloadSheet({
    required this.detail,
    required this.isDark,
    required this.theme,
    required this.onLaunchUrl,
  });

  @override
  State<_SeriesDownloadSheet> createState() => _SeriesDownloadSheetState();
}

class _SeriesDownloadSheetState extends State<_SeriesDownloadSheet> {
  int? _selectedSeasonIndex;
  int? _selectedEpisodeIndex;

  @override
  Widget build(BuildContext context) {
    final seasons = widget.detail.seasons;
    final isDark = widget.isDark;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
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
                Text('All Download Links', style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: isDark ? Colors.white : Colors.black87,
                )),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),

          // Season selector - improved contrast
          if (seasons.isNotEmpty) ...[
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                itemBuilder: (_, index) {
                  final isSelected = _selectedSeasonIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(seasons[index].name),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedSeasonIndex = index;
                          _selectedEpisodeIndex = null;
                        });
                      },
                      selectedColor: isDark
                          ? const Color(0xFFE50914).withOpacity(0.35)
                          : const Color(0xFFE50914).withOpacity(0.15),
                      backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFE50914)
                            : (isDark ? Colors.white24 : Colors.grey.shade400),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white70 : Colors.black54),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
          ],

          // Episode list - improved contrast
          if (_selectedSeasonIndex != null && seasons[_selectedSeasonIndex!].episodes.isNotEmpty) ...[
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: seasons[_selectedSeasonIndex!].episodes.length,
                itemBuilder: (_, index) {
                  final episode = seasons[_selectedSeasonIndex!].episodes[index];
                  final isSelected = _selectedEpisodeIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(episode.name),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedEpisodeIndex = index);
                      },
                      selectedColor: isDark
                          ? const Color(0xFFF5C518).withOpacity(0.35)
                          : const Color(0xFFF5C518).withOpacity(0.15),
                      backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFF5C518)
                            : (isDark ? Colors.white24 : Colors.grey.shade400),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white70 : Colors.black54),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
          ],

          // Download links table
          if (_selectedSeasonIndex != null && _selectedEpisodeIndex != null)
            Expanded(
              child: _buildLinksTable(seasons[_selectedSeasonIndex!].episodes[_selectedEpisodeIndex!].downloadLinks, scrollController),
            )
          else if (_selectedSeasonIndex == null && widget.detail.downloadLinks.isNotEmpty)
            Expanded(
              child: _buildLinksTable(widget.detail.downloadLinks, scrollController),
            )
          else
            Expanded(
              child: Center(
                child: Text(
                  _selectedSeasonIndex == null
                      ? 'Select a season'
                      : 'Select an episode',
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinksTable(List<MovieDownloadLink> links, ScrollController controller) {
    final isDark = widget.isDark;

    return Column(
      children: [
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
          child: links.isEmpty
              ? Center(child: Text('No links', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45)))
              : ListView.builder(
                  controller: controller,
                  itemCount: links.length,
                  itemBuilder: (_, index) {
                    final link = links[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
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
                                ? TextButton(
                                    onPressed: () => widget.onLaunchUrl(link.url),
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                    child: Text('Open', style: TextStyle(color: isDark ? const Color(0xFFF5C518) : const Color(0xFFD4A817), fontSize: 12)),
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
}

// ===== Series Watch Modal =====
class _SeriesWatchSheet extends StatefulWidget {
  final MovieDetail detail;
  final bool isDark;
  final ThemeData theme;
  final Function(String) onLaunchUrl;

  const _SeriesWatchSheet({
    required this.detail,
    required this.isDark,
    required this.theme,
    required this.onLaunchUrl,
  });

  @override
  State<_SeriesWatchSheet> createState() => _SeriesWatchSheetState();
}

class _SeriesWatchSheetState extends State<_SeriesWatchSheet> {
  int? _selectedSeasonIndex;
  int? _selectedEpisodeIndex;

  @override
  Widget build(BuildContext context) {
    final seasons = widget.detail.seasons;
    final isDark = widget.isDark;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
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
                Text('Watch Online', style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: isDark ? Colors.white : Colors.black87,
                )),
              ],
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),

          if (seasons.isNotEmpty) ...[
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: seasons.length,
                itemBuilder: (_, index) {
                  final isSelected = _selectedSeasonIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(seasons[index].name),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _selectedSeasonIndex = index;
                          _selectedEpisodeIndex = null;
                        });
                      },
                      selectedColor: isDark
                          ? const Color(0xFFE50914).withOpacity(0.35)
                          : const Color(0xFFE50914).withOpacity(0.15),
                      backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFE50914)
                            : (isDark ? Colors.white24 : Colors.grey.shade400),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white70 : Colors.black54),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
          ],

          if (_selectedSeasonIndex != null && seasons[_selectedSeasonIndex!].episodes.isNotEmpty) ...[
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: seasons[_selectedSeasonIndex!].episodes.length,
                itemBuilder: (_, index) {
                  final episode = seasons[_selectedSeasonIndex!].episodes[index];
                  final isSelected = _selectedEpisodeIndex == index;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(episode.name),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedEpisodeIndex = index);
                      },
                      selectedColor: isDark
                          ? const Color(0xFFF5C518).withOpacity(0.35)
                          : const Color(0xFFF5C518).withOpacity(0.15),
                      backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                      side: BorderSide(
                        color: isSelected
                            ? const Color(0xFFF5C518)
                            : (isDark ? Colors.white24 : Colors.grey.shade400),
                        width: isSelected ? 1.5 : 1.0,
                      ),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white70 : Colors.black54),
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade300),
          ],

          if (_selectedSeasonIndex != null && _selectedEpisodeIndex != null)
            Expanded(
              child: _buildLinksTable(seasons[_selectedSeasonIndex!].episodes[_selectedEpisodeIndex!].downloadLinks, scrollController),
            )
          else if (_selectedSeasonIndex == null && widget.detail.downloadLinks.isNotEmpty)
            Expanded(
              child: _buildLinksTable(widget.detail.downloadLinks, scrollController),
            )
          else
            Expanded(
              child: Center(
                child: Text(
                  _selectedSeasonIndex == null
                      ? 'Select a season'
                      : 'Select an episode',
                  style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinksTable(List<MovieDownloadLink> links, ScrollController controller) {
    final isDark = widget.isDark;

    return Column(
      children: [
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
          child: links.isEmpty
              ? Center(child: Text('No links', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45)))
              : ListView.builder(
                  controller: controller,
                  itemCount: links.length,
                  itemBuilder: (_, index) {
                    final link = links[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
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
                                ? TextButton(
                                    onPressed: () => widget.onLaunchUrl(link.url),
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                    child: Text('Watch', style: TextStyle(color: isDark ? const Color(0xFFF5C518) : const Color(0xFFD4A817), fontSize: 12)),
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
}
