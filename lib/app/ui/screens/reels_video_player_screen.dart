// =============================================================================
// Phase 4 Steps E/F/G — Reels Video Player Screen (TikTok/IG-style)
// =============================================================================
// Full-screen vertical-swipe video player for browsing Reels.
//
// Architecture:
//   - PageView with scrollDirection: vertical + viewportFraction: 1.0
//   - Each page is a _ReelPage (StatefulWidget) that owns its own
//     media_kit Player + VideoController.
//   - Auto-play: when a page becomes the current page, its player.play()
//     is called. When the user swipes to the next page, the previous
//     page's player is paused (but kept loaded — the user can swipe
//     back without re-buffering).
//   - Loop: listen to player.stream.completed → on completion, seek(0)
//     + play(). Seamless loop without a visible restart.
//   - Mute: shared across all pages via _ReelsVideoPlayerScreenState
//     (parent). Default muted (mobile-user-friendly). Stored in
//     SharedPreferences so the user's last choice persists across
//     sessions.
//   - Action stack (right side, vertical): Like, Bookmark, Episodes,
//     Details. Each is a circular icon button with a count/label below.
//   - Title + description (bottom-left, over a gradient).
//   - Step F — Episodes modal: bottom-sheet listing all episodes;
//     selecting one shows a loading overlay on the player, switches
//     the video URL, and auto-plays.
//   - Step G — Details modal: bottom-sheet with poster, title, trending
//     badge, upload time, stats row (likes / episodes / downloads),
//     description, and tappable download links (copy to clipboard).
//
// Player lifecycle:
//   - The parent owns a single PageController. The visible page is the
//     "active" page; the previous and next pages are kept mounted by
//     PageView (default cacheExtent) but their players are paused.
//   - Each _ReelPage creates its Player in initState and disposes in
//     dispose(). The Player is created SYNCHRONOUSLY (no async device
//     detection — Reels are short clips, not 4K movies, so we skip
//     the elaborate perf-tier tuning from video_player_screen.dart).
//   - On page change, parent calls _setCurrentIndex(index) which
//     iterates _reelPageKeys and calls setActive(true/false) on each.
//     The active page plays; others pause.
//
// Why a SEPARATE screen from video_player_screen.dart:
//   - video_player_screen.dart is 2832 lines tuned for full movies with
//     seek bar, audio/subtitle track selection, brightness drag, etc.
//   - Reels need NONE of that. A 100-line player is enough: load →
//     play → loop → mute toggle → dispose.
//   - Keeping them separate avoids the risk of breaking the movie
//     player's careful Phase 3 lifecycle hardening.
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/reel.dart';
import 'package:cm_movies/app/core/services/reels_service.dart';

/// Entry point: pushes a full-screen Reels video player.
/// Bro taps a Reel cell in ReelsPage → _onReelTap navigates here.
class ReelsVideoPlayerScreen extends StatefulWidget {
  /// The full list of Reels to swipe through (passed by ReelsPage so
  /// swiping forward/backward stays within the same batch).
  final List<Reel> reels;

  /// The initial page index (which Reel to start at).
  final int initialIndex;

  const ReelsVideoPlayerScreen({
    super.key,
    required this.reels,
    required this.initialIndex,
  });

  @override
  State<ReelsVideoPlayerScreen> createState() => _ReelsVideoPlayerScreenState();
}

