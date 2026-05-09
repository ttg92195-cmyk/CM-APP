import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  /// Get movies with cursor-based pagination
  Future<Map<String, dynamic>> getMovies({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _moviesRef
          .where('type', isEqualTo: 'movie')
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

        // Sort client-side
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

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
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _moviesRef
          .where('type', isEqualTo: 'series')
          .orderBy('createdAt', descending: true)
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

        // Sort client-side
        series.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

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
  Future<List<Movie>> searchAllPosts(String keyword) async {
    if (keyword.trim().isEmpty) return [];

    final lowerKeyword = keyword.toLowerCase();
    final upperKeyword = lowerKeyword + '\uf8ff';

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
  }

  /// Get trending movies
  Future<List<Movie>> getTrendingMovies() async {
    try {
      final snapshot = await _moviesRef
          .where('type', isEqualTo: 'movie')
          .where('isTrending', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(20)
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
            .limit(20)
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
          .limit(20)
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
            .limit(20)
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
    int limit = 20,
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
    int limit = 20,
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

  /// Search movies by keyword using Firestore prefix search + client-side fallback
  Future<Map<String, dynamic>> searchMovies(
    String keyword, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    final lowerKeyword = keyword.toLowerCase().trim();
    if (lowerKeyword.isEmpty) {
      return {'movies': <Movie>[], 'hasMore': false, 'lastDoc': null};
    }

    // Primary approach: Firestore prefix search (server-side, efficient)
    try {
      final upperKeyword = lowerKeyword + '\uf8ff';
      final snapshot = await _moviesRef
          .where('title', isGreaterThanOrEqualTo: lowerKeyword)
          .where('title', isLessThanOrEqualTo: upperKeyword)
          .orderBy('title')
          .limit(limit * 2) // Fetch extra to account for case mismatches
          .get();

      var results = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Firestore prefix search is case-sensitive, so also do a
      // case-insensitive contains filter client-side as enhancement
      final filtered = results
          .where((m) => m.title.toLowerCase().contains(lowerKeyword))
          .toList();

      // If prefix search found enough results, return them
      if (filtered.length >= limit) {
        return {
          'movies': filtered.take(limit).toList(),
          'hasMore': filtered.length > limit,
          'lastDoc': null,
        };
      }

      // If prefix search didn't find enough, supplement with a broader search
      // but limit to 50 docs to avoid excessive reads
      final broaderSnapshot = await _moviesRef.limit(50).get();
      final broaderMovies = broaderSnapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Combine results, avoiding duplicates
      final seenIds = results.map((m) => m.id).toSet();
      final additionalMovies = broaderMovies
          .where((m) => !seenIds.contains(m.id) && m.title.toLowerCase().contains(lowerKeyword))
          .toList();

      final combined = [...filtered, ...additionalMovies];
      return {
        'movies': combined.take(limit).toList(),
        'hasMore': combined.length > limit,
        'lastDoc': null,
      };
    } catch (e) {
      debugPrint('searchMovies failed: $e');
      return {
        'movies': <Movie>[],
        'hasMore': false,
        'lastDoc': null,
      };
    }
  }

  /// Search movies with multiple filters (client-side for reliability)
  /// Supports: keyword, genre, type, year, rating, and sorting
  Future<Map<String, dynamic>> searchMoviesWithFilters({
    String? keyword,
    String? genre,
    String? type, // 'movie' or 'series'
    String? year,
    String? rating, // e.g. '7', '8' - minimum rating
    String? sortBy, // 'latest', 'rating', 'name'
    int limit = 50,
  }) async {
    try {
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
        // Default: latest first - only if no genre filter (needs composite index)
        if (genre == null || genre.isEmpty) {
          query = query.orderBy('createdAt', descending: true);
        }
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

      // Keyword filter
      if (keyword != null && keyword.trim().isNotEmpty) {
        final lowerKeyword = keyword.toLowerCase().trim();
        filtered = filtered
            .where((m) => m.title.toLowerCase().contains(lowerKeyword))
            .toList();
      }

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
        'hasMore': filtered.length > limit,
        'lastDoc': null,
      };
    } catch (e) {
      debugPrint('searchMoviesWithFilters failed: $e');
      // Fallback: fetch all and filter entirely client-side
      try {
        final snapshot = await _moviesRef.limit(limit).get();
        var allMovies = snapshot.docs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();

        var filtered = allMovies;

        if (keyword != null && keyword.trim().isNotEmpty) {
          final lowerKeyword = keyword.toLowerCase().trim();
          filtered = filtered
              .where((m) => m.title.toLowerCase().contains(lowerKeyword))
              .toList();
        }
        if (genre != null && genre.isNotEmpty) {
          filtered = filtered
              .where((m) => m.categories.contains(genre))
              .toList();
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

        // Default sort: latest first
        filtered.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

        return {
          'movies': filtered.take(limit).toList(),
          'hasMore': filtered.length > limit,
          'lastDoc': null,
        };
      } catch (e2) {
        debugPrint('searchMoviesWithFilters fallback also failed: $e2');
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
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
    int limit = 20,
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
  Future<List<Movie>> getMoviesByTagSimple(String tagName, {int limit = 20}) async {
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

  /// Add a new movie
  Future<String> addMovie(Map<String, dynamic> data) async {
    // Auto-generate slug if not provided
    if (!data.containsKey('slug') || (data['slug'] as String).isEmpty) {
      data['slug'] = _generateSlug(data['title'] as String);
    }

    // Check for duplicate slug - if exists, update instead of creating new
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
      data['updatedAt'] = FieldValue.serverTimestamp();
      // Don't overwrite createdAt if document exists
      data.remove('createdAt');

      // Calculate category/tag count changes (same logic as updateMovie)
      final oldCategories = List<String>.from(existingData['categories'] ?? []);
      final oldTags = List<String>.from(existingData['tags'] ?? []);
      final newCategories = List<String>.from(data['categories'] ?? oldCategories);
      final newTags = List<String>.from(data['tags'] ?? oldTags);

      // Decrement old categories that are removed
      for (final cat in oldCategories) {
        if (!newCategories.contains(cat)) {
          await _decrementCount(_genresRef, cat);
        }
      }
      // Increment new categories that are added
      for (final cat in newCategories) {
        if (!oldCategories.contains(cat)) {
          await _incrementCount(_genresRef, cat);
        }
      }

      // Decrement old tags that are removed
      for (final tag in oldTags) {
        if (!newTags.contains(tag)) {
          await _decrementCount(_tagsRef, tag);
        }
      }
      // Increment new tags that are added
      for (final tag in newTags) {
        if (!oldTags.contains(tag)) {
          await _incrementCount(_tagsRef, tag);
        }
      }

      await existingDoc.reference.update(data);

      return existingDoc.id;
    }

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

  /// Update a movie
  Future<void> updateMovie(String id, Map<String, dynamic> data) async {
    // Get old movie data to update counts
    final oldDoc = await _moviesRef.doc(id).get();
    if (oldDoc.exists) {
      final oldData = oldDoc.data() as Map<String, dynamic>;
      final oldCategories = List<String>.from(oldData['categories'] ?? []);
      final oldTags = List<String>.from(oldData['tags'] ?? []);

      final newCategories = List<String>.from(data['categories'] ?? oldCategories);
      final newTags = List<String>.from(data['tags'] ?? oldTags);

      // Decrement old categories that are removed
      for (final cat in oldCategories) {
        if (!newCategories.contains(cat)) {
          await _decrementCount(_genresRef, cat);
        }
      }
      // Increment new categories that are added
      for (final cat in newCategories) {
        if (!oldCategories.contains(cat)) {
          await _incrementCount(_genresRef, cat);
        }
      }

      // Decrement old tags that are removed
      for (final tag in oldTags) {
        if (!newTags.contains(tag)) {
          await _decrementCount(_tagsRef, tag);
        }
      }
      // Increment new tags that are added
      for (final tag in newTags) {
        if (!oldTags.contains(tag)) {
          await _incrementCount(_tagsRef, tag);
        }
      }
    }

    data['updatedAt'] = FieldValue.serverTimestamp();
    await _moviesRef.doc(id).update(data);
  }

  /// Delete a movie
  Future<void> deleteMovie(String id) async {
    // Get movie data to update counts
    final doc = await _moviesRef.doc(id).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;

      // Decrement genre counts
      final categories = List<String>.from(data['categories'] ?? []);
      for (final genreName in categories) {
        await _decrementCount(_genresRef, genreName);
      }

      // Decrement tag counts
      final tags = List<String>.from(data['tags'] ?? []);
      for (final tagName in tags) {
        await _decrementCount(_tagsRef, tagName);
      }
    }

    await _moviesRef.doc(id).delete();
  }

  /// Add a genre
  Future<String> addGenre(String name) async {
    final docRef = await _genresRef.add({
      'name': name,
      'moviesCount': 0,
    });
    return docRef.id;
  }

  /// Update a genre
  Future<void> updateGenre(String id, String name) async {
    await _genresRef.doc(id).update({'name': name});
  }

  /// Delete a genre
  Future<void> deleteGenre(String id) async {
    await _genresRef.doc(id).delete();
  }

  /// Add a tag
  Future<String> addTag(String name) async {
    final docRef = await _tagsRef.add({
      'name': name,
      'moviesCount': 0,
    });
    return docRef.id;
  }

  /// Update a tag
  Future<void> updateTag(String id, String name) async {
    await _tagsRef.doc(id).update({'name': name});
  }

  /// Delete a tag
  Future<void> deleteTag(String id) async {
    await _tagsRef.doc(id).delete();
  }

  /// Add a collection
  Future<String> addCollection(String name) async {
    final docRef = await _collectionsRef.add({
      'name': name,
      'moviesCount': 0,
    });
    return docRef.id;
  }

  /// Update a collection
  Future<void> updateCollection(String id, String name) async {
    await _collectionsRef.doc(id).update({'name': name});
  }

  /// Delete a collection
  Future<void> deleteCollection(String id) async {
    await _collectionsRef.doc(id).delete();
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
}
