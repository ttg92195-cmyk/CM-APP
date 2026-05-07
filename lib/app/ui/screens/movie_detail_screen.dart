import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/constants.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/api_service.dart';
import 'package:cm_movies/app/core/services/bookmark_service.dart';
import 'package:cm_movies/app/core/services/recent_service.dart';

class MovieDetailScreen extends StatefulWidget {
  final String slug;

  const MovieDetailScreen({super.key, required this.slug});

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  final BookmarkService _bookmarkService = BookmarkService();
  final RecentService _recentService = RecentService();

  MovieDetail? _movieDetail;
  bool _isLoading = true;
  String? _error;
  bool _isBookmarked = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      final detail = await _apiService.getMovieDetail(widget.slug);
      if (detail != null && mounted) {
        // Add to recent
        final movie = Movie(
          id: detail.id,
          title: detail.title,
          slug: detail.slug,
          year: detail.year,
          poster: detail.poster,
        );
        await _recentService.addRecent(movie);

        // Check bookmark
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
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

    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) {
        return [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            actions: [
              IconButton(
                icon: Icon(
                  _isBookmarked
                      ? Icons.bookmark
                      : Icons.bookmark_outline,
                  color: _isBookmarked ? Colors.amber : null,
                ),
                onPressed: _toggleBookmark,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Poster backdrop
                  if (detail.fullPosterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: detail.fullPosterUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.movie, size: 64),
                      ),
                    )
                  else
                    Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.movie, size: 64),
                    ),
                  // Gradient overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.8),
                        ],
                      ),
                    ),
                  ),
                  // Title overlay
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 60,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                offset: Offset(0, 1),
                                blurRadius: 3,
                                color: Colors.black54,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (detail.year != null) ...[
                              Text(
                                detail.year!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (detail.categories.isNotEmpty)
                              Text(
                                detail.categories
                                    .map((c) => c.name)
                                    .join(', '),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: appConfig.translate('overview')),
                  Tab(text: appConfig.translate('cast')),
                  Tab(text: appConfig.translate('download')),
                ],
              ),
            ),
          ),
        ];
      },
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(detail, appConfig, theme),
          _buildCastTab(detail, theme),
          _buildDownloadTab(detail, appConfig, theme),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(
      MovieDetail detail, AppConfig appConfig, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Directors
          if (detail.directors.isNotEmpty) ...[
            Text(
              appConfig.translate('director'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: detail.directors
                  .map((d) => Chip(
                        label: Text(d),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Categories
          if (detail.categories.isNotEmpty) ...[
            Text(
              appConfig.translate('categories'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: detail.categories
                  .map((c) => Chip(
                        label: Text(c.name),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Tags
          if (detail.tags.isNotEmpty) ...[
            Text(
              appConfig.translate('tag'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: detail.tags
                  .map((t) => Chip(
                        label: Text(t.name),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Overview
          if (detail.overview != null && detail.overview!.isNotEmpty) ...[
            Text(
              appConfig.translate('overview'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Html(
              data: detail.overview!,
              style: {
                'body': Style(
                  fontSize: FontSize(14),
                  lineHeight: const LineHeight(1.5),
                  color: theme.colorScheme.onSurface,
                ),
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCastTab(MovieDetail detail, ThemeData theme) {
    if (detail.casts.isEmpty) {
      return Center(
        child: Text(
          'No cast information available',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: detail.casts.length,
      itemBuilder: (context, index) {
        final cast = detail.casts[index];
        return Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: cast.fullProfileUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: cast.fullProfileUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              cast.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDownloadTab(
      MovieDetail detail, AppConfig appConfig, ThemeData theme) {
    // Check if downloads are disabled
    if (!appConfig.downloadEnabled) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_disabled,
              size: 64,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                appConfig.translate('download_disabled_msg'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                appConfig.setDownloadEnabled(true);
              },
              icon: const Icon(Icons.download_rounded),
              label: Text(appConfig.translate('download_toggle')),
            ),
          ],
        ),
      );
    }
    if (detail.downloadLinks.isEmpty) {
      return Center(
        child: Text(
          'No download links available',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: detail.downloadLinks.length,
      itemBuilder: (context, index) {
        final link = detail.downloadLinks[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: link.url.isNotEmpty ? () => _launchUrl(link.url) : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.download_rounded,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link.serverName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (link.quality != null) ...[
                              _buildInfoChip(
                                  appConfig.translate('quality'),
                                  link.quality!,
                                  theme),
                              const SizedBox(width: 8),
                            ],
                            if (link.resolution != null) ...[
                              _buildInfoChip(
                                  appConfig.translate('resolution'),
                                  link.resolution!,
                                  theme),
                              const SizedBox(width: 8),
                            ],
                            if (link.size != null)
                              _buildInfoChip(
                                  appConfig.translate('size'),
                                  link.size!,
                                  theme),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(String label, String value, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