class _ReelsVideoPlayerScreenState extends State<ReelsVideoPlayerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  // Shared mute state across all pages. Persisted to SharedPreferences.
  bool _isMuted = true;
  static const String _muteKey = 'reels_muted';

  // Per-page state holders (so the parent can talk to children
  // without rebuilding them all on every page change).
  final Map<int, GlobalKey<_ReelPageState>> _pageKeys = {};

  // Per-Reel like state — toggled locally + syncs to Firestore.
  final Set<String> _likedReelIds = {};
  final Map<String, int> _likeCountOverrides = {};

  // Per-Reel bookmark state — local only for Step E; Step H will persist.
  final Set<String> _bookmarkedReelIds = {};

  // Per-Reel current episode index — supports multi-episode Reels where
  // the user can switch between Episode 1, 2, 3... via the Episodes modal.
  // Keyed by Reel.id. Default value (when absent from map) is 0 (the main
  // videoUrl, or the first explicit episode when episodes list is set).
  final Map<String, int> _currentEpisodeIndex = {};

  // Per-page "is episode currently switching" flag — shows CircularProgressIndicator
  // overlay on the active video player while we're opening a new Media.
  // Set true on episode select → cleared when open() completes.
  bool _isEpisodeSwitching = false;

  SharedPreferences? _prefsCache;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.reels.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _loadMutePreference();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadMutePreference() async {
    try {
      _prefsCache ??= await SharedPreferences.getInstance();
      final stored = _prefsCache!.getBool(_muteKey);
      if (stored != null && mounted) {
        setState(() => _isMuted = stored);
      }
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final next = !_isMuted;
    setState(() => _isMuted = next);
    try {
      _prefsCache ??= await SharedPreferences.getInstance();
      await _prefsCache!.setBool(_muteKey, next);
    } catch (_) {}
    // Apply mute to all currently-mounted pages.
    for (final key in _pageKeys.values) {
      key.currentState?._applyMute(next);
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    // Pause previous pages, play new page.
    for (final entry in _pageKeys.entries) {
      final isActive = entry.key == index;
      entry.value.currentState?._setActive(isActive);
    }
  }

  void _toggleLike(String reelId) {
    final isLiked = _likedReelIds.contains(reelId);
    setState(() {
      if (isLiked) {
        _likedReelIds.remove(reelId);
        _likeCountOverrides[reelId] = (_likeCountOverrides[reelId] ??
                widget.reels.firstWhere((r) => r.id == reelId).likeCount) -
            1;
      } else {
        _likedReelIds.add(reelId);
        _likeCountOverrides[reelId] = (_likeCountOverrides[reelId] ??
                widget.reels.firstWhere((r) => r.id == reelId).likeCount) +
            1;
      }
    });
    // Best-effort sync to Firestore. Skip on unlike for now to keep
    // Phase 4 simple — Bro can audit which Reels got liked via the
    // likeCount field on each doc.
    if (!isLiked) {
      ReelsService.instance.incrementLikeCount(reelId).catchError((_) {});
    }
  }

  void _toggleBookmark(String reelId) {
    setState(() {
      if (_bookmarkedReelIds.contains(reelId)) {
        _bookmarkedReelIds.remove(reelId);
      } else {
        _bookmarkedReelIds.add(reelId);
      }
    });
    // Step H will persist bookmarks to Firestore `users/{uid}/reel_bookmarks/`.
    // For now, just show a SnackBar.
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _bookmarkedReelIds.contains(reelId)
              ? '${appConfig.translate('bookmark')} ✓'
              : '${appConfig.translate('bookmark')} ✗',
        ),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showEpisodesModal(Reel reel) {
    // Phase 4 Step F — bottom-sheet listing all episodes.
    // Selecting an episode: shows CircularProgressIndicator overlay on
    // the video player + switches the video + auto-plays.
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!reel.hasEpisodes) {
      // Single-video Reel — no episodes to switch between.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appConfig.translate('reels_empty')),
          duration: const Duration(milliseconds: 800),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final currentIndex = _currentEpisodeIndex[reel.id] ?? 0;
    final bgColor =
        isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final accentColor = const Color(0xFFE50914);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white54 : Colors.black54;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    children: [
                      Icon(Icons.video_library,
                          color: accentColor, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appConfig.translate('reel_episodes'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${reel.episodeCount} ${appConfig.translate('episodes').toLowerCase()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
                // Episode list
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: reel.episodes.length,
                    itemBuilder: (listCtx, i) {
                      final ep = reel.episodes[i];
                      final isSelected = i == currentIndex;
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accentColor.withOpacity(0.15)
                                : (isDark
                                    ? Colors.white10
                                    : Colors.black12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: isSelected
                                    ? accentColor
                                    : textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          ep.title,
                          style: TextStyle(
                            color: isSelected ? accentColor : textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.play_circle_fill,
                                color: accentColor, size: 24)
                            : Icon(Icons.play_circle_outline,
                                color: textSecondary, size: 22),
                        onTap: () {
                          Navigator.pop(sheetCtx, i);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((selectedIndex) {
      if (selectedIndex is int && selectedIndex >= 0) {
        _switchEpisode(reel.id, selectedIndex);
      }
    });
  }

  /// Switch the active Reel's video to episode [newIndex]. Shows
  /// CircularProgressIndicator overlay on the active page while loading,
  /// then calls _ReelPage's _openEpisode method via the page key.
  Future<void> _switchEpisode(String reelId, int newIndex) async {
    final currentReel = widget.reels[_currentIndex];
    if (currentReel.id != reelId) return; // safety: user already swiped
    if (newIndex < 0 || newIndex >= currentReel.episodes.length) return;

    final currentIdx = _currentEpisodeIndex[reelId] ?? 0;
    if (newIndex == currentIdx) return; // no-op

    setState(() {
      _currentEpisodeIndex[reelId] = newIndex;
      _isEpisodeSwitching = true;
    });

    // Tell the active page to open the new episode's video URL.
    final pageKey = _pageKeys[_currentIndex];
    if (pageKey != null) {
      final state = pageKey.currentState;
      if (state != null) {
        await state._openEpisode(newIndex);
      }
    }

    if (mounted) {
      setState(() => _isEpisodeSwitching = false);
    }
  }

  void _showDetailsModal(Reel reel) {
    // Phase 4 Step G — bottom-sheet showing full Reel details:
    //   - Poster thumbnail (9:16) + title + trending badge + upload time
    //   - Stats row: like count, episode count, download-link count
    //   - Description (scrollable, only if non-empty)
    //   - Download links: tappable rows that copy the URL to clipboard
    // The video keeps playing behind the sheet (same as Episodes modal).
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final accentColor = const Color(0xFFE50914);
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.white54 : Colors.black54;
    final dividerColor = isDark ? Colors.white10 : Colors.black12;

    final posterUrl = reel.posterUrl ?? '';
    final hasPoster = posterUrl.isNotEmpty;
    final description = (reel.description ?? '').trim();
    final timeAgo = reel.timeAgo;
    final likeCount = _effectiveLikeCount(reel);
    final episodeCount = reel.episodeCount;
    final downloadCount = reel.downloadLinks.length;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: accentColor, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          appConfig.translate('reel_details'),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      // Close button — easier dismissal than swiping.
                      IconButton(
                        onPressed: () => Navigator.pop(sheetCtx),
                        icon: Icon(Icons.close, color: textSecondary, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                // Scrollable content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ===== Poster + title + badges =====
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Poster thumbnail (9:16 ratio, 72x128).
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 72,
                                height: 128,
                                child: hasPoster
                                    ? CachedNetworkImage(
                                        imageUrl: posterUrl,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.black12,
                                          child: const Center(
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          ),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: isDark
                                              ? Colors.white10
                                              : Colors.black12,
                                          child: Icon(Icons.video_library,
                                              color: textSecondary, size: 28),
                                        ),
                                      )
                                    : Container(
                                        color: isDark
                                            ? Colors.white10
                                            : Colors.black12,
                                        child: Icon(Icons.video_library,
                                            color: textSecondary, size: 28),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Title + trending badge + upload time.
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    reel.title,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (reel.isTrending) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.local_fire_department,
                                              color: Colors.orange, size: 13),
                                          const SizedBox(width: 4),
                                          Text(
                                            appConfig.translate('trending'),
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (timeAgo.isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(Icons.schedule,
                                            color: textSecondary, size: 13),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            timeAgo,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: textSecondary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // ===== Stats row =====
                        Row(
                          children: [
                            Expanded(
                              child: _buildDetailStat(
                                icon: Icons.favorite,
                                iconColor: Colors.redAccent,
                                value: '$likeCount',
                                label: appConfig.translate('like_count'),
                                bg: isDark ? Colors.white10 : Colors.black12,
                                valueColor: textPrimary,
                                labelColor: textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildDetailStat(
                                icon: Icons.video_library,
                                iconColor: accentColor,
                                value: '$episodeCount',
                                label: appConfig.translate('episodes'),
                                bg: isDark ? Colors.white10 : Colors.black12,
                                valueColor: textPrimary,
                                labelColor: textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildDetailStat(
                                icon: Icons.download,
                                iconColor: Colors.blueAccent,
                                value: '$downloadCount',
                                label: appConfig.translate('download'),
                                bg: isDark ? Colors.white10 : Colors.black12,
                                valueColor: textPrimary,
                                labelColor: textSecondary,
                              ),
                            ),
                          ],
                        ),
                        // ===== Description =====
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 18),
                          Text(
                            appConfig.translate('reel_description'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 14,
                              color: textPrimary,
                              height: 1.5,
                            ),
                          ),
                        ],
                        // ===== Download links =====
                        if (downloadCount > 0) ...[
                          const SizedBox(height: 18),
                          Text(
                            '${appConfig.translate('download')} (${downloadCount})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...reel.downloadLinks.asMap().entries.map((entry) {
                            final i = entry.key;
                            final link = entry.value;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  // Copy the download URL to clipboard so
                                  // the user can paste it into a browser
                                  // or download manager. Close the sheet
                                  // first so the confirmation SnackBar is
                                  // visible (a SnackBar shown while the
                                  // sheet is open renders behind it).
                                  Clipboard.setData(
                                      ClipboardData(text: link));
                                  Navigator.pop(sheetCtx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        appConfig.translate('link_copied'),
                                      ),
                                      duration:
                                          const Duration(milliseconds: 1200),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white10
                                        : Colors.black12,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.link,
                                          color: accentColor, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${appConfig.translate('copy_link')} ${i + 1}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: textPrimary,
                                            fontWeight: FontWeight.w500,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(Icons.copy,
                                          color: textSecondary, size: 16),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Small stat card used in the Details modal stats row.
  Widget _buildDetailStat({
    required IconData icon,
    required Color iconColor,
    required String value,
    required String label,
    required Color bg,
    required Color valueColor,
    required Color labelColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: labelColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  int _effectiveLikeCount(Reel reel) {
    return _likeCountOverrides[reel.id] ?? reel.likeCount;
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.black;

    return Scaffold(
      backgroundColor: bgColor,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        controller: _pageController,
        onPageChanged: _onPageChanged,
        itemCount: widget.reels.length,
        itemBuilder: (context, index) {
          final key = _pageKeys.putIfAbsent(
              index, () => GlobalKey<_ReelPageState>());
          return _ReelPage(
            key: key,
            reel: widget.reels[index],
            isActive: index == _currentIndex,
            isMuted: _isMuted,
            likeCount: _effectiveLikeCount(widget.reels[index]),
            isLiked: _likedReelIds.contains(widget.reels[index].id),
            isBookmarked: _bookmarkedReelIds.contains(widget.reels[index].id),
            currentEpisodeIndex:
                _currentEpisodeIndex[widget.reels[index].id] ?? 0,
            isEpisodeSwitching:
                _isEpisodeSwitching && index == _currentIndex,
            onToggleMute: _toggleMute,
            onToggleLike: () => _toggleLike(widget.reels[index].id),
            onToggleBookmark: () => _toggleBookmark(widget.reels[index].id),
            onShowEpisodes: () => _showEpisodesModal(widget.reels[index]),
            onShowDetails: () => _showDetailsModal(widget.reels[index]),
          );
        },
      ),
    );
  }
}

// =============================================================================
// _ReelPage — single page in the PageView.
// Owns its own media_kit Player + VideoController.
// =============================================================================

class _ReelPage extends StatefulWidget {
  final Reel reel;
  final bool isActive;
  final bool isMuted;
  final int likeCount;
  final bool isLiked;
  final bool isBookmarked;
  final int currentEpisodeIndex;
  final bool isEpisodeSwitching;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleBookmark;
  final VoidCallback onShowEpisodes;
  final VoidCallback onShowDetails;

  const _ReelPage({
    super.key,
    required this.reel,
    required this.isActive,
    required this.isMuted,
    required this.likeCount,
    required this.isLiked,
    required this.isBookmarked,
    required this.currentEpisodeIndex,
    required this.isEpisodeSwitching,
    required this.onToggleMute,
    required this.onToggleLike,
    required this.onToggleBookmark,
    required this.onShowEpisodes,
    required this.onShowDetails,
  });

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  late final Player _player;
  late final VideoController _controller;
  bool _isInitialized = false;
  bool _isBuffering = true;
  bool _hasError = false;
  bool _isLocalActive = false; // tracks whether THIS page is currently active

  // Stream subscriptions for cleanup.
  final List<StreamSubscription> _streamSubs = [];

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 16 * 1024 * 1024, // 16MB — Reels are short, no need for huge buffer
          title: 'KMM Reels',
          logLevel: MPVLogLevel.error,
        ),
      );
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          // Default GPU output — Reels are short clips, no need for
          // the elaborate vo/hwdec probing from video_player_screen.dart.
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );
      _isInitialized = true;

      // Listen for buffering state changes.
      _streamSubs.add(
        _player.stream.buffering.listen((isBuffering) {
          if (mounted) setState(() => _isBuffering = isBuffering);
        }),
      );
      // Listen for errors.
      _streamSubs.add(
        _player.stream.error.listen((error) {
          if (mounted && error.isNotEmpty) {
            debugPrint('Reels player error: $error');
            setState(() => _hasError = true);
          }
        }),
      );
      // Loop on completion: seek(0) + play().
      _streamSubs.add(
        _player.stream.completed.listen((completed) {
          if (completed && mounted && !_hasError) {
            _player.seek(Duration.zero);
            _player.play();
          }
        }),
      );

      // Open + play.
      await _player.open(Media(widget.reel.videoUrl));
      if (!mounted) return;
      // Apply initial mute state.
      _player.setVolume(widget.isMuted ? 0.0 : 100.0);
      // Auto-play if this page is the initial active page.
      if (widget.isActive) {
        _isLocalActive = true;
        await _player.play();
      }
      if (mounted) setState(() => _isBuffering = false);
    } catch (e) {
      debugPrint('Reels player init failed: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    for (final sub in _streamSubs) {
      try {
        sub.cancel();
      } catch (_) {}
    }
    _streamSubs.clear();
    if (_isInitialized) {
      try {
        _player.stop().timeout(const Duration(seconds: 1)).catchError((_) {});
      } catch (_) {}
      try {
        _player.dispose().timeout(const Duration(seconds: 2)).catchError((_) {});
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(_ReelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Active state changed → play or pause.
    if (widget.isActive != oldWidget.isActive) {
      _setActive(widget.isActive);
    }
    // Mute state changed → apply to player.
    if (widget.isMuted != oldWidget.isMuted) {
      _applyMute(widget.isMuted);
    }
  }

  void _setActive(bool active) {
    if (_isLocalActive == active) return;
    _isLocalActive = active;
    if (!_isInitialized) return;
    try {
      if (active) {
        _player.play();
      } else {
        _player.pause();
      }
    } catch (_) {}
  }

  void _applyMute(bool muted) {
    if (!_isInitialized) return;
    try {
      _player.setVolume(muted ? 0.0 : 100.0);
    } catch (_) {}
  }

  /// Phase 4 Step F — Switch the active video to episode [episodeIndex].
  /// Called by the parent when the user selects an episode from the modal.
  /// Sets _isBuffering=true (which the parent uses to show a loading
  /// overlay), stops the current video, opens the new Media, and
  /// auto-plays.
  Future<void> _openEpisode(int episodeIndex) async {
    if (!_isInitialized) return;
    final url = widget.reel.videoUrlForEpisode(episodeIndex);
    if (url == null || url.isEmpty) return;

    // Mark local buffering state so the page shows the loading overlay
    // until open() completes and the buffering stream fires.
    if (mounted) setState(() => _isBuffering = true);

    try {
      // Stop + pause current playback first to release native decoder
      // resources before opening the new Media.
      try {
        await _player.stop().timeout(const Duration(seconds: 1));
      } catch (_) {}
      // Open the new episode video URL.
      await _player.open(Media(url));
      if (!mounted) return;
      // Auto-play if this page is currently active.
      if (widget.isActive) {
        await _player.play();
      }
    } catch (e) {
      debugPrint('Reels episode switch failed: $e');
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isBuffering = false);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final appConfig = Provider.of<AppConfig>(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // ====================== VIDEO SURFACE ======================
        if (_isInitialized && !_hasError)
          Video(
            controller: _controller,
            controls: NoVideoControls,
            fit: BoxFit.cover,
          )
        else if (_hasError)
          _buildErrorState(appConfig)
        else
          _buildLoadingState(),

        // ====================== POSTER BACKDROP (placeholder while buffering) ======================
        if (_isBuffering && reel.posterUrl != null && reel.posterUrl!.isNotEmpty)
          Positioned.fill(
            child: Image.network(
              reel.posterUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

        // ====================== EPISODE SWITCHING OVERLAY ======================
        // Phase 4 Step F — Shows a CircularProgressIndicator + dim background
        // while the user's selected episode is loading. Bro asked for this
        // exact UX: "Episode 2 ကိုရွေးချက်လိုက်ရင် Video Player က
        // အဝိုင်းလည်လာပြီး Episode 2 ကိုပြောင်းသွားမယ်။"
        if (widget.isEpisodeSwitching)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),

        // ====================== GRADIENT OVERLAY ======================
        // Dark gradient at top + bottom for text legibility + UI readability.
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.5),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                  stops: const [0.0, 0.2, 0.6, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ====================== TOP BAR (back + mute) ======================
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Back',
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      widget.isMuted
                          ? Icons.volume_off_outlined
                          : Icons.volume_up_outlined,
                      color: Colors.white,
                    ),
                    onPressed: widget.onToggleMute,
                    tooltip: widget.isMuted ? 'Unmute' : 'Mute',
                  ),
                ],
              ),
            ),
          ),
        ),

        // ====================== RIGHT-SIDE ACTION STACK ======================
        Positioned(
          right: 12,
          bottom: 120,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(
                icon: widget.isLiked
                    ? Icons.favorite
                    : Icons.favorite_border,
                label: _formatCount(widget.likeCount),
                color: widget.isLiked ? Colors.redAccent : Colors.white,
                onTap: widget.onToggleLike,
              ),
              const SizedBox(height: 18),
              _buildActionButton(
                icon: widget.isBookmarked
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                label: appConfig.translate('bookmark'),
                color: widget.isBookmarked
                    ? const Color(0xFFE50914)
                    : Colors.white,
                onTap: widget.onToggleBookmark,
              ),
              if (reel.hasEpisodes) ...[
                const SizedBox(height: 18),
                _buildActionButton(
                  icon: Icons.video_library_outlined,
                  label: appConfig.translate('episodes'),
                  color: Colors.white,
                  onTap: widget.onShowEpisodes,
                ),
              ],
              const SizedBox(height: 18),
              _buildActionButton(
                icon: Icons.info_outline,
                label: appConfig.translate('details'),
                color: Colors.white,
                onTap: widget.onShowDetails,
              ),
            ],
          ),
        ),

        // ====================== BOTTOM-LEFT: TITLE + DESCRIPTION ======================
        Positioned(
          left: 16,
          right: 80, // leave room for the action stack
          bottom: 32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                reel.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                ),
              ),
              if (reel.description != null && reel.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  reel.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 4)],
                  ),
                ),
              ],
              if (reel.isTrending) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.trending_up, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'TRENDING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // BUILD HELPERS
  // ============================================================
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black87, blurRadius: 2)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        color: Colors.white,
        strokeWidth: 2,
      ),
    );
  }

  Widget _buildErrorState(AppConfig appConfig) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Unable to play this Reel',
              style: TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              label: const Text('Close'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Format like count as "1.2K" / "3.4M" — matches _ReelGridCell pattern.
  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}
