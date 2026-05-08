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
  }

  /// Get series with cursor-based pagination
  Future<Map<String, dynamic>> getSeries({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
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
  }

  /// Get trending TV shows
  Future<List<Movie>> getTrendingTvShows() async {
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
  }

  /// Get movie detail by slug
  Future<MovieDetail?> getMovieBySlug(String slug) async {
    final snapshot = await _moviesRef
        .where('slug', isEqualTo: slug)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    return MovieDetail.fromMap(
      doc.data() as Map<String, dynamic>,
      docId: doc.id,
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
  }

  /// Get movies by tag name
  Future<Map<String, dynamic>> getMoviesByTag(
    String tagName, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
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
  }

  /// Search movies by keyword (prefix match)
  Future<Map<String, dynamic>> searchMovies(
    String keyword, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    final lowerKeyword = keyword.toLowerCase();
    final upperKeyword = lowerKeyword + '\uf8ff';

    Query query = _moviesRef
        .where('title', isGreaterThanOrEqualTo: lowerKeyword)
        .where('title', isLessThanOrEqualTo: upperKeyword)
        .orderBy('title')
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

  /// Get movies by tag name (simple list, for home screen sections)
  Future<List<Movie>> getMoviesByTagSimple(String tagName, {int limit = 20}) async {
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
