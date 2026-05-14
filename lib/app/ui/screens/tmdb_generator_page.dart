import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/app/core/services/tmdb_service.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';

class TmdbGeneratorPage extends StatefulWidget {
  const TmdbGeneratorPage({super.key});

  @override
  State<TmdbGeneratorPage> createState() => _TmdbGeneratorPageState();
}

class _TmdbGeneratorPageState extends State<TmdbGeneratorPage> {
  final TmdbService _tmdbService = TmdbService();
  final FirestoreContentService _contentService = FirestoreContentService();

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
  bool _skipDescriptionUpdate = false;
  int _syncRemainingMovies = 0;
  int _syncRemainingSeries = 0;

  // Batch size for sync operations
  static const int _syncBatchSize = 20;

  // Filter collapse
  bool _filtersExpanded = true;

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
    _loadGenres();
    _loadImportedTmdbIds();
    _loadSyncRemainingCounts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  Future<void> _loadImportedTmdbIds() async {
    try {
      // BUG FIX: Fetch all movies and extract tmdbId client-side.
      // We fetch in batches if needed, and handle both int and String tmdbId types.
      final snapshot = await FirebaseFirestore.instance
          .collection('movies')
          .limit(5000)
          .get();

      if (mounted) {
        setState(() {
          _importedTmdbIds.clear();
          for (final doc in snapshot.docs) {
            final rawTmdbId = doc.data()['tmdbId'];
            if (rawTmdbId == null) continue;
            // Handle both int and String types for tmdbId
            final tmdbId = rawTmdbId is int
                ? rawTmdbId
                : int.tryParse(rawTmdbId.toString());
            if (tmdbId != null && tmdbId > 0) {
              _importedTmdbIds.add(tmdbId);
            }
          }
        });
        debugPrint('Imported tmdbIds loaded: ${_importedTmdbIds.length} items');
      }
    } catch (e) {
      debugPrint('Error loading imported tmdbIds: $e');
    }
  }

  /// Count how many movies/series have no lastSyncDate field (never synced)
  Future<void> _loadSyncRemainingCounts() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('movies')
          .limit(5000)
          .get();

