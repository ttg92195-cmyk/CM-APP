import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/services/poster_cache_manager.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/ui/screens/add_movie_page.dart';
import 'package:cm_movies/app/ui/screens/add_series_page.dart';
import 'package:cm_movies/app/ui/screens/edit_movie_page.dart';
import 'package:cm_movies/app/ui/screens/admin_notification_page.dart';
import 'package:cm_movies/app/ui/screens/admin_users_page.dart';
import 'package:cm_movies/app/ui/screens/batch_import_page.dart';

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
  //
  // PAGINATION: 20 per page so the admin sees a manageable chunk per
  // page and can flip pages quickly. Previously this was 30 (default
  // raised from 20 in commit 33b5dd5, June 11) — Bro reported the
  // Movies/Series tabs were loading too many posts at once, and the
  // same applies here for the Admin Panel's grid view. Reverted to 20
  // per page for consistency with the rest of the app.
  static const int _pageSize = 20;
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingPage = false;
  List<DocumentSnapshot> _pageLastDocs = []; // lastDoc for each loaded page
  Map<int, List<Movie>> _pageCache = {}; // cached posts per page

  // === SERIES TAB — DEDICATED PAGINATION STATE ===
  // Before this fix, the Series tab filtered CLIENT-SIDE from the All tab's
  // _pageCache (which only holds 30 mixed posts per page). With 1068 movies
  // and only 3 series in the DB, page 1 of getAllPosts() almost always had
  // 0 series — so the Series tab showed "No posts found" even though the
  // tab label correctly said "Series (3)" (from Firestore aggregate count).
  // Search worked because searchAllPosts() queries the whole DB.
  //
  // Fix: Series tab now uses getSeries() directly with its own pagination
  // state, decoupled from the All tab. The All tab and Movies tab are
  // unchanged (Movies tab filters from All tab's _pageCache, which works
  // fine because the vast majority of posts are movies).
  int _seriesCurrentPage = 1;
  bool _seriesHasMore = true;
  bool _seriesIsLoadingPage = false;
  List<DocumentSnapshot> _seriesPageLastDocs = [];
  Map<int, List<Movie>> _seriesPageCache = {};

  List<Movie> _allPosts = []; // accumulated posts for search/filter
  List<Movie> _filteredPosts = [];
  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<TagAndGenres> _collections = [];

  bool _isLoading = true;
  String _searchQuery = '';
  int _genresTagsSubTabIndex = 0;

  // Total counts in Firestore (fetched via AggregateQuery.count() so the tab
  // labels show the REAL total, not just the count of currently-loaded pages).
  // Before this fix, the tab labels showed "All (30)" because they used
  // _allPosts.length — which only reflects the first page of 30 posts. With
  // 1068 movies in Firestore, Bro thought 1038 movies had been deleted, when
  // in fact they were just on later pages.
  int _totalCountAll = 0;
  int _totalCountMovies = 0;
  int _totalCountSeries = 0;

  // Bulk delete
  Set<String> _selectedPostIds = {};
  bool get _isSelecting => _selectedPostIds.isNotEmpty;

  // Advanced filtering
  String? _filterGenre;
  String? _filterYear;

  // Banner settings
  List<String> _bannerImageUrls = [];
  final TextEditingController _bannerUrl1Controller = TextEditingController();
  final TextEditingController _bannerUrl2Controller = TextEditingController();
  final TextEditingController _bannerUrl3Controller = TextEditingController();

  // Search debouncer
  Timer? _searchDebounceTimer;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 500);

  // Global search state (decoupled from pagination)
  bool _isSearching = false;
  List<Movie> _globalSearchResults = [];
  bool _isSearchingLoading = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    // AUDIT C4 — these three banner URL controllers were declared at class
    // level (lines 68-70) but never disposed. They lived for the entire
    // admin-panel session and were re-leaked every time the admin reopened
    // the page. Each TextEditingController holds framework listeners
    // (text selection, focus, change notifications) that are only released
    // by an explicit dispose() call.
    _bannerUrl1Controller.dispose();
    _bannerUrl2Controller.dispose();
    _bannerUrl3Controller.dispose();
    super.dispose();
  }

  /// Load initial data: first page of posts + genres/tags/collections
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      // Reset pagination state — All tab
      _currentPage = 1;
      _hasMore = true;
      _pageLastDocs = [];
      _pageCache = {};
      _allPosts = [];

      // Reset pagination state — Series tab (separate from All tab)
      _seriesCurrentPage = 1;
      _seriesHasMore = true;
      _seriesPageLastDocs = [];
      _seriesPageCache = {};

      // Fetch All-tab page 1, Series-tab page 1, and supporting data, all
      // in parallel. The extra getSeries() call adds ~1 Firestore round-trip
      // but no extra latency because it runs concurrently with the other
      // futures. Cost: ~30 reads (page size) for the Series tab — tiny
      // compared to the bug it fixes (Series tab was always empty).
      final results = await Future.wait([
        _contentService.getAllPosts(limit: _pageSize),
        _contentService.getSeries(limit: _pageSize),
        _contentService.getGenres(),
        _contentService.getTags(),
        _contentService.getCollections(),
        _contentService.getBannerConfig(),
      ]);

      // Fetch total counts (cheap: uses Firestore AggregateQuery.count(),
      // billed as a single document read regardless of collection size).
      // Run in parallel so this doesn't add latency. These give us the REAL
      // total — used for tab labels ("All (1068)" instead of "All (30)").
      final totalCounts = await _contentService.getTotalPostCounts();

      if (mounted) {
        final postsData = results[0] as Map<String, dynamic>;
        final posts = postsData['movies'] as List<Movie>;
        final hasMore = postsData['hasMore'] as bool;
        final lastDoc = postsData['lastDoc'] as DocumentSnapshot?;

        // Series tab page 1
        final seriesData = results[1] as Map<String, dynamic>;
        final seriesPosts = seriesData['movies'] as List<Movie>;
        final seriesHasMore = seriesData['hasMore'] as bool;
        final seriesLastDoc = seriesData['lastDoc'] as DocumentSnapshot?;

        setState(() {
          _pageCache[1] = posts;
          _allPosts = List.from(posts);
          _filteredPosts = List.from(posts);
          _hasMore = hasMore;
          if (lastDoc != null) {
            _pageLastDocs = [lastDoc];
          }

          // Populate Series tab cache
          _seriesPageCache[1] = seriesPosts;
          _seriesHasMore = seriesHasMore;
          if (seriesLastDoc != null) {
            _seriesPageLastDocs = [seriesLastDoc];
          }

          _genres = results[2] as List<TagAndGenres>;
          _tags = results[3] as List<TagAndGenres>;
          _collections = results[4] as List<TagAndGenres>;
          _bannerImageUrls = results[5] is List
              ? List<String>.from((results[5] as List).whereType<String>())
              : [];
          _totalCountAll = totalCounts['all'] ?? 0;
          _totalCountMovies = totalCounts['movies'] ?? 0;
          _totalCountSeries = totalCounts['series'] ?? 0;
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

  // ==========================================================================
  // SERIES TAB — DEDICATED PAGINATION
  // ==========================================================================
  // These methods mirror _loadPage / _nextPage / _prevPage / _knownPages but
  // operate on the Series tab's separate pagination state, calling
  // getSeries() directly instead of filtering from getAllPosts().

  /// Load a specific page of SERIES posts (Series tab only).
  Future<void> _loadSeriesPage(int page) async {
    if (page < 1) return;
    if (_seriesIsLoadingPage) return;

    // If page is cached, just switch to it
    if (_seriesPageCache.containsKey(page)) {
      setState(() {
        _seriesCurrentPage = page;
      });
      return;
    }

    // Can only load next page if we have the previous page's last doc
    if (page > 1 && _seriesPageLastDocs.length < page - 1) return;

    // Can't go beyond available pages
    if (page > 1 && !_seriesHasMore && _seriesPageCache[page - 1] != null) {
      return;
    }

    setState(() => _seriesIsLoadingPage = true);

    try {
      DocumentSnapshot? startAfter;
      if (page > 1 && _seriesPageLastDocs.length >= page - 1) {
        startAfter = _seriesPageLastDocs[page - 2];
      }

      final result = await _contentService.getSeries(
        limit: _pageSize,
        startAfter: startAfter,
      );

      if (mounted) {
        final series = result['movies'] as List<Movie>;
        final hasMore = result['hasMore'] as bool;
        final lastDoc = result['lastDoc'] as DocumentSnapshot?;

        setState(() {
          _seriesPageCache[page] = series;
          _seriesHasMore = hasMore;
          if (lastDoc != null) {
            while (_seriesPageLastDocs.length < page) {
              _seriesPageLastDocs.add(lastDoc);
            }
          }
          _seriesCurrentPage = page;
          _seriesIsLoadingPage = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _seriesIsLoadingPage = false);
    }
  }

  void _nextSeriesPage() {
    if (_seriesHasMore || _seriesPageCache.containsKey(_seriesCurrentPage + 1)) {
      _loadSeriesPage(_seriesCurrentPage + 1);
    }
  }

  void _prevSeriesPage() {
    if (_seriesCurrentPage > 1) {
      _loadSeriesPage(_seriesCurrentPage - 1);
    }
  }

  int get _knownSeriesPages {
    final maxCached = _seriesPageCache.keys.fold(0, (a, b) => a > b ? a : b);
    return _seriesHasMore ? maxCached + 1 : maxCached;
  }

  void _filterPosts(String query) {
    _searchDebounceTimer?.cancel();

    if (query.trim().isEmpty) {
      // Not searching — reset to paginated view
      setState(() {
        _isSearching = false;
        _globalSearchResults = [];
        _searchQuery = '';
        _applyFilters();
      });
      return;
    }

    // Debounce: wait 500ms after user stops typing
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      _performGlobalSearch(query.trim());
    });
  }

  /// Perform global search across entire Firestore database (decoupled from pagination)
  Future<void> _performGlobalSearch(String keyword) async {
    setState(() {
      _isSearching = true;
      _isSearchingLoading = true;
      _searchQuery = keyword;
    });

    try {
      final results = await _contentService.searchAllPosts(keyword);
      if (mounted) {
        setState(() {
          _globalSearchResults = results;
          _isSearchingLoading = false;
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint('Global search error: $e');
      if (mounted) {
        setState(() {
          _globalSearchResults = [];
          _isSearchingLoading = false;
        });
      }
    }
  }

  void _applyFilters() {
    // When searching globally, filter from global search results instead of page cache
    final sourceList = _isSearching ? _globalSearchResults : _allPosts;
    
    _filteredPosts = sourceList.where((post) {
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
    final count = _selectedPostIds.length;
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

    // Get current page posts — All tab
    final currentPagePosts = _pageCache[_currentPage] ?? [];
    // Get current page posts — Series tab (dedicated cache, NOT filtered
    // from currentPagePosts which would miss series on movie-heavy pages).
    final currentSeriesPagePosts = _seriesPageCache[_seriesCurrentPage] ?? [];
    final movies = _filteredPosts.where((p) => p.type != 'series').toList();
    final series = _filteredPosts.where((p) => p.type == 'series').toList();

    // For tab view, use filtered posts from current page
    final currentAllPosts = _searchQuery.isNotEmpty || _filterGenre != null || _filterYear != null
        ? _filteredPosts
        : currentPagePosts;
    final currentMovies = _searchQuery.isNotEmpty || _filterGenre != null || _filterYear != null
        ? movies
        : currentPagePosts.where((p) => p.type != 'series').toList();
    // Series tab: when not searching, use the DEDICATED series cache (fixes
    // the "No posts found" bug). When searching, fall back to filtering
    // _filteredPosts (which comes from searchAllPosts across the whole DB).
    final currentSeries = _searchQuery.isNotEmpty || _filterGenre != null || _filterYear != null
        ? series
        : currentSeriesPagePosts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersPage()));
            },
            tooltip: 'Users',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          labelPadding: const EdgeInsets.symmetric(horizontal: 2),
          tabAlignment: TabAlignment.fill,
          tabs: [
            // When user is searching or filtering, show the count of
            // matches (currentAllPosts.length). When NOT searching, show
            // the REAL total from Firestore (_totalCountAll) so the user
            // knows exactly how many movies exist in the database — not
            // just how many are loaded on the current page.
            Tab(text: _isSearching || _filterGenre != null || _filterYear != null
                ? 'All (${currentAllPosts.length})'
                : 'All ($_totalCountAll)'),
            Tab(text: _isSearching || _filterGenre != null || _filterYear != null
                ? 'Movies (${currentMovies.length})'
                : 'Movies ($_totalCountMovies)'),
            Tab(text: _isSearching || _filterGenre != null || _filterYear != null
                ? 'Series (${currentSeries.length})'
                : 'Series ($_totalCountSeries)'),
            const Tab(text: 'Tags'),
            const Tab(text: 'Banner'),
            const Tab(text: 'Notify'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPostsTab(currentAllPosts, isDark, tabIndex: 0),
                _buildPostsTab(currentMovies, isDark, tabIndex: 1),
                _buildPostsTab(currentSeries, isDark, tabIndex: 2),
                _buildGenresTagsTab(isDark),
                _buildBannerTab(isDark),
                const AdminNotificationPage(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final index = _tabController.index;
          if (index <= 2) {
            _showAddOptions();
          } else if (index == 3) {
            _addGenreTagDialog();
          }
          // Tab 4 (Banner) and Tab 5 (Notify) have their own UI — no FAB action needed
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
            const Divider(height: 1),
            // =========================================================================
            // Task 28 — Batch Import button RE-ENABLED.
            //
            // Was temporarily disabled in Task 27 because a wrong-type
            // field in the JSON file (e.g., `categories: "Action"` as
            // a string instead of a list) made the entire All Posts
            // grid disappear. Task 27 fixed BOTH sides:
            //   - READ side: Movie.fromMap is now defensive — never
            //     throws on bad data, so the grid stays visible even
            //     if one doc has a wrong-type field.
            //   - WRITE side: addMovie()/_buildSafeUpdateMap() now
            //     coerces list-typed fields to List<String> or skips
            //     them, so future imports can't corrupt docs.
            //
            // Bro confirmed on real device: build green, All Posts
            // grid stays visible even with bad JSON. Button is back.
            // =========================================================================
            ListTile(
              leading: const Icon(Icons.upload_file, color: Color(0xFFE50914)),
              title: const Text('Batch Import (JSON)'),
              subtitle: const Text(
                'Import multiple movies/series from a JSON file.',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BatchImportPage()),
                ).then((_) => _loadInitialData());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsTab(List<Movie> posts, bool isDark, {required int tabIndex}) {
    // Series tab (tabIndex == 2) uses its OWN pagination state, decoupled
    // from the All tab. All/Movies tabs share the All tab's pagination.
    final bool isSeriesTab = tabIndex == 2;
    final bool isLoadingThisPage =
        isSeriesTab ? _seriesIsLoadingPage : _isLoadingPage;
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
            controller: _searchController,
            onChanged: _filterPosts,
            decoration: InputDecoration(
              hintText: 'Search posts...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _filterPosts('');
                      },
                    )
                  : null,
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
          child: _isSearchingLoading
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : _isSearching
                  ? (_filteredPosts.isEmpty
                      ? const Center(child: Text('No posts found.'))
                      : ListView.builder(
                          itemCount: _filteredPosts.length,
                          itemBuilder: (context, index) {
                            final post = _filteredPosts[index];
                            return _buildPostListItem(post, isDark);
                          },
                        ))
                  : isLoadingThisPage
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
        // Pagination controls — only show when NOT searching.
        // Series tab uses its own pagination controls (dedicated cache).
        if (!_isSearching && _searchQuery.isEmpty && _filterGenre == null && _filterYear == null)
          isSeriesTab
              ? _buildPaginationControls(isDark, forSeriesTab: true)
              : _buildPaginationControls(isDark, forSeriesTab: false),
      ],
    );
  }

  Widget _buildPaginationControls(bool isDark, {required bool forSeriesTab}) {
    // Pick the right pagination state based on which tab we're rendering.
    final int knownPages = forSeriesTab ? _knownSeriesPages : _knownPages;
    final int currentPage = forSeriesTab ? _seriesCurrentPage : _currentPage;
    final bool hasMore = forSeriesTab ? _seriesHasMore : _hasMore;
    final Map<int, List<Movie>> pageCache =
        forSeriesTab ? _seriesPageCache : _pageCache;
    final void Function() prevPage =
        forSeriesTab ? _prevSeriesPage : _prevPage;
    final void Function() nextPage =
        forSeriesTab ? _nextSeriesPage : _nextPage;
    final Future<void> Function(int) loadPage =
        forSeriesTab ? _loadSeriesPage : _loadPage;

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
              onPressed: currentPage > 1 ? prevPage : null,
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
                    onTap: () => loadPage(pageNum),
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
              onPressed: hasMore || pageCache.containsKey(currentPage + 1)
                  ? nextPage
                  : null,
              icon: const Icon(Icons.chevron_right),
              iconSize: 22,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              style: IconButton.styleFrom(
                foregroundColor: hasMore || pageCache.containsKey(currentPage + 1)
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
                        cacheManager: PosterCacheManager.instance,
                        cacheKey: post.id,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 200),
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

  Widget _buildBannerTab(bool isDark) {
    // Initialize controllers with existing URLs
    if (_bannerImageUrls.isNotEmpty) {
      if (_bannerUrl1Controller.text.isEmpty && _bannerImageUrls.length > 0) {
        _bannerUrl1Controller.text = _bannerImageUrls[0];
      }
      if (_bannerUrl2Controller.text.isEmpty && _bannerImageUrls.length > 1) {
        _bannerUrl2Controller.text = _bannerImageUrls[1];
      }
      if (_bannerUrl3Controller.text.isEmpty && _bannerImageUrls.length > 2) {
        _bannerUrl3Controller.text = _bannerImageUrls[2];
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Banner Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Add up to 3 external image URLs for the Home banner slider.',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54),
          ),
          const SizedBox(height: 24),

          // URL 1
          _buildBannerUrlField(
            controller: _bannerUrl1Controller,
            label: 'Banner Image 1',
            hint: 'https://example.com/banner1.jpg',
            isDark: isDark,
          ),
          const SizedBox(height: 16),

          // URL 2
          _buildBannerUrlField(
            controller: _bannerUrl2Controller,
            label: 'Banner Image 2',
            hint: 'https://example.com/banner2.jpg',
            isDark: isDark,
          ),
          const SizedBox(height: 16),

          // URL 3
          _buildBannerUrlField(
            controller: _bannerUrl3Controller,
            label: 'Banner Image 3',
            hint: 'https://example.com/banner3.jpg',
            isDark: isDark,
          ),
          const SizedBox(height: 24),

          // Save button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saveBannerConfig,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Preview section
          Text(
            'Preview',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _buildBannerPreview(isDark),
        ],
      ),
    );
  }

  Widget _buildBannerUrlField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(Icons.link, size: 20),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      controller.clear();
                      setState(() {});
                    },
                  )
                : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
          keyboardType: TextInputType.url,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildBannerPreview(bool isDark) {
    final urls = [
      _bannerUrl1Controller.text.trim(),
      _bannerUrl2Controller.text.trim(),
      _bannerUrl3Controller.text.trim(),
    ].where((url) => url.isNotEmpty).toList();

    if (urls.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            'No banner images configured',
            style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
          ),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: urls[index],
                fit: BoxFit.cover,
                width: 200,
                height: 120,
                placeholder: (_, __) => Container(
                  width: 200,
                  height: 120,
                  color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade200,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 200,
                  height: 120,
                  color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade200,
                  child: Icon(Icons.broken_image, color: isDark ? Colors.white24 : Colors.black12),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveBannerConfig() async {
    final urls = [
      _bannerUrl1Controller.text.trim(),
      _bannerUrl2Controller.text.trim(),
      _bannerUrl3Controller.text.trim(),
    ].where((url) => url.isNotEmpty).toList();

    try {
      await _contentService.saveBannerConfig(urls);
      if (mounted) {
        setState(() => _bannerImageUrls = urls);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Banner settings saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving banner: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    // AUDIT C5 — dispose the controller after the dialog closes so its
    // framework listeners are released. `whenComplete` runs whether the
    // dialog was popped with a result, with null (back button), or even
    // errored. The previous code only consumed `controller.text` and then
    // left the controller to leak.
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
        // Capture the value BEFORE disposing the controller.
        final name = controller.text.trim();
        // Add based on current sub-tab in Genres/Tags tab
        final genresTagsSubTab = _genresTagsSubTabIndex;
        if (genresTagsSubTab == 0) {
          await _contentService.addGenre(name);
        } else if (genresTagsSubTab == 1) {
          await _contentService.addTag(name);
        } else if (genresTagsSubTab == 2) {
          await _contentService.addCollection(name);
        }
        _loadInitialData();
      }
    }).whenComplete(() {
      controller.dispose();
    });
  }

  Future<void> _editItemDialog(TagAndGenres item, String type) async {
    final controller = TextEditingController(text: item.name);
    String? result;
    try {
      result = await showDialog<String>(
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
    } finally {
      // AUDIT C5 — dispose regardless of how the dialog closed.
      controller.dispose();
    }
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
