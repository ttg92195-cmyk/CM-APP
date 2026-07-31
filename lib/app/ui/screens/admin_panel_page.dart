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
import 'package:cm_movies/app/ui/components/no_toolbar_on_single_tap_text_field.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage>
    with SingleTickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  late TabController _tabController;

  // ==========================================================================
  // Phase 4.3 — INFINITE SCROLL (replaces page-number pagination)
  // ==========================================================================
  // Before Phase 4.3, the Admin Panel used a page-number pagination system
  // (⬅️ 1 2 3 ➡️) at the bottom of All/Movies/Series tabs. Bro reported this
  // felt out of place in a mobile app — modern apps use infinite scroll with
  // a pull-to-refresh and a bottom loading spinner.
  //
  // New model:
  //   - _allPosts accumulates every post we've fetched so far (no more page
  //     cache keyed by page number).
  //   - _lastVisibleDoc is the cursor for the next getAllPosts(startAfter:).
  //   - _hasMore flips false when Firestore returns a short page.
  //   - NotificationListener<ScrollNotification> on each ListView triggers
  //     _loadMore() when the user gets within 200px of the bottom.
  //   - RefreshIndicator wraps the ListView for pull-to-refresh.
  //   - A bottom status tile shows: loading spinner / "No more posts" / none.
  //
  // The Series tab mirrors this with its own state (decoupled from the All
  // tab because getSeries() queries only series docs).
  // ==========================================================================
  static const int _pageSize = 20;

  // All tab + Movies tab (shared) — Movies tab is a filtered view of All tab.
  List<Movie> _allPosts = [];            // accumulated list
  bool _hasMore = true;                  // can fetch more?
  bool _isLoadingMore = false;           // fetching next chunk?
  DocumentSnapshot? _lastVisibleDoc;     // cursor for startAfter()

  // Series tab — dedicated state (same design, new shape)
  List<Movie> _allSeriesPosts = [];      // accumulated series list
  bool _seriesHasMore = true;
  bool _seriesIsLoadingMore = false;
  DocumentSnapshot? _seriesLastVisibleDoc;

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

  // Phase 4.43 — Server-side filter state (decoupled from pagination).
  //
  // PROBLEM THIS FIXES:
  // Before Phase 4.43, _applyFilters() filtered CLIENT-SIDE from _allPosts,
  // which only contains the first 20 docs (page 1, sorted by updatedAt desc).
  // So when the user picked a genre like "Animation", they only saw the
  // Animation movies that happened to be in the 20 most-recent docs — which
  // were almost always the ones they had just EDITED (editing bumps updatedAt,
  // pushing the post into page 1). The user reported this as "Animation Post
  // Edit လုပ်ထားဖူးတဲ့ Animation Post တွေ့ပေါ်လာတာ" (only edited Animation
  // posts appear). Same bug for All Years.
  //
  // FIX:
  // When a genre/year filter is set AND no search keyword is active, run a
  // server-side Firestore query (searchMoviesWithFilters) to fetch ALL
  // matching posts across the entire DB, not just page-1 cache. Mirror the
  // _isSearching pattern: dedicated loading flag + dedicated results list,
  // bypassing the paginated _allPosts cache entirely.
  //
  // When a search keyword IS active, the search path already returns full-DB
  // results, so genre/year filter is applied client-side on top of those
  // results (no separate server-side filter query needed).
  bool _isFiltering = false;
  bool _isFilterLoading = false;
  List<Movie> _filterQueryResults = [];

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
      // Phase 4.3 — reset infinite-scroll state for All tab.
      _allPosts = [];
      _hasMore = true;
      _isLoadingMore = false;
      _lastVisibleDoc = null;

      // Reset infinite-scroll state for Series tab.
      _allSeriesPosts = [];
      _seriesHasMore = true;
      _seriesIsLoadingMore = false;
      _seriesLastVisibleDoc = null;

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
          // Phase 4.3 — All tab: directly populate accumulated list + cursor.
          _allPosts = List.from(posts);
          _filteredPosts = List.from(posts);
          _hasMore = hasMore;
          _lastVisibleDoc = lastDoc;

          // Series tab: same shape — accumulated list + cursor.
          _allSeriesPosts = List.from(seriesPosts);
          _seriesHasMore = seriesHasMore;
          _seriesLastVisibleDoc = seriesLastDoc;

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

        // Phase 4.43 — if a filter was active when _loadInitialData was
        // called (e.g., user deleted a post while filtering by genre),
        // re-run the server-side filter query so the filtered list
        // reflects the new DB state. Without this, the user would see
        // stale filter results (with the deleted post still in the list)
        // until they manually re-selected the filter.
        if (_isFiltering ||
            (_filterGenre != null && _filterGenre!.isNotEmpty) ||
            (_filterYear != null && _filterYear!.isNotEmpty)) {
          await _applyServerSideFilters();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==========================================================================
  // Phase 4.3 — INFINITE SCROLL: _loadMore + _loadMoreSeries + _refresh
  // ==========================================================================
  // These replace the old _loadPage / _nextPage / _prevPage / _knownPages
  // (and the Series-tab mirrors). The new model is cursor-based: each call
  // to _loadMore appends a chunk of _pageSize posts to _allPosts, advancing
  // _lastVisibleDoc to the last doc of the new chunk. _hasMore flips false
  // when Firestore returns a short page (or an empty page).
  // ==========================================================================

  /// Fetch the next chunk of posts for the All/Movies tab using cursor-based
  /// pagination. Appends to _allPosts and advances _lastVisibleDoc.
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final result = await _contentService.getAllPosts(
        limit: _pageSize,
        startAfter: _lastVisibleDoc,
      );

      if (!mounted) return;
      final posts = result['movies'] as List<Movie>;
      final hasMore = result['hasMore'] as bool;
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;

      setState(() {
        _allPosts.addAll(posts);
        _hasMore = hasMore;
        if (lastDoc != null) {
          _lastVisibleDoc = lastDoc;
        }
        // Defensive: if Firestore returned an empty page, force _hasMore off
        // so we don't keep retrying. firestore_content_service should already
        // do this, but never trust a remote call to be perfectly behaved.
        if (posts.isEmpty) {
          _hasMore = false;
        }
        _applyFilters();
        _isLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Phase 4.3 _loadMore error: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  /// Fetch the next chunk of SERIES posts (Series tab only).
  Future<void> _loadMoreSeries() async {
    if (_seriesIsLoadingMore || !_seriesHasMore) return;

    setState(() => _seriesIsLoadingMore = true);
    try {
      final result = await _contentService.getSeries(
        limit: _pageSize,
        startAfter: _seriesLastVisibleDoc,
      );

      if (!mounted) return;
      final series = result['movies'] as List<Movie>;
      final hasMore = result['hasMore'] as bool;
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;

      setState(() {
        _allSeriesPosts.addAll(series);
        _seriesHasMore = hasMore;
        if (lastDoc != null) {
          _seriesLastVisibleDoc = lastDoc;
        }
        if (series.isEmpty) {
          _seriesHasMore = false;
        }
        _seriesIsLoadingMore = false;
      });
    } catch (e) {
      debugPrint('Phase 4.3 _loadMoreSeries error: $e');
      if (mounted) setState(() => _seriesIsLoadingMore = false);
    }
  }

  /// Phase 4.3 — pull-to-refresh handler.
  /// Re-fetches the first page WITHOUT blanking the screen. The existing
  /// _allPosts list stays visible until the new data arrives, then is
  /// replaced atomically in a single setState. If the fetch fails, the
  /// old data is kept (better UX than an empty screen with an error).
  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        _contentService.getAllPosts(limit: _pageSize),
        _contentService.getSeries(limit: _pageSize),
        _contentService.getGenres(),
        _contentService.getTags(),
        _contentService.getCollections(),
        _contentService.getBannerConfig(),
      ]);
      final totalCounts = await _contentService.getTotalPostCounts();

      if (!mounted) return;
      final postsData = results[0] as Map<String, dynamic>;
      final posts = postsData['movies'] as List<Movie>;
      final hasMore = postsData['hasMore'] as bool;
      final lastDoc = postsData['lastDoc'] as DocumentSnapshot?;

      final seriesData = results[1] as Map<String, dynamic>;
      final seriesPosts = seriesData['movies'] as List<Movie>;
      final seriesHasMore = seriesData['hasMore'] as bool;
      final seriesLastDoc = seriesData['lastDoc'] as DocumentSnapshot?;

      setState(() {
        _allPosts = List.from(posts);
        _filteredPosts = List.from(posts);
        _hasMore = hasMore;
        _lastVisibleDoc = lastDoc;
        _isLoadingMore = false;

        _allSeriesPosts = List.from(seriesPosts);
        _seriesHasMore = seriesHasMore;
        _seriesLastVisibleDoc = seriesLastDoc;
        _seriesIsLoadingMore = false;

        _genres = results[2] as List<TagAndGenres>;
        _tags = results[3] as List<TagAndGenres>;
        _collections = results[4] as List<TagAndGenres>;
        _bannerImageUrls = results[5] is List
            ? List<String>.from((results[5] as List).whereType<String>())
            : [];
        _totalCountAll = totalCounts['all'] ?? 0;
        _totalCountMovies = totalCounts['movies'] ?? 0;
        _totalCountSeries = totalCounts['series'] ?? 0;
      });
    } catch (e) {
      debugPrint('Phase 4.3 _refresh error: $e');
      // Don't clear existing data on error — keep showing what we have.
    }
  }

  void _filterPosts(String query) {
    _searchDebounceTimer?.cancel();

    if (query.trim().isEmpty) {
      // Not searching — reset to non-search mode.
      // Phase 4.43 — if a genre/year filter is still active, we need to
      // re-run the server-side filter query (because while search was
      // active, _isFiltering was false and _filterQueryResults was empty).
      // _applyServerSideFilters handles this case: it detects no search
      // keyword, sees whether a filter is set, and either runs the
      // server-side query or restores the paginated _allPosts view.
      setState(() {
        _isSearching = false;
        _globalSearchResults = [];
        _searchQuery = '';
      });
      _applyServerSideFilters();
      return;
    }

    // Debounce: wait 500ms after user stops typing
    _searchDebounceTimer = Timer(_searchDebounceDuration, () {
      _performGlobalSearch(query.trim());
    });
  }

  /// Perform global search across entire Firestore database (decoupled from pagination)
  Future<void> _performGlobalSearch(String keyword) async {
    // Phase 4.43 — cancel any in-flight server-side filter query state.
    // If a filter query was loading when the user started typing, the
    // filter's setState (when it eventually completes) would call
    // _applyFilters(), which is correct (it picks _globalSearchResults
    // when _isSearching is true). But _isFilterLoading might still be
    // true, showing the loading spinner over ready search results.
    // Reset filter state here to keep the UI consistent.
    setState(() {
      _isSearching = true;
      _isSearchingLoading = true;
      _searchQuery = keyword;
      _isFiltering = false;
      _isFilterLoading = false;
      _filterQueryResults = [];
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
    // Phase 4.43 — Source list priority: search > filter > paginated cache.
    //
    // - When searching: use _globalSearchResults (already a full-DB query).
    //   Genre/year are then applied client-side on top.
    // - When filtering (no search keyword): use _filterQueryResults (already
    //   a full-DB query for the genre/year). The client-side filter below is
    //   a safety net — searchMoviesWithFilters already filters server-side,
    //   but keeping the client-side check guarantees correctness if the
    //   server-side query path ever drifts.
    // - Otherwise: use _allPosts (page-1 cache, sorted by updatedAt desc).
    final List<Movie> sourceList;
    if (_isSearching) {
      sourceList = _globalSearchResults;
    } else if (_isFiltering) {
      sourceList = _filterQueryResults;
    } else {
      sourceList = _allPosts;
    }

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

  /// Phase 4.43 — Run a server-side Firestore query for the current genre/year
  /// filter state. Mirrors the _performGlobalSearch pattern.
  ///
  /// Called whenever the user picks a genre or year from the dropdowns, OR
  /// when the user clears the search box while a filter is still active.
  ///
  /// Behavior:
  /// - If a search keyword is active: do nothing. _applyFilters() will use
  ///   _globalSearchResults as the source and apply genre/year client-side.
  /// - If no filter is set: reset _isFiltering and re-run _applyFilters to
  ///   restore the paginated _allPosts view.
  /// - Otherwise: set _isFilterLoading=true, run searchMoviesWithFilters,
  ///   populate _filterQueryResults, and call _applyFilters.
  ///
  /// The Firestore limit is 500 — generous enough for the entire catalog of
  /// any single genre or year (admin catalog is ~1068 posts total). If a
  /// single genre/year ever exceeds 500 docs, the user can refine with a
  /// search keyword to narrow further.
  Future<void> _applyServerSideFilters() async {
    // If searching, defer to the search path — _applyFilters handles the
    // client-side genre/year overlay on _globalSearchResults.
    if (_searchQuery.isNotEmpty) {
      _isFiltering = false;
      _filterQueryResults = [];
      _applyFilters();
      return;
    }

    final hasFilter = (_filterGenre != null && _filterGenre!.isNotEmpty) ||
        (_filterYear != null && _filterYear!.isNotEmpty);

    if (!hasFilter) {
      // No filter active — restore paginated _allPosts view.
      if (mounted) {
        setState(() {
          _isFiltering = false;
          _isFilterLoading = false;
          _filterQueryResults = [];
          _applyFilters();
        });
      } else {
        _isFiltering = false;
        _isFilterLoading = false;
        _filterQueryResults = [];
        _applyFilters();
      }
      return;
    }

    // Filter active — show loading state, then run the server-side query.
    if (mounted) {
      setState(() {
        _isFiltering = true;
        _isFilterLoading = true;
      });
    } else {
      _isFiltering = true;
      _isFilterLoading = true;
    }

    try {
      final result = await _contentService.searchMoviesWithFilters(
        genre: _filterGenre,
        year: _filterYear,
        limit: 500,
      );
      if (mounted) {
        setState(() {
          _filterQueryResults =
              (result['movies'] as List).cast<Movie>();
          _isFilterLoading = false;
          _applyFilters();
        });
      }
    } catch (e) {
      debugPrint('Phase 4.43 server-side filter error: $e');
      if (mounted) {
        setState(() {
          _filterQueryResults = [];
          _isFilterLoading = false;
          _applyFilters();
        });
      }
    }
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

    // Phase 4.3 — infinite scroll: All/Movies tabs share _allPosts (Movies
    // tab is a filtered view of All tab). Series tab uses its own dedicated
    // _allSeriesPosts list (decoupled because getSeries() queries only
    // series docs). When searching/filtering, _filteredPosts is used
    // instead (search returns full results from searchAllPosts; filter is
    // applied client-side to _allPosts).
    final movies = _filteredPosts.where((p) => p.type != 'series').toList();
    final series = _filteredPosts.where((p) => p.type == 'series').toList();

    final bool isFiltering = _searchQuery.isNotEmpty ||
        _filterGenre != null ||
        _filterYear != null;

    final currentAllPosts = isFiltering ? _filteredPosts : _allPosts;
    final currentMovies = isFiltering
        ? movies
        : _allPosts.where((p) => p.type != 'series').toList();
    final currentSeries = isFiltering ? series : _allSeriesPosts;

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
    // Phase 4.3 — Series tab (tabIndex == 2) uses its OWN infinite-scroll
    // state, decoupled from the All tab. All/Movies tabs share the All
    // tab's state (Movies tab is a filtered view of All tab's _allPosts).
    final bool isSeriesTab = tabIndex == 2;
    final bool isLoadingMore = isSeriesTab ? _seriesIsLoadingMore : _isLoadingMore;
    final bool hasMore = isSeriesTab ? _seriesHasMore : _hasMore;
    final Future<void> Function() loadMore =
        isSeriesTab ? _loadMoreSeries : _loadMore;

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
          child: NoToolbarOnSingleTapTextField(
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
        // Posts list — Phase 4.3: RefreshIndicator + infinite-scroll ListView.
        // Phase 4.43 — also show the loading spinner while the server-side
        // filter query is running (mirrors _isSearchingLoading behavior).
        Expanded(
          child: (_isSearchingLoading || _isFilterLoading)
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFFE50914),
                  onRefresh: _refresh,
                  child: _buildPostsList(
                    posts: posts,
                    isDark: isDark,
                    isLoadingMore: isLoadingMore,
                    hasMore: hasMore,
                    loadMore: loadMore,
                  ),
                ),
        ),
      ],
    );
  }

  /// Phase 4.3 — Builds the posts ListView with infinite-scroll footer.
  ///
  /// Three modes:
  ///   1. Searching: flat list of search results (no footer — search
  ///      returns full results from searchAllPosts across the whole DB,
  ///      so no pagination needed). Still wrapped in a ListView so the
  ///      parent RefreshIndicator has something to scroll.
  ///   2. Empty list (no search, no posts loaded yet): a minimal ListView
  ///      with a "No posts found" message. The ListView is needed so
  ///      pull-to-refresh still works on an empty list.
  ///   3. Normal: ListView with `posts.length + 1` items. The extra item
  ///      is the footer (loading spinner / "No more posts" / idle spacer).
  ///      A NotificationListener<ScrollNotification> wraps the ListView
  ///      and triggers `loadMore` when the user gets within 200px of the
  ///      bottom.
  Widget _buildPostsList({
    required List<Movie> posts,
    required bool isDark,
    required bool isLoadingMore,
    required bool hasMore,
    required Future<void> Function() loadMore,
  }) {
    // Mode 1: searching OR filtering — flat list, no footer.
    //
    // Phase 4.43 — _isFiltering now uses the same flat-list mode as
    // _isSearching. The server-side filter query returns the full result
    // set (up to 500 docs) in one shot, so there's no pagination footer
    // to show. If the user wants to narrow further, they refine the
    // filter or add a search keyword.
    if (_isSearching || _isFiltering) {
      if (posts.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(child: Text('No posts found.')),
          ],
        );
      }
      return ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: posts.length,
        itemBuilder: (context, index) =>
            _buildPostListItem(posts[index], isDark),
      );
    }

    // Mode 2: empty list — allow pull-to-refresh.
    if (posts.isEmpty && !isLoadingMore) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No posts found.')),
        ],
      );
    }

    // Mode 3: normal infinite-scroll list with footer.
    //
    // physics: AlwaysScrollableScrollPhysics — required so the user can
    // overscroll to trigger RefreshIndicator even when the list is short.
    //
    // The NotificationListener captures ALL scroll notifications (not just
    // ScrollEndNotification) so the loadMore fires promptly when the user
    // flings to the bottom. The `isLoadingMore`/`hasMore` guards inside
    // _loadMore itself prevent double-fires.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Phase 4.43 — don't trigger paginated _loadMore while searching
        // or filtering. Both modes have their own complete result sets.
        if (_isSearching || _isFiltering) return false;
        // Trigger on both ScrollUpdateNotification (mid-scroll) and
        // ScrollEndNotification (fling settled). This makes the next chunk
        // load proactively as the user approaches the bottom, instead of
        // waiting for the scroll to fully stop.
        if (notification is! ScrollUpdateNotification &&
            notification is! ScrollEndNotification &&
            notification is! OverscrollNotification) {
          return false;
        }
        final metrics = notification.metrics;
        // Guard: don't trigger if the list isn't scrollable yet. This
        // prevents auto-firing _loadMore on tiny lists where
        // maxScrollExtent is 0 or very small (e.g. only 2-3 posts fit).
        // Once the user has enough posts to scroll, this guard passes and
        // the bottom-trigger logic kicks in.
        if (metrics.maxScrollExtent < 100) return false;
        if (metrics.pixels >= metrics.maxScrollExtent - 200) {
          loadMore();
        }
        return false;
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        // +1 for the footer tile (loading spinner / "No more posts" / spacer).
        itemCount: posts.length + 1,
        itemBuilder: (context, index) {
          if (index == posts.length) {
            return _buildListFooter(
              isLoadingMore: isLoadingMore,
              hasMore: hasMore,
              isDark: isDark,
            );
          }
          return _buildPostListItem(posts[index], isDark);
        },
      ),
    );
  }

  /// Phase 4.3 — Bottom status tile for the posts ListView.
  /// Shows one of three states:
  ///   - Loading more: spinner + "Loading more..."
  ///   - No more posts: subtle "No more posts" with check icon
  ///   - Idle (more available): small spacer at the bottom
  Widget _buildListFooter({
    required bool isLoadingMore,
    required bool hasMore,
    required bool isDark,
  }) {
    if (isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Text(
                'Loading more...',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 8),
              Text(
                'No more posts',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // Idle — small bottom padding so the next scroll-trigger has room.
    return const SizedBox(height: 32);
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
                  });
                  // Phase 4.43 — run server-side query instead of client-side
                  // filter. _applyServerSideFilters handles the loading state
                  // and the source-list swap inside _applyFilters.
                  _applyServerSideFilters();
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
                  });
                  // Phase 4.43 — see genre dropdown comment above.
                  _applyServerSideFilters();
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
                });
                // Phase 4.43 — _applyServerSideFilters detects no filter is
                // set and restores the paginated _allPosts view.
                _applyServerSideFilters();
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
                      // Phase 4.21 — "Edited 3h ago" စာသား: edit လုပ်ခဲ့ရင် နောက်ဆုံးပြင်ချိန်
                      if (post.wasEdited && post.editedAgo.isNotEmpty) ...[
                        const Text(' \u2022 ', style: TextStyle(fontSize: 12)),
                        Text(
                          post.editedAgo,
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFFFF6D00).withOpacity(isDark ? 0.85 : 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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
                      // Phase 4.21 — EDITED badge: post ကို admin ပြင်လိုက်ပြီဆိုရင်ပြပါ
                      if (post.wasEdited) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6D00).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'EDITED',
                            style: TextStyle(
                              color: Color(0xFFFF6D00),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
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
