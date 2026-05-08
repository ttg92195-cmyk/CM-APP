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
                                          child: const Icon(Icons.tv, size: 64),
                                        ),
                            )
                          : detail.fullPosterUrl.isNotEmpty
                              ? CachedNetworkImage(imageUrl: detail.fullPosterUrl, fit: BoxFit.cover)
                              : Container(
                                  color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                                  child: const Icon(Icons.tv, size: 64),
                                )
                      ),
                ),
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.1),
                        Colors.black.withOpacity(0.4),
                        Colors.black.withOpacity(0.95),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        IconButton(
                          icon: Icon(
                            _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                            color: _isBookmarked ? Colors.amber : Colors.white,
                          ),
                          onPressed: _toggleBookmark,
                        ),
                      ],
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
                          shadows: [Shadow(offset: Offset(0, 1), blurRadius: 3, color: Colors.black54)],
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
                              color: const Color(0xFFE50914).withOpacity(0.8),
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
                            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(16)),
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
                        disabledBackgroundColor: Colors.grey.shade700,
                        disabledForegroundColor: Colors.grey.shade400,
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
                        disabledBackgroundColor: Colors.grey.shade700,
                        disabledForegroundColor: Colors.grey.shade400,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Tags row
            if (detail.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: detail.tags.take(6).map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(tag, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 11)),
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
                    Text('Synopsis', style: const TextStyle(color: Color(0xFFF5C518), fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final textSpan = TextSpan(
                          text: detail.overview!,
                          style: TextStyle(fontSize: 14, height: 1.6, color: isDark ? Colors.white70 : Colors.black87),
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
                              style: TextStyle(fontSize: 14, height: 1.6, color: isDark ? Colors.white70 : Colors.black87),
                            ),
                            if (isOverflow)
                              GestureDetector(
                                onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    _synopsisExpanded ? 'read less' : '...read more',
                                    style: const TextStyle(color: Color(0xFFF5C518), fontSize: 13, fontWeight: FontWeight.w500, decoration: TextDecoration.underline),
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
                    Text('Director', style: const TextStyle(color: Color(0xFFF5C518), fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: detail.directors.map((d) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: isDark ? Colors.white12 : Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
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
                    Text('Cast', style: const TextStyle(color: Color(0xFFF5C518), fontSize: 16, fontWeight: FontWeight.bold)),
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
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isDark ? Colors.white70 : Colors.black87)),
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

            // Seasons list (inline)
            if (detail.seasons.isNotEmpty) ...[
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Seasons & Episodes', style: const TextStyle(color: Color(0xFFF5C518), fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...detail.seasons.map((season) => _buildSeasonExpansion(season, isDark, theme)),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSeasonExpansion(Season season, bool isDark, ThemeData theme) {
    return ExpansionTile(
      title: Text(season.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      tilePadding: EdgeInsets.zero,
      children: season.episodes.map((episode) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFE50914).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.play_circle_outline, color: Color(0xFFE50914), size: 20),
        ),
        title: Text(episode.name, style: const TextStyle(fontSize: 13)),
        subtitle: Text('${episode.downloadLinks.length} link(s)', style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
        trailing: episode.downloadLinks.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.download, size: 18, color: Color(0xFFF5C518)),
                onPressed: () => _showEpisodeDownloadModal(episode, season.name),
              )
            : null,
        onTap: () => _showEpisodeDownloadModal(episode, season.name),
      )).toList(),
    );
  }

  void _showEpisodeDownloadModal(Episode episode, String seasonName) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
              decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text('$seasonName - ${episode.name}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  const Icon(Icons.download_rounded, color: Color(0xFFF5C518)),
                  const SizedBox(width: 8),
                  Text('All Download Links', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: isDark ? Colors.white10 : Colors.grey.shade100,
              child: Row(
                children: [
                  _tableCell('No', 40, isHeader: true),
                  _tableCell('Server', 80, isHeader: true),
                  _tableCell('Quality', 70, isHeader: true),
                  _tableCell('Size', 70, isHeader: true),
                  _tableCell('Link', 80, isHeader: true),
                ],
              ),
            ),
            Expanded(
              child: episode.downloadLinks.isEmpty
                  ? Center(child: Text('No download links available', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: episode.downloadLinks.length,
                      itemBuilder: (_, index) {
                        final link = episode.downloadLinks[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: isDark ? Colors.white10 : Colors.grey.shade200)),
                          ),
                          child: Row(
                            children: [
                              _tableCell('${index + 1}', 40),
                              _tableCell(link.serverName, 80),
                              _tableCell(link.quality ?? '-', 70),
                              _tableCell(link.size ?? '-', 70),
                              SizedBox(
                                width: 80,
                                child: link.url.isNotEmpty
                                    ? TextButton(
                                        onPressed: () => _launchUrl(link.url),
                                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                        child: const Text('Open', style: TextStyle(color: Color(0xFFF5C518), fontSize: 12)),
                                      )
                                    : const Text('-', style: TextStyle(fontSize: 12)),
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

  Widget _tableCell(String text, double width, {bool isHeader = false}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? null : (Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87),
        ),
        overflow: TextOverflow.ellipsis,
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
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.download_rounded, color: Color(0xFFF5C518)),
                const SizedBox(width: 8),
                Text('All Download Links', style: widget.theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),

          // Season selector
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
                      selectedColor: const Color(0xFFE50914).withOpacity(0.3),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFFE50914) : Colors.grey.withOpacity(0.5),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
          ],

          // Episode list
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
                      selectedColor: const Color(0xFFF5C518).withOpacity(0.3),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFFF5C518) : Colors.grey.withOpacity(0.5),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
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
                  style: TextStyle(color: widget.theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinksTable(List<MovieDownloadLink> links, ScrollController controller) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: widget.isDark ? Colors.white10 : Colors.grey.shade100,
          child: Row(
            children: [
              _tableCell('No', 40, isHeader: true),
              _tableCell('Server', 80, isHeader: true),
              _tableCell('Quality', 70, isHeader: true),
              _tableCell('Size', 70, isHeader: true),
              _tableCell('Link', 80, isHeader: true),
            ],
          ),
        ),
        Expanded(
          child: links.isEmpty
              ? Center(child: Text('No links', style: TextStyle(color: widget.theme.colorScheme.onSurface.withOpacity(0.5))))
              : ListView.builder(
                  controller: controller,
                  itemCount: links.length,
                  itemBuilder: (_, index) {
                    final link = links[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: widget.isDark ? Colors.white10 : Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          _tableCell('${index + 1}', 40),
                          _tableCell(link.serverName, 80),
                          _tableCell(link.quality ?? '-', 70),
                          _tableCell(link.size ?? '-', 70),
                          SizedBox(
                            width: 80,
                            child: link.url.isNotEmpty
                                ? TextButton(
                                    onPressed: () => widget.onLaunchUrl(link.url),
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                    child: const Text('Open', style: TextStyle(color: Color(0xFFF5C518), fontSize: 12)),
                                  )
                                : const Text('-', style: TextStyle(fontSize: 12)),
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

  Widget _tableCell(String text, double width, {bool isHeader = false}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? null : (widget.isDark ? Colors.white70 : Colors.black87),
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
            decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled, color: Color(0xFFF5C518)),
                const SizedBox(width: 8),
                Text('Watch Online', style: widget.theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),

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
                      selectedColor: const Color(0xFFE50914).withOpacity(0.3),
                      side: BorderSide(color: isSelected ? const Color(0xFFE50914) : Colors.grey.withOpacity(0.5)),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
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
                      onSelected: (_) => setState(() => _selectedEpisodeIndex = index),
                      selectedColor: const Color(0xFFF5C518).withOpacity(0.3),
                      side: BorderSide(color: isSelected ? const Color(0xFFF5C518) : Colors.grey.withOpacity(0.5)),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
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
                  _selectedSeasonIndex == null ? 'Select a season' : 'Select an episode',
                  style: TextStyle(color: widget.theme.colorScheme.onSurface.withOpacity(0.5)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLinksTable(List<MovieDownloadLink> links, ScrollController controller) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: widget.isDark ? Colors.white10 : Colors.grey.shade100,
          child: Row(
            children: [
              _tableCell('No', 40, isHeader: true),
              _tableCell('Server', 80, isHeader: true),
              _tableCell('Quality', 70, isHeader: true),
              _tableCell('Size', 70, isHeader: true),
              _tableCell('Link', 80, isHeader: true),
            ],
          ),
        ),
        Expanded(
          child: links.isEmpty
              ? Center(child: Text('No links', style: TextStyle(color: widget.theme.colorScheme.onSurface.withOpacity(0.5))))
              : ListView.builder(
                  controller: controller,
                  itemCount: links.length,
                  itemBuilder: (_, index) {
                    final link = links[index];
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: widget.isDark ? Colors.white10 : Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          _tableCell('${index + 1}', 40),
                          _tableCell(link.serverName, 80),
                          _tableCell(link.quality ?? '-', 70),
                          _tableCell(link.size ?? '-', 70),
                          SizedBox(
                            width: 80,
                            child: link.url.isNotEmpty
                                ? TextButton(
                                    onPressed: () => widget.onLaunchUrl(link.url),
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                    child: const Text('Watch', style: TextStyle(color: Color(0xFFF5C518), fontSize: 12)),
                                  )
                                : const Text('-', style: TextStyle(fontSize: 12)),
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

  Widget _tableCell(String text, double width, {bool isHeader = false}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? null : (widget.isDark ? Colors.white70 : Colors.black87),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
