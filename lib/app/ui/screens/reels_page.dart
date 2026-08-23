// =============================================================================
// Phase 4 Step D — Reels Tab Grid UI
// =============================================================================
// Replaces the Step C placeholder body with a 3-column vertical-video
// thumbnail grid (9:16 ratio per cell, like TikTok/IG Reels thumbnails).
//
// Each grid cell shows:
//   - Poster image (CachedNetworkImage, 9:16 ratio, with retry)
//   - Gradient overlay at the bottom for text legibility
//   - Title overlay (max 2 lines, ellipsis)
//   - Like count badge (top-right, heart icon + count)
//   - Trending badge (top-left, "🔥 Trending" pill) when isTrending=true
//   - Episode count badge (bottom-left, "N episodes" pill) when episodes > 1
//
// Page-level behavior:
//   - Pull-to-refresh (RefreshIndicator + AlwaysScrollableScrollPhysics).
//   - Infinite scroll (NotificationListener triggers _loadMore near the
//     bottom of the list).
//   - 3-tier fallback inherited from ReelsService.getReels() — if the
//     primary orderBy('updatedAt') query fails for missing index, falls
//     back to orderBy('createdAt') → no orderBy. The grid never appears
//     empty just because an index isn't deployed.
//   - Tap on a Reel cell → SnackBar saying "Coming in Step E" for now.
//     Step E will replace this with the vertical-swipe full-screen
//     video player.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/reel.dart';
import 'package:cm_movies/app/core/services/reels_service.dart';
import 'package:cm_movies/app/ui/screens/reels_video_player_screen.dart';

