import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/tmdb_service.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/components/no_toolbar_on_single_tap_text_field.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';

class TmdbGeneratorPage extends StatefulWidget {
  const TmdbGeneratorPage({super.key});

  @override
  State<TmdbGeneratorPage> createState() => _TmdbGeneratorPageState();
}

class _TmdbGeneratorPageState extends State<TmdbGeneratorPage>
    with SingleTickerProviderStateMixin {
  final TmdbService _tmdbService = TmdbService();
  final FirestoreContentService _contentService = FirestoreContentService();

  // Tab controller
  late TabController _tabController;

  // Filter state
  String _type = 'movie'; // 'movie' or 'series'
  int? _selectedGenreId;
  String? _selectedYear;
  String _selectedLanguage = ''; // Original language filter (empty = all)
  String _selectedSortBy = 'popularity.desc';
  int _postLimit = 20;
  final TextEditingController _searchController = TextEditingController();

  // Genre maps
  List<Map<String, dynamic>> _movieGenres = [];
  List<Map<String, dynamic>> _tvGenres = [];
  Map<int, String> _genreIdToName = {};

  // Results state
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  bool _isSearching = false;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalResults = 0;

  // Selection state
  final Set<int> _selectedIds = {};

  // Already imported tmdbIds from Firestore
  final Set<int> _importedTmdbIds = {};

  // Import state
  bool _isImporting = false;
  int _importProgress = 0;
  int _importTotal = 0;
  String _importCurrentTitle = '';
  int _importSuccessCount = 0;
  int _importFailureCount = 0;

  // Sync state
  bool _isSyncing = false;
  int _syncProgress = 0;
  int _syncTotal = 0;
  String _syncCurrentTitle = '';
  int _syncSuccessCount = 0;
  int _syncFailureCount = 0;
  bool _skipDescriptionUpdate = true; // Default to true for sync dashboard
  int _syncRemainingMovies = 0;
  int _syncRemainingSeries = 0;

  // Batch size for sync operations
  static const int _syncBatchSize = 20;

  // Filter collapse
  bool _filtersExpanded = true;

  // Dashboard stats
  int _totalMovies = 0;
  int _totalSeries = 0;
  int _moviesNeedSync = 0;
  int _seriesNeedSync = 0;
  int _ongoingSeries = 0;
  int _endedSeries = 0;
  bool _isStatsLoading = false;

  // ==================== MY POSTS TAB STATE (Task 30, Number 2) ====================
  // Shows the movies/series already in Firestore (i.e. "the admin's posts"),
  // with a search filter and per-card trash-icon delete. Mirrors the UI of
  // BatchPostsScreen but uses cursor-based pagination via getAllPosts()
  // instead of getMoviesByIds() (because here we want ALL posts, not a
  // fixed list from a batch).
  List<Movie> _myPosts = [];
  List<Movie> _myPostsFiltered = [];
  bool _myPostsIsLoading = false;
  bool _myPostsIsLoadingMore = false;
  bool _myPostsHasMore = true;
  DocumentSnapshot? _myPostsLastDoc;
  String _myPostsSearchQuery = '';
  final TextEditingController _myPostsSearchController =
      TextEditingController();
  Timer? _myPostsDebounce;
  // Set to true after the first successful load so we don't keep reloading
  // every time the user taps into the tab. Pull-to-refresh / refresh button
  // will reset this and force a fresh load.
  bool _myPostsLoadedOnce = false;

  // ==================== MY POSTS — PER-POST SYNC STATE (Task 37, Number 4) ====================
  // Tracks which post docIds currently have a single-post TMDB sync running.
  // The Update icon on each card swaps to a small spinner while its id is in
  // the set, so the user sees immediate per-card feedback. The set is also
  // used to disable the trash icon for the same card while a sync is in
  // flight (avoids a race where delete + sync fight over the same doc).
  final Set<String> _myPostsSyncingIds = {};

  // Year list
  static const List<String> _yearOptions = [
    '2025', '2024', '2023', '2022', '2021', '2020',
    '2019', '2018', '2017', '2016', '2015', '2014',
    '2013', '2012', '2011', '2010', '2009', '2008',
    '2007', '2006', '2005', '2004', '2003', '2002',
    '2001', '2000', '1999', '1998', '1997', '1996',
    '1995', '1990', '1985', '1980', '1975', '1970',
  ];

  // Language options — used as `with_original_language` filter for discover API
  // Display language (API `language` param) is always 'en-US' so titles appear in English
  static const List<Map<String, String>> _languageOptions = [
    {'code': '', 'name': 'All Languages'},
    {'code': 'en', 'name': 'English'},
    {'code': 'ja', 'name': 'Japanese'},
    {'code': 'ko', 'name': 'Korean'},
    {'code': 'th', 'name': 'Thai'},
    {'code': 'hi', 'name': 'Hindi'},
    {'code': 'zh', 'name': 'Chinese'},
    {'code': 'fr', 'name': 'French'},
    {'code': 'es', 'name': 'Spanish'},
    {'code': 'de', 'name': 'German'},
  ];

  // Sort options
  static const List<Map<String, String>> _sortOptions = [
    {'value': 'popularity.desc', 'label': 'Popularity'},
    {'value': 'primary_release_date.desc', 'label': 'Release Date'},
    {'value': 'vote_average.desc', 'label': 'Rating'},
  ];

  // Post limit options
  static const List<int> _postLimitOptions = [20, 50, 100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    // Task 30 (Number 2): 3 tabs — Import, Sync From TMDB, My Posts.
    _tabController = TabController(length: 3, vsync: this);
    // Lazy-load My Posts tab on first visit — see _onTabChanged.
    _tabController.addListener(_onTabChanged);
    _loadGenres();
    // Single combined query — see _loadMoviesSnapshot() doc for why.
    _loadMoviesSnapshot();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _myPostsSearchController.dispose();
    _myPostsDebounce?.cancel();
    super.dispose();
  }

  /// Task 30 (Number 2) — lazy-load "My Posts" tab on first visit, so
  /// opening the screen doesn't trigger an extra Firestore query every
  /// time. The user might only ever use Import + Sync, never My Posts.
  void _onTabChanged() {
    // _tabController.indexIsChanging fires twice per change (start + end);
    // only act on the final stable index to avoid double loads.
    if (_tabController.indexIsChanging) return;
    if (_tabController.index == 2 && !_myPostsLoadedOnce && !_myPostsIsLoading) {
      _loadMyPosts(isRefresh: true);
    }
  }

  // ==================== DATA LOADING ====================

  Future<void> _loadGenres() async {
    try {
      final movieGenres = await _tmdbService.getMovieGenres();
      final tvGenres = await _tmdbService.getTVGenres();

      if (mounted) {
        setState(() {
          _movieGenres = movieGenres;
          _tvGenres = tvGenres;
          _updateGenreMap();
        });
      }
    } catch (e) {
      debugPrint('Error loading genres: $e');
    }
  }

  void _updateGenreMap() {
    _genreIdToName = {};
    final genres = _type == 'movie' ? _movieGenres : _tvGenres;
    for (final genre in genres) {
      _genreIdToName[genre['id'] as int] = genre['name'] as String;
    }
  }

  /// =========================================================================
  /// ONE-PASS DATA LOADER (replaces former _loadImportedTmdbIds + _loadDashboardStats)
  /// =========================================================================
  /// BEFORE this fix, opening the TMDB Generator page fired TWO separate
  /// `movies.limit(5000).get()` queries — one in `_loadImportedTmdbIds()`
  /// (extracted only tmdbId for the _importedTmdbIds set) and another in
  /// `_loadDashboardStats()` (computed totalMovies / totalSeries / sync
  /// counters / series status). Both iterated the same 5000 docs.
  ///
  /// Audit finding H1: this doubled Firebase reads on every page open.
  /// Bro reported Firebase usage rising from 4.4% → 19% in one week; this
  /// page was a major contributor since it's opened often during imports.
  ///
  /// NOW: one query, one pass. _importedTmdbIds + all dashboard stats are
  /// populated in the same setState. Callers that previously invoked
  /// `_loadImportedTmdbIds(); _loadDashboardStats();` in pairs now call
  /// `_loadMoviesSnapshot();` once.
  ///
  /// Public aliases `_loadImportedTmdbIds()` and `_loadDashboardStats()`
  /// are kept as thin wrappers so external references (e.g., the refresh
  /// button on line 1131) continue to work without code churn.
  /// =========================================================================
  Future<void> _loadMoviesSnapshot() async {
    if (mounted) setState(() => _isStatsLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('movies')
          .limit(5000)
          .get();

      // Local accumulators — populated in a single pass.
      final importedTmdbIds = <int>{};
      int totalMovies = 0;
      int totalSeries = 0;
      int moviesNeedSync = 0;
      int seriesNeedSync = 0;
      int ongoingSeries = 0;
      int endedSeries = 0;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final rawTmdbId = data['tmdbId'];

        // --- collect tmdbId for _importedTmdbIds ---
        if (rawTmdbId != null) {
          final tmdbId = rawTmdbId is int
              ? rawTmdbId
              : int.tryParse(rawTmdbId.toString());
          if (tmdbId != null && tmdbId > 0) {
            importedTmdbIds.add(tmdbId);
          }
        }

        // --- compute dashboard stats ---
        final type = data['type']?.toString();
        if (type == 'movie') {
          totalMovies++;
          // Need sync: has tmdbId but no lastSyncDate
          if (rawTmdbId != null && rawTmdbId is int && rawTmdbId > 0) {
            if (!data.containsKey('lastSyncDate')) {
              moviesNeedSync++;
            }
          }
        } else if (type == 'series') {
          totalSeries++;
          // Need sync: has tmdbId but no lastSyncDate
          if (rawTmdbId != null && rawTmdbId is int && rawTmdbId > 0) {
            if (!data.containsKey('lastSyncDate')) {
              seriesNeedSync++;
            }
          }
          // Check series status
          final status = data['status']?.toString() ?? '';
          if (status == 'Returning Series') {
            ongoingSeries++;
          } else if (status == 'Ended' || status == 'Canceled') {
            endedSeries++;
          }
        }
      }

      if (mounted) {
        setState(() {
          _importedTmdbIds
            ..clear()
            ..addAll(importedTmdbIds);
          _totalMovies = totalMovies;
          _totalSeries = totalSeries;
          _moviesNeedSync = moviesNeedSync;
          _seriesNeedSync = seriesNeedSync;
          _ongoingSeries = ongoingSeries;
          _endedSeries = endedSeries;
          _syncRemainingMovies = moviesNeedSync;
          _syncRemainingSeries = seriesNeedSync;
          _isStatsLoading = false;
        });
        debugPrint('Movies snapshot loaded: '
            '${_importedTmdbIds.length} tmdbIds, '
            '$totalMovies movies, $totalSeries series, '
            '$moviesNeedSync movies need sync, $seriesNeedSync series need sync');
      }
    } catch (e) {
      debugPrint('Error loading movies snapshot: $e');
      if (mounted) {
        setState(() => _isStatsLoading = false);
      }
    }
  }

  /// Thin wrapper kept for backward compatibility with existing call sites
  /// (e.g. the refresh button on the dashboard). Always refreshes BOTH the
  /// imported tmdbId set AND the dashboard stats in a single Firestore query.
  Future<void> _loadImportedTmdbIds() => _loadMoviesSnapshot();

  /// Thin wrapper kept for backward compatibility. Always refreshes BOTH
  /// the imported tmdbId set AND the dashboard stats in a single query.
  Future<void> _loadDashboardStats() => _loadMoviesSnapshot();

  // ==================== SEARCH & IMPORT ====================

  Future<void> _performSearch() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _results.clear();
      _selectedIds.clear();
      _currentPage = 1;
    });

    try {
      final query = _searchController.text.trim();
      Map<String, dynamic> response;

      final originalLang = _selectedLanguage.isNotEmpty ? _selectedLanguage : null;

      if (query.isNotEmpty) {
        _isSearching = true;
        response = _type == 'movie'
            ? await _tmdbService.searchMovies(query, page: 1)
            : await _tmdbService.searchTV(query, page: 1);
      } else {
        _isSearching = false;
        final sortKey = _type == 'movie'
            ? _selectedSortBy
            : _selectedSortBy.replaceAll('primary_release_date', 'first_air_date');

        response = _type == 'movie'
            ? await _tmdbService.discoverMovies(
                genre: _selectedGenreId,
                year: _selectedYear,
                language: 'en-US',
                originalLanguage: originalLang,
                sortBy: sortKey,
                page: 1,
              )
            : await _tmdbService.discoverTV(
                genre: _selectedGenreId,
                year: _selectedYear,
                language: 'en-US',
                originalLanguage: originalLang,
                sortBy: sortKey,
                page: 1,
              );
      }

      final rawResults = List<Map<String, dynamic>>.from(response['results'] ?? []);

      final results = rawResults.where((item) {
        final id = item['id'];
        return id == null || !_importedTmdbIds.contains(id);
      }).toList();

      if (mounted) {
        setState(() {
          _results = results;
          _totalPages = (response['total_pages'] ?? 1) as int;
          _totalResults = (response['total_results'] ?? 0) as int;
          _isLoading = false;
        });
      }

      if (_postLimit > 20 && results.length < _postLimit) {
        await _loadMorePages();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to search: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMorePages() async {
    final maxPages = (_postLimit / 20).ceil();
    for (int page = 2; page <= maxPages && page <= _totalPages; page++) {
      try {
        final query = _searchController.text.trim();
        Map<String, dynamic> response;

        final originalLang = _selectedLanguage.isNotEmpty ? _selectedLanguage : null;

        if (_isSearching) {
          response = _type == 'movie'
              ? await _tmdbService.searchMovies(query, page: page)
              : await _tmdbService.searchTV(query, page: page);
        } else {
          final sortKey = _type == 'movie'
              ? _selectedSortBy
              : _selectedSortBy.replaceAll('primary_release_date', 'first_air_date');

          response = _type == 'movie'
              ? await _tmdbService.discoverMovies(
                  genre: _selectedGenreId,
                  year: _selectedYear,
                  language: 'en-US',
                  originalLanguage: originalLang,
                  sortBy: sortKey,
                  page: page,
                )
              : await _tmdbService.discoverTV(
                  genre: _selectedGenreId,
                  year: _selectedYear,
                  language: 'en-US',
                  originalLanguage: originalLang,
                  sortBy: sortKey,
                  page: page,
                );
        }

        final rawMoreResults = List<Map<String, dynamic>>.from(response['results'] ?? []);
        final moreResults = rawMoreResults.where((item) {
          final id = item['id'];
          return id == null || !_importedTmdbIds.contains(id);
        }).toList();
        if (mounted) {
          setState(() {
            _results.addAll(moreResults);
          });
        }

        if (_results.length >= _postLimit) break;
      } catch (e) {
        debugPrint('Error loading page $page: $e');
        break;
      }
    }

    if (mounted && _results.length > _postLimit) {
      setState(() {
        _results = _results.sublist(0, _postLimit);
      });
    }
  }

  Future<void> _importSelected() async {
    final selected = _selectedIds.toList();
    if (selected.isEmpty) return;

    final notYetImported = selected.where((id) => !_importedTmdbIds.contains(id)).toList();
    final alreadyImportedCount = selected.length - notYetImported.length;

    if (notYetImported.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('All $alreadyImportedCount ${_type == 'movie' ? 'movie' : 'series'}${alreadyImportedCount > 1 ? 's' : ''} already imported!'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Confirmation'),
        content: Text(
          'Import ${notYetImported.length} ${_type == 'movie' ? 'movie' : 'series'}${notYetImported.length > 1 ? 's' : ''} from TMDB to Firestore?'
          '${alreadyImportedCount > 0 ? '\n\n($alreadyImportedCount already imported — skipped)' : ''}'
          '\n\nThis will fetch full details for each item and save them to your database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            child: const Text('Import', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importTotal = notYetImported.length;
      _importSuccessCount = 0;
      _importFailureCount = 0;
      _importCurrentTitle = '';
    });

    for (int i = 0; i < notYetImported.length; i++) {
      final tmdbId = notYetImported[i];
      final resultItem = _results.firstWhere(
        (r) => r['id'] == tmdbId,
        orElse: () => <String, dynamic>{},
      );
      final itemTitle = resultItem['title']?.toString() ?? resultItem['name']?.toString() ?? 'Unknown';

      setState(() {
        _importProgress = i + 1;
        _importCurrentTitle = itemTitle;
      });

      try {
        final existingDoc = await _contentService.findByTmdbId(tmdbId);
        if (existingDoc != null) {
          debugPrint('SKIP IMPORT: tmdbId $tmdbId ($itemTitle) already exists in Firestore (doc: ${existingDoc.id})');
          if (mounted) {
            setState(() {
              _importedTmdbIds.add(tmdbId);
            });
          }
          continue;
        }

        Map<String, dynamic> fullDetails;
        Map<String, dynamic> firestoreData;

        if (_type == 'movie') {
          fullDetails = await _tmdbService.getMovieDetails(tmdbId);
          if (!fullDetails.containsKey('genre_ids') && fullDetails.containsKey('genres')) {
            fullDetails['genre_ids'] = (fullDetails['genres'] as List)
                .map((g) => g['id'])
                .toList();
          }
          firestoreData = TmdbService.mapMovieToFirestore(fullDetails, _genreIdToName);
        } else {
          fullDetails = await _tmdbService.getTVDetails(tmdbId);
          if (!fullDetails.containsKey('genre_ids') && fullDetails.containsKey('genres')) {
            fullDetails['genre_ids'] = (fullDetails['genres'] as List)
                .map((g) => g['id'])
                .toList();
          }
          firestoreData = TmdbService.mapTVToFirestore(fullDetails, _genreIdToName);
        }

        debugPrint('IMPORT: tmdbId=$tmdbId title=${firestoreData['title']} duration=${firestoreData['duration']}');

        await _contentService.addMovie(firestoreData);

        if (mounted) {
          setState(() {
            _importSuccessCount++;
            _importedTmdbIds.add(tmdbId);
          });
        }
      } catch (e) {
        debugPrint('Error importing tmdbId $tmdbId: $e');
        if (mounted) {
          setState(() {
            _importFailureCount++;
          });
        }
      }
    }

    if (mounted) {
      setState(() {
        _isImporting = false;
        _selectedIds.clear();
      });

      // Single combined query (replaces the former pair).
      _loadMoviesSnapshot();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import complete! Success: $_importSuccessCount, Failed: $_importFailureCount'
            '${alreadyImportedCount > 0 ? ', Skipped: $alreadyImportedCount' : ''}',
          ),
          backgroundColor: _importFailureCount > 0 ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ==================== SYNC OPERATIONS ====================

  /// Public: Sync Movies with confirmation dialog
  Future<void> _syncMovies() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync Movies'),
        content: Text(
          'This will sync up to $_syncBatchSize movies from TMDB that have a tmdbId and update their data in Firestore.\n\n'
          'Movies that have never been synced or have an older sync date are prioritized.\n\n'
          'Overview/description will NOT be updated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            child: const Text('Sync', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _doSyncMovies();
  }

  /// Internal: Execute movie sync without confirmation dialog
  Future<void> _doSyncMovies() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('movies')
          .where('type', isEqualTo: 'movie')
          .limit(5000)
          .get();

      final docs = snapshot.docs.where((doc) {
        final tmdbId = doc.data()['tmdbId'] as int?;
        return tmdbId != null && tmdbId > 0;
      }).toList();

      docs.sort((a, b) {
        final aSync = a.data()['lastSyncDate'] as Timestamp?;
        final bSync = b.data()['lastSyncDate'] as Timestamp?;
        if (aSync == null && bSync == null) return 0;
        if (aSync == null) return -1;
        if (bSync == null) return 1;
        return aSync.compareTo(bSync);
      });

      final batchDocs = docs.take(_syncBatchSize).toList();
      final totalRemaining = docs.length;

      if (batchDocs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No movies with tmdbId found to sync.')),
          );
        }
        return;
      }

      setState(() {
        _isSyncing = true;
        _syncProgress = 0;
        _syncTotal = batchDocs.length;
        _syncSuccessCount = 0;
        _syncFailureCount = 0;
        _syncCurrentTitle = '';
        _syncRemainingMovies = totalRemaining - batchDocs.length;
      });

      final syncItems = <Map<String, dynamic>>[];
      for (int i = 0; i < batchDocs.length; i++) {
        final doc = batchDocs[i];
        final data = doc.data();
        final tmdbId = data['tmdbId'] as int?;
        final title = data['title']?.toString() ?? 'Unknown';
        if (tmdbId != null && tmdbId > 0) {
          syncItems.add({
            'docId': doc.id,
            'tmdbId': tmdbId,
            'title': title,
          });
        }
      }

      for (int i = 0; i < syncItems.length; i++) {
        final docId = syncItems[i]['docId'] as String;
        final tmdbId = syncItems[i]['tmdbId'] as int;
        final title = syncItems[i]['title'] as String;

        setState(() {
          _syncProgress = i + 1;
          _syncCurrentTitle = title;
        });

        try {
          debugPrint('SYNC MOVIE [$i/${syncItems.length}]: docId=$docId tmdbId=$tmdbId title=$title');

          final fullDetails = await _tmdbService.getMovieDetails(tmdbId);
          final fetchedTitle = fullDetails['title']?.toString() ?? 'Unknown';
          debugPrint('SYNC MOVIE: TMDB returned title="$fetchedTitle" for tmdbId=$tmdbId');

          if (!fullDetails.containsKey('genre_ids') && fullDetails.containsKey('genres')) {
            fullDetails['genre_ids'] = (fullDetails['genres'] as List)
                .map((g) => g['id'])
                .toList();
          }

          final firestoreData = TmdbService.mapMovieToFirestore(fullDetails, _genreIdToName);

          final safeUpdate = <String, dynamic>{};
          for (final key in ['title', 'year', 'poster', 'backdrop', 'rating',
              'duration', 'isAdult', 'categories', 'directors', 'casts',
              'tmdbId', 'country']) {
            if (firestoreData.containsKey(key)) {
              safeUpdate[key] = firestoreData[key];
            }
          }

          // NEVER update overview during sync
          // (overview is intentionally excluded from safeUpdate)

          debugPrint('SYNC MOVIE: safeUpdate title=${safeUpdate['title']} tmdbId=${safeUpdate['tmdbId']} duration=${safeUpdate['duration']}');

          final currentDoc = await FirebaseFirestore.instance
              .collection('movies')
              .doc(docId)
              .get();
          if (currentDoc.exists) {
            final currentData = currentDoc.data() as Map<String, dynamic>;
            final currentTmdbId = currentData['tmdbId'];
            final currentTitle = currentData['title'];
            if (currentTmdbId != tmdbId) {
              debugPrint('SKIP: Doc $docId tmdbId mismatch (expected=$tmdbId, actual=$currentTmdbId title=$currentTitle)');
              setState(() => _syncFailureCount++);
              continue;
            }
            await FirebaseFirestore.instance.runTransaction((transaction) async {
              final freshDoc = await transaction.get(
                FirebaseFirestore.instance.collection('movies').doc(docId),
              );
              if (!freshDoc.exists) return;
              final freshTmdbId = (freshDoc.data() as Map<String, dynamic>)['tmdbId'];
              if (freshTmdbId != tmdbId) {
                debugPrint('TX SKIP: Doc $docId tmdbId changed during sync (expected=$tmdbId, actual=$freshTmdbId)');
                return;
              }
              safeUpdate['updatedAt'] = FieldValue.serverTimestamp();
              safeUpdate['lastSyncDate'] = FieldValue.serverTimestamp();
              transaction.update(
                FirebaseFirestore.instance.collection('movies').doc(docId),
                safeUpdate,
              );
            });
          } else {
            debugPrint('SKIP: Doc $docId no longer exists');
            setState(() => _syncFailureCount++);
            continue;
          }

          debugPrint('SYNC MOVIE SUCCESS: docId=$docId tmdbId=$tmdbId title=${safeUpdate['title']}');
          setState(() => _syncSuccessCount++);
        } catch (e) {
          debugPrint('Error syncing movie $tmdbId (docId=$docId): $e');
          setState(() => _syncFailureCount++);
        }
      }

      if (mounted) {
        setState(() => _isSyncing = false);
        // Single combined query (replaces the former pair).
        _loadMoviesSnapshot();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Movie sync batch complete! Success: $_syncSuccessCount, Failed: $_syncFailureCount\n$_syncRemainingMovies remaining to sync',
            ),
            backgroundColor: _syncFailureCount > 0 ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Public: Sync Series with confirmation dialog
  Future<void> _syncSeries() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync Series'),
        content: Text(
          'This will sync up to $_syncBatchSize series from TMDB that have a tmdbId and update their data in Firestore.\n\n'
          'Series that have never been synced or have an older sync date are prioritized.\n\n'
          'Overview/description will NOT be updated. Episode counts for ongoing seasons will be refreshed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            child: const Text('Sync', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _doSyncSeries();
  }

  /// Internal: Execute series sync without confirmation dialog
  Future<void> _doSyncSeries() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('movies')
          .where('type', isEqualTo: 'series')
          .limit(5000)
          .get();

      final docs = snapshot.docs.where((doc) {
        final tmdbId = doc.data()['tmdbId'] as int?;
        return tmdbId != null && tmdbId > 0;
      }).toList();

      docs.sort((a, b) {
        final aSync = a.data()['lastSyncDate'] as Timestamp?;
        final bSync = b.data()['lastSyncDate'] as Timestamp?;
        if (aSync == null && bSync == null) return 0;
        if (aSync == null) return -1;
        if (bSync == null) return 1;
        return aSync.compareTo(bSync);
      });

      final batchDocs = docs.take(_syncBatchSize).toList();
      final totalRemaining = docs.length;

      if (batchDocs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No series with tmdbId found to sync.')),
          );
        }
        return;
      }

      setState(() {
        _isSyncing = true;
        _syncProgress = 0;
        _syncTotal = batchDocs.length;
        _syncSuccessCount = 0;
        _syncFailureCount = 0;
        _syncCurrentTitle = '';
        _syncRemainingSeries = totalRemaining - batchDocs.length;
      });

      final syncItems = <Map<String, dynamic>>[];
      for (int i = 0; i < batchDocs.length; i++) {
        final doc = batchDocs[i];
        final data = doc.data();
        final tmdbId = data['tmdbId'] as int?;
        final title = data['title']?.toString() ?? 'Unknown';
        if (tmdbId != null && tmdbId > 0) {
          syncItems.add({
            'docId': doc.id,
            'tmdbId': tmdbId,
            'title': title,
          });
        }
      }

      for (int i = 0; i < syncItems.length; i++) {
        final docId = syncItems[i]['docId'] as String;
        final tmdbId = syncItems[i]['tmdbId'] as int;
        final title = syncItems[i]['title'] as String;

        setState(() {
          _syncProgress = i + 1;
          _syncCurrentTitle = title;
        });

        try {
          debugPrint('SYNC SERIES [$i/${syncItems.length}]: docId=$docId tmdbId=$tmdbId title=$title');

          final fullDetails = await _tmdbService.getTVDetails(tmdbId);
          final fetchedTitle = fullDetails['name']?.toString() ?? 'Unknown';
          debugPrint('SYNC SERIES: TMDB returned title="$fetchedTitle" for tmdbId=$tmdbId');

          if (!fullDetails.containsKey('genre_ids') && fullDetails.containsKey('genres')) {
            fullDetails['genre_ids'] = (fullDetails['genres'] as List)
                .map((g) => g['id'])
                .toList();
          }

          final firestoreData = TmdbService.mapTVToFirestore(fullDetails, _genreIdToName);

          final safeUpdate = <String, dynamic>{};
          for (final key in ['title', 'year', 'poster', 'backdrop', 'rating',
              'duration', 'isAdult', 'categories', 'directors', 'casts',
              'tmdbId', 'country', 'status']) {
            if (firestoreData.containsKey(key)) {
              safeUpdate[key] = firestoreData[key];
            }
          }

          // NEVER update overview, seasons, downloadLinks, watchLinks during sync
          // (these are intentionally excluded to preserve user's custom data)

          debugPrint('SYNC SERIES: safeUpdate title=${safeUpdate['title']} tmdbId=${safeUpdate['tmdbId']} duration=${safeUpdate['duration']} status=${safeUpdate['status']}');

          final currentDoc = await FirebaseFirestore.instance
              .collection('movies')
              .doc(docId)
              .get();
          if (currentDoc.exists) {
            final currentData = currentDoc.data() as Map<String, dynamic>;
            final currentTmdbId = currentData['tmdbId'];
            final currentTitle = currentData['title'];
            if (currentTmdbId != tmdbId) {
              debugPrint('SKIP: Doc $docId tmdbId mismatch (expected=$tmdbId, actual=$currentTmdbId title=$currentTitle)');
              setState(() => _syncFailureCount++);
              continue;
            }
            await FirebaseFirestore.instance.runTransaction((transaction) async {
              final freshDoc = await transaction.get(
                FirebaseFirestore.instance.collection('movies').doc(docId),
              );
              if (!freshDoc.exists) return;
              final freshTmdbId = (freshDoc.data() as Map<String, dynamic>)['tmdbId'];
              if (freshTmdbId != tmdbId) {
                debugPrint('TX SKIP: Doc $docId tmdbId changed during sync (expected=$tmdbId, actual=$freshTmdbId)');
                return;
              }
              safeUpdate['updatedAt'] = FieldValue.serverTimestamp();
              safeUpdate['lastSyncDate'] = FieldValue.serverTimestamp();
              transaction.update(
                FirebaseFirestore.instance.collection('movies').doc(docId),
                safeUpdate,
              );
            });
          } else {
            debugPrint('SKIP: Doc $docId no longer exists');
            setState(() => _syncFailureCount++);
            continue;
          }

          debugPrint('SYNC SERIES SUCCESS: docId=$docId tmdbId=$tmdbId title=${safeUpdate['title']}');
          setState(() => _syncSuccessCount++);
        } catch (e) {
          debugPrint('Error syncing series $tmdbId (docId=$docId): $e');
          setState(() => _syncFailureCount++);
        }
      }

      if (mounted) {
        setState(() => _isSyncing = false);
        // Single combined query (replaces the former pair).
        _loadMoviesSnapshot();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Series sync batch complete! Success: $_syncSuccessCount, Failed: $_syncFailureCount\n$_syncRemainingSeries remaining to sync',
            ),
            backgroundColor: _syncFailureCount > 0 ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Sync All: runs both movie and series sync sequentially
  Future<void> _syncAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync All'),
        content: Text(
          'This will sync up to $_syncBatchSize movies AND $_syncBatchSize series from TMDB.\n\n'
          'Metadata (rating, poster, backdrop, categories) will be updated, but overview/description will NOT be changed.\n\n'
          'For ongoing series, episode counts will also be refreshed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            child: const Text('Sync All', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Run movie sync, then series sync (no extra confirmation dialogs)
    await _doSyncMovies();
    if (mounted && !_isSyncing) {
      await _doSyncSeries();
    }
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search TMDB'),
        content: NoToolbarOnSingleTapTextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter movie or series title...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onSubmitted: (_) {
            Navigator.pop(ctx);
            _performSearch();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performSearch();
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: !_isImporting && !_isSyncing,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : null,
        appBar: AppBar(
          title: const Text('TMDB Generator'),
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.cloud_download, size: 18),
                text: 'Import',
              ),
              Tab(
                icon: Icon(Icons.sync, size: 18),
                text: 'Sync From TMDB',
              ),
              // Task 30 (Number 2): "My Posts" tab — view + delete already-
              // imported movies/series. Trash icon overlay on each card.
              Tab(
                icon: Icon(Icons.video_library, size: 18),
                text: 'My Posts',
              ),
            ],
            indicatorColor: const Color(0xFFE50914),
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
          ),
          actions: [
            // Search icon
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _isImporting || _isSyncing ? null : _showSearchDialog,
            ),
            // Refresh
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isImporting || _isSyncing
                  ? null
                  : () {
                      // Single combined query (replaces the former pair).
                      _loadMoviesSnapshot();
                    },
              tooltip: 'Refresh status',
            ),
            // Selected count + Import button (only on Import tab)
            if (_selectedIds.isNotEmpty && _tabController.index == 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Center(
                  child: ElevatedButton.icon(
                    onPressed: _isImporting ? null : _importSelected,
                    icon: const Icon(Icons.download, size: 18),
                    label: Text('${_selectedIds.length}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE50914),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: Size.zero,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: _isImporting
            ? _buildImportProgress()
            : _isSyncing
                ? _buildSyncProgress()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // Tab 1: Import
                      _buildImportTab(isDark),
                      // Tab 2: Sync Dashboard
                      _buildSyncDashboardTab(isDark),
                      // Tab 3 (Task 30, Number 2): My Posts — view + delete.
                      _buildMyPostsTab(isDark),
                    ],
                  ),
      ),
    );
  }

  // ==================== IMPORT TAB ====================

  Widget _buildImportTab(bool isDark) {
    return Column(
      children: [
        _buildFilterSection(isDark),
        _buildActionBar(isDark),
        Expanded(child: _buildResultsGrid(isDark)),
      ],
    );
  }

  // ==================== MY POSTS TAB (Task 30, Number 2) ====================
  //
  // Shows every movie/series already in Firestore, in updatedAt-desc order.
  // Layout mirrors BatchPostsScreen (3-col grid, childAspectRatio 0.53) so
  // the visual is consistent with the Batch Import → View Created Posts grid
  // — Bro already knows that UX. Differences vs. BatchPostsScreen:
  //   - Uses cursor-based pagination (getAllPosts) instead of getMoviesByIds,
  //     because here we want EVERY post, not a fixed list from a batch.
  //   - "Load more" infinite scroll at the bottom (no fixed count).
  //   - Pull-to-refresh via RefreshIndicator.
  //   - Search is client-side, same as BatchPostsScreen.

  Future<void> _loadMyPosts({bool isRefresh = false}) async {
    if (_myPostsIsLoading) return;
    if (isRefresh) {
      // Reset state for a fresh load.
      setState(() {
        _myPostsIsLoading = true;
        _myPosts = [];
        _myPostsFiltered = [];
        _myPostsHasMore = true;
        _myPostsLastDoc = null;
        _myPostsLoadedOnce = true;
      });
    } else {
      if (!_myPostsHasMore || _myPostsIsLoadingMore) return;
      setState(() => _myPostsIsLoadingMore = true);
    }

    try {
      final result = await _contentService.getAllPosts(
        limit: 30,
        startAfter: isRefresh ? null : _myPostsLastDoc,
      );
      final newMovies = (result['movies'] as List).cast<Movie>();
      final hasMore = result['hasMore'] as bool;
      final lastDoc = result['lastDoc'] as DocumentSnapshot?;

      if (mounted) {
        setState(() {
          if (isRefresh) {
            _myPosts = newMovies;
          } else {
            // De-dup by doc ID — if the user added/edited a movie since the
            // last page loaded, it might appear at the top of the next page
            // AND in our existing list (because updatedAt bumped). Filter
            // those out so the grid doesn't show duplicates.
            final seenIds = _myPosts.map((m) => m.id).toSet();
            _myPosts.addAll(
              newMovies.where((m) => !seenIds.contains(m.id)),
            );
          }
          _myPostsHasMore = hasMore;
          _myPostsLastDoc = lastDoc;
          _myPostsIsLoading = false;
          _myPostsIsLoadingMore = false;
          _applyMyPostsFilter();
        });
      }
    } catch (e) {
      debugPrint('MyPosts _loadMyPosts failed: $e');
      if (mounted) {
        setState(() {
          _myPostsIsLoading = false;
          _myPostsIsLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load posts: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Apply the current search query to [_myPosts], populating
  /// [_myPostsFiltered]. Called on every load + every search keystroke.
  void _applyMyPostsFilter() {
    final q = _myPostsSearchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      _myPostsFiltered = List.of(_myPosts);
    } else {
      _myPostsFiltered = _myPosts
          .where((m) => m.title.toLowerCase().contains(q))
          .toList();
    }
  }

  /// Delete a single post from Firestore, then remove it from both
  /// [_myPosts] and [_myPostsFiltered]. Mirrors the delete flow in
  /// BatchPostsScreen so the UX is identical across the two screens.
  Future<void> _deleteMyPost(Movie movie) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: Text(
          'Delete "${movie.title}"?\n\n'
          'This permanently removes the post from Firestore. '
          'This action cannot be undone.',
        ),
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
      await _contentService.deleteMovie(movie.id);
      if (mounted) {
        setState(() {
          _myPosts.removeWhere((m) => m.id == movie.id);
          _myPostsFiltered.removeWhere((m) => m.id == movie.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${movie.title}"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('MyPosts _deleteMyPost failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete "${movie.title}": $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ==================== MY POSTS — PER-POST SYNC (Task 37, Number 4) ====================
  //
  // Single-post TMDB sync, invoked by tapping the Update icon on a card in
  // the My Posts tab. Reuses the EXACT same per-doc logic that
  // `_doSyncMovies()` / `_doSyncSeries()` use for batch sync, so behavior
  // (which fields are updated, transaction safety, lastSyncDate stamp) is
  // identical. The only differences are:
  //   1. We read tmdbId + type from Firestore by docId (the Movie model
  //      doesn't expose tmdbId), so we don't depend on the in-memory
  //      object being fresh.
  //   2. We refresh only the affected entry in `_myPosts` on success
  //      instead of triggering a full `_loadMyPosts(isRefresh: true)`.
  //      This is much cheaper (no extra Firestore query) and keeps the
  //      scroll position stable.
  //   3. We track in-flight state via `_myPostsSyncingIds` so the card
  //      shows a per-card spinner and the trash icon is disabled while
  //      the sync is running.

  /// Show a confirmation dialog, then run `_doSyncSinglePost`.
  Future<void> _syncSinglePost(Movie movie) async {
    // Refuse if already syncing this same post (user double-tapped).
    if (_myPostsSyncingIds.contains(movie.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update from TMDB'),
        content: Text(
          'Refresh metadata for "${movie.title}" from TMDB?\n\n'
          'This will update: title, year, poster, backdrop, rating, '
          'duration, isAdult, categories, directors, casts, country'
          '${movie.type == 'series' ? ', status' : ''}.\n\n'
          'Overview/description will NOT be overwritten. '
          '${movie.type == 'series' ? 'Seasons, downloadLinks, watchLinks will NOT be overwritten. ' : ''}'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
            ),
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _doSyncSinglePost(movie);
  }

  /// Internal: execute the single-post sync. Throws are caught here and
  /// surfaced via SnackBar; the caller (`_syncSinglePost`) does not need
  /// its own try/catch.
  Future<void> _doSyncSinglePost(Movie movie) async {
    final docId = movie.id;
    if (docId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot sync: post has no document id.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _myPostsSyncingIds.add(docId));
    try {
      // 1) Read the current doc to get tmdbId + type. The Movie model
      //    doesn't expose tmdbId, and type may have been changed by an
      //    admin edit since the list was loaded — read fresh.
      final docSnap = await FirebaseFirestore.instance
          .collection('movies')
          .doc(docId)
          .get();
      if (!docSnap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${movie.title}" no longer exists.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final data = docSnap.data() as Map<String, dynamic>;
      final rawTmdbId = data['tmdbId'];
      final int? tmdbId = rawTmdbId is int
          ? rawTmdbId
          : rawTmdbId == null
              ? null
              : int.tryParse(rawTmdbId.toString());
      if (tmdbId == null || tmdbId <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '"${movie.title}" has no TMDB id — cannot sync from TMDB. '
                'This post was likely added via Batch Import without a tmdbId.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      final String docType =
          (data['type']?.toString() ?? movie.type ?? 'movie').toLowerCase();
      final isSeries = docType == 'series';

      // 2) Fetch fresh details from TMDB.
      final fullDetails = isSeries
          ? await _tmdbService.getTVDetails(tmdbId)
          : await _tmdbService.getMovieDetails(tmdbId);

      // 3) Normalize genre_ids (TMDB /movie/{id} and /tv/{id} return full
      //    genre objects under `genres`, but the mapper expects
      //    `genre_ids`).
      if (!fullDetails.containsKey('genre_ids') &&
          fullDetails.containsKey('genres')) {
        fullDetails['genre_ids'] = (fullDetails['genres'] as List)
            .map((g) => g['id'])
            .toList();
      }

      // 4) Map to Firestore schema using the same static mappers as batch
      //    sync.
      final firestoreData = isSeries
          ? TmdbService.mapTVToFirestore(fullDetails, _genreIdToName)
          : TmdbService.mapMovieToFirestore(fullDetails, _genreIdToName);

      // 5) Build the safeUpdate map — identical key list to batch sync so
      //    the behavior matches exactly. Overview, seasons, downloadLinks,
      //    watchLinks are intentionally excluded.
      final safeUpdate = <String, dynamic>{};
      final allowedKeys = isSeries
          ? const [
              'title', 'year', 'poster', 'backdrop', 'rating',
              'duration', 'isAdult', 'categories', 'directors', 'casts',
              'tmdbId', 'country', 'status',
            ]
          : const [
              'title', 'year', 'poster', 'backdrop', 'rating',
              'duration', 'isAdult', 'categories', 'directors', 'casts',
              'tmdbId', 'country',
            ];
      for (final key in allowedKeys) {
        if (firestoreData.containsKey(key)) {
          safeUpdate[key] = firestoreData[key];
        }
      }

      // 6) Transactional update — re-read inside the tx to confirm tmdbId
      //    still matches (same safety check as batch sync).
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final freshDoc = await transaction.get(
          FirebaseFirestore.instance.collection('movies').doc(docId),
        );
        if (!freshDoc.exists) return;
        final freshData = freshDoc.data() as Map<String, dynamic>;
        final freshTmdbIdRaw = freshData['tmdbId'];
        final int? freshTmdbId = freshTmdbIdRaw is int
            ? freshTmdbIdRaw
            : freshTmdbIdRaw == null
                ? null
                : int.tryParse(freshTmdbIdRaw.toString());
        if (freshTmdbId != tmdbId) {
          debugPrint('TX SKIP: Doc $docId tmdbId changed during sync '
              '(expected=$tmdbId, actual=$freshTmdbId)');
          return;
        }
        safeUpdate['updatedAt'] = FieldValue.serverTimestamp();
        safeUpdate['lastSyncDate'] = FieldValue.serverTimestamp();
        transaction.update(
          FirebaseFirestore.instance.collection('movies').doc(docId),
          safeUpdate,
        );
      });

      // 7) Refresh ONLY this post in the in-memory list — re-read the doc
      //    so we get the server timestamps + any other fields. This avoids
      //    a full _loadMyPosts() that would reset pagination + scroll.
      final refreshedSnap = await FirebaseFirestore.instance
          .collection('movies')
          .doc(docId)
          .get();
      if (refreshedSnap.exists && mounted) {
        final refreshedMovie = Movie.fromMap(
          refreshedSnap.data() as Map<String, dynamic>,
          docId: refreshedSnap.id,
        );
        setState(() {
          final idx = _myPosts.indexWhere((m) => m.id == docId);
          if (idx >= 0) _myPosts[idx] = refreshedMovie;
          final fIdx = _myPostsFiltered.indexWhere((m) => m.id == docId);
          if (fIdx >= 0) _myPostsFiltered[fIdx] = refreshedMovie;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Updated "${movie.title}" from TMDB.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('MyPosts _doSyncSinglePost failed for docId=$docId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update "${movie.title}": $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _myPostsSyncingIds.remove(docId));
      } else {
        _myPostsSyncingIds.remove(docId);
      }
    }
  }

  void _navigateToDetailFromMyPosts(Movie movie) {
    final isSeries = movie.type == 'series';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isSeries
            ? SeriesDetailScreen(slug: movie.slug)
            : MovieDetailScreen(slug: movie.slug),
      ),
    ).then((_) {
      // Refresh on return — the user might have edited/deleted the
      // movie from inside the detail screen.
      if (mounted) _loadMyPosts(isRefresh: true);
    });
  }

  void _onMyPostsSearchChanged(String value) {
    _myPostsDebounce?.cancel();
    _myPostsDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _myPostsSearchQuery = value;
          _applyMyPostsFilter();
        });
      }
    });
  }

  /// Build the per-card Update icon for the My Posts tab (Task 37, Number 4).
  ///
  /// ALWAYS shown — the Movie model doesn't expose `tmdbId`, so we can't
  /// hide the icon based on sync eligibility without an extra Firestore
  /// read per card. If the user taps it on a post without a tmdbId, the
  /// helper shows a friendly orange SnackBar explaining why. This is
  /// better than either hiding the icon based on a guess or paying a
  /// read per card just to decide whether to show it.
  ///
  /// When [isSyncing] is true, the icon is replaced by a small white
  /// CircularProgressIndicator and the GestureDetector's onTap is null so
  /// taps are ignored. The container keeps the same size + border so the
  /// card layout doesn't shift between states.
  Widget _buildUpdateIcon(Movie movie, bool isSyncing) {
    // The Movie model doesn't expose tmdbId; we infer sync eligibility
    // from the post's source. Posts imported via TMDB or Batch Import
    // with a tmdbId set will have it in Firestore, but we can't see it
    // from the model. Conservative behavior: ALWAYS show the icon. If
    // the user taps it and the doc turns out to have no tmdbId, the
    // helper shows a friendly orange SnackBar explaining why. This is
    // better than hiding the icon based on a guess (the guess would
    // always say "no tmdbId" because the field isn't on the model).
    //
    // The icon is sized + styled to match the trash icon on the right
    // for visual symmetry.
    return GestureDetector(
      onTap: isSyncing ? null : () => _syncSinglePost(movie),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSyncing
                ? Colors.white24
                : const Color(0xFFE50914), // brand red
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: isSyncing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.sync,
                color: Colors.white,
                size: 16,
              ),
      ),
    );
  }

  /// Build the "My Posts" tab body. Structure mirrors BatchPostsScreen:
  /// AppBar-style header row (count + refresh), search bar, hint row,
  /// then the 3-col grid with trash-icon overlay on each card.
  Widget _buildMyPostsTab(bool isDark) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Header row — count + refresh button.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Icon(Icons.video_library,
                  color: Color(0xFFE50914), size: 18),
              const SizedBox(width: 8),
              Text(
                _myPostsSearchQuery.trim().isEmpty
                    ? 'My Posts (${_myPosts.length}'
                        '${_myPostsHasMore ? '+' : ''})'
                    : 'My Posts (${_myPostsFiltered.length}/${_myPosts.length})',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_myPostsIsLoading || _myPostsIsLoadingMore)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFE50914),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => _loadMyPosts(isRefresh: true),
                  tooltip: 'Refresh posts',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),

        // Search bar — client-side filter on title.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: NoToolbarOnSingleTapTextField(
            controller: _myPostsSearchController,
            onChanged: _onMyPostsSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search by title...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _myPostsSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _myPostsSearchController.clear();
                        _onMyPostsSearchChanged('');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE50914)),
              ),
            ),
          ),
        ),

        // Hint row — explains the two action icons on each card.
        if (_myPostsFiltered.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sync icon (left): update from TMDB.  '
                    'Trash icon (right): delete post.',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Grid of movie cards with delete overlay.
        Expanded(
          child: _myPostsIsLoading && _myPosts.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _myPostsFiltered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _myPostsSearchQuery.trim().isEmpty
                                ? Icons.video_library_outlined
                                : Icons.search_off,
                            size: 56,
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.3),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _myPostsSearchQuery.trim().isEmpty
                                ? 'No posts yet. Import some from the Import tab.'
                                : 'No posts match your search.',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.5),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (_myPostsSearchQuery.trim().isEmpty) ...[
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                _tabController.animateTo(0);
                              },
                              icon: const Icon(Icons.cloud_download,
                                  size: 16),
                              label: const Text('Go to Import'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFE50914),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        // Infinite scroll: when we get within 200px of the
                        // bottom AND there's more data AND we're not already
                        // loading more, load the next page.
                        if (notification is ScrollUpdateNotification &&
                            _myPostsHasMore &&
                            !_myPostsIsLoadingMore &&
                            !_myPostsIsLoading &&
                            notification.metrics.pixels >
                                notification.metrics.maxScrollExtent - 200) {
                          _loadMyPosts();
                        }
                        return false;
                      },
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 6),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.53,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: _myPostsFiltered.length +
                            (_myPostsIsLoadingMore ? 6 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _myPostsFiltered.length) {
                            return const Center(
                                child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ));
                          }
                          final movie = _myPostsFiltered[index];
                          // Per-card syncing state — when true, the Update
                          // icon swaps to a small spinner and the trash
                          // icon is disabled to avoid races.
                          final isSyncing =
                              _myPostsSyncingIds.contains(movie.id);
                          return Stack(
                            children: [
                              MovieCard(
                                movie: movie,
                                onTap: () =>
                                    _navigateToDetailFromMyPosts(movie),
                              ),
                              // Update-from-TMDB icon — top-LEFT corner.
                              // (Task 37, Number 4.) Only shown for posts
                              // that have a tmdbId (i.e. were imported from
                              // TMDB or have one assigned). Posts added via
                              // Batch Import without tmdbId cannot be
                              // synced — hide the icon for those.
                              Positioned(
                                top: 4,
                                left: 4,
                                child: _buildUpdateIcon(movie, isSyncing),
                              ),
                              // Trash-icon delete button — top-right corner.
                              // Mirrors BatchPostsScreen styling exactly.
                              // Disabled (grayed out + no onTap) while a
                              // sync is in flight for the same card.
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: isSyncing
                                      ? null
                                      : () => _deleteMyPost(movie),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSyncing
                                            ? Colors.white24
                                            : Colors.red.shade300,
                                        width: 1.5,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.delete_outline,
                                      color: isSyncing
                                          ? Colors.white24
                                          : Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  // ==================== SYNC DASHBOARD TAB ====================

  Widget _buildSyncDashboardTab(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.dashboard, color: Color(0xFFE50914), size: 24),
              const SizedBox(width: 10),
              const Text(
                'Sync Dashboard',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_isStatsLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFE50914),
                  ),
                ),
              if (!_isStatsLoading)
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _loadMoviesSnapshot,
                  tooltip: 'Refresh stats',
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Statistics Cards — 2x2 Grid
          _buildStatsGrid(isDark),
          const SizedBox(height: 20),

          // Series Status Row
          _buildSeriesStatusRow(isDark),
          const SizedBox(height: 24),

          // Manual Sync Section
          _buildManualSyncSection(isDark),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(bool isDark) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.8,
      children: [
        _buildStatCard(
          isDark: isDark,
          value: _totalMovies,
          label: 'Total Movies',
          icon: Icons.movie,
          color: const Color(0xFFE50914),
        ),
        _buildStatCard(
          isDark: isDark,
          value: _totalSeries,
          label: 'Total Series',
          icon: Icons.tv,
          color: const Color(0xFFE50914),
        ),
        _buildStatCard(
          isDark: isDark,
          value: _moviesNeedSync,
          label: 'Movies Need Sync',
          icon: Icons.sync_problem,
          color: _moviesNeedSync > 0 ? Colors.orange : Colors.green,
        ),
        _buildStatCard(
          isDark: isDark,
          value: _seriesNeedSync,
          label: 'Series Need Sync',
          icon: Icons.sync_problem,
          color: _seriesNeedSync > 0 ? Colors.orange : Colors.green,
        ),
      ],
    );
  }

  Widget _buildSeriesStatusRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            isDark: isDark,
            value: _ongoingSeries,
            label: 'Ongoing Series',
            icon: Icons.play_circle_filled,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            isDark: isDark,
            value: _endedSeries,
            label: 'Ended Series',
            icon: Icons.stop_circle_outlined,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required bool isDark,
    required int value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const Spacer(),
              Text(
                value.toString(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualSyncSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, color: Color(0xFFE50914), size: 22),
              const SizedBox(width: 10),
              const Text(
                'Manual Sync',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Sync will update metadata (rating, poster, backdrop) and fetch new episodes for ongoing series. '
            'Overview/description will NOT be overwritten. Each batch processes up to $_syncBatchSize items.',
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildSyncButton(
                  label: 'Sync Series',
                  subtitle: _seriesNeedSync > 0 ? '$_seriesNeedSync pending' : 'All synced',
                  icon: Icons.tv,
                  onPressed: _isSyncing ? null : _syncSeries,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSyncButton(
                  label: 'Sync Movies',
                  subtitle: _moviesNeedSync > 0 ? '$_moviesNeedSync pending' : 'All synced',
                  icon: Icons.movie,
                  onPressed: _isSyncing ? null : _syncMovies,
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildSyncButton(
                  label: 'Sync All',
                  subtitle: 'Movies + Series',
                  icon: Icons.sync,
                  onPressed: _isSyncing ? null : _syncAll,
                  isDark: isDark,
                  isPrimary: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton({
    required String label,
    required String subtitle,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool isDark,
    bool isPrimary = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? const Color(0xFFE50914) : (isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100),
        foregroundColor: isPrimary ? Colors.white : (isDark ? Colors.white : Colors.black87),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isPrimary
              ? BorderSide.none
              : BorderSide(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        elevation: isPrimary ? 4 : 0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isPrimary ? Colors.white70 : (isDark ? Colors.white38 : Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== FILTER & RESULTS (Import Tab) ====================

  Widget _buildFilterSection(bool isDark) {
    final genres = _type == 'movie' ? _movieGenres : _tvGenres;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: Column(
        children: [
          // Collapsible header
          InkWell(
            onTap: () => setState(() => _filtersExpanded = !_filtersExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    color: const Color(0xFFE50914),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Filters',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const Spacer(),
                  Icon(
                    _filtersExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_filtersExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  // Row 1: Type, Genre, Year
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Type',
                          value: _type,
                          items: const [
                            DropdownMenuItem(value: 'movie', child: Text('Movies')),
                            DropdownMenuItem(value: 'series', child: Text('TV Series')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _type = val!;
                              _selectedGenreId = null;
                              _updateGenreMap();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Genre',
                          value: _selectedGenreId?.toString() ?? '',
                          items: [
                            const DropdownMenuItem(value: '', child: Text('All Genres')),
                            ...genres.map((g) => DropdownMenuItem(
                                  value: g['id'].toString(),
                                  child: Text(g['name'].toString()),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedGenreId = (val != null && val.isNotEmpty) ? int.tryParse(val) : null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Year',
                          value: _selectedYear ?? '',
                          items: [
                            const DropdownMenuItem(value: '', child: Text('All Years')),
                            ..._yearOptions.map((y) => DropdownMenuItem(
                                  value: y,
                                  child: Text(y),
                                )),
                          ],
                          onChanged: (val) {
                            setState(() => _selectedYear = (val != null && val.isNotEmpty) ? val : null);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Row 2: Language, Sort By, Post Limit
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Language',
                          value: _selectedLanguage,
                          items: _languageOptions.map((l) => DropdownMenuItem(
                            value: l['code'],
                            child: Text(l['name']!),
                          )).toList(),
                          onChanged: (val) {
                            setState(() => _selectedLanguage = val!);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Sort By',
                          value: _selectedSortBy,
                          items: _sortOptions.map((s) => DropdownMenuItem(
                            value: s['value'],
                            child: Text(s['label']!),
                          )).toList(),
                          onChanged: (val) {
                            setState(() => _selectedSortBy = val!);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildFilterDropdown(
                          label: 'Limit',
                          value: _postLimit.toString(),
                          items: _postLimitOptions.map((l) => DropdownMenuItem(
                            value: l.toString(),
                            child: Text(l.toString()),
                          )).toList(),
                          onChanged: (val) {
                            setState(() => _postLimit = int.parse(val!));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Search by title + Search button
                  Row(
                    children: [
                      Expanded(
                        child: NoToolbarOnSingleTapTextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search by title...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onSubmitted: (_) => _performSearch(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _performSearch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Search'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        SizedBox(
          height: 40,
          child: DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            isDense: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(bool isDark) {
    if (_results.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            '$_totalResults results',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const Spacer(),
          if (_selectedIds.isNotEmpty)
            Text(
              '${_selectedIds.length} selected',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE50914),
                fontWeight: FontWeight.w600,
              ),
            ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              setState(() {
                if (_selectedIds.length == _results.length) {
                  _selectedIds.clear();
                } else {
                  _selectedIds.clear();
                  for (final r in _results) {
                    final id = r['id'] as int?;
                    if (id != null) _selectedIds.add(id);
                  }
                }
              });
            },
            child: Text(
              _selectedIds.length == _results.length ? 'Deselect All' : 'Select All',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsGrid(bool isDark) {
    if (_isLoading && _results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFE50914)),
            SizedBox(height: 16),
            Text('Loading from TMDB...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _performSearch,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_filter_outlined,
              size: 64,
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              'Search TMDB to discover movies & series',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use filters above or search by title',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.53,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final item = _results[index];
        return _buildResultCard(item, isDark);
      },
    );
  }

  Widget _buildResultCard(Map<String, dynamic> item, bool isDark) {
    final tmdbId = item['id'] as int?;
    final title = item['title']?.toString() ?? item['name']?.toString() ?? 'Unknown';
    final posterPath = item['poster_path']?.toString();
    final rating = (item['vote_average'] ?? 0).toDouble();
    final releaseDate = item['release_date']?.toString() ?? item['first_air_date']?.toString() ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : '';
    final isSelected = tmdbId != null && _selectedIds.contains(tmdbId);
    final isImported = tmdbId != null && _importedTmdbIds.contains(tmdbId);

    return GestureDetector(
      onTap: () {
        if (tmdbId != null) {
          setState(() {
            if (_selectedIds.contains(tmdbId)) {
              _selectedIds.remove(tmdbId);
            } else {
              _selectedIds.add(tmdbId);
            }
          });
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: const Color(0xFFE50914), width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Poster with badges
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                    child: posterPath != null && posterPath.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: TmdbService.getPosterUrl(posterPath),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFFE50914),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                              child: Icon(
                                Icons.movie,
                                color: isDark ? Colors.white24 : Colors.black12,
                              ),
                            ),
                          )
                        : Container(
                            color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
                            child: Icon(
                              Icons.movie,
                              size: 40,
                              color: isDark ? Colors.white24 : Colors.black12,
                            ),
                          ),
                  ),
                  // Checkbox
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? const Color(0xFFE50914)
                            : Colors.black.withOpacity(0.5),
                        border: Border.all(
                          color: isSelected ? const Color(0xFFE50914) : Colors.white70,
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : null,
                    ),
                  ),
                  // Rating badge
                  if (rating > 0)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, size: 12, color: Color(0xFFFF0000)),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Color(0xFFFF0000),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Imported/New badge
                  Positioned(
                    bottom: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isImported
                            ? Colors.green.withOpacity(0.85)
                            : const Color(0xFFE50914).withOpacity(0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isImported ? 'Imported' : 'New',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info section
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                    if (year.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          year,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== PROGRESS OVERLAYS ====================

  Widget _buildImportProgress() {
    final progress = _importTotal > 0 ? _importProgress / _importTotal : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_download,
              size: 64,
              color: Color(0xFFE50914),
            ),
            const SizedBox(height: 24),
            Text(
              'Importing from TMDB...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _importCurrentTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black54,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2A2A2A)
                    : Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$_importProgress/$_importTotal imported (${(progress * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '✓ $_importSuccessCount',
                  style: const TextStyle(color: Colors.green, fontSize: 13),
                ),
                const SizedBox(width: 16),
                Text(
                  '✗ $_importFailureCount',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncProgress() {
    final progress = _syncTotal > 0 ? _syncProgress / _syncTotal : 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sync,
              size: 64,
              color: Color(0xFFE50914),
            ),
            const SizedBox(height: 24),
            Text(
              'Syncing with TMDB...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _syncCurrentTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black54,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF2A2A2A)
                    : Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$_syncProgress/$_syncTotal synced (${(progress * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '✓ $_syncSuccessCount',
                  style: const TextStyle(color: Colors.green, fontSize: 13),
                ),
                const SizedBox(width: 16),
                Text(
                  '✗ $_syncFailureCount',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
