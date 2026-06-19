import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';

class FirestoreContentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get _moviesRef => _firestore.collection('movies');
  CollectionReference get _genresRef => _firestore.collection('genres');
  CollectionReference get _tagsRef => _firestore.collection('tags');
  CollectionReference get _collectionsRef => _firestore.collection('collections');

  // ==================== READ OPERATIONS ====================

  /// Find a movie document by tmdbId — returns the first match or null
  Future<DocumentSnapshot?> findByTmdbId(dynamic tmdbId) async {
    if (tmdbId == null) return null;
    try {
      final snapshot = await _moviesRef
          .where('tmdbId', isEqualTo: tmdbId)
          .limit(1)
          .get();
      return snapshot.docs.isNotEmpty ? snapshot.docs.first : null;
    } catch (e) {
      debugPrint('findByTmdbId failed: $e');
      return null;
    }
  }

  /// Get movies with cursor-based pagination
  Future<Map<String, dynamic>> getMovies({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      // Sort by updatedAt (descending) so that admin edits push the movie to
      // the front of the Home list. Newly added movies also have updatedAt set.
      Query query = _moviesRef
          .where('type', isEqualTo: 'movie')
          .orderBy('updatedAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final movies = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      return {
        'movies': movies,
        'hasMore': snapshot.docs.length >= limit,
        'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      // Fallback: if composite index doesn't exist, try without orderBy
      debugPrint('getMovies with orderBy failed, trying fallback: $e');
      try {
        Query query = _moviesRef
            .where('type', isEqualTo: 'movie')
            .limit(limit);

        final snapshot = await query.get();
        final movies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();

        // Sort client-side by updatedAt (falls back to createdAt if updatedAt missing)
        movies.sort((a, b) {
          final aDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
          final bDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
          return aDate.compareTo(bDate);
        });

        return {
          'movies': movies,
          'hasMore': snapshot.docs.length >= limit,
          'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        };
      } catch (e2) {
        debugPrint('getMovies fallback also failed: $e2');
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }
  }

  /// Get series with cursor-based pagination
  Future<Map<String, dynamic>> getSeries({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      // Sort by updatedAt (descending) so that admin edits push the series to
      // the front of the Home list. Newly added series also have updatedAt set.
      Query query = _moviesRef
          .where('type', isEqualTo: 'series')
          .orderBy('updatedAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final series = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      return {
        'movies': series,
        'hasMore': snapshot.docs.length >= limit,
        'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      // Fallback: if composite index doesn't exist, try without orderBy
      debugPrint('getSeries with orderBy failed, trying fallback: $e');
      try {
        Query query = _moviesRef
            .where('type', isEqualTo: 'series')
            .limit(limit);

        final snapshot = await query.get();
        final series = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();

        // Sort client-side by updatedAt (falls back to createdAt if updatedAt missing)
        series.sort((a, b) {
          final aDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
          final bDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
          return aDate.compareTo(bDate);
        });

        return {
          'movies': series,
          'hasMore': snapshot.docs.length >= limit,
          'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        };
      } catch (e2) {
        debugPrint('getSeries fallback also failed: $e2');
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }
  }

  /// Get all movies and series (for admin panel)
  Future<Map<String, dynamic>> getAllPosts({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    Query query = _moviesRef
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    final movies = snapshot.docs
        .map((doc) => Movie.fromMap(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ))
        .toList();

    return {
      'movies': movies,
      'hasMore': snapshot.docs.length >= limit,
      'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    };
  }

  /// Search all posts (for admin panel)
  /// Uses 'title_lowercase' field for case-insensitive prefix search
  Future<List<Movie>> searchAllPosts(String keyword) async {
    if (keyword.trim().isEmpty) return [];

    final lowerKeyword = keyword.toLowerCase().trim();
    final upperKeyword = lowerKeyword + '\uf8ff';

    try {
      // Primary: search on 'title_lowercase' field (case-insensitive prefix match)
      final snapshot = await _moviesRef
          .where('title_lowercase', isGreaterThanOrEqualTo: lowerKeyword)
          .where('title_lowercase', isLessThanOrEqualTo: upperKeyword)
          .orderBy('title_lowercase')
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
    } catch (e) {
      // Fallback: if title_lowercase index doesn't exist, try old 'title' field
      debugPrint('searchAllPosts with title_lowercase failed, trying fallback: $e');
      try {
        final snapshot = await _moviesRef
            .where('title', isGreaterThanOrEqualTo: lowerKeyword)
            .where('title', isLessThanOrEqualTo: upperKeyword)
            .orderBy('title')
            .limit(50)
            .get();

        return snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();
      } catch (e2) {
        debugPrint('searchAllPosts fallback also failed: $e2');
        return [];
      }
    }
  }

  /// Get trending movies
  Future<List<Movie>> getTrendingMovies() async {
    try {
      final snapshot = await _moviesRef
          .where('type', isEqualTo: 'movie')
          .where('isTrending', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
    } catch (e) {
      // Fallback: if composite index doesn't exist, try simpler query
      debugPrint('getTrendingMovies with orderBy failed, trying fallback: $e');
      try {
        final snapshot = await _moviesRef
            .where('type', isEqualTo: 'movie')
            .where('isTrending', isEqualTo: true)
            .limit(50)
            .get();

        final movies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
        return movies;
      } catch (e2) {
        debugPrint('getTrendingMovies fallback also failed: $e2');
        return [];
      }
    }
  }

  /// Get trending TV shows
  Future<List<Movie>> getTrendingTvShows() async {
    try {
      final snapshot = await _moviesRef
          .where('type', isEqualTo: 'series')
          .where('isTrending', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();

      return snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
    } catch (e) {
      // Fallback: if composite index doesn't exist, try simpler query
      debugPrint('getTrendingTvShows with orderBy failed, trying fallback: $e');
      try {
        final snapshot = await _moviesRef
            .where('type', isEqualTo: 'series')
            .where('isTrending', isEqualTo: true)
            .limit(50)
            .get();

        final movies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
        return movies;
      } catch (e2) {
        debugPrint('getTrendingTvShows fallback also failed: $e2');
        return [];
      }
    }
  }

  /// Get movie detail by slug
  /// Prefers the most recently updated document when duplicates exist.
  Future<MovieDetail?> getMovieBySlug(String slug) async {
    try {
      // Try with orderBy first (requires composite index: slug + updatedAt)
      final snapshot = await _moviesRef
          .where('slug', isEqualTo: slug)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return MovieDetail.fromMap(
          doc.data() as Map<String, dynamic>,
          docId: doc.id,
        );
      }
    } catch (e) {
      // Fallback: if composite index doesn't exist, fetch all and pick best
      debugPrint('getMovieBySlug with orderBy failed, trying fallback: $e');
    }

    // Fallback: fetch all matching and pick the most complete one
    final snapshot = await _moviesRef
        .where('slug', isEqualTo: slug)
        .limit(10)
        .get();

    if (snapshot.docs.isEmpty) return null;

    // Pick the document with the most data (poster, backdrop, rating, etc.)
    DocumentSnapshot? bestDoc;
    int bestScore = -1;

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      int score = 0;
      // Score based on how many fields have actual data
      if (data['poster'] != null) score += 3;
      if (data['backdrop'] != null) score += 3;
      if (data['rating'] != null) score += 2;
      if (data['duration'] != null) score += 2;
      if (data['resolution'] != null) score += 1;
      if (data['overview'] != null) score += 1;
      if ((data['categories'] as List?)?.isNotEmpty == true) score += 2;
      if ((data['tags'] as List?)?.isNotEmpty == true) score += 1;
      if (data['updatedAt'] != null) score += 5; // Prefer recently updated
      if (score > bestScore) {
        bestScore = score;
        bestDoc = doc;
      }
    }

    if (bestDoc == null) return null;

    return MovieDetail.fromMap(
      bestDoc.data() as Map<String, dynamic>,
      docId: bestDoc.id,
    );
  }

  /// Get movie detail by ID
  Future<MovieDetail?> getMovieById(String id) async {
    final doc = await _moviesRef.doc(id).get();
    if (!doc.exists) return null;

    return MovieDetail.fromMap(
      doc.data() as Map<String, dynamic>,
      docId: doc.id,
    );
  }

  /// Get movies by genre name
  Future<Map<String, dynamic>> getMoviesByGenre(
    String genreName, {
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _moviesRef
          .where('categories', arrayContains: genreName)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final movies = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      return {
        'movies': movies,
        'hasMore': snapshot.docs.length >= limit,
        'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      // Fallback without orderBy if composite index missing
      debugPrint('getMoviesByGenre with orderBy failed, trying fallback: $e');
      try {
        Query query = _moviesRef
            .where('categories', arrayContains: genreName)
            .limit(limit);

        final snapshot = await query.get();
        final movies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

        return {
          'movies': movies,
          'hasMore': snapshot.docs.length >= limit,
          'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        };
      } catch (e2) {
        debugPrint('getMoviesByGenre fallback also failed: $e2');
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }
  }

  /// Get movies by tag name
  Future<Map<String, dynamic>> getMoviesByTag(
    String tagName, {
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _moviesRef
          .where('tags', arrayContains: tagName)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final movies = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      return {
        'movies': movies,
        'hasMore': snapshot.docs.length >= limit,
        'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      // Fallback without orderBy if composite index missing
      debugPrint('getMoviesByTag with orderBy failed, trying fallback: $e');
      try {
        Query query = _moviesRef
            .where('tags', arrayContains: tagName)
            .limit(limit);

        final snapshot = await query.get();
        final movies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

        return {
          'movies': movies,
          'hasMore': snapshot.docs.length >= limit,
          'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        };
      } catch (e2) {
        debugPrint('getMoviesByTag fallback also failed: $e2');
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }
  }

  /// Search movies by keyword using Firestore prefix search on 'title_lowercase' + search_keywords + client-side fallback
  Future<Map<String, dynamic>> searchMovies(
    String keyword, {
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    final lowerKeyword = keyword.toLowerCase().trim();
    if (lowerKeyword.isEmpty) {
      return {'movies': <Movie>[], 'hasMore': false, 'lastDoc': null};
    }

    // Primary approach: Use search_keywords array for word-level matching + prefix search
    try {
      final upperKeyword = lowerKeyword + '\uf8ff';

      // Strategy 1: Firestore prefix search on 'title_lowercase' (finds titles STARTING with keyword)
      final prefixSnapshot = await _moviesRef
          .where('title_lowercase', isGreaterThanOrEqualTo: lowerKeyword)
          .where('title_lowercase', isLessThanOrEqualTo: upperKeyword)
          .orderBy('title_lowercase')
          .limit(limit * 2)
          .get();

      final prefixResults = prefixSnapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Strategy 2: Use search_keywords array for non-prefix word matching
      // e.g. "Avengers" will find "The Avengers" because "avengers" is in search_keywords
      final keywordSnapshot = await _moviesRef
          .where('search_keywords', arrayContains: lowerKeyword)
          .limit(limit * 2)
          .get();

      final keywordResults = keywordSnapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Combine both result sets, deduplicating by ID
      final seenIds = <String>{};
      final allResults = <Movie>[];
      for (final m in [...prefixResults, ...keywordResults]) {
        if (!seenIds.contains(m.id)) {
          seenIds.add(m.id);
          allResults.add(m);
        }
      }

      // Client-side contains filter as enhancement (catches partial matches within results)
      final filtered = allResults
          .where((m) => m.titleLowercase.contains(lowerKeyword))
          .toList();

      // If combined search found enough results, return them
      if (filtered.length >= limit) {
        return {
          'movies': filtered.take(limit).toList(),
          'hasMore': filtered.length > limit,
          'lastDoc': null,
        };
      }

      // Fallback: broader search to catch any remaining matches
      final broaderSnapshot = await _moviesRef
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();
      final broaderMovies = broaderSnapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Combine results, avoiding duplicates
      final additionalMovies = broaderMovies
          .where((m) => !seenIds.contains(m.id) && m.titleLowercase.contains(lowerKeyword))
          .toList();

      final combined = [...filtered, ...additionalMovies];
      return {
        'movies': combined.take(limit).toList(),
        'hasMore': combined.length > limit,
        'lastDoc': null,
      };
    } catch (e) {
      // Fallback: try search_keywords then old 'title' field
      debugPrint('searchMovies with primary strategy failed, trying fallback: $e');
      try {
        // Try search_keywords array first
        final keywordSnapshot = await _moviesRef
            .where('search_keywords', arrayContains: lowerKeyword)
            .limit(limit * 2)
            .get();

        if (keywordSnapshot.docs.isNotEmpty) {
          final results = keywordSnapshot.docs
              .map((doc) => Movie.fromMap(
                    doc.data() as Map<String, dynamic>,
                    docId: doc.id,
                  ))
              .toList();
          return {
            'movies': results.take(limit).toList(),
            'hasMore': results.length > limit,
            'lastDoc': null,
          };
        }

        // Last resort: old 'title' field prefix search
        final upperKeyword = lowerKeyword + '\uf8ff';
        final snapshot = await _moviesRef
            .where('title', isGreaterThanOrEqualTo: lowerKeyword)
            .where('title', isLessThanOrEqualTo: upperKeyword)
            .orderBy('title')
            .limit(limit * 2)
            .get();

        var results = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();

        final filtered = results
            .where((m) => m.title.toLowerCase().contains(lowerKeyword))
            .toList();

        return {
          'movies': filtered.take(limit).toList(),
          'hasMore': filtered.length > limit,
          'lastDoc': null,
        };
      } catch (e2) {
        debugPrint('searchMovies fallback also failed: $e2');
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }
  }

  /// Search movies with multiple filters (client-side for reliability)
  /// Supports: keyword, genre, type, year, rating, and sorting
  /// Advanced search: supports Name + Year combined search (e.g., "Kung Fu Panda 2008")
  /// by splitting query into tokens and matching all tokens against title/year
  Future<Map<String, dynamic>> searchMoviesWithFilters({
    String? keyword,
    String? genre,
    String? type, // 'movie' or 'series'
    String? year,
    String? rating, // e.g. '7', '8' - minimum rating
    String? sortBy, // 'latest', 'rating', 'name'
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      // Determine if we need keyword-based search (more extensive fetching)
      final hasKeyword = keyword != null && keyword.trim().isNotEmpty;

      if (hasKeyword) {
        // For keyword searches, we need to fetch more documents to find matches
        // especially for old movies that may not appear in the first batch
        return _searchWithKeyword(
          keyword: keyword!,
          genre: genre,
          type: type,
          year: year,
          rating: rating,
          sortBy: sortBy,
          limit: limit,
          startAfter: startAfter,
        );
      }

      // No keyword — just filter-based browsing with pagination
      Query query = _moviesRef;

      // Apply server-side filters where possible
      if (type != null && type.isNotEmpty) {
        query = query.where('type', isEqualTo: type);
      }
      if (genre != null && genre.isNotEmpty) {
        query = query.where('categories', arrayContains: genre);
      }

      // Order by - only if we don't have genre filter (composite index issue)
      if (sortBy == 'rating') {
        query = query.orderBy('rating', descending: true);
      } else if (sortBy == 'name') {
        query = query.orderBy('title');
      } else {
        if (genre == null || genre.isEmpty) {
          query = query.orderBy('createdAt', descending: true);
        }
      }

      // Apply cursor-based pagination
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      query = query.limit(limit);

      final snapshot = await query.get();
      var allMovies = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Client-side filtering for fields that can't be queried together in Firestore
      var filtered = allMovies;

      // Type filter (client-side fallback if not applied server-side)
      if (type != null && type.isNotEmpty && genre != null && genre.isNotEmpty) {
        filtered = filtered.where((m) => m.type == type).toList();
      }

      // Year filter
      if (year != null && year.isNotEmpty) {
        filtered = filtered.where((m) => m.year == year).toList();
      }

      // Rating filter (minimum rating)
      if (rating != null && rating.isNotEmpty) {
        final minRating = double.tryParse(rating) ?? 0.0;
        filtered = filtered.where((m) {
          final movieRating = double.tryParse(m.rating ?? '0') ?? 0.0;
          return movieRating >= minRating;
        }).toList();
      }

      // Client-side sort fallback for genre queries
      if (genre != null && genre.isNotEmpty) {
        if (sortBy == 'rating') {
          filtered.sort((a, b) =>
              (double.tryParse(b.rating ?? '0') ?? 0.0)
              .compareTo(double.tryParse(a.rating ?? '0') ?? 0.0));
        } else if (sortBy == 'name') {
          filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        } else {
          filtered.sort((a, b) => (b.createdAt ?? DateTime(2000))
              .compareTo(a.createdAt ?? DateTime(2000)));
        }
      }

      return {
        'movies': filtered.take(limit).toList(),
        'hasMore': allMovies.length >= limit,
        'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('searchMoviesWithFilters failed: $e');
      return {
        'movies': <Movie>[],
        'hasMore': false,
        'lastDoc': null,
      };
    }
  }

  /// Internal: keyword-based search that fetches more documents to find old movies too
  /// Supports advanced token-based search: "Kung Fu Panda 2008" matches title AND year
  Future<Map<String, dynamic>> _searchWithKeyword({
    required String keyword,
    String? genre,
    String? type,
    String? year,
    String? rating,
    String? sortBy,
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    // Split keyword into tokens for advanced search
    final rawTokens = keyword.toLowerCase().trim().split(RegExp(r'\s+'));
    // Separate year-like tokens (4 digits) from name tokens
    final yearTokens = <String>[];
    final nameTokens = <String>[];
    for (final token in rawTokens) {
      if (RegExp(r'^\d{4}$').hasMatch(token)) {
        yearTokens.add(token);
      } else {
        nameTokens.add(token);
      }
    }

    // Build a comprehensive search query
    // Fetch a large batch to ensure old movies are included
    final fetchLimit = (limit * 3).clamp(60, 200);

    try {
      // Strategy 1: Firestore prefix search on 'title_lowercase' (case-insensitive)
      final lowerKeyword = keyword.toLowerCase().trim();
      final upperKeyword = lowerKeyword + '\uf8ff';
      final prefixSnapshot = await _moviesRef
          .where('title_lowercase', isGreaterThanOrEqualTo: lowerKeyword)
          .where('title_lowercase', isLessThanOrEqualTo: upperKeyword)
          .orderBy('title_lowercase')
          .limit(fetchLimit)
          .get();

      final prefixMovies = prefixSnapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Strategy 2: search_keywords array for each name token (non-prefix word matching)
      // e.g. searching "Avengers" finds "The Avengers" because "avengers" is a search_keyword
      final keywordResults = <Movie>[];
      final keywordSeenIds = <String>{};
      for (final token in nameTokens) {
        try {
          final kwSnapshot = await _moviesRef
              .where('search_keywords', arrayContains: token)
              .limit(fetchLimit)
              .get();
          for (final doc in kwSnapshot.docs) {
            final movie = Movie.fromMap(doc.data() as Map<String, dynamic>, docId: doc.id);
            if (!keywordSeenIds.contains(movie.id)) {
              keywordSeenIds.add(movie.id);
              keywordResults.add(movie);
            }
          }
        } catch (_) {
          // search_keywords field may not exist yet, skip gracefully
        }
      }

      // Also fetch recent movies to find older ones
      Query broaderQuery = _moviesRef.orderBy('createdAt', descending: true);
      if (startAfter != null) {
        broaderQuery = broaderQuery.startAfterDocument(startAfter);
      }
      broaderQuery = broaderQuery.limit(fetchLimit);

      final broaderSnapshot = await broaderQuery.get();
      final broaderMovies = broaderSnapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Combine results from all strategies, deduplicating by ID
      final seenIds = <String>{};
      final allMovies = <Movie>[];

      for (final m in [...prefixMovies, ...keywordResults, ...broaderMovies]) {
        if (!seenIds.contains(m.id)) {
          seenIds.add(m.id);
          allMovies.add(m);
        }
      }

      // Apply token-based advanced filtering
      var filtered = allMovies.where((m) {
        // All name tokens must be contained in the movie title (case-insensitive)
        final lowerTitle = m.titleLowercase;
        final nameMatch = nameTokens.isEmpty ||
            nameTokens.every((token) => lowerTitle.contains(token));

        // If year tokens present, at least one must match the movie year
        final yearMatch = yearTokens.isEmpty ||
            (m.year != null && yearTokens.contains(m.year!.toLowerCase()));

        return nameMatch && yearMatch;
      }).toList();

      // Apply additional filters
      if (genre != null && genre.isNotEmpty) {
        filtered = filtered.where((m) => m.categories.contains(genre)).toList();
      }
      if (type != null && type.isNotEmpty) {
        filtered = filtered.where((m) => m.type == type).toList();
      }
      if (year != null && year.isNotEmpty) {
        filtered = filtered.where((m) => m.year == year).toList();
      }
      if (rating != null && rating.isNotEmpty) {
        final minRating = double.tryParse(rating) ?? 0.0;
        filtered = filtered.where((m) {
          final movieRating = double.tryParse(m.rating ?? '0') ?? 0.0;
          return movieRating >= minRating;
        }).toList();
      }

      // Sort results
      if (sortBy == 'rating') {
        filtered.sort((a, b) =>
            (double.tryParse(b.rating ?? '0') ?? 0.0)
            .compareTo(double.tryParse(a.rating ?? '0') ?? 0.0));
      } else if (sortBy == 'name') {
        filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      } else {
        filtered.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
      }

      final hasMore = filtered.length > limit ||
          broaderMovies.length >= fetchLimit;

      return {
        'movies': filtered.take(limit).toList(),
        'hasMore': hasMore,
        'lastDoc': broaderSnapshot.docs.isNotEmpty ? broaderSnapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('_searchWithKeyword failed: $e');
      return {
        'movies': <Movie>[],
        'hasMore': false,
        'lastDoc': null,
      };
    }
  }

  /// Get available years from movies collection
  Future<List<String>> getAvailableYears() async {
    try {
      final snapshot = await _moviesRef.limit(100).get();
      final years = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final year = data['year']?.toString();
        if (year != null && year.isNotEmpty && year != 'null') {
          years.add(year);
        }
      }
      final sortedYears = years.toList()
        ..sort((a, b) => b.compareTo(a)); // Descending: newest first
      return sortedYears;
    } catch (e) {
      debugPrint('getAvailableYears failed: $e');
      return [];
    }
  }

  /// Get all genres
  Future<List<TagAndGenres>> getGenres() async {
    final snapshot = await _genresRef.orderBy('name').get();
    return snapshot.docs
        .map((doc) => TagAndGenres.fromMap(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ))
        .toList();
  }

  /// Get all tags
  Future<List<TagAndGenres>> getTags() async {
    final snapshot = await _tagsRef.orderBy('name').get();
    return snapshot.docs
        .map((doc) => TagAndGenres.fromMap(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ))
        .toList();
  }

  /// Get all collections
  Future<List<TagAndGenres>> getCollections() async {
    final snapshot = await _collectionsRef.orderBy('name').get();
    return snapshot.docs
        .map((doc) => TagAndGenres.fromMap(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ))
        .toList();
  }

  /// Get movies by collection name
  Future<Map<String, dynamic>> getMoviesByCollection(
    String collectionName, {
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _moviesRef
          .where('collections', arrayContains: collectionName)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final movies = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      return {
        'movies': movies,
        'hasMore': snapshot.docs.length >= limit,
        'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('getMoviesByCollection with orderBy failed, trying fallback: $e');
      try {
        Query query = _moviesRef
            .where('collections', arrayContains: collectionName)
            .limit(limit);

        final snapshot = await query.get();
        final movies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

        return {
          'movies': movies,
          'hasMore': snapshot.docs.length >= limit,
          'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        };
      } catch (e2) {
        debugPrint('getMoviesByCollection fallback also failed: $e2');
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }
  }

  /// Get movies by tag name (simple list, for home screen sections)
  Future<List<Movie>> getMoviesByTagSimple(String tagName, {int limit = 50}) async {
    try {
      final snapshot = await _moviesRef
          .where('tags', arrayContains: tagName)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();
    } catch (e) {
      // Fallback without orderBy if composite index missing
      debugPrint('getMoviesByTagSimple with orderBy failed, trying fallback: $e');
      try {
        final snapshot = await _moviesRef
            .where('tags', arrayContains: tagName)
            .limit(limit)
            .get();

        final movies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
        return movies;
      } catch (e2) {
        debugPrint('getMoviesByTagSimple fallback also failed: $e2');
        return [];
      }
    }
  }

  /// Get movies/series featuring a specific actor by name.
  /// Searches Firestore 'casts' array for objects with matching 'name' field.
  /// This only returns items already in the library (no TMDB API call).
  Future<List<Movie>> getMoviesByActor(String actorName) async {
    try {
      // Firestore doesn't support querying inside array of objects directly,
      // so we fetch recent posts and filter client-side by cast name.
      final snapshot = await _moviesRef
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get();

      final movies = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            // Check if this movie's casts contain the actor
            final casts = data['casts'] as List?;
            if (casts != null) {
              final hasActor = casts.any((cast) {
                if (cast is Map<String, dynamic>) {
                  return (cast['name'] as String?)?.toLowerCase() ==
                      actorName.toLowerCase();
                }
                return false;
              });
              if (hasActor) {
                return Movie.fromMap(data, docId: doc.id);
              }
            }
            return null;
          })
          .whereType<Movie>()
          .toList();

      return movies;
    } catch (e) {
      debugPrint('getMoviesByActor failed: $e');
      // Fallback: try without orderBy
      try {
        final snapshot = await _moviesRef.limit(100).get();
        final movies = snapshot.docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final casts = data['casts'] as List?;
              if (casts != null) {
                final hasActor = casts.any((cast) {
                  if (cast is Map<String, dynamic>) {
                    return (cast['name'] as String?)?.toLowerCase() ==
                        actorName.toLowerCase();
                  }
                  return false;
                });
                if (hasActor) {
                  return Movie.fromMap(data, docId: doc.id);
                }
              }
              return null;
            })
            .whereType<Movie>()
            .toList();
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
        return movies;
      } catch (e2) {
        debugPrint('getMoviesByActor fallback also failed: $e2');
        return [];
      }
    }
  }

  // ==================== ADMIN VERIFICATION (Defense-in-Depth) ====================

  /// Verify that the current user is an admin by checking Firestore directly.
  /// This provides defense-in-depth beyond just Firestore rules — even if rules
  /// are misconfigured, the client-side check prevents accidental admin operations.
  Future<bool> _isCurrentUserAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;
      final data = doc.data()!;
      return data['role'] == 'admin' || data['isAdmin'] == true;
    } catch (e) {
      debugPrint('Admin verification failed: $e');
      return false;
    }
  }

  /// Throws an exception if the current user is not an admin.
  /// Call this at the start of every admin-only operation.
  Future<void> _requireAdmin() async {
    final isAdmin = await _isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception('Admin permission required. You are not authorized to perform this action.');
    }
  }

  // ==================== ADMIN CRUD OPERATIONS ====================

  /// Generate slug from title
  String _generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
  }

  /// Add a new movie (admin only)
  /// Checks for duplicate tmdbId FIRST, then falls back to slug check.
  /// If a document with the same tmdbId exists, it updates instead of creating a duplicate.
  Future<String> addMovie(Map<String, dynamic> data) async {
    await _requireAdmin();
    // Auto-generate slug if not provided
    if (!data.containsKey('slug') || (data['slug'] as String).isEmpty) {
      data['slug'] = _generateSlug(data['title'] as String);
    }

    // Auto-generate 'title_lowercase' for case-insensitive Firestore search
    if (data.containsKey('title') && (data['title'] as String).isNotEmpty) {
      data['title_lowercase'] = (data['title'] as String).toLowerCase();
      // Auto-generate 'search_keywords' array for word-level Firestore search
      data['search_keywords'] = _generateSearchKeywords(data['title'] as String);
    }

    // === PRIORITY 1: Check for duplicate tmdbId ===
    final tmdbId = data['tmdbId'];
    if (tmdbId != null) {
      final existingByTmdbId = await findByTmdbId(tmdbId);
      if (existingByTmdbId != null) {
        final existingData = existingByTmdbId.data() as Map<String, dynamic>;
        debugPrint('tmdbId $tmdbId already exists (doc: ${existingByTmdbId.id}), updating instead of creating duplicate');
        // Build safe update map — only update TMDB fields, preserve user-edited fields
        final safeData = _buildSafeUpdateMap(data, existingData);
        safeData['updatedAt'] = FieldValue.serverTimestamp();
        safeData.remove('createdAt');
        // Remove fields that should never be overwritten
        safeData.remove('slug'); // Keep existing slug
        safeData.remove('downloadLinks'); // Keep user's download links
        safeData.remove('seasons'); // Keep user's seasons/episodes
        safeData.remove('tags'); // Keep user's tags
        safeData.remove('isTrending'); // Keep user's trending status

        // Update category counts
        final oldCategories = List<String>.from(existingData['categories'] ?? []);
        final oldTags = List<String>.from(existingData['tags'] ?? []);
        final newCategories = List<String>.from(safeData['categories'] ?? oldCategories);
        final newTags = List<String>.from(safeData['tags'] ?? oldTags);
        for (final cat in oldCategories) {
          if (!newCategories.contains(cat)) await _decrementCount(_genresRef, cat);
        }
        for (final cat in newCategories) {
          if (!oldCategories.contains(cat)) await _incrementCount(_genresRef, cat);
        }
        for (final tag in oldTags) {
          if (!newTags.contains(tag)) await _decrementCount(_tagsRef, tag);
        }
        for (final tag in newTags) {
          if (!oldTags.contains(tag)) await _incrementCount(_tagsRef, tag);
        }

        await existingByTmdbId.reference.update(safeData);
        return existingByTmdbId.id;
      }
    }

    // === PRIORITY 2: Check for duplicate slug ===
    final slug = data['slug'] as String;
    final existingSnapshot = await _moviesRef
        .where('slug', isEqualTo: slug)
        .limit(1)
        .get();

    if (existingSnapshot.docs.isNotEmpty) {
      // A document with this slug already exists - update it instead
      final existingDoc = existingSnapshot.docs.first;
      final existingData = existingDoc.data() as Map<String, dynamic>;
      debugPrint('Slug "$slug" already exists (doc: ${existingDoc.id}), updating instead of creating duplicate');
      final safeData = _buildSafeUpdateMap(data, existingData);
      safeData['updatedAt'] = FieldValue.serverTimestamp();
      safeData.remove('createdAt');
      safeData.remove('slug');
      safeData.remove('downloadLinks');
      safeData.remove('seasons');
      safeData.remove('tags');
      safeData.remove('isTrending');

      // Update category counts
      final oldCategories = List<String>.from(existingData['categories'] ?? []);
      final oldTags = List<String>.from(existingData['tags'] ?? []);
      final newCategories = List<String>.from(safeData['categories'] ?? oldCategories);
      final newTags = List<String>.from(safeData['tags'] ?? oldTags);
      for (final cat in oldCategories) {
        if (!newCategories.contains(cat)) await _decrementCount(_genresRef, cat);
      }
      for (final cat in newCategories) {
        if (!oldCategories.contains(cat)) await _incrementCount(_genresRef, cat);
      }
      for (final tag in oldTags) {
        if (!newTags.contains(tag)) await _decrementCount(_tagsRef, tag);
      }
      for (final tag in newTags) {
        if (!oldTags.contains(tag)) await _incrementCount(_tagsRef, tag);
      }

      await existingDoc.reference.update(safeData);
      return existingDoc.id;
    }

    // === No duplicate: Create new document ===
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();

    final docRef = await _moviesRef.add(data);

    // Update genre moviesCount
    if (data.containsKey('categories')) {
      for (final genreName in data['categories'] as List) {
        await _incrementCount(_genresRef, genreName.toString());
      }
    }

    // Update tag moviesCount
    if (data.containsKey('tags')) {
      for (final tagName in data['tags'] as List) {
        await _incrementCount(_tagsRef, tagName.toString());
      }
    }

    return docRef.id;
  }

  /// Build a safe update map from TMDB data that only contains
  /// fields that should be updated from TMDB, preserving user-edited fields.
  static const _tmdbUpdateFields = [
    'title', 'title_lowercase', 'year', 'poster', 'backdrop', 'overview', 'rating',
    'duration', 'type', 'isAdult', 'categories', 'directors',
    'casts', 'tmdbId', 'country', 'status',
  ];

  Map<String, dynamic> _buildSafeUpdateMap(
    Map<String, dynamic> newData,
    Map<String, dynamic> existingData,
  ) {
    final result = <String, dynamic>{};
    for (final field in _tmdbUpdateFields) {
      if (newData.containsKey(field)) {
        final value = newData[field];

        // CRITICAL: skip empty / null / blank values so we never overwrite an
        // existing non-empty value with junk. This was the root cause of the
        // "posters disappeared after Batch Import" bug — when a JSON import
        // file omitted the poster field or set it to "", the old code would
        // happily write an empty string over the existing poster URL, leaving
        // the admin panel showing movies with no poster image.
        //
        // Rules:
        //   - null            → skip (don't update)
        //   - empty string    → skip (don't update — keep existing)
        //   - whitespace-only → skip (don't update)
        //   - empty list/map  → skip (don't wipe existing categories/tags/etc.)
        //   - anything else   → update
        if (_isEmptyValue(value)) continue;

        result[field] = value;
      }
    }
    return result;
  }

  /// Returns true if [value] is "empty" in the sense that it should NOT be
  /// used to overwrite an existing non-empty value during an update.
  /// See [_buildSafeUpdateMap] for the rationale.
  bool _isEmptyValue(dynamic value) {
    if (value == null) return true;
    if (value is String && value.trim().isEmpty) return true;
    if (value is List && value.isEmpty) return true;
    if (value is Map && value.isEmpty) return true;
    return false;
  }

  /// Update a movie (admin only)
  Future<void> updateMovie(String id, Map<String, dynamic> data) async {
    await _requireAdmin();
    // Get old movie data to update counts
    final oldDoc = await _moviesRef.doc(id).get();
    if (oldDoc.exists) {
      final oldData = oldDoc.data() as Map<String, dynamic>;
      final oldCategories = List<String>.from(oldData['categories'] ?? []);
      final oldTags = List<String>.from(oldData['tags'] ?? []);

      final newCategories = List<String>.from(data['categories'] ?? oldCategories);
      final newTags = List<String>.from(data['tags'] ?? oldTags);

      // Use batch writes for count updates to prevent hanging on sequential writes
      final batch = _firestore.batch();

      // Decrement old categories that are removed
      for (final cat in oldCategories) {
        if (!newCategories.contains(cat)) {
          await _batchDecrementCount(batch, _genresRef, cat);
        }
      }
      // Increment new categories that are added
      for (final cat in newCategories) {
        if (!oldCategories.contains(cat)) {
          await _batchIncrementCount(batch, _genresRef, cat);
        }
      }

      // Decrement old tags that are removed
      for (final tag in oldTags) {
        if (!newTags.contains(tag)) {
          await _batchDecrementCount(batch, _tagsRef, tag);
        }
      }
      // Increment new tags that are added
      for (final tag in newTags) {
        if (!oldTags.contains(tag)) {
          await _batchIncrementCount(batch, _tagsRef, tag);
        }
      }

      // Commit all count updates in a single batch write
      await batch.commit();
    }

    data['updatedAt'] = FieldValue.serverTimestamp();

    // Auto-update 'title_lowercase' and 'search_keywords' when title changes
    if (data.containsKey('title') && (data['title'] as String).isNotEmpty) {
      data['title_lowercase'] = (data['title'] as String).toLowerCase();
      data['search_keywords'] = _generateSearchKeywords(data['title'] as String);
    }

    await _moviesRef.doc(id).update(data);
  }

  /// Delete a movie (admin only)
  Future<void> deleteMovie(String id) async {
    await _requireAdmin();
    // Get movie data to update counts
    final doc = await _moviesRef.doc(id).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;

      // Use batch writes for count updates
      final batch = _firestore.batch();

      // Decrement genre counts
      final categories = List<String>.from(data['categories'] ?? []);
      for (final genreName in categories) {
        await _batchDecrementCount(batch, _genresRef, genreName);
      }

      // Decrement tag counts
      final tags = List<String>.from(data['tags'] ?? []);
      for (final tagName in tags) {
        await _batchDecrementCount(batch, _tagsRef, tagName);
      }

      // Commit all count updates in a single batch write
      await batch.commit();
    }

    await _moviesRef.doc(id).delete();
  }

  /// Add a genre (admin only)
  Future<String> addGenre(String name) async {
    await _requireAdmin();
    final docRef = await _genresRef.add({
      'name': name,
      'moviesCount': 0,
    });
    return docRef.id;
  }

  /// Update a genre (admin only)
  Future<void> updateGenre(String id, String name) async {
    await _requireAdmin();
    await _genresRef.doc(id).update({'name': name});
  }

  /// Delete a genre (admin only)
  Future<void> deleteGenre(String id) async {
    await _requireAdmin();
    await _genresRef.doc(id).delete();
  }

  /// Add a tag (admin only)
  Future<String> addTag(String name) async {
    await _requireAdmin();
    final docRef = await _tagsRef.add({
      'name': name,
      'moviesCount': 0,
    });
    return docRef.id;
  }

  /// Update a tag (admin only)
  Future<void> updateTag(String id, String name) async {
    await _requireAdmin();
    await _tagsRef.doc(id).update({'name': name});
  }

  /// Delete a tag (admin only)
  Future<void> deleteTag(String id) async {
    await _requireAdmin();
    await _tagsRef.doc(id).delete();
  }

  /// Add a collection (admin only)
  Future<String> addCollection(String name) async {
    await _requireAdmin();
    final docRef = await _collectionsRef.add({
      'name': name,
      'moviesCount': 0,
    });
    return docRef.id;
  }

  /// Update a collection (admin only)
  Future<void> updateCollection(String id, String name) async {
    await _requireAdmin();
    await _collectionsRef.doc(id).update({'name': name});
  }

  /// Delete a collection (admin only)
  Future<void> deleteCollection(String id) async {
    await _requireAdmin();
    await _collectionsRef.doc(id).delete();
  }

  // ==================== BACKFILL & BANNER CONFIG ====================

  /// Generate search keywords from title for word-level Firestore search.
  /// Splits title into individual lowercase words, stripping punctuation.
  /// e.g. "The Avengers: Endgame" → ["the", "avengers", "endgame"]
  List<String> _generateSearchKeywords(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')  // Replace non-word chars with space
        .split(RegExp(r'\s+'))                     // Split on whitespace
        .where((word) => word.isNotEmpty && word.length >= 2)  // Skip empty & single-char
        .toList();
  }

  /// Get banner configuration from Firestore
  /// Reads 'imageUrls' array from 'app_settings/banner_config' document
  Future<List<String>> getBannerConfig() async {
    try {
      final doc = await _firestore.collection('app_settings').doc('banner_config').get();
      if (!doc.exists) return [];
      final data = doc.data()!;
      final urls = data['imageUrls'] as List?;
      if (urls == null) return [];
      return urls.map((url) => url.toString()).where((url) => url.isNotEmpty).toList();
    } catch (e) {
      debugPrint('getBannerConfig failed: $e');
      return [];
    }
  }

  /// Save banner configuration to Firestore
  /// Writes 'imageUrls' array to 'app_settings/banner_config' document
  Future<void> saveBannerConfig(List<String> imageUrls) async {
    await _requireAdmin();
    try {
      await _firestore.collection('app_settings').doc('banner_config').set({
        'imageUrls': imageUrls,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('saveBannerConfig failed: $e');
      rethrow;
    }
  }

  // ==================== HELPER METHODS ====================

  /// Increment moviesCount for a genre/tag/collection by name
  Future<void> _incrementCount(CollectionReference ref, String name) async {
    final snapshot = await ref.where('name', isEqualTo: name).limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final currentCount = (doc.data() as Map<String, dynamic>)['moviesCount'] as int? ?? 0;
      await doc.reference.update({'moviesCount': currentCount + 1});
    }
  }

  /// Decrement moviesCount for a genre/tag/collection by name
  Future<void> _decrementCount(CollectionReference ref, String name) async {
    final snapshot = await ref.where('name', isEqualTo: name).limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final currentCount = (doc.data() as Map<String, dynamic>)['moviesCount'] as int? ?? 0;
      if (currentCount > 0) {
        await doc.reference.update({'moviesCount': currentCount - 1});
      }
    }
  }

  /// Batch increment — adds count update to a WriteBatch instead of committing individually
  Future<void> _batchIncrementCount(WriteBatch batch, CollectionReference ref, String name) async {
    final snapshot = await ref.where('name', isEqualTo: name).limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final currentCount = (doc.data() as Map<String, dynamic>)['moviesCount'] as int? ?? 0;
      batch.update(doc.reference, {'moviesCount': currentCount + 1});
    }
  }

  /// Batch decrement — adds count update to a WriteBatch instead of committing individually
  Future<void> _batchDecrementCount(WriteBatch batch, CollectionReference ref, String name) async {
    final snapshot = await ref.where('name', isEqualTo: name).limit(1).get();
    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final currentCount = (doc.data() as Map<String, dynamic>)['moviesCount'] as int? ?? 0;
      if (currentCount > 0) {
        batch.update(doc.reference, {'moviesCount': currentCount - 1});
      }
    }
  }
}
