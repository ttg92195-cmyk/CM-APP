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
    // === PRIMARY: orderBy('updatedAt', descending) — admin edits bump to top ===
    // Requires composite index (type ASC, updatedAt DESC). Declared in
    // firestore.indexes.json. If the index isn't deployed yet (e.g., Bro
    // hasn't run `firebase deploy --only firestore:indexes`), this query
    // throws and we fall through to the SECONDARY path below.
    try {
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
      debugPrint('getMovies: primary orderBy(updatedAt) failed: $e — trying createdAt fallback');
    }

    // === SECONDARY: orderBy('createdAt', descending) ===
    // Uses the EXISTING composite index (type ASC, createdAt DESC) declared
    // in firestore.indexes.json. New movies (created via TMDB Generator /
    // Admin Panel / Batch Import) all have createdAt set to server
    // timestamp at creation time, so this puts newly-added movies at the
    // top of the list — fixing Bro's 'TMDB Generator new movie doesn't
    // appear at top of Home' bug.
    //
    // Trade-off vs primary: admin EDITS won't bump a movie to the top
    // (createdAt is preserved on update, only updatedAt changes). That's
    // an acceptable degradation when the updatedAt index isn't deployed
    // yet — better than showing a stale random sample.
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
      debugPrint('getMovies: secondary orderBy(createdAt) also failed: $e — falling back to no-orderBy');
    }

    // === TERTIARY: no orderBy — last-resort for legacy docs missing both
    //     timestamps. Fetches by document ID order (essentially arbitrary)
    //     and sorts client-side. With small `limit` (e.g., Home's 10),
    //     this returns a non-representative sample — new movies likely
    //     missing. Acceptable only when primary and secondary both fail.
    try {
      Query query = _moviesRef
          .where('type', isEqualTo: 'movie')
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
      debugPrint('getMovies: no-orderBy fallback also failed: $e2');
      return {
        'movies': <Movie>[],
        'hasMore': false,
        'lastDoc': null,
      };
    }
  }

  /// Get series with cursor-based pagination
  Future<Map<String, dynamic>> getSeries({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    // === PRIMARY: orderBy('updatedAt', descending) — admin edits bump to top ===
    // See getMovies() for the rationale behind the 3-tier fallback strategy.
    try {
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
      debugPrint('getSeries: primary orderBy(updatedAt) failed: $e — trying createdAt fallback');
    }

    // === SECONDARY: orderBy('createdAt', descending) ===
    // Uses the EXISTING composite index (type ASC, createdAt DESC). New
    // series appear at the top of the list. See getMovies() for full
    // explanation of the trade-off vs primary.
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
      debugPrint('getSeries: secondary orderBy(createdAt) also failed: $e — falling back to no-orderBy');
    }

    // === TERTIARY: no orderBy — last-resort for legacy docs missing both
    //     timestamps. See getMovies() for full explanation.
    try {
      Query query = _moviesRef
          .where('type', isEqualTo: 'series')
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
      debugPrint('getSeries: no-orderBy fallback also failed: $e2');
      return {
        'movies': <Movie>[],
        'hasMore': false,
        'lastDoc': null,
      };
    }
  }

  /// Get all movies and series (for admin panel).
  ///
  /// Robustness strategy mirrors getMovies() / getSeries():
  ///   1. PRIMARY  — orderBy('updatedAt', descending). This is the same field
  ///      Home uses, so movies that appear on Home will appear here too.
  ///   2. FALLBACK — If primary throws (e.g., missing index) OR returns 0
  ///      docs (e.g., legacy movies that have neither 'updatedAt' nor
  ///      'createdAt' because they were created via an older code path),
  ///      retry without orderBy and sort client-side. This guarantees that
  ///      the Admin Panel NEVER shows an empty list when movies exist.
  ///
  /// Background: a previous regression caused the Admin Panel → All tab to
  /// appear empty even though Home showed 1068 movies. Root cause was that
  /// this method used orderBy('createdAt') with no fallback, so any movie
  /// missing the 'createdAt' field was silently excluded from the query
  /// result. Search still worked because searchAllPosts() orders by
  /// 'title_lowercase' (a different field that those movies did have).
  /// This fix aligns getAllPosts() with getMovies() so the three code paths
  /// no longer disagree on which movies "exist".
  Future<Map<String, dynamic>> getAllPosts({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    // === PRIMARY: orderBy('updatedAt') — same field Home uses ===
    try {
      Query query = _moviesRef
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

      // If we got at least one movie, or we got fewer than `limit` (meaning
      // we've reached the end of the collection), this is a trustworthy
      // result — return it.
      if (movies.isNotEmpty || snapshot.docs.length < limit) {
        return {
          'movies': movies,
          'hasMore': snapshot.docs.length >= limit,
          'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        };
      }

      // movies is empty AND snapshot.docs.length >= limit — suspicious.
      // This shouldn't normally happen, but if it does (e.g., all docs in
      // this page were skipped by Movie.fromMap throwing — unlikely), fall
      // through to the no-orderBy fallback below so we don't return empty.
      debugPrint('getAllPosts: primary returned 0 movies but limit=$limit — falling through to no-orderBy fallback');
    } catch (e) {
      // Most likely cause: missing composite index (shouldn't happen here
      // since we have no `where` clause, but the catch is cheap insurance).
      debugPrint('getAllPosts: primary orderBy(updatedAt) failed: $e — falling back to no-orderBy query');
    }

    // === FALLBACK: no orderBy — fetch by document ID order, sort client-side ===
    // This handles the case where movies exist but lack 'updatedAt' (e.g.,
    // legacy imports). Without orderBy, Firestore returns docs in document
    // ID order, which is stable enough for cursor-based pagination to work.
    try {
      Query query = _moviesRef.limit(limit);

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

      // Sort client-side by updatedAt (falls back to createdAt if missing).
      // Movies with neither field sort to the bottom (DateTime(2000)).
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
      debugPrint('getAllPosts: no-orderBy fallback also failed: $e2');
      return {
        'movies': <Movie>[],
        'hasMore': false,
        'lastDoc': null,
      };
    }
  }

  /// Get the REAL total counts of movies/series in Firestore (for Admin Panel
  /// tab labels). Uses Firestore's AggregateQuery.count() which is billed as
  /// a single document read regardless of collection size — cheap and fast.
  ///
  /// Returns a map with keys:
  ///   - 'all'    : total count of documents in the movies collection
  ///   - 'movies' : count where type == 'movie'
  ///   - 'series' : count where type == 'series'
  ///
  /// If any of the count queries fail (e.g., permission denied), the value
  /// is returned as 0 — the caller can fall back to the page-loaded count.
  Future<Map<String, int>> getTotalPostCounts() async {
    try {
      final allCount = await _moviesRef.count().get();
      final moviesCount = await _moviesRef
          .where('type', isEqualTo: 'movie')
          .count()
          .get();
      final seriesCount = await _moviesRef
          .where('type', isEqualTo: 'series')
          .count()
          .get();
      return {
        'all': allCount.count ?? 0,
        'movies': moviesCount.count ?? 0,
        'series': seriesCount.count ?? 0,
      };
    } catch (e) {
      debugPrint('getTotalPostCounts failed: $e');
      return {'all': 0, 'movies': 0, 'series': 0};
    }
  }

  /// Search all posts (for admin panel)
  /// Uses 'title_lowercase' field for case-insensitive prefix search
  /// with substring fallback for short queries (1-2 chars) so that
  /// single-character searches like "o" still return matches.
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

      final prefixResults = snapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // SUBSTRING FALLBACK for short queries (<=2 chars).
      // Same rationale as _searchWithKeyword Strategy 1.5 — see comment there.
      //
      // Always fires for short queries (length <= 2) regardless of whether
      // the prefix search returned matches. This catches titles like
      // "Spider-Man" or "Thor" when the user types "o" — these don't START
      // with "o" so prefix search misses them, but they CONTAIN "o" so the
      // substring fallback finds them. The previous version only fired this
      // fallback when prefixResults was empty, which meant single-letter
      // searches like "o" only returned movies starting with "o" (Ocean's,
      // Once Upon a Time, etc.) — Bro reported this exact bug on the Admin
      // Panel Tab too. Task 25.
      if (lowerKeyword.length <= 2) {
        try {
          final subSnapshot = await _moviesRef.limit(200).get();
          final subResults = subSnapshot.docs
              .map((doc) => Movie.fromMap(
                    doc.data() as Map<String, dynamic>,
                    docId: doc.id,
                  ))
              .where((m) => m.titleLowercase.contains(lowerKeyword))
              .toList();
          // Merge prefix + substring, dedup by ID.
          final seenIds = <String>{};
          final merged = <Movie>[];
          for (final m in [...prefixResults, ...subResults]) {
            if (!seenIds.contains(m.id)) {
              seenIds.add(m.id);
              merged.add(m);
            }
          }
          return merged;
        } catch (_) {
          return prefixResults;
        }
      }

      return prefixResults;
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

  /// Batch-fetch latest Movie data for a list of movie IDs.
  ///
  /// Used by Bookmark/Recent pages to refresh stale cached ratings:
  /// when a user bookmarks a movie, the Movie object is snapshotted to
  /// Firestore/local storage at that moment. If the admin later edits
  /// the rating (or any field), the cached copy stays stale. This method
  /// re-fetches the latest Movie data in a single Firestore call (using
  /// 'in' query — up to 30 IDs per call, Firestore limit) so the UI can
  /// display the current rating instead of the cached "N/A".
  ///
  /// Returns a Map<movieId, Movie> for O(1) lookup. Movies that no
  /// longer exist are silently skipped (their IDs won't appear in the
  /// returned map).
  ///
  /// Cost: 1 read per movie ID, batched into 1 query per 30 IDs.
  /// For typical bookmark/recent lists (10-50 items), this is 1-2 queries.
  Future<Map<String, Movie>> getMoviesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final result = <String, Movie>{};
    // Firestore 'in' query supports max 30 values per call.
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += 30) {
      chunks.add(ids.sublist(i, (i + 30).clamp(0, ids.length)));
    }
    try {
      final futures = chunks.map((chunk) async {
        final snap = await _moviesRef.where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in snap.docs) {
          final movie = Movie.fromMap(doc.data() as Map<String, dynamic>, docId: doc.id);
          result[movie.id] = movie;
        }
      });
      await Future.wait(futures);
    } catch (e) {
      debugPrint('getMoviesByIds failed: $e');
    }
    return result;
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

    // =========================================================================
    // OPTIMIZATION (mirrors the legacy searchMovies() pattern, now removed)
    // =========================================================================
    // Before: 2 + 2N queries/search (N = name token count) = up to ~500 reads
    //   prefix + (per-token search_keywords) + orderBy(updatedAt) + no-orderBy
    // After:  1 + N queries/search = ~100-200 reads (50-75% reduction)
    //   Broader fallbacks are skipped when the primary queries returned
    //   ANY matching result. Only legacy movies missing both
    //   'title_lowercase' and 'search_keywords' trigger the fallback.
    // =========================================================================

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

      // Strategy 1.5: SUBSTRING FALLBACK for short queries (1-2 chars)
      // =========================================================================
      // Bro reported (Task 25) that searching a single character like "o"
      // returned only movies STARTING with "o" (e.g. "Ocean's Eleven",
      // "Once Upon a Time") but NOT movies CONTAINING "o" anywhere in the
      // title (e.g. "Thor", "Iron Man 2", "Doctor Strange"). Meanwhile
      // searching "ON" returned some movies with "on" anywhere — confusing.
      //
      // Root cause:
      //   - Strategy 1 (prefix search) only matches titles that START with
      //     the query. For "o", it returns plenty of results (Ocean's, Once,
      //     Oldboy, etc.), so prefixMovies is NOT empty.
      //   - The previous version of this Strategy 1.5 only fired when
      //     `prefixMovies.isEmpty && keywordResults.isEmpty` — which rarely
      //     happens for single letters (because Strategy 1 almost always
      //     finds prefix matches). So the substring fallback never ran,
      //     and the early-exit returned only the prefix matches.
      //   - For "ON": Strategy 1 returns fewer prefix matches (movies
      //     starting with "on" are rarer), so the substring fallback DID
      //     fire and found movies containing "on" anywhere. That's why
      //     Bro saw "some movies" for "ON" but "only starting-with-O
      //     movies" for "O".
      //
      // FIX (Task 25): Always run the substring fallback for short queries
      // (length <= 2), regardless of whether Strategies 1 and 2 returned
      // matches. The early-exit logic below already merges
      // prefixMovies + keywordResults + substringResults and applies a
      // client-side `title.contains(query)` filter for short queries, so
      // the user will see BOTH prefix matches (movies starting with "o")
      // AND substring matches (movies containing "o" anywhere) — exactly
      // what Bro wants.
      //
      // Cost: +1 Firestore query (~fetchLimit reads) for EVERY short
      // search. At fetchLimit=60 reads/query (limit=20 → 20*3 clamped to
      // 60) and Bro's typical usage, this adds ~5-10% to Firebase Reads
      // — acceptable per Bro's explicit OK.
      final substringResults = <Movie>[];
      if (lowerKeyword.length <= 2) {
        try {
          final subSnapshot = await _moviesRef.limit(fetchLimit).get();
          for (final doc in subSnapshot.docs) {
            final movie = Movie.fromMap(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            );
            // Case-insensitive substring match on title
            if (movie.titleLowercase.contains(lowerKeyword)) {
              substringResults.add(movie);
            }
          }
        } catch (e) {
          debugPrint('_searchWithKeyword substring fallback failed: $e');
        }
      }

      // Pre-combine what we have so far. If primary queries already returned
      // movies that match every name token AND year token, we can SKIP the
      // expensive broader fallback queries below (saves ~200 reads).
      final earlySeenIds = <String>{};
      final earlyAllMovies = <Movie>[];
      for (final m in [...prefixMovies, ...keywordResults, ...substringResults]) {
        if (!earlySeenIds.contains(m.id)) {
          earlySeenIds.add(m.id);
          earlyAllMovies.add(m);
        }
      }
      final earlyFiltered = earlyAllMovies.where((m) {
        final lowerTitle = m.titleLowercase;
        // For short single-token queries (<=2 chars), use substring match
        // instead of token-every-contains. This prevents "o" from being
        // rejected just because it isn't a full word in the title.
        final nameMatch = nameTokens.isEmpty ||
            (lowerKeyword.length <= 2 && nameTokens.length == 1
                ? lowerTitle.contains(nameTokens.first)
                : nameTokens.every((token) => lowerTitle.contains(token)));
        final yearMatch = yearTokens.isEmpty ||
            (m.year != null && yearTokens.contains(m.year!.toLowerCase()));
        return nameMatch && yearMatch;
      }).toList();

      // --- EARLY EXIT: skip broader fallbacks if primary returned matches ---
      // Apply the same downstream filters + sort so the user sees the same
      // result shape they would have seen with the full query path.
      if (earlyFiltered.isNotEmpty) {
        var filtered = earlyFiltered;
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
        // Sort results (same logic as the main path below).
        if (sortBy == 'rating') {
          filtered.sort((a, b) =>
              (double.tryParse(b.rating ?? '0') ?? 0.0)
              .compareTo(double.tryParse(a.rating ?? '0') ?? 0.0));
        } else if (sortBy == 'name') {
          filtered.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        } else {
          filtered.sort((a, b) {
            final aDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
            final bDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
            return aDate.compareTo(bDate);
          });
        }
        return {
          'movies': filtered.take(limit).toList(),
          'hasMore': filtered.length > limit,
          'lastDoc': null,
        };
      }

      // --- FALLBACK: only when primary queries returned 0 matches ----------
      // Run broader queries to catch LEGACY movies missing both
      // 'title_lowercase' and 'search_keywords' fields.
      //
      // IMPORTANT: We use TWO parallel broader queries here instead of one:
      //   - broaderByUpdatedAt: orderBy('updatedAt', descending) — catches
      //     recently-updated movies that have 'updatedAt' field (added via
      //     addMovie / updateMovie).
      //   - broaderNoOrderBy:   plain .limit() without orderBy — catches
      //     LEGACY movies that have neither 'updatedAt' nor 'createdAt'
      //     field. Firestore's orderBy(field) silently excludes any doc
      //     missing that field — that's why a previous version of this
      //     code used orderBy('createdAt') and could NOT find movies that
      //     Bro had imported via an older code path that didn't set
      //     'createdAt'. Bro reported "search any movie → nothing shows"
      //     because of this exact bug. The no-orderBy path guarantees
      //     every movie in the collection is a candidate for the
      //     client-side title filter below.
      //
      // Both queries are limited to fetchLimit (60-200 docs). Pagination
      // via startAfterDocument only works on the orderBy path; the
      // no-orderBy path is best-effort and skipped when paginating.
      Query broaderByUpdatedAt = _moviesRef
          .orderBy('updatedAt', descending: true);
      if (startAfter != null) {
        broaderByUpdatedAt = broaderByUpdatedAt.startAfterDocument(startAfter);
      }
      broaderByUpdatedAt = broaderByUpdatedAt.limit(fetchLimit);

      final broaderMovies = <Movie>[];
      try {
        final snapshot = await broaderByUpdatedAt.get();
        for (final doc in snapshot.docs) {
          broaderMovies.add(Movie.fromMap(
            doc.data() as Map<String, dynamic>,
            docId: doc.id,
          ));
        }
      } catch (e) {
        debugPrint('_searchWithKeyword broaderByUpdatedAt failed: $e — '
            'will rely on no-orderBy fallback');
      }

      // No-orderBy fallback: only on first page (startAfter == null).
      // On subsequent pages, we'd need a stable cursor, which orderBy
      // provides — without orderBy, pagination is unsafe. So we accept
      // that legacy movies are only fully searchable on page 1.
      if (startAfter == null) {
        try {
          final legacySnapshot = await _moviesRef.limit(fetchLimit).get();
          for (final doc in legacySnapshot.docs) {
            final movie = Movie.fromMap(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            );
            // Dedup against the orderBy results — same movie could appear
            // in both if it has updatedAt.
            final id = movie.id;
            final alreadySeen = broaderMovies.any((m) => m.id == id);
            if (!alreadySeen) {
              broaderMovies.add(movie);
            }
          }
        } catch (e) {
          debugPrint('_searchWithKeyword legacy fallback failed: $e');
        }
      }

      // Combine results from all strategies, deduplicating by ID
      final seenIds = <String>{};
      final allMovies = <Movie>[];

      for (final m in [...prefixMovies, ...keywordResults, ...substringResults, ...broaderMovies]) {
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
        // 'latest' — sort by updatedAt with fallback to createdAt, so that
        // movies missing one of the timestamp fields still sort correctly
        // relative to the others (DateTime(2000) sentinel sorts to bottom).
        filtered.sort((a, b) {
          final aDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
          final bDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
          return aDate.compareTo(bDate);
        });
      }

      final hasMore = filtered.length > limit ||
          broaderMovies.length >= fetchLimit;

      // lastDoc: cursor for pagination. We can only paginate using the
      // orderBy('updatedAt') query, so we look up the last movie in our
      // combined list and find the corresponding snapshot. Since we don't
      // keep the snapshot around, we return null here and let the caller
      // re-run the search with the next "page" by skipping already-seen IDs.
      // For the search screen, infinite scroll beyond page 1 is rarely used
      // (users typically refine their query instead), so this is acceptable.
      return {
        'movies': filtered.take(limit).toList(),
        'hasMore': hasMore,
        'lastDoc': null,
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
  ///
  /// Public so [BatchImportService] can verify admin ONCE at the start of a
  /// batch run, then pass `skipAdminCheck: true` to the per-item [addMovie]
  /// calls. Before this was made public, every item in a 100-movie batch
  /// import re-fetched the user doc, wasting 100 Firestore reads. See audit
  /// finding C2.
  Future<bool> isCurrentUserAdmin() async {
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
  ///
  /// Public so [BatchImportService] can call this ONCE at the start of a
  /// batch import run. After that, the per-item [addMovie] calls can skip
  /// the redundant per-item admin check by passing `skipAdminCheck: true`.
  /// See audit finding C2.
  Future<void> verifyAdmin() async {
    final isAdmin = await isCurrentUserAdmin();
    if (!isAdmin) {
      throw Exception('Admin permission required. You are not authorized to perform this action.');
    }
  }

  /// Private alias kept for backward compat with existing internal call sites
  /// (updateMovie, deleteMovie, addGenre, updateGenre, etc. — none of which
  /// are called from tight loops, so the per-call admin read is fine there).
  Future<void> _requireAdmin() => verifyAdmin();

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
  ///
  /// {@template skipAdminCheck_param}
  /// [skipAdminCheck] — when true, skips the per-call admin verification
  /// Firestore read. CALLER IS RESPONSIBLE for having already verified admin
  /// status (e.g. via [verifyAdmin]) before calling this in a tight loop.
  /// Used by [BatchImportService.runImport] to avoid N redundant admin reads
  /// for an N-movie import. Default is false (safe for one-off callers).
  /// See audit finding C2.
  /// {@endtemplate}
  ///
  /// Audit finding C1: counter increments / decrements now use a [WriteBatch]
  /// instead of sequential `_incrementCount` / `_decrementCount` calls. A
  /// movie with 3 genres + 2 tags used to issue 10 separate Firestore ops
  /// (5 reads + 5 writes) for counter sync; now it issues 5 reads + 1 batch
  /// write. For a 100-movie batch import that's 400 fewer writes per run.
  Future<String> addMovie(
    Map<String, dynamic> data, {
    bool skipAdminCheck = false,
  }) async {
    if (!skipAdminCheck) await _requireAdmin();
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

        // Update category counts via WriteBatch (audit C1).
        // We still need the per-name reads to compute current+1, but the
        // writes are committed together instead of one-by-one.
        final oldCategories = List<String>.from(existingData['categories'] ?? []);
        final oldTags = List<String>.from(existingData['tags'] ?? []);
        final newCategories = List<String>.from(safeData['categories'] ?? oldCategories);
        final newTags = List<String>.from(safeData['tags'] ?? oldTags);

        final batch = _firestore.batch();
        // Also fold the movie update itself into the same batch — saves one
        // round-trip. (Existing-by-tmdbId branch is the most common path
        // for Batch Import because admins usually re-import to update.)
        batch.update(existingByTmdbId.reference, safeData);
        for (final cat in oldCategories) {
          if (!newCategories.contains(cat)) {
            await _batchDecrementCount(batch, _genresRef, cat);
          }
        }
        for (final cat in newCategories) {
          if (!oldCategories.contains(cat)) {
            await _batchIncrementCount(batch, _genresRef, cat);
          }
        }
        for (final tag in oldTags) {
          if (!newTags.contains(tag)) {
            await _batchDecrementCount(batch, _tagsRef, tag);
          }
        }
        for (final tag in newTags) {
          if (!oldTags.contains(tag)) {
            await _batchIncrementCount(batch, _tagsRef, tag);
          }
        }
        await batch.commit();

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

      // Update category counts via WriteBatch (audit C1).
      final oldCategories = List<String>.from(existingData['categories'] ?? []);
      final oldTags = List<String>.from(existingData['tags'] ?? []);
      final newCategories = List<String>.from(safeData['categories'] ?? oldCategories);
      final newTags = List<String>.from(safeData['tags'] ?? oldTags);

      final batch = _firestore.batch();
      batch.update(existingDoc.reference, safeData);
      for (final cat in oldCategories) {
        if (!newCategories.contains(cat)) {
          await _batchDecrementCount(batch, _genresRef, cat);
        }
      }
      for (final cat in newCategories) {
        if (!oldCategories.contains(cat)) {
          await _batchIncrementCount(batch, _genresRef, cat);
        }
      }
      for (final tag in oldTags) {
        if (!newTags.contains(tag)) {
          await _batchDecrementCount(batch, _tagsRef, tag);
        }
      }
      for (final tag in newTags) {
        if (!oldTags.contains(tag)) {
          await _batchIncrementCount(batch, _tagsRef, tag);
        }
      }
      await batch.commit();

      return existingDoc.id;
    }

    // === No duplicate: Create new document ===
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();

    // Audit C1: fold genre/tag counter increments into a single WriteBatch
    // that ALSO contains the new movie doc add. This saves N writes (one per
    // genre/tag) plus a round-trip for the movie insert itself.
    final batch = _firestore.batch();
    final newDocRef = _moviesRef.doc();
    batch.set(newDocRef, data);

    if (data.containsKey('categories')) {
      for (final genreName in data['categories'] as List) {
        await _batchIncrementCount(batch, _genresRef, genreName.toString());
      }
    }
    if (data.containsKey('tags')) {
      for (final tagName in data['tags'] as List) {
        await _batchIncrementCount(batch, _tagsRef, tagName.toString());
      }
    }
    await batch.commit();

    return newDocRef.id;
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
    // IMPORTANT: Do NOT skip single-character tokens here. A previous version
    // used `word.length >= 2` which broke single-character searches like "o"
    // or "a" — the arrayContains query needs those single-char tokens to be
    // present in the search_keywords array for a 1-character query to match.
    // Single-char tokens are very common in titles like "A.I.", "X-Men",
    // "R.E.D.", "MIB", "O Brother, Where Art Thou?", etc. Including them
    // ensures searching "o" finds "O Brother" and searching "x" finds "X-Men".
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')  // Replace non-word chars with space
        .split(RegExp(r'\s+'))                     // Split on whitespace
        .where((word) => word.isNotEmpty)          // Skip empty only
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
