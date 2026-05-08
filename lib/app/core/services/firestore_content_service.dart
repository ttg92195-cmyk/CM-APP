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

  /// Search movies by keyword (client-side for reliability)
  Future<Map<String, dynamic>> searchMovies(
    String keyword, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    final lowerKeyword = keyword.toLowerCase().trim();
    if (lowerKeyword.isEmpty) {
      return {'movies': <Movie>[], 'hasMore': false, 'lastDoc': null};
    }

    // Primary approach: Fetch all movies and filter client-side
    // This is more reliable than Firestore prefix search which is case-sensitive
    try {
      final snapshot = await _moviesRef.limit(500).get();
      final allMovies = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // Client-side case-insensitive search - matches anywhere in title
      final filtered = allMovies
          .where((m) => m.title.toLowerCase().contains(lowerKeyword))
          .toList();

      return {
        'movies': filtered.take(limit).toList(),
        'hasMore': filtered.length > limit,
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
      debugPrint('Slug "$slug" already exists (doc: ${existingDoc.id}), updating instead of creating duplicate');
      data['updatedAt'] = FieldValue.serverTimestamp();
      // Don't overwrite createdAt if document exists
      data.remove('createdAt');
      await existingDoc.reference.update(data);

      // Update genre/tag counts for new selections
      if (data.containsKey('categories')) {
        for (final genreName in data['categories'] as List) {
          await _incrementCount(_genresRef, genreName.toString());
        }
      }
      if (data.containsKey('tags')) {
        for (final tagName in data['tags'] as List) {
          await _incrementCount(_tagsRef, tagName.toString());
        }
      }

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