      int movieCount = 0;
      int seriesCount = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final tmdbId = data['tmdbId'];
        if (tmdbId == null) continue;
        if (tmdbId is! int || tmdbId <= 0) continue;
        if (data.containsKey('lastSyncDate')) continue; // already synced
        final type = data['type']?.toString();
        if (type == 'movie') {
          movieCount++;
        } else if (type == 'series') {
          seriesCount++;
        }
      }
      if (mounted) {
        setState(() {
          _syncRemainingMovies = movieCount;
          _syncRemainingSeries = seriesCount;
        });
      }
    } catch (e) {
      debugPrint('Error loading sync remaining counts: $e');
    }
  }

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

      // Extract original language filter for discover, always use en-US for display
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
                language: 'en-US', // Always English for display
                originalLanguage: originalLang, // Filter by original language
                sortBy: sortKey,
                page: 1,
              )
            : await _tmdbService.discoverTV(
                genre: _selectedGenreId,
                year: _selectedYear,
                language: 'en-US', // Always English for display
                originalLanguage: originalLang, // Filter by original language
                sortBy: sortKey,
                page: 1,
              );
      }

      final rawResults = List<Map<String, dynamic>>.from(response['results'] ?? []);

      // Filter out already-imported items so the grid only shows NEW posts
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

      // Load more pages if postLimit > 20 and filtered results are insufficient
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

        // Extract original language filter for discover, always use en-US for display
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
                  language: 'en-US', // Always English for display
                  originalLanguage: originalLang, // Filter by original language
                  sortBy: sortKey,
                  page: page,
                )
              : await _tmdbService.discoverTV(
                  genre: _selectedGenreId,
                  year: _selectedYear,
                  language: 'en-US', // Always English for display
                  originalLanguage: originalLang, // Filter by original language
                  sortBy: sortKey,
                  page: page,
                );
        }

        final rawMoreResults = List<Map<String, dynamic>>.from(response['results'] ?? []);
        // Filter out already-imported items so the grid only shows NEW posts
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

    // Trim to postLimit
    if (mounted && _results.length > _postLimit) {
      setState(() {
        _results = _results.sublist(0, _postLimit);
      });
    }
  }

  Future<void> _importSelected() async {
    final selected = _selectedIds.toList();
    if (selected.isEmpty) return;

    // BUG FIX: Filter out already-imported items to prevent duplicates
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
        // Double-check: verify not already imported in Firestore
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

        // Fetch full details with credits
        Map<String, dynamic> fullDetails;
        Map<String, dynamic> firestoreData;

        if (_type == 'movie') {
          fullDetails = await _tmdbService.getMovieDetails(tmdbId);
          // Merge genre_ids from discover into full details if needed
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

        // Save to Firestore using FirestoreContentService
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

      // Refresh imported status so badges update immediately
      _loadImportedTmdbIds();

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

  Future<void> _syncMovies() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync Movies'),
        content: Text(
          'This will sync up to $_syncBatchSize movies from TMDB that have a tmdbId and update their data in Firestore.\n\n'
          'Movies that have never been synced or have an older sync date are prioritized.',
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

    try {
      // Fetch movies with type='movie' and filter for tmdbId client-side
      final snapshot = await FirebaseFirestore.instance
          .collection('movies')
          .where('type', isEqualTo: 'movie')
          .limit(5000)
          .get();

      final docs = snapshot.docs.where((doc) {
        final tmdbId = doc.data()['tmdbId'] as int?;
        return tmdbId != null && tmdbId > 0;
      }).toList();

      // Sort: no lastSyncDate first, then by lastSyncDate ascending (oldest first)
      docs.sort((a, b) {
        final aSync = a.data()['lastSyncDate'] as Timestamp?;
        final bSync = b.data()['lastSyncDate'] as Timestamp?;
        if (aSync == null && bSync == null) return 0;
        if (aSync == null) return -1;
        if (bSync == null) return 1;
        return aSync.compareTo(bSync);
      });

      // Take only the batch size
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

      // Collect (docId, tmdbId, title) pairs FIRST to prevent stale references
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

          // Build SAFE update map — only TMDB fields, preserve user data
          final safeUpdate = <String, dynamic>{};
          for (final key in ['title', 'year', 'poster', 'backdrop', 'rating',
              'duration', 'isAdult', 'categories', 'directors', 'casts',
              'tmdbId', 'country']) {
            if (firestoreData.containsKey(key)) {
              safeUpdate[key] = firestoreData[key];
            }
          }

          // Conditionally include overview
          if (!_skipDescriptionUpdate && firestoreData.containsKey('overview')) {
            safeUpdate['overview'] = firestoreData['overview'];
          }

          debugPrint('SYNC MOVIE: safeUpdate title=${safeUpdate['title']} tmdbId=${safeUpdate['tmdbId']} duration=${safeUpdate['duration']}');

          // CRITICAL: Validate document still has the same tmdbId before updating
          // This prevents data corruption from stale references
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
            // Use Firestore Transaction for atomic read-then-write
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
        // Refresh imported status and remaining counts after sync
        _loadImportedTmdbIds();
        _loadSyncRemainingCounts();
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

  Future<void> _syncSeries() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync Series'),
        content: Text(
          'This will sync up to $_syncBatchSize series from TMDB that have a tmdbId and update their data in Firestore.\n\n'
          'Series that have never been synced or have an older sync date are prioritized.',
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

    try {
      // Fetch series with type='series' and filter for tmdbId client-side
      final snapshot = await FirebaseFirestore.instance
          .collection('movies')
          .where('type', isEqualTo: 'series')
          .limit(5000)
          .get();

      final docs = snapshot.docs.where((doc) {
        final tmdbId = doc.data()['tmdbId'] as int?;
        return tmdbId != null && tmdbId > 0;
      }).toList();

      // Sort: no lastSyncDate first, then by lastSyncDate ascending (oldest first)
      docs.sort((a, b) {
        final aSync = a.data()['lastSyncDate'] as Timestamp?;
        final bSync = b.data()['lastSyncDate'] as Timestamp?;
        if (aSync == null && bSync == null) return 0;
        if (aSync == null) return -1;
        if (bSync == null) return 1;
        return aSync.compareTo(bSync);
      });

      // Take only the batch size
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

      // Collect (docId, tmdbId, title) pairs FIRST to prevent stale references
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

          // Build SAFE update map — only TMDB fields, preserve user data
          final safeUpdate = <String, dynamic>{};
          for (final key in ['title', 'year', 'poster', 'backdrop', 'rating',
              'duration', 'isAdult', 'categories', 'directors', 'casts',
              'tmdbId', 'country', 'seasons']) {
            if (firestoreData.containsKey(key)) {
              safeUpdate[key] = firestoreData[key];
            }
          }

          // Conditionally include overview
          if (!_skipDescriptionUpdate && firestoreData.containsKey('overview')) {
            safeUpdate['overview'] = firestoreData['overview'];
          }

          debugPrint('SYNC SERIES: safeUpdate title=${safeUpdate['title']} tmdbId=${safeUpdate['tmdbId']} duration=${safeUpdate['duration']}');

          // CRITICAL: Validate document still has the same tmdbId before updating
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
            // Use Firestore Transaction for atomic read-then-write
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
        // Refresh imported status and remaining counts after sync
        _loadImportedTmdbIds();
        _loadSyncRemainingCounts();
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

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search TMDB'),
        content: TextField(
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
          actions: [
            // Search icon
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _isImporting || _isSyncing ? null : _showSearchDialog,
            ),
            // Refresh imported status
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isImporting || _isSyncing ? null : _loadImportedTmdbIds,
              tooltip: 'Refresh imported status',
            ),
            // Selected count + Import button
            if (_selectedIds.isNotEmpty)
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
                : Column(
                    children: [
                      _buildFilterSection(isDark),
                      _buildActionBar(isDark),
                      Expanded(child: _buildResultsGrid(isDark)),
                      _buildSyncSection(isDark),
                    ],
                  ),
      ),
    );
  }

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
                        child: TextField(
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.48,
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
                  // Poster image
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
                            const Icon(Icons.star, size: 12, color: Colors.amber),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Colors.amber,
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
            // Info section - compact for 3-column grid
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

  Widget _buildSyncSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.sync, color: Color(0xFFE50914), size: 18),
              const SizedBox(width: 8),
              const Text(
                'Sync from TMDB',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              // Skip Description Toggle
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Skip Description',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      value: _skipDescriptionUpdate,
                      onChanged: (val) {
                        setState(() => _skipDescriptionUpdate = val);
                      },
                      activeColor: const Color(0xFFE50914),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _syncMovies,
                      icon: const Icon(Icons.movie, size: 16),
                      label: const Text('Sync Movies', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (_syncRemainingMovies > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$_syncRemainingMovies remaining',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isSyncing ? null : _syncSeries,
                      icon: const Icon(Icons.tv, size: 16),
                      label: const Text('Sync Series', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (_syncRemainingSeries > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '$_syncRemainingSeries remaining',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
