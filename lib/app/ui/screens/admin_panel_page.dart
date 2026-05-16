import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/ui/screens/add_movie_page.dart';
import 'package:cm_movies/app/ui/screens/add_series_page.dart';
import 'package:cm_movies/app/ui/screens/edit_movie_page.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage>
    with SingleTickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  late TabController _tabController;

  // Pagination state
  static const int _pageSize = 30;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingPage = false;
  List<DocumentSnapshot> _pageLastDocs = []; // lastDoc for each loaded page
  Map<int, List<Movie>> _pageCache = {}; // cached posts per page

  List<Movie> _allPosts = []; // accumulated posts for search/filter
  List<Movie> _filteredPosts = [];
  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<TagAndGenres> _collections = [];

  bool _isLoading = true;
  String _searchQuery = '';
  int _genresTagsSubTabIndex = 0;

  // Bulk delete
  Set<String> _selectedPostIds = {};
  bool get _isSelecting => _selectedPostIds.isNotEmpty;

  // Advanced filtering
  String? _filterGenre;
  String? _filterYear;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Load initial data: first page of posts + genres/tags/collections
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      // Reset pagination state
      _currentPage = 1;
      _hasMore = true;
      _pageLastDocs = [];
      _pageCache = {};
      _allPosts = [];

      final results = await Future.wait([
        _contentService.getAllPosts(limit: _pageSize),
        _contentService.getGenres(),
        _contentService.getTags(),
        _contentService.getCollections(),
      ]);

      if (mounted) {
        final postsData = results[0] as Map<String, dynamic>;
        final posts = postsData['movies'] as List<Movie>;
        final hasMore = postsData['hasMore'] as bool;
        final lastDoc = postsData['lastDoc'] as DocumentSnapshot?;

        setState(() {
          _pageCache[1] = posts;
          _allPosts = List.from(posts);
          _filteredPosts = List.from(posts);
          _hasMore = hasMore;
          if (lastDoc != null) {
            _pageLastDocs = [lastDoc];
          }
          _genres = results[1] as List<TagAndGenres>;
          _tags = results[2] as List<TagAndGenres>;
          _collections = results[3] as List<TagAndGenres>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Load a specific page of posts
  Future<void> _loadPage(int page) async {
    if (page < 1) return;
    if (_isLoadingPage) return;

    // If page is cached, just switch to it
    if (_pageCache.containsKey(page)) {
      setState(() {
        _currentPage = page;
        _applyFilters();
      });
      return;
    }

    // Can only load next page if we have the previous page's last doc
    if (page > 1 && _pageLastDocs.length < page - 1) return;

    // Can't go beyond available pages
    if (page > 1 && !_hasMore && _pageCache[page - 1] != null) {
      // We've reached the end
      return;
    }

    setState(() => _isLoadingPage = true);

    try {
      DocumentSnapshot? startAfter;
      if (page > 1 && _pageLastDocs.length >= page - 1) {
        startAfter = _pageLastDocs[page - 2]; // last doc of previous page
      }

      final result = await _contentService.getAllPosts(
        limit: _pageSize,
        startAfter: startAfter,
      );

      if (mounted) {
        final posts = result['movies'] as List<Movie>;
        final hasMore = result['hasMore'] as bool;
        final lastDoc = result['lastDoc'] as DocumentSnapshot?;

        setState(() {
          _pageCache[page] = posts;
          _hasMore = hasMore;
          if (lastDoc != null) {
            // Ensure we have lastDocs for all pages up to this one
            while (_pageLastDocs.length < page) {
              if (_pageLastDocs.length == page - 1) {
                _pageLastDocs.add(lastDoc);
              } else {
                // This shouldn't happen, but handle gracefully
                _pageLastDocs.add(lastDoc);
              }
            }
          }
          // Accumulate posts for search/filter
          _allPosts = [];
          for (int i = 1; i <= _pageCache.keys.reduce((a, b) => a > b ? a : b); i++) {
            if (_pageCache.containsKey(i)) {
              _allPosts.addAll(_pageCache[i]!);
            }
          }
          _currentPage = page;
          _applyFilters();
          _isLoadingPage = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPage = false);
    }
  }

  /// Go to next page
  void _nextPage() {
    if (_hasMore || _pageCache.containsKey(_currentPage + 1)) {
      _loadPage(_currentPage + 1);
    }
  }

  /// Go to previous page
  void _prevPage() {
    if (_currentPage > 1) {
      _loadPage(_currentPage - 1);
    }
  }

  /// Get total number of pages we know about
  int get _knownPages {
    final maxCached = _pageCache.keys.fold(0, (a, b) => a > b ? a : b);
    return _hasMore ? maxCached + 1 : maxCached;
  }

  void _filterPosts(String query) {
    setState(() {
      _searchQuery = query;
      _applyFilters();
    });
  }

  void _applyFilters() {
    _filteredPosts = _allPosts.where((post) {
      // Search query filter
      if (_searchQuery.isNotEmpty &&
          !post.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      // Genre filter
      if (_filterGenre != null && _filterGenre!.isNotEmpty) {
        if (!post.categories.any((c) =>
            c.toLowerCase() == _filterGenre!.toLowerCase())) {
          return false;
        }
      }
      // Year filter
      if (_filterYear != null && _filterYear!.isNotEmpty) {
        if (post.year != _filterYear) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<String> get _availableYears {
    final years = _allPosts
        .where((p) => p.year != null && p.year!.isNotEmpty)
        .map((p) => p.year!)
        .toSet()
        .toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  Future<void> _bulkDeleteSelected() async {
    if (_selectedPostIds.isEmpty) return;
    final count = _selectedPostIds.size;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Bulk Delete Confirmation', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete $count post${count > 1 ? 's' : ''}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE50914)),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      int deleted = 0;
      for (final id in _selectedPostIds.toList()) {
        try {
          await _contentService.deleteMovie(id);
          deleted++;
        } catch (_) {}
      }
      _selectedPostIds.clear();
      await _loadInitialData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $deleted post${deleted > 1 ? 's' : ''} successfully')),
        );
      }
    }
  }

  Future<void> _deletePost(String id, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Confirmation'),
        content: Text('Are you sure you want to delete this ${type == 'series' ? 'series' : 'movie'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _contentService.deleteMovie(id);
      _loadInitialData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted successfully')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get current page posts
    final currentPagePosts = _pageCache[_currentPage] ?? [];
    final movies = _filteredPosts.where((p) => p.type != 'series').toList();
    final series = _filteredPosts.where((p) => p.type == 'series').toList();

    // For tab view, use filtered posts from current page
    final currentAllPosts = _searchQuery.isNotEmpty || _filterGenre != null || _filterYear != null
        ? _filteredPosts
        : currentPagePosts;
    final currentMovies = _searchQuery.isNotEmpty || _filterGenre != null || _filterYear != null
        ? movies
        : currentPagePosts.where((p) => p.type != 'series').toList();
    final currentSeries = _searchQuery.isNotEmpty || _filterGenre != null || _filterYear != null
        ? series
        : currentPagePosts.where((p) => p.type == 'series').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'All (${currentAllPosts.length})'),
            Tab(text: 'Movies (${currentMovies.length})'),
            Tab(text: 'Series (${currentSeries.length})'),
            const Tab(text: 'Genres/Tags'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPostsTab(currentAllPosts, isDark),
                _buildPostsTab(currentMovies, isDark),
                _buildPostsTab(currentSeries, isDark),
                _buildGenresTagsTab(isDark),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final index = _tabController.index;
          if (index <= 2) {
            _showAddOptions();
          } else {
            _addGenreTagDialog();
          }
        },
        backgroundColor: const Color(0xFFE50914),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.movie, color: Color(0xFFE50914)),
              title: const Text('Add Movie'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddMoviePage(initialType: 'movie')),
                ).then((_) => _loadInitialData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.tv, color: Color(0xFFE50914)),
              title: const Text('Add Series'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddSeriesPage()),
                ).then((_) => _loadInitialData());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsTab(List<Movie> posts, bool isDark) {
    return Column(
      children: [
        // Bulk delete bar
        if (_isSelecting)
          Container(
            color: const Color(0xFFE50914).withOpacity(0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${_selectedPostIds.length} selected',
                  style: const TextStyle(
                    color: Color(0xFFE50914),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedPostIds.clear());
                  },
                  child: const Text('Clear', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _bulkDeleteSelected,
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Delete Selected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            onChanged: _filterPosts,
            decoration: InputDecoration(
              hintText: 'Search posts...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
          ),
        ),
        // Filter bar
        _buildFilterBar(isDark),
        // Posts list
        Expanded(
          child: _isLoadingPage
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : posts.isEmpty
                  ? const Center(child: Text('No posts found.'))
                  : ListView.builder(
                      itemCount: posts.length,
                      itemBuilder: (context, index) {
                        final post = posts[index];
                        return _buildPostListItem(post, isDark);
                      },
                    ),
        ),
        // Pagination controls - only show when not searching/filtering
        if (_searchQuery.isEmpty && _filterGenre == null && _filterYear == null)
          _buildPaginationControls(isDark),
      ],
    );
  }

  Widget _buildPaginationControls(bool isDark) {
    final knownPages = _knownPages;
    final currentPage = _currentPage;

    // Calculate which page numbers to show
    List<int> pageNumbers = [];
    if (knownPages <= 7) {
      // Show all pages if 7 or fewer
      for (int i = 1; i <= knownPages; i++) {
        pageNumbers.add(i);
      }
    } else {
      // Show: 1 ... currentPage-1 currentPage currentPage+1 ... lastKnown
      pageNumbers.add(1);
      if (currentPage > 3) pageNumbers.add(-1); // -1 represents ellipsis
      for (int i = currentPage - 1; i <= currentPage + 1; i++) {
        if (i > 1 && i < knownPages) pageNumbers.add(i);
      }
      if (currentPage < knownPages - 2) pageNumbers.add(-2); // -2 represents ellipsis
      pageNumbers.add(knownPages);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous button
            IconButton(
              onPressed: currentPage > 1 ? _prevPage : null,
              icon: const Icon(Icons.chevron_left),
              iconSize: 22,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              style: IconButton.styleFrom(
                foregroundColor: currentPage > 1
                    ? const Color(0xFFE50914)
                    : (isDark ? Colors.white24 : Colors.grey.shade400),
              ),
            ),
            const SizedBox(width: 4),
            // Page numbers
            ...pageNumbers.map((pageNum) {
              if (pageNum < 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '...',
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 14,
                    ),
                  ),
                );
              }
              final isCurrentPage = pageNum == currentPage;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: isCurrentPage
                      ? const Color(0xFFE50914)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () => _loadPage(pageNum),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: Text(
                        '$pageNum',
                        style: TextStyle(
                          color: isCurrentPage
                              ? Colors.white
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isCurrentPage ? FontWeight.bold : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 4),
            // Next button
            IconButton(
              onPressed: _hasMore || _pageCache.containsKey(currentPage + 1)
                  ? _nextPage
                  : null,
              icon: const Icon(Icons.chevron_right),
              iconSize: 22,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              style: IconButton.styleFrom(
                foregroundColor: _hasMore || _pageCache.containsKey(currentPage + 1)
                    ? const Color(0xFFE50914)
                    : (isDark ? Colors.white24 : Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          // Genre dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: DropdownButton<String>(
                value: _filterGenre ?? '',
                hint: const Text('Genre', style: TextStyle(fontSize: 13)),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: const Icon(Icons.filter_list, size: 18),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('All Genres', style: TextStyle(fontSize: 13)),
                  ),
                  ..._genres.map((g) => DropdownMenuItem<String>(
                    value: g.name,
                    child: Text(g.name, style: const TextStyle(fontSize: 13)),
                  )),
                ],
                onChanged: (value) {
                  setState(() {
                    _filterGenre = (value == null || value.isEmpty) ? null : value;
                    _applyFilters();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Year dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: DropdownButton<String>(
                value: _filterYear ?? '',
                hint: const Text('Year', style: TextStyle(fontSize: 13)),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: const Icon(Icons.calendar_today, size: 16),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('All Years', style: TextStyle(fontSize: 13)),
                  ),
                  ..._availableYears.map((y) => DropdownMenuItem<String>(
                    value: y,
                    child: Text(y, style: const TextStyle(fontSize: 13)),
                  )),
                ],
                onChanged: (value) {
                  setState(() {
                    _filterYear = (value == null || value.isEmpty) ? null : value;
                    _applyFilters();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Clear filters button
          if (_filterGenre != null || _filterYear != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 20, color: Color(0xFFE50914)),
              onPressed: () {
                setState(() {
                  _filterGenre = null;
                  _filterYear = null;
                  _applyFilters();
                });
              },
              tooltip: 'Clear filters',
            ),
        ],
      ),
    );
  }

  Widget _buildPostListItem(Movie post, bool isDark) {
    final theme = Theme.of(context);
    final isSelected = _selectedPostIds.contains(post.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isSelected
          ? const Color(0xFFE50914).withOpacity(0.1)
          : null,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Color(0xFFE50914), width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox for bulk selection
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedPostIds.contains(post.id)) {
                    _selectedPostIds.remove(post.id);
                  } else {
                    _selectedPostIds.add(post.id);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 4),
                child: Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedPostIds.add(post.id);
                      } else {
                        _selectedPostIds.remove(post.id);
                      }
                    });
                  },
                  activeColor: const Color(0xFFE50914),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 55,
                height: 78,
                child: post.fullPosterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: post.fullPosterUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                          child: const Icon(Icons.movie, size: 24),
                        ),
                      )
                    : Container(
                        color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                        child: const Icon(Icons.movie, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (post.year != null && post.year!.isNotEmpty)
                        Text(post.year!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                      if (post.year != null && post.year!.isNotEmpty)
                        const Text(' \u2022 ', style: TextStyle(fontSize: 12)),
                      if (post.rating != null && post.rating!.isNotEmpty) ...[
                        const Icon(Icons.star, size: 12, color: Color(0xFFFF0000)),
                        Text(post.rating!, style: const TextStyle(fontSize: 12, color: Color(0xFFFF0000))),
                        const Text(' \u2022 ', style: TextStyle(fontSize: 12)),
                      ],
                      Text(
                        post.timeAgo.isNotEmpty ? post.timeAgo : 'Unknown',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (post.isTrending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('TRENDING', style: TextStyle(color: Color(0xFFE50914), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (post.type == 'series' ? Colors.blue : Colors.green).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          post.type == 'series' ? 'SERIES' : 'MOVIE',
                          style: TextStyle(
                            color: post.type == 'series' ? Colors.blue : Colors.green,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Edit & Delete buttons
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EditMoviePage(movieId: post.id)),
                    ).then((_) => _loadInitialData());
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400),
                  onPressed: () => _deletePost(post.id, post.type ?? 'movie'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenresTagsTab(bool isDark) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            onTap: (index) {
              setState(() => _genresTagsSubTabIndex = index);
            },
            tabs: const [
              Tab(text: 'Genres'),
              Tab(text: 'Tags'),
              Tab(text: 'Collections'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSimpleList(_genres, isDark, 'genre'),
                _buildSimpleList(_tags, isDark, 'tag'),
                _buildSimpleList(_collections, isDark, 'collection'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleList(List<TagAndGenres> items, bool isDark, String type) {
    if (items.isEmpty) return Center(child: Text('No ${type}s yet. Tap + to add one.'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE50914).withOpacity(0.15),
            child: Text('${index + 1}', style: const TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold)),
          ),
          title: Text(item.name),
          subtitle: Text('${item.moviesCount ?? 0} movies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editItemDialog(item, type)),
              IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400), onPressed: () => _deleteItemDialog(item, type)),
            ],
          ),
        );
      },
    );
  }

  void _addGenreTagDialog() {
    final controller = TextEditingController();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
            const SizedBox(height: 12),
            const Text('This will be added as a Genre, Tag, or Collection based on the current tab.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    ).then((result) async {
      if (result == true && controller.text.trim().isNotEmpty) {
        // Add based on current sub-tab in Genres/Tags tab
        final genresTagsSubTab = _genresTagsSubTabIndex;
        if (genresTagsSubTab == 0) {
          await _contentService.addGenre(controller.text.trim());
        } else if (genresTagsSubTab == 1) {
          await _contentService.addTag(controller.text.trim());
        } else if (genresTagsSubTab == 2) {
          await _contentService.addCollection(controller.text.trim());
        }
        _loadInitialData();
      }
    });
  }

  Future<void> _editItemDialog(TagAndGenres item, String type) async {
    final controller = TextEditingController(text: item.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${type[0].toUpperCase()}${type.substring(1)}'),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: 'Name'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      if (type == 'genre') await _contentService.updateGenre(item.id, result);
      else if (type == 'tag') await _contentService.updateTag(item.id, result);
      else await _contentService.updateCollection(item.id, result);
      _loadInitialData();
    }
  }

  Future<void> _deleteItemDialog(TagAndGenres item, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${type[0].toUpperCase()}${type.substring(1)}'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      if (type == 'genre') await _contentService.deleteGenre(item.id);
      else if (type == 'tag') await _contentService.deleteTag(item.id);
      else await _contentService.deleteCollection(item.id);
      _loadInitialData();
    }
  }
}
