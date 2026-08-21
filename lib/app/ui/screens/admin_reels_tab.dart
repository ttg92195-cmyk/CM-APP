// =============================================================================
// Phase 4 Step B — Admin Reels Tab
// =============================================================================
// The Reels tab embedded inside the Admin Panel (admin_panel_page.dart).
// Shows a vertical list of all Reels in the Firestore `reels` collection
// with poster thumbnail + title + episode/download counts + edit/delete
// buttons. Pull-to-refresh reloads from Firestore. Empty state shows a
// friendly hint pointing to the FAB.
//
// The tab is a separate StatefulWidget (NOT inside admin_panel_page.dart)
// so it manages its own loading + pagination state without bloating the
// admin_panel_page.dart which is already 1700+ lines.
//
// The parent admin_panel_page.dart:
//   - Imports this file.
//   - Adds `const Tab(text: 'Reels')` to its TabBar.
//   - Adds `_buildReelsTab(isDark)` to its TabBarView children list,
//     which just returns `const AdminReelsTab()`.
//   - Routes its FAB to ReelFormPage when on the Reels tab.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/app/core/models/reel.dart';
import 'package:cm_movies/app/core/services/reels_service.dart';
import 'package:cm_movies/app/ui/screens/reel_form_page.dart';

class AdminReelsTab extends StatefulWidget {
  const AdminReelsTab({super.key});

  @override
  State<AdminReelsTab> createState() => _AdminReelsTabState();
}

class _AdminReelsTabState extends State<AdminReelsTab>
    with WidgetsBindingObserver {
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
    // Listen for app resume — admin might have come back from a ReelFormPage
    // that was opened from outside this tab's parent. The parent admin_panel_page
    // also calls setState on form return, which forces a rebuild but NOT a
    // re-fetch. We need to re-fetch on resume.
    WidgetsBinding.instance.addObserver(this);
    _loadReels();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-fetch on app resume so any changes the admin made via Firebase
    // Console in a separate browser tab show up immediately.
    if (state == AppLifecycleState.resumed) {
      _loadReels(showLoading: false);
    }
  }

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
      // Silent fail — the user can retry by scrolling.
      debugPrint('loadMore failed: $e');
    }
  }

  Future<void> _onRefresh() async {
    await _loadReels(showLoading: false);
  }

  // ============================================================
  // EDIT / DELETE
  // ============================================================
  Future<void> _openEditForm(Reel reel) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ReelFormPage(reel: reel)),
    );
    if (result == true) {
      _loadReels(showLoading: false);
    }
  }

  Future<void> _confirmDelete(Reel reel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reel'),
        content: Text('Are you sure you want to delete "${reel.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteReel(reel.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reel deleted')),
      );
      _loadReels(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
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
    if (_reels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_collection_outlined,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No reels yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tap the + button below to add your first Reel.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              _scrollController.position.pixels >=
                  _scrollController.position.maxScrollExtent - 200 &&
              _hasMore &&
              !_isLoadingMore) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: _reels.length + 1, // +1 for trailing loader
          itemBuilder: (context, index) {
            if (index == _reels.length) {
              if (_isLoadingMore) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (!_hasMore) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      '— end of list —',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            }
            final reel = _reels[index];
            return _buildReelCard(reel, isDark);
          },
        ),
      ),
    );
  }

  Widget _buildReelCard(Reel reel, bool isDark) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openEditForm(reel),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster thumbnail (9:16 aspect for vertical video feel)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 60,
                  height: 107, // ~9:16
                  child: reel.posterUrl != null && reel.posterUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: reel.posterUrl!,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: isDark ? Colors.white10 : Colors.black05,
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.red.withOpacity(0.1),
                            child: const Icon(Icons.broken_image, size: 24),
                          ),
                        )
                      : Container(
                          color: isDark ? Colors.white10 : Colors.black05,
                          child: const Icon(Icons.video_library, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Title + metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      reel.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildMetaChip(
                          icon: Icons.video_library,
                          label: '${reel.episodeCount} ep',
                        ),
                        if (reel.downloadLinks.isNotEmpty)
                          _buildMetaChip(
                            icon: Icons.download,
                            label: '${reel.downloadLinks.length} dl',
                          ),
                        _buildMetaChip(
                          icon: Icons.favorite,
                          label: '${reel.likeCount}',
                        ),
                        if (reel.isTrending)
                          _buildMetaChip(
                            icon: Icons.trending_up,
                            label: 'Trending',
                            color: const Color(0xFFE50914),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (reel.createdAt != null)
                      Text(
                        reel.timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                  ],
                ),
              ),
              // Action buttons
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                    tooltip: 'Edit',
                    onPressed: () => _openEditForm(reel),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 20,
                        color: Colors.red.shade400),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(reel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final fg = color ?? Colors.grey.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fg.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: fg)),
        ],
      ),
    );
  }
}