class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  final ReelsService _service = ReelsService.instance;
  final ScrollController _scrollController = ScrollController();
  final int _pageSize = 30;

  List<Reel> _reels = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  Object? _lastDoc;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadReels();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // DATA LOADING
  // ============================================================
  Future<void> _loadReels({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final result = await _service.getReels(limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _reels = (result['reels'] as List<Reel>).toList();
        _lastDoc = result['startAfter'];
        _hasMore = _reels.length >= _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load reels: $e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _service.getReels(
        limit: _pageSize,
        startAfter: _lastDoc as dynamic,
      );
      if (!mounted) return;
      final newReels = (result['reels'] as List<Reel>).toList();
      setState(() {
        _reels.addAll(newReels);
        _lastDoc = result['startAfter'];
        _hasMore = newReels.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      debugPrint('ReelsPage._loadMore failed: $e');
    }
  }

  Future<void> _onRefresh() async {
    await _loadReels(showLoading: false);
  }

  void _onReelTap(Reel reel) {
    // Phase 4 Step E — push the full-screen vertical-swipe video player.
    // Pass the FULL _reels list so the user can swipe forward/backward
    // through the batch without leaving the player.
    final index = _reels.indexOf(reel);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReelsVideoPlayerScreen(
          reels: _reels,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);

    return Scaffold(
      backgroundColor: bgColor,
      // No AppBar — Step D shows a full-bleed grid like TikTok/IG.
      // The drawer (drawer button on Home) is still accessible via
      // the AppBar on Home tab, so Reels tab doesn't need one.
      body: _isLoading
          ? _buildSkeletonGrid(isDark)
          : _errorMessage != null
              ? _buildErrorState(theme)
              : _reels.isEmpty
                  ? _buildEmptyState(appConfig, theme)
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      color: const Color(0xFFE50914),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollEndNotification &&
                              _scrollController.position.pixels >=
                                  _scrollController
                                          .position.maxScrollExtent -
                                      200 &&
                              _hasMore &&
                              !_isLoadingMore) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: CustomScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            // Header with title
                            SliverToBoxAdapter(
                              child: _buildHeader(appConfig, theme),
                            ),
                            // Reels grid (3 columns, 9:16 ratio per cell)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  // 9:16 ratio = 0.5625. Slightly tighter
                                  // than movie posters (0.53) to match the
                                  // vertical-video aspect.
                                  childAspectRatio: 0.5625,
                                  crossAxisSpacing: 6,
                                  mainAxisSpacing: 6,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => _ReelGridCell(
                                    reel: _reels[index],
                                    onTap: () => _onReelTap(_reels[index]),
                                  ),
                                  childCount: _reels.length,
                                ),
                              ),
                            ),
                            // Loading more indicator
                            if (_isLoadingMore)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                ),
                              ),
                            // End-of-list indicator
                            if (!_hasMore && _reels.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Center(
                                    child: Text(
                                      '— ${appConfig.translate('reels')} —',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _buildHeader(AppConfig appConfig, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Icon(
            Icons.video_collection,
            color: const Color(0xFFE50914),
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            appConfig.translate('reels'),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: theme.brightness == Brightness.dark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================
  Widget _buildEmptyState(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_collection_outlined,
              size: 80,
              color: const Color(0xFFE50914).withOpacity(0.6),
            ),
            const SizedBox(height: 16),
            Text(
              appConfig.translate('reels_empty'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ERROR STATE
  // ============================================================
  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadReels(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SKELETON LOADING (initial load)
  // ============================================================
  Widget _buildSkeletonGrid(bool isDark) {
    final shimmerColor = isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05);
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          sliver: SliverGrid(
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.5625,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => Container(
                decoration: BoxDecoration(
                  color: shimmerColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              childCount: 12,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// _ReelGridCell — single cell in the 3-column Reels grid.
// =============================================================================
// Stateful so the retry button can re-trigger CachedNetworkImage.
// 9:16 ratio with a poster image + bottom gradient overlay + title +
// badges (trending top-left, like count top-right, episode count bottom-left).
// =============================================================================

class _ReelGridCell extends StatefulWidget {
  final Reel reel;
  final VoidCallback onTap;

  const _ReelGridCell({required this.reel, required this.onTap});

  @override
  State<_ReelGridCell> createState() => _ReelGridCellState();
}

class _ReelGridCellState extends State<_ReelGridCell> {
  int _posterRetryCount = 0;
  static const int _maxAutoRetries = 1;

  String get _posterUrl {
    if (_posterRetryCount == 0) return widget.reel.posterUrl ?? '';
    final base = widget.reel.posterUrl ?? '';
    if (base.isEmpty) return base;
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}retry=$_posterRetryCount';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reel = widget.reel;
    final hasPoster = reel.posterUrl != null && reel.posterUrl!.isNotEmpty;

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          // Container with subtle shadow lift, matching MovieCard pattern.
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ====================== POSTER ======================
              if (hasPoster)
                CachedNetworkImage(
                  imageUrl: _posterUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: isDark ? Colors.white10 : Colors.black12,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                  errorWidget: (_, __, ___) => InkWell(
                    onTap: () {
                      if (_posterRetryCount < _maxAutoRetries + 5) {
                        setState(() => _posterRetryCount++);
                      }
                    },
                    child: Container(
                      color: Colors.red.withOpacity(0.1),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              color: Colors.red, size: 28),
                          SizedBox(height: 4),
                          Icon(Icons.refresh,
                              color: Colors.white54, size: 14),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Container(
                  color: isDark ? Colors.white10 : Colors.black12,
                  child: const Icon(Icons.video_library, size: 36),
                ),

              // ====================== BOTTOM GRADIENT OVERLAY ======================
              // Adds a dark gradient from transparent at top to black at
              // bottom so the title text stays legible over any poster.
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.0),
                          Colors.black.withOpacity(0.0),
                          Colors.black.withOpacity(0.4),
                          Colors.black.withOpacity(0.85),
                        ],
                        stops: const [0.0, 0.5, 0.75, 1.0],
                      ),
                    ),
                  ),
                ),
              ),

              // ====================== TRENDING BADGE (top-left) ======================
              if (reel.isTrending)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.trending_up,
                            color: Colors.white, size: 10),
                        SizedBox(width: 3),
                        Text(
                          'TRENDING',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ====================== LIKE COUNT BADGE (top-right) ======================
              if (reel.likeCount > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.favorite,
                            color: Colors.redAccent, size: 10),
                        const SizedBox(width: 3),
                        Text(
                          _formatCount(reel.likeCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ====================== EPISODE COUNT BADGE (bottom-left, above title) ======================
              if (reel.hasEpisodes)
                Positioned(
                  bottom: 38,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.video_library,
                            color: Colors.white70, size: 10),
                        const SizedBox(width: 3),
                        Text(
                          '${reel.episodeCount} eps',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ====================== TITLE (bottom) ======================
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Text(
                  reel.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    shadows: [
                      Shadow(
                        color: Colors.black54,
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Format large like counts as "1.2K", "3.4M" etc.
  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
