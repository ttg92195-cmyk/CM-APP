import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/admin_audit_service.dart';
import 'package:cm_movies/app/core/services/rate_limiter_service.dart';

class FirestoreContentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection references
  CollectionReference get _moviesRef => _firestore.collection('movies');
  CollectionReference get _genresRef => _firestore.collection('genres');
  CollectionReference get _tagsRef => _firestore.collection('tags');
  CollectionReference get _collectionsRef => _firestore.collection('collections');

  // ==================== Phase 4.12 — Universe Keywords Map ====================
  //
  // When a collection name matches one of these keys (lowercased), the
  // fallback uses `arrayContainsAny` with the mapped keyword list INSTEAD
  // OF the single-word pipeline. This lets Bro create a "Marvel" collection
  // and immediately see all Iron Man, Thor, Avengers, Spider-Man movies
  // without manually tagging each movie.
  //
  // Why this matters: previously "Marvel" only matched movies whose title
  // contained "marvel" (very few — most Marvel movies are named after the
  // hero, e.g. "Iron Man", "Thor"). Now we expand the query to include
  // every hero/franchise keyword in the Marvel universe.
  //
  // Cost: ONE Firestore query (arrayContainsAny) instead of N parallel
  // queries. On the Spark (free) plan, this minimizes reads.
  //
  // To extend: add new universes here. Map keys MUST be lowercase; values
  // are lists of lowercase search_keywords tokens (must match how
  // _generateSearchKeys stores them — split on whitespace, punctuation
  // stripped, so "Spider-Man" becomes ["spider", "man"] — use "spider"
  // AND "spiderman" to cover both forms).
  static const Map<String, List<String>> _universeKeywords = {
    'marvel': [
      'marvel', 'iron', 'thor', 'america', 'avengers', 'deadpool',
      'wolverine', 'hulk', 'loki', 'venom', 'spider', 'spiderman',
      'panther', 'guardians', 'strange', 'bats',
    ],
    'dc': [
      'dc', 'batman', 'superman', 'joker', 'aquaman', 'flash',
      'shazam', 'wonder', 'lantern',
    ],
    'harry potter': ['potter', 'beasts', 'hogwarts'],
    'star wars': ['wars', 'jedi', 'sith', 'mandalorian'],
    'monsterverse': ['godzilla', 'kong'],
    'the conjuring universe': ['conjuring', 'annabelle', 'nun', 'valak'],
    'lord of the rings': ['rings', 'hobbit', 'middle', 'gandalf'],
  };

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

  // ==================== PHASE 4.14: AGGREGATION-BASED DASHBOARD STATS ====================
  //
  // BEFORE Phase 4.14: TmdbGeneratorPage._loadMoviesSnapshot() did
  //   `movies.limit(5000).get()` to compute 6 dashboard stats + populate
  //   the _importedTmdbIds set in a single pass. 5,000 reads per page open.
  //   Opening the page 10 times burned the entire Spark daily quota
  //   (50,000 reads/day).
  //
  // NOW: 6 aggregation queries (`count().get()`) run in parallel via
  //   [getDashboardStats]. Each aggregation query costs 1 read regardless
  //   of collection size. Total: ~6 reads per page open (vs 5,000).
  //
  // The _importedTmdbIds set is no longer pre-populated on page load.
  // Instead, [getImportedTmdbIds] does a `whereIn` query for ONLY the
  // tmdbIds currently shown in search results (~20 reads per search).
  //
  // NOTE: Some of these aggregation queries use 2-3 where clauses and may
  // require composite indexes. If a query fails (e.g. missing index), the
  // corresponding stat is returned as 0 and a debugPrint is emitted with
  // Firestore's error message — which includes a URL to create the index
  // in Firebase Console. The caller (UI) gracefully shows 0 until Bro
  // creates the index.

  /// Helper: run a count aggregation query, returning 0 on error.
  /// Used by [getDashboardStats] so one failing query (e.g. missing
  /// composite index) doesn't tank the whole stats load.
  Future<int> _safeCount(
    Future<AggregateQuerySnapshot> query,
    String label,
  ) async {
    try {
      final snap = await query;
      return snap.count ?? 0;
    } catch (e) {
      // Firestore's missing-index error includes a URL to create the
      // index in Firebase Console. Bro can click it to fix the stat.
      debugPrint('getDashboardStats: $label failed (likely missing composite '
          'index — see Firestore error for create-URL): $e');
      return 0;
    }
  }

  /// Returns all 6 dashboard stats in parallel via aggregation queries.
  ///
  /// Total Firestore reads: ~6 (one per count query).
  /// Compare with the old `_loadMoviesSnapshot` approach: 5,000 reads.
  ///
  /// Returns a Map with keys:
  ///   - 'totalMovies'    : count where type == 'movie'
  ///   - 'totalSeries'    : count where type == 'series'
  ///   - 'moviesNeedSync' : count where type=='movie' AND tmdbId>0 AND
  ///                        lastSyncDate is null (requires composite index)
  ///   - 'seriesNeedSync' : count where type=='series' AND tmdbId>0 AND
  ///                        lastSyncDate is null (requires composite index)
  ///   - 'ongoingSeries'  : count where type=='series' AND
  ///                        status=='Returning Series' (composite index)
  ///   - 'endedSeries'    : count where type=='series' AND
  ///                        status IN ['Ended','Canceled'] (composite index)
  ///
  /// If any query fails (e.g. missing composite index), that stat returns 0.
  Future<Map<String, int>> getDashboardStats() async {
    final results = await Future.wait([
      // totalMovies — single-field where, no composite index needed.
      _safeCount(
        _moviesRef.where('type', isEqualTo: 'movie').count().get(),
        'totalMovies',
      ),
      // totalSeries — single-field where, no composite index needed.
      _safeCount(
        _moviesRef.where('type', isEqualTo: 'series').count().get(),
        'totalSeries',
      ),
      // moviesNeedSync — 3-field composite index required:
      //   (type ASC, tmdbId ASC, lastSyncDate ASC).
      _safeCount(
        _moviesRef
            .where('type', isEqualTo: 'movie')
            .where('tmdbId', isGreaterThan: 0)
            .where('lastSyncDate', isNull: true)
            .count()
            .get(),
        'moviesNeedSync',
      ),
      // seriesNeedSync — 3-field composite index required:
      //   (type ASC, tmdbId ASC, lastSyncDate ASC).
      _safeCount(
        _moviesRef
            .where('type', isEqualTo: 'series')
            .where('tmdbId', isGreaterThan: 0)
            .where('lastSyncDate', isNull: true)
            .count()
            .get(),
        'seriesNeedSync',
      ),
      // ongoingSeries — 2-field composite index required:
      //   (type ASC, status ASC).
      _safeCount(
        _moviesRef
            .where('type', isEqualTo: 'series')
            .where('status', isEqualTo: 'Returning Series')
            .count()
            .get(),
        'ongoingSeries',
      ),
      // endedSeries — 2-field composite index required:
      //   (type ASC, status ASC).
      _safeCount(
        _moviesRef
            .where('type', isEqualTo: 'series')
            .where('status', whereIn: ['Ended', 'Canceled'])
            .count()
            .get(),
        'endedSeries',
      ),
    ]);

    return {
      'totalMovies': results[0],
      'totalSeries': results[1],
      'moviesNeedSync': results[2],
      'seriesNeedSync': results[3],
      'ongoingSeries': results[4],
      'endedSeries': results[5],
    };
  }

  /// Returns the subset of [tmdbIds] that already exist in the `movies`
  /// collection. Uses `whereIn` with chunking (max 30 per query — Firestore
  /// hard limit) to handle large input lists.
  ///
  /// Replaces the old approach of reading all 5,000 docs from `movies` on
  /// every TmdbGeneratorPage open to build a complete `_importedTmdbIds`
  /// set. Now the page only checks the IDs currently shown in search
  /// results — typically 20 IDs → 1 read.
  ///
  /// Reads: ceil(tmdbIds.length / 30). For 20 search results: 1 read.
  /// For 1000 search results (extreme case): 34 reads — still 147x cheaper
  /// than the old 5,000.
  Future<Set<int>> getImportedTmdbIds(List<int> tmdbIds) async {
    if (tmdbIds.isEmpty) return <int>{};

    // Firestore whereIn accepts max 30 values per query.
    final chunks = <List<int>>[];
    for (var i = 0; i < tmdbIds.length; i += 30) {
      final end = (i + 30 > tmdbIds.length) ? tmdbIds.length : i + 30;
      chunks.add(tmdbIds.sublist(i, end));
    }

    final result = <int>{};
    try {
      final snapshots = await Future.wait(
        chunks
            .map((chunk) => _moviesRef.where('tmdbId', whereIn: chunk).get()),
      );
      for (final snap in snapshots) {
        for (final doc in snap.docs) {
          // _moviesRef is an untyped CollectionReference, so doc.data()
          // returns Object? — must cast to Map<String, dynamic>? before
          // indexing. Same pattern used elsewhere in this file (e.g. line
          // ~2023 in addMovie: existingByTmdbId.data() as Map<String, dynamic>).
          final data = doc.data() as Map<String, dynamic>?;
          final rawTmdbId = data?['tmdbId'];
          if (rawTmdbId is int) {
            result.add(rawTmdbId);
          } else if (rawTmdbId != null) {
            final parsed = int.tryParse(rawTmdbId.toString());
            if (parsed != null && parsed > 0) result.add(parsed);
          }
        }
      }
    } catch (e) {
      debugPrint('getImportedTmdbIds failed: $e');
    }

    return result;
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
      //
      // Phase 4.22 — OLD code used `_moviesRef.limit(200).get()` which only
      // scanned the first 200 docs in Firestore's natural order. If a movie
      // like "Your Name" was beyond doc #200, it was silently missed — same
      // bug as the user-facing search. Fixed here by paginated full-scan
      // (batch 500, cap 5000) using startAfterDocument cursor.
      if (lowerKeyword.length <= 2) {
        try {
          const int batchSize = 500;
          const int maxTotalDocs = 5000;
          QuerySnapshot? batchSnapshot;
          int totalScanned = 0;
          bool more = true;
          final subResults = <Movie>[];
          while (more && totalScanned < maxTotalDocs) {
            Query batchQuery = _moviesRef.limit(batchSize);
            if (batchSnapshot != null && batchSnapshot.docs.isNotEmpty) {
              batchQuery = batchQuery.startAfterDocument(batchSnapshot.docs.last);
            }
            batchSnapshot = await batchQuery.get();
            if (batchSnapshot.docs.isEmpty) break;
            totalScanned += batchSnapshot.docs.length;
            for (final doc in batchSnapshot.docs) {
              final movie = Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              );
              if (movie.titleLowercase.contains(lowerKeyword)) {
                subResults.add(movie);
              }
            }
            more = batchSnapshot.docs.length >= batchSize;
          }
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
  ///
  /// `limit` controls the page size. Home screen passes 10 (it only
  /// shows 10 in the horizontal list — fetching 50 was wasting 5x
  /// Firestore reads + 5x document download bandwidth on every Home
  /// load). Category page and detail screens use the default 50 so
  /// users can scroll through more trending items when they tap
  /// "More" or open "Related Movies".
  Future<List<Movie>> getTrendingMovies({int limit = 50}) async {
    try {
      final snapshot = await _moviesRef
          .where('type', isEqualTo: 'movie')
          .where('isTrending', isEqualTo: true)
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
      // Fallback: if composite index doesn't exist, try simpler query
      debugPrint('getTrendingMovies with orderBy failed, trying fallback: $e');
      try {
        final snapshot = await _moviesRef
            .where('type', isEqualTo: 'movie')
            .where('isTrending', isEqualTo: true)
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
        debugPrint('getTrendingMovies fallback also failed: $e2');
        return [];
      }
    }
  }

  /// Get trending TV shows
  ///
  /// See [getTrendingMovies] for the `limit` parameter rationale.
  Future<List<Movie>> getTrendingTvShows({int limit = 50}) async {
    try {
      final snapshot = await _moviesRef
          .where('type', isEqualTo: 'series')
          .where('isTrending', isEqualTo: true)
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
      // Fallback: if composite index doesn't exist, try simpler query
      debugPrint('getTrendingTvShows with orderBy failed, trying fallback: $e');
      try {
        final snapshot = await _moviesRef
            .where('type', isEqualTo: 'series')
            .where('isTrending', isEqualTo: true)
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
    String? typeFilter,
  }) async {
    // Task 38 Req 5 — server-side type filter for Genres tab pagination.
    // Without this, the 20-doc page contains mixed movie+series docs, the
    // client-side filter (in FilterResultPage) discards the wrong-type ones,
    // and the visible grid is shorter than the viewport — so the scroll
    // trigger never fires and infinite scroll silently dies at 20 docs.
    // See genres_tags_collections_page.dart for the matching call sites.
    try {
      Query query = _moviesRef
          .where('categories', arrayContains: genreName);
      if (typeFilter != null) {
        query = query.where('type', isEqualTo: typeFilter);
      }
      query = query
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
      // (e.g., the new (categories, type, createdAt) 3-field index isn't
      // deployed yet — see firestore.indexes.json). This fallback path
      // works WITHOUT any composite index because equality + array-contains
      // queries don't require one; only orderBy on a 3rd field does.
      debugPrint('getMoviesByGenre with orderBy failed, trying fallback: $e');
      try {
        Query query = _moviesRef
            .where('categories', arrayContains: genreName);
        if (typeFilter != null) {
          query = query.where('type', isEqualTo: typeFilter);
        }
        query = query.limit(limit);

        // Task 39 — fallback path MUST honor startAfterDocument too,
        // otherwise pagination silently breaks when the composite index
        // (categories, type, createdAt) isn't deployed yet: the fallback
        // would return page 1 again on every _loadMore call, dedup would
        // strip all 20 docs (already in _seenIds), and the grid would be
        // stuck at 20 items forever while the auto-load safety net spins
        // in an infinite loop. Without orderBy, Firestore returns docs in
        // document-ID order; startAfterDocument(lastDoc) advances the
        // cursor by doc ID, which is consistent and deterministic.
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
    String? typeFilter,
  }) async {
    // Task 38 Req 5 — server-side type filter for Tags tab pagination.
    // See getMoviesByGenre above for the rationale.
    try {
      Query query = _moviesRef
          .where('tags', arrayContains: tagName);
      if (typeFilter != null) {
        query = query.where('type', isEqualTo: typeFilter);
      }
      query = query
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
            .where('tags', arrayContains: tagName);
        if (typeFilter != null) {
          query = query.where('type', isEqualTo: typeFilter);
        }
        query = query.limit(limit);

        // Task 39 — fallback path MUST honor startAfterDocument too.
        // See getMoviesByGenre fallback above for the full rationale.
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
  ///
  /// Phase 4.7 — TRUE server-side cursor pagination.
  ///
  /// HISTORY: Phase 4.1 added client-side chunk pagination — fetched 200 docs
  /// once, sliced 20 per page from memory. This caused Bro's reported bug:
  /// "first search shows nothing for a moment, then 200 results appear all at
  /// once instead of 20 first". The 200-doc fetch was slow + atomic, so users
  /// saw either nothing or everything depending on timing.
  ///
  /// FIX (Phase 4.7): Now we paginate Strategy 1 (prefix query on
  /// title_lowercase) using a real Firestore cursor. Strategy 2 (array-
  /// contains on search_keywords) and the substring fallback only run on the
  /// FIRST page (startAfter == null) — they have no stable cursor. On
  /// subsequent pages, only Strategy 1 runs, which gives us a real
  /// DocumentSnapshot cursor to return.
  ///
  /// Result: page 1 returns 20 docs in ~1 Firestore read-batch, page 2
  /// returns the next 20, etc. True pagination, no client-side slicing.
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

    final lowerKeyword = keyword.toLowerCase().trim();
    final upperKeyword = lowerKeyword + '\uf8ff';
    final isFirstPage = startAfter == null;

    try {
      // =========================================================================
      // Phase 4.7 — STRATEGY 1: PREFIX QUERY (the ONLY paginated strategy)
      // =========================================================================
      // Strategy 1 is the primary result source for keyword searches (e.g.
      // "o" matches all titles starting with "o"). It uses orderBy on
      // title_lowercase, so it supports a real Firestore cursor — we can
      // safely paginate this query across multiple pages.
      //
      // fetchLimit: number of docs to fetch per page. We fetch slightly
      // more than `limit` so we have headroom for the year/genre/rating
      // client-side filters below (which can drop some of the fetched docs).
      final fetchLimit = (limit * 2).clamp(40, 100);

      Query prefixQuery = _moviesRef
          .where('title_lowercase', isGreaterThanOrEqualTo: lowerKeyword)
          .where('title_lowercase', isLessThanOrEqualTo: upperKeyword)
          .orderBy('title_lowercase')
          .limit(fetchLimit);
      if (startAfter != null) {
        prefixQuery = prefixQuery.startAfterDocument(startAfter);
      }
      final prefixSnapshot = await prefixQuery.get();
      final prefixMovies = prefixSnapshot.docs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      // =========================================================================
      // STRATEGY 2 + SUBSTRING FALLBACK: only on the FIRST page
      // =========================================================================
      // These have no stable cursor (no orderBy for substring, no shared
      // ordering between array-contains and prefix). On page 2+, only
      // Strategy 1 runs — so the user might miss a few movies that
      // match only via search_keywords or substring on later pages.
      // Acceptable trade-off for true pagination; the missing movies
      // appear on page 1's merged result set anyway.
      final keywordResults = <Movie>[];
      final substringResults = <Movie>[];
      if (isFirstPage) {
        // Strategy 2: search_keywords array-contains for each name token
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

        // Substring fallback for short queries (1-2 chars) — see Strategy 1.5
        // comment in the git history (Task 25). Lets "o" match "Thor",
        // "Iron Man 2", "Doctor Strange" too, not just prefix matches.
        //
        // Phase 4.22 — OLD code used `_moviesRef.limit(fetchLimit).get()`
        // which only scanned the first 100 docs in Firestore's natural order.
        // If a movie like "Your Name" was beyond doc #100, it was silently
        // missed — even though its title contains "o". This is the root cause
        // of Bro's bug report: "o" search was returning incomplete results.
        //
        // FIX: Paginated full-collection scan using `startAfterDocument`.
        // Batch size 500, safety cap 5000 docs (10 batches). Catalog of
        // 5000 movies is rare for an indie app; if exceeded, the user gets
        // the first 5000-doc subset which is still far better than 100.
        if (lowerKeyword.length <= 2) {
          try {
            const int batchSize = 500;
            const int maxTotalDocs = 5000;
            QuerySnapshot? batchSnapshot;
            int totalScanned = 0;
            bool more = true;
            while (more && totalScanned < maxTotalDocs) {
              Query batchQuery = _moviesRef.limit(batchSize);
              if (batchSnapshot != null && batchSnapshot.docs.isNotEmpty) {
                batchQuery = batchQuery.startAfterDocument(batchSnapshot.docs.last);
              }
              batchSnapshot = await batchQuery.get();
              if (batchSnapshot.docs.isEmpty) break;
              totalScanned += batchSnapshot.docs.length;
              for (final doc in batchSnapshot.docs) {
                final movie = Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                );
                if (movie.titleLowercase.contains(lowerKeyword)) {
                  substringResults.add(movie);
                }
              }
              more = batchSnapshot.docs.length >= batchSize;
            }
            if (totalScanned >= maxTotalDocs) {
              debugPrint(
                '_searchWithKeyword substring fallback hit safety cap '
                '($maxTotalDocs docs scanned for "$lowerKeyword"). '
                'Catalog may be larger — consider backfilling search_keywords '
                'with character n-grams for true server-side search.',
              );
            }
          } catch (e) {
            debugPrint('_searchWithKeyword substring fallback failed: $e');
          }
        }
      }

      // Merge Strategy 1 + (page-1-only) Strategies 2 & 3, dedup by ID.
      // Strategy 1 results come FIRST so cursor-based pagination stays
      // stable across pages (we always return the last prefixSnapshot doc
      // as the next cursor).
      final seenIds = <String>{};
      final allMovies = <Movie>[];
      for (final m in [...prefixMovies, ...keywordResults, ...substringResults]) {
        if (!seenIds.contains(m.id)) {
          seenIds.add(m.id);
          allMovies.add(m);
        }
      }

      // Apply token-based advanced filtering (name tokens + year tokens)
      var filtered = allMovies.where((m) {
        final lowerTitle = m.titleLowercase;
        final nameMatch = nameTokens.isEmpty ||
            (lowerKeyword.length <= 2 && nameTokens.length == 1
                ? lowerTitle.contains(nameTokens.first)
                : nameTokens.every((token) => lowerTitle.contains(token)));
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
        // 'latest' — sort by updatedAt with fallback to createdAt
        filtered.sort((a, b) {
          final aDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
          final bDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
          return aDate.compareTo(bDate);
        });
      }

      // Take only `limit` results for this page.
      final pageMovies = filtered.take(limit).toList();

      // Phase 4.7 — Return a REAL cursor (last doc from Strategy 1).
      // Since Strategy 1 is the only paginated query and its results come
      // first in the merge, the last doc of prefixSnapshot is a valid
      // cursor for the next page. If the user's filters dropped all
      // prefixMovies from this page (rare edge case), we still return
      // the last prefixSnapshot doc — the next page will continue from
      // there with fresh prefix matches.
      final lastDoc = prefixSnapshot.docs.isNotEmpty
          ? prefixSnapshot.docs.last
          : null;

      // hasMore: true if Strategy 1 returned a full batch (more pages
      // likely available). If Strategy 1 returned fewer than fetchLimit,
      // there are no more prefix matches — pagination stops.
      final hasMore = prefixSnapshot.docs.length >= fetchLimit;

      return {
        'movies': pageMovies,
        'hasMore': hasMore,
        'lastDoc': lastDoc,
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
  ///
  /// Phase 4.8 — Automatic search_keywords fallback.
  ///
  /// HISTORY: When Bro creates a brand-new Collection (e.g. "Marvel") in the
  /// admin panel, no movies have `collections: ["Marvel"]` set yet. The
  /// collection tab would show "No movies found" until Bro manually edited
  /// every movie to add the collection tag. Bro wanted this to be 100%
  /// automatic: the moment a collection is created, the app should show
  /// movies whose `search_keywords` array contains the collection name
  /// (case-insensitive). This works because every movie already has its
  /// title auto-tokenized into search_keywords (e.g. "Avengers: Endgame"
  /// → ['avengers', 'endgame']).
  ///
  /// FIX (Phase 4.8): On the FIRST page (startAfter == null), if the primary
  /// `collections` array-contains query returns zero results, fall back to a
  /// `search_keywords` array-contains query. Subsequent pages continue
  /// paginating whatever query path was selected on page 1.
  ///
  /// Cursor stability: both primary and fallback queries use the same
  /// `.orderBy('createdAt', descending: true)` + `.limit(limit)` shape, so
  /// the DocumentSnapshot cursor is interchangeable between them. The
  /// fallback path returns its own lastDoc, which `_loadMore()` in the
  /// collection screen passes back as startAfter — and since both queries
  /// sort by the same field, the cursor is valid for either path.
  Future<Map<String, dynamic>> getMoviesByCollection(
    String collectionName, {
    int limit = 50,
    DocumentSnapshot? startAfter,
    String? typeFilter,
  }) async {
    // Task 38 Req 5 — server-side type filter for Collections tab pagination.
    // See getMoviesByGenre above for the rationale.
    //
    // Phase 4.9 — Stateless cursor inspection for page 2+ routing.
    //
    // HISTORY: Phase 4.8 added search_keywords fallback on page 1 only.
    // Bug: on page 2+, the cursor (lastDoc from page 1) might come from
    // the fallback path (search_keywords), in which case its `collections`
    // array does NOT contain `collectionName`. Using that cursor in the
    // primary `collections arrayContains` query would either return empty
    // (Firestore's startAfterDocument uses the cursor's field values, and
    // a movie not in the result set causes pagination to silently fail)
    // or throw an error — causing pagination to stop after page 1.
    //
    // FIX (Phase 4.9): Before attempting the primary query on page 2+,
    // inspect the cursor's `collections` array. If `collectionName` is
    // NOT in it, route directly to the search_keywords fallback — the
    // cursor was definitely produced by the fallback path, so we should
    // continue paginating that same path. This is fully stateless: no
    // need to track which path was used on page 1 in any external state.
    if (startAfter != null) {
      final cursorCollections = _readCollectionsFromCursor(startAfter);
      if (!cursorCollections.contains(collectionName)) {
        // Cursor is from the fallback path — route directly there.
        debugPrint('Phase 4.9: cursor has no "$collectionName" in '
            'collections — routing page 2+ to search_keywords fallback');
        final fallbackResult = await _getMoviesByCollectionFallback(
          collectionName: collectionName,
          limit: limit,
          startAfter: startAfter,
          typeFilter: typeFilter,
        );
        if (fallbackResult != null) {
          return fallbackResult;
        }
        // Fallback returned empty (end of search_keywords matches) —
        // return empty result. Don't try primary; the cursor is invalid
        // for primary (collections doesn't contain the name).
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }

    try {
      Query query = _moviesRef
          .where('collections', arrayContains: collectionName);
      if (typeFilter != null) {
        query = query.where('type', isEqualTo: typeFilter);
      }
      query = query
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

      // Phase 4.8 — Auto fallback to search_keywords when:
      //   (a) primary query returned empty, AND
      //   (b) we're on the first page (startAfter == null).
      // On subsequent pages we DON'T fallback here — Phase 4.9's cursor
      // inspection above already routed page 2+ correctly.
      if (movies.isEmpty && startAfter == null) {
        final fallbackResult = await _getMoviesByCollectionFallback(
          collectionName: collectionName,
          limit: limit,
          startAfter: startAfter,
          typeFilter: typeFilter,
        );
        if (fallbackResult != null) {
          return fallbackResult;
        }
        // Fallback also returned empty (or threw) — fall through to the
        // empty-result return below.
      }

      return {
        'movies': movies,
        'hasMore': snapshot.docs.length >= limit,
        'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      };
    } catch (e) {
      debugPrint('getMoviesByCollection with orderBy failed, trying fallback: $e');
      try {
        Query query = _moviesRef
            .where('collections', arrayContains: collectionName);
        if (typeFilter != null) {
          query = query.where('type', isEqualTo: typeFilter);
        }
        query = query.limit(limit);

        // Task 39 — fallback path MUST honor startAfterDocument too.
        // See getMoviesByGenre fallback above for the full rationale.
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
        movies.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

        // Phase 4.8 — Same auto-fallback on the no-orderBy fallback path.
        // (Page 1 only — page 2+ is routed by Phase 4.9 cursor inspection.)
        if (movies.isEmpty && startAfter == null) {
          final kwFallback = await _getMoviesByCollectionFallback(
            collectionName: collectionName,
            limit: limit,
            startAfter: startAfter,
            typeFilter: typeFilter,
          );
          if (kwFallback != null) {
            return kwFallback;
          }
        }

        return {
          'movies': movies,
          'hasMore': snapshot.docs.length >= limit,
          'lastDoc': snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        };
      } catch (e2) {
        debugPrint('getMoviesByCollection fallback also failed: $e2');
        // Phase 4.8 — Last-resort: try search_keywords even if both
        // collections queries threw (e.g. composite index missing AND
        // collection is genuinely empty). Page 1 only.
        if (startAfter == null) {
          final kwFallback = await _getMoviesByCollectionFallback(
            collectionName: collectionName,
            limit: limit,
            startAfter: startAfter,
            typeFilter: typeFilter,
          );
          if (kwFallback != null) {
            return kwFallback;
          }
        }
        return {
          'movies': <Movie>[],
          'hasMore': false,
          'lastDoc': null,
        };
      }
    }
  }

  /// Phase 4.9 — Read the `collections` array from a DocumentSnapshot
  /// cursor. Returns an empty list if the field is missing, not a list,
  /// or the snapshot has no data. Used by getMoviesByCollection to
  /// decide whether to route page 2+ to the search_keywords fallback.
  ///
  /// Stateless: we don't track which query path was used on page 1 in
  /// any external state. Instead, we infer it from the cursor itself:
  /// if the cursor's `collections` field does NOT contain the search
  /// collectionName, the cursor must have come from the fallback path
  /// (search_keywords results don't have the collection tagged).
  List<String> _readCollectionsFromCursor(DocumentSnapshot cursor) {
    try {
      final data = cursor.data();
      if (data == null) return const [];
      if (data is! Map<String, dynamic>) return const [];
      final collections = data['collections'];
      if (collections is! List) return const [];
      return collections
          .whereType<String>()
          .toList(growable: false);
    } catch (e) {
      debugPrint('Phase 4.9: _readCollectionsFromCursor failed: $e');
      return const [];
    }
  }

  /// Phase 4.12 — Ultimate Universe Hybrid Strategy fallback.
  ///
  /// HISTORY:
  ///   - Phase 4.8/4.10/4.11 progressively improved the search_keywords
  ///     fallback for `getMoviesByCollection`. Phase 4.11 handled
  ///     punctuation, stop words, and fuzzy matching for arbitrary
  ///     collection names like "Spider-Man", "Lord of the Rings".
  ///   - BUT: Bro wants a TRUE universe experience. Creating a "Marvel"
  ///     collection should show ALL Marvel movies (Iron Man, Thor,
  ///     Avengers, Spider-Man, etc.) — not just movies whose title
  ///     literally contains "marvel". Same for DC, Harry Potter, etc.
  ///   - Phase 4.12 adds a Universe Keywords Map (see
  ///     `_universeKeywords` at the top of this class). When the
  ///     collection name matches a universe key, we use
  ///     `arrayContainsAny` with the mapped keyword list (ONE Firestore
  ///     query, minimal reads) and return ALL matched movies without
  ///     client-side filtering — every matched keyword is by definition
  ///     part of the universe.
  ///   - For non-universe collections, the Phase 4.11 pipeline
  ///     (punctuation strip → stop-word filter → longest word queryKey →
  ///     fuzzy normalize) is preserved unchanged.
  ///
  /// COST ANALYSIS:
  ///   - Universe path: 1 Firestore query with arrayContainsAny on up to
  ///     30 keywords. Firestore bills this as ONE read batch (number of
  ///     docs returned = reads, NOT number of array values). Far cheaper
  ///     than N parallel queries.
  ///   - Non-universe path: same as Phase 4.11 — 1 query, 3x over-fetch,
  ///     client-side fuzzy filter.
  ///
  /// PAGINATION + CURSOR (preserved from Phase 4.10/4.11):
  ///   - lastDoc = pageDocs.last (last SHOWN doc, NOT last fetched).
  ///   - hasMore = filteredDocs.length > limit (FILTERED count, not raw).
  ///   - Over-fetch 3x for non-universe filter headroom.
  ///   - Universe path: filteredDocs == snapshot.docs (no filtering),
  ///     so hasMore is essentially snapshot.docs.length > limit.
  Future<Map<String, dynamic>?> _getMoviesByCollectionFallback({
    required String collectionName,
    required int limit,
    required DocumentSnapshot? startAfter,
    required String? typeFilter,
  }) async {
    final token = collectionName.toLowerCase().trim();
    if (token.isEmpty) return null;

    // === Universe detection ===
    // If the collection name matches a key in _universeKeywords, use the
    // mapped keyword list with arrayContainsAny. Otherwise, fall through
    // to the Phase 4.11 single-word pipeline.
    final isUniverse = _universeKeywords.containsKey(token);
    final List<String> universeTokens =
        isUniverse ? _universeKeywords[token]! : const [];

    // === Non-universe pipeline (Phase 4.11 preserved) ===
    // Only computed when isUniverse is false. Hoisted out so the variable
    // is in scope for both try and catch blocks.
    List<String> cleanTokens = const [];
    List<String> searchTokens = const [];
    String queryKey = '';
    String normalizedPhrase = '';
    if (!isUniverse) {
      // Step 1: Punctuation strip + tokenize
      cleanTokens = token
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (cleanTokens.isEmpty) return null;

      // Step 2: Stop-word filter
      const stopWords = {
        'the', 'of', 'and', 'a', 'an', 'in', 'or', 'x', 'vs', 'to',
        'for', 'by', 'with', 'at', 'on', 'from',
      };
      searchTokens = cleanTokens
          .where((w) => !stopWords.contains(w))
          .toList();
      if (searchTokens.isEmpty) {
        searchTokens = cleanTokens;
      }

      // Step 3: Pick longest word as queryKey
      final sorted = List<String>.from(searchTokens)
        ..sort((a, b) => b.length.compareTo(a.length));
      queryKey = sorted.first;
    }

    // Fuzzy normalization helper (used by non-universe filter only,
    // but defined here so both try and catch blocks can reference it).
    String normalize(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
    normalizedPhrase = normalize(token);

    try {
      Query query;
      if (isUniverse) {
        // === Universe path — arrayContainsAny on mapped keywords ===
        // ONE Firestore query covers all heroes in the universe.
        query = _moviesRef.where(
          'search_keywords',
          arrayContainsAny: universeTokens,
        );
      } else {
        // === Non-universe path — single keyword (Phase 4.11) ===
        query = _moviesRef.where(
          'search_keywords',
          arrayContains: queryKey,
        );
      }
      if (typeFilter != null) {
        query = query.where('type', isEqualTo: typeFilter);
      }
      query = query
          .orderBy('createdAt', descending: true)
          .limit(limit * 3);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return null;

      // === Client-side filter ===
      // Universe path: keep ALL docs (every keyword match is part of the
      // universe by definition). Non-universe path: fuzzy phrase filter.
      final filteredDocs = snapshot.docs.where((doc) {
        if (isUniverse) return true;
        final data = doc.data() as Map<String, dynamic>;
        final title = data['title']?.toString() ?? '';
        final titleLower =
            data['title_lowercase']?.toString() ?? title.toLowerCase();
        return normalize(titleLower).contains(normalizedPhrase);
      }).toList();

      if (filteredDocs.isEmpty) return null;

      final hasMore = filteredDocs.length > limit;
      final pageDocs = hasMore
          ? filteredDocs.sublist(0, limit)
          : filteredDocs;

      final movies = pageDocs
          .map((doc) => Movie.fromMap(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ))
          .toList();

      final lastDoc = pageDocs.isNotEmpty ? pageDocs.last : null;

      debugPrint('Phase 4.12 (Universe Hybrid): collection '
          '"$collectionName" — isUniverse=$isUniverse, '
          'fetched ${snapshot.docs.length}, showing ${movies.length}, '
          'hasMore=$hasMore');

      return {
        'movies': movies,
        'hasMore': hasMore,
        'lastDoc': lastDoc,
      };
    } catch (e) {
      debugPrint('Phase 4.12: universe hybrid fallback threw: $e — '
          'trying without orderBy');
      // No-orderBy fallback (composite index missing on
      // search_keywords + type + createdAt).
      try {
        Query query;
        if (isUniverse) {
          query = _moviesRef.where(
            'search_keywords',
            arrayContainsAny: universeTokens,
          );
        } else {
          query = _moviesRef.where(
            'search_keywords',
            arrayContains: queryKey,
          );
        }
        if (typeFilter != null) {
          query = query.where('type', isEqualTo: typeFilter);
        }
        query = query.limit(limit * 3);

        if (startAfter != null) {
          query = query.startAfterDocument(startAfter);
        }

        final snapshot = await query.get();
        if (snapshot.docs.isEmpty) return null;

        final filteredDocs = snapshot.docs.where((doc) {
          if (isUniverse) return true;
          final data = doc.data() as Map<String, dynamic>;
          final title = data['title']?.toString() ?? '';
          final titleLower =
              data['title_lowercase']?.toString() ?? title.toLowerCase();
          return normalize(titleLower).contains(normalizedPhrase);
        }).toList();

        if (filteredDocs.isEmpty) return null;

        // Sort by createdAt desc (since Firestore didn't orderBy).
        filteredDocs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTs = aData['createdAt'] as Timestamp?;
          final bTs = bData['createdAt'] as Timestamp?;
          final aDate = aTs?.toDate() ?? DateTime(2000);
          final bDate = bTs?.toDate() ?? DateTime(2000);
          return bDate.compareTo(aDate);
        });

        final hasMore = filteredDocs.length > limit;
        final pageDocs = hasMore
            ? filteredDocs.sublist(0, limit)
            : filteredDocs;

        final movies = pageDocs
            .map((doc) => Movie.fromMap(
                  doc.data() as Map<String, dynamic>,
                  docId: doc.id,
                ))
            .toList();

        final lastDoc = pageDocs.isNotEmpty ? pageDocs.last : null;

        debugPrint('Phase 4.12: no-orderBy fallback — '
            'fetched ${snapshot.docs.length}, showing ${movies.length}');

        return {
          'movies': movies,
          'hasMore': hasMore,
          'lastDoc': lastDoc,
        };
      } catch (e2) {
        debugPrint('Phase 4.12: no-orderBy fallback also failed: $e2');
        return null;
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
  ///
  /// Task 42#1 fix: previously only matched casts stored as
  /// `Map<String, dynamic>` (TMDB Generator format). But Firestore's Flutter
  /// plugin returns nested array elements as `Map<dynamic, dynamic>` (NOT
  /// `Map<String, dynamic>`) on most platforms — so the `is` check failed
  /// silently and 0 results were returned. Older posts with casts saved as
  /// `List<String>` (Batch Import legacy format) were also missed.
  ///
  /// Now uses [_extractCastName] which handles all 3 storage formats — same
  /// defensive logic as `MovieDetail._parseCastMembers`. Also raised limit
  /// from 100 → 500 so older posts in larger libraries are reachable.
  Future<List<Movie>> getMoviesByActor(String actorName) async {
    final needle = actorName.trim().toLowerCase();
    if (needle.isEmpty) return [];

    try {
      // Firestore doesn't support querying inside array of objects directly,
      // so we fetch recent posts and filter client-side by cast name.
      final snapshot = await _moviesRef
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();

      final movies = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final casts = data['casts'];
            if (casts is List) {
              final hasActor = casts.any((cast) {
                final name = _extractCastName(cast);
                return name != null && name.toLowerCase() == needle;
              });
              if (hasActor) {
                try {
                  return Movie.fromMap(data, docId: doc.id);
                } catch (_) {
                  return null;
                }
              }
            }
            return null;
          })
          .whereType<Movie>()
          .toList();

      return movies;
    } catch (e) {
      debugPrint('getMoviesByActor failed: $e');
      // Fallback: try without orderBy (covers missing composite index)
      try {
        final snapshot = await _moviesRef.limit(500).get();
        final movies = snapshot.docs
            .map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final casts = data['casts'];
              if (casts is List) {
                final hasActor = casts.any((cast) {
                  final name = _extractCastName(cast);
                  return name != null && name.toLowerCase() == needle;
                });
                if (hasActor) {
                  try {
                    return Movie.fromMap(data, docId: doc.id);
                  } catch (_) {
                    return null;
                  }
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

  /// Extract a cast member's display name from any of the 3 storage formats
  /// used in Firestore 'casts' arrays:
  ///   1. `Map<String, dynamic>` — TMDB Generator format (proper)
  ///   2. `Map<dynamic, dynamic>` — Firestore's runtime return type for
  ///      nested array objects (the type that broke the old `is` check)
  ///   3. `String` — legacy Batch Import format
  /// Returns null when no usable name can be extracted.
  ///
  /// Mirrors the defensive logic in `MovieDetail._parseCastMembers` so that
  /// actor-search results match what the detail page actually renders.
  static String? _extractCastName(dynamic cast) {
    if (cast == null) return null;
    if (cast is Map) {
      final name = cast['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
      return null;
    }
    if (cast is String) {
      final name = cast.trim();
      return name.isEmpty ? null : name;
    }
    // int / bool / other — best-effort toString, trimmed.
    final s = cast.toString().trim();
    return s.isEmpty ? null : s;
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
    bool skipAuditLog = false,
  }) async {
    // Phase 2.8: rate-limit admin writes to stop runaway loops.
    // Note: BatchImportService calls addMovie in a tight loop with
    // skipAdminCheck:true. The rate limit is enforced on the OUTER
    // call (BatchImportService.runImport), not here per-movie, so
    // skipAdminCheck callers also skip the rate limit check to avoid
    // false positives. A 100-movie batch would otherwise blow through
    // the 30/min limit in 30s. The batch-level rate limit
    // (batch_import.start: 5/hour) is the real backstop.
    if (!skipAdminCheck) {
      RateLimiter.instance.enforce(RateLimitPolicies.movieAdd);
    }
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

        // Phase 2.4 — audit-log this as an update-via-duplicate-tmdbId.
        // The addMovie() entry point transparently creates OR updates
        // depending on whether a duplicate is found, so the audit log
        // captures which path was taken via the `via` details field.
        if (!skipAuditLog) {
          unawaited(AdminAuditService.instance.record(
            action: AdminAuditAction.movieUpdate,
            collection: AdminAuditCollection.movies,
            docId: existingByTmdbId.id,
            details: {
              'title': data['title'],
              'tmdbId': tmdbId,
              'via': 'duplicate_tmdbId',
            },
          ));
        }
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

      // Phase 2.4 — audit-log this as an update-via-duplicate-slug.
      if (!skipAuditLog) {
        unawaited(AdminAuditService.instance.record(
          action: AdminAuditAction.movieUpdate,
          collection: AdminAuditCollection.movies,
          docId: existingDoc.id,
          details: {
            'title': data['title'],
            'slug': slug,
            'via': 'duplicate_slug',
          },
        ));
      }
      return existingDoc.id;
    }

    // === No duplicate: Create new document ===
    data['createdAt'] = FieldValue.serverTimestamp();
    data['updatedAt'] = FieldValue.serverTimestamp();

    // Task 27 ("All Posts disappeared" bug): coerce list-typed fields
    // BEFORE writing. Same protection as in _buildSafeUpdateMap() — a
    // JSON file with `categories: "Action"` (string instead of list)
    // used to be written verbatim, then crash Movie.fromMap later. Now
    // we coerce to List<String> or remove the field entirely so the
    // new doc has clean data from the start.
    for (final listField in ['categories', 'directors', 'tags']) {
      if (data.containsKey(listField)) {
        final coerced = _coerceToStringList(data[listField]);
        if (coerced == null) {
          data.remove(listField);
        } else {
          data[listField] = coerced;
        }
      }
    }

    // Task 31 ("An Error Occurred" bug): `casts` needs the SAME special
    // handling here as in _buildSafeUpdateMap — coerce to a proper
    // List<Map<String, dynamic>> in CastMember shape so reading it back
    // via MovieDetail.fromMap doesn't throw. See _coerceToCastMaps for
    // the full rationale.
    if (data.containsKey('casts')) {
      final coerced = _coerceToCastMaps(data['casts']);
      if (coerced == null) {
        data.remove('casts');
      } else {
        data['casts'] = coerced;
      }
    }

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

    // Phase 2.4 — audit-log this as a movie create.
    if (!skipAuditLog) {
      unawaited(AdminAuditService.instance.record(
        action: AdminAuditAction.movieCreate,
        collection: AdminAuditCollection.movies,
        docId: newDocRef.id,
        details: {
          'title': data['title'],
          'tmdbId': data['tmdbId'],
          'type': data['type'],
          'slug': data['slug'],
        },
      ));
    }
    return newDocRef.id;
  }

  /// Build a safe update map from TMDB data that only contains
  /// fields that should be updated from TMDB, preserving user-edited fields.
  //
  // Task 31 ("Search can't find re-imported movie" bug): `search_keywords`
  // was missing from this list. When a Batch Import JSON file updated an
  // existing movie with a NEW title, `title` and `title_lowercase` got
  // overwritten (because they were already in this list), but
  // `search_keywords` was NOT updated — so it stayed as the OLD title's
  // tokens. The Home Search uses `search_keywords arrayContains` (Strategy 2)
  // as one of its main query strategies; with stale tokens, searches for the
  // new title found nothing via Strategy 2, and the client-side filter
  // `title.contains(query)` then filtered out Strategy 1's prefix matches
  // (because the new title's words didn't appear in the stale search_keywords
  // list, and the early-exit merge confused things). Net effect: re-imported
  // movies with new titles were unsearchable.
  //
  // FIX: add `search_keywords` to the list so it's regenerated alongside
  // `title` / `title_lowercase` when the title changes. The value is
  // computed below from `newData['title']`.
  static const _tmdbUpdateFields = [
    'title', 'title_lowercase', 'search_keywords',
    'year', 'poster', 'backdrop', 'overview', 'rating',
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

        // Task 27 ("All Posts disappeared" bug): coerce list-typed fields
        // to List<String>. If a JSON Batch Import file has
        // `categories: "Action"` (string instead of list), the old code
        // wrote the string to Firestore, which later crashed
        // `Movie.fromMap` and made the Admin Panel All Posts tab appear
        // empty. This coercion is the WRITE-SIDE fix — bad-type values
        // are either coerced to a proper list or skipped entirely.
        if (field == 'categories' || field == 'directors') {
          final coerced = _coerceToStringList(value);
          if (coerced == null) continue; // skip — can't coerce safely
          result[field] = coerced;
          continue;
        }

        // Task 31 ("An Error Occurred" bug): `casts` is special. It's
        // stored in Firestore as a List<Map<String, dynamic>> (each Map
        // has 'name' and 'profilePath' keys, per CastMember model). But
        // JSON Batch Import files often send it as:
        //   - List<String>:   ["Actor A", "Actor B"]
        //   - String:         "Actor A"
        //   - List<Map>:       [{name: "Actor A", ...}]
        //
        // The previous code ran `_coerceToStringList` on it, producing
        // a List<String>. That was WRITTEN to Firestore successfully,
        // but then `MovieDetail.fromMap` blew up trying to cast each
        // String to Map<String, dynamic> for CastMember — and the detail
        // page showed "An Error Occurred".
        //
        // FIX: coerce `casts` to a proper List<Map<String, dynamic>>
        // where each Map is `{name: <string>}`. The defensive
        // MovieDetail.fromMap (Task 31) handles reading this back.
        if (field == 'casts') {
          final coerced = _coerceToCastMaps(value);
          if (coerced == null) continue; // skip — can't coerce safely
          result[field] = coerced;
          continue;
        }

        result[field] = value;
      }
    }

    // Task 31 ("Search can't find re-imported movie" bug): if the title is
    // being updated, regenerate `search_keywords` from the NEW title so the
    // Home Search's `arrayContains` strategy stays in sync with the new
    // title. The previous version only added `search_keywords` to the field
    // list above — but JSON Batch Import files never include a
    // `search_keywords` field (it's an internally-computed field), so the
    // loop above skipped it. We synthesize it here from `title` instead.
    if (result.containsKey('title') && result['title'] is String) {
      final title = result['title'] as String;
      if (title.trim().isNotEmpty) {
        result['search_keywords'] = _generateSearchKeywords(title);
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

  /// Coerce [value] to a List<String>, or return null if it can't be
  /// coerced safely. Used by [addMovie] to PREVENT writing wrong-type
  /// values to Firestore (e.g., `categories: "Action"` as a string).
  ///
  /// Task 27 ("All Posts disappeared" bug): when a JSON Batch Import
  /// file contained `categories` as a string instead of a list, the
  /// old code wrote the string to Firestore, which later crashed
  /// `Movie.fromMap` and made the entire Admin Panel All Posts tab
  /// appear empty. This coercion is the WRITE-SIDE fix; the defensive
  /// `Movie.fromMap` is the READ-SIDE fix.
  ///
  /// Rules:
  ///   - null                       → null (skip)
  ///   - List (any element types)   → List<String> (each element via toString)
  ///   - String (non-empty)         → [value] (single-element list)
  ///   - String (empty)             → null (skip — equivalent to _isEmptyValue)
  ///   - any other type             → null (skip — don't write junk)
  List<String>? _coerceToStringList(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      final result = value
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return result.isEmpty ? null : result;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : [trimmed];
    }
    // int, bool, Map, etc. — don't write anything
    return null;
  }

  /// Coerce [value] to a List<Map<String, dynamic>> in CastMember shape,
  /// or return null if it can't be coerced safely. Companion to
  /// [_coerceToStringList] — used for the `casts` field.
  ///
  /// Task 31 ("An Error Occurred" bug): JSON Batch Import files often
  /// send `casts` as a List<String> (e.g., `["Actor A", "Actor B"]`)
  /// or as a plain String (e.g., `"Actor A"`). The previous code ran
  /// `_coerceToStringList` on it, producing a List<String> written to
  /// Firestore. But `MovieDetail.fromMap` expected `casts` to be a
  /// List<Map<String, dynamic>> (each Map has 'name'/'profilePath'
  /// keys for CastMember). The type mismatch threw inside
  /// `CastMember.fromMap(x as Map<String, dynamic>)` and the detail
  /// page showed "An Error Occurred".
  ///
  /// This coercion produces a proper List<Map<String, dynamic>> where
  /// each Map is shaped like `{name: <string>, profilePath: null}`.
  /// Existing CastMember Maps in the input are preserved as-is (so
  /// TMDB's real cast data with profile paths is kept intact).
  ///
  /// Rules:
  ///   - null                              → null (skip)
  ///   - List<Map<String, dynamic>>        → returned as-is (proper CastMember shape)
  ///   - List<String>                      → [{name: s, profilePath: null}, ...]
  ///   - List with mixed types             → each element coerced to a Map
  ///   - String (non-empty)                → [{name: value, profilePath: null}]
  ///   - String (empty) / other types      → null (skip)
  List<Map<String, dynamic>>? _coerceToCastMaps(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      final result = <Map<String, dynamic>>[];
      for (final e in value) {
        if (e == null) continue;
        if (e is Map<String, dynamic>) {
          // Already a proper CastMember map — preserve as-is.
          result.add(e);
        } else if (e is Map) {
          // Loose Map — copy to Map<String, dynamic>.
          final m = <String, dynamic>{};
          e.forEach((k, v) => m[k.toString()] = v);
          result.add(m);
        } else {
          // String, int, etc. — wrap as a CastMember-shaped map.
          final name = e.toString().trim();
          if (name.isNotEmpty) {
            result.add({'name': name, 'profilePath': null});
          }
        }
      }
      return result.isEmpty ? null : result;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : [{'name': trimmed, 'profilePath': null}];
    }
    // int, bool, Map, etc. — don't write anything
    return null;
  }

  /// Update a movie (admin only)
  Future<void> updateMovie(String id, Map<String, dynamic> data) async {
    RateLimiter.instance.enforce(RateLimitPolicies.movieUpdate);
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

    // Phase 2.4 — audit-log the movie update. Details include the fields
    // being changed so an admin reviewing the audit log can see at a
    // glance what was edited without having to fetch the doc.
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.movieUpdate,
      collection: AdminAuditCollection.movies,
      docId: id,
      details: {
        'title': data['title'],
        'fieldsChanged': data.keys.toList(),
      },
    ));
  }

  /// Delete a movie (admin only)
  Future<void> deleteMovie(String id) async {
    RateLimiter.instance.enforce(RateLimitPolicies.movieDelete);
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

    // Phase 2.4 — audit-log the movie delete. Capture title from the
    // pre-delete snapshot so the audit log shows what was deleted (the
    // doc no longer exists post-delete, so we can't read it back).
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.movieDelete,
      collection: AdminAuditCollection.movies,
      docId: id,
      details: {
        'title': doc.exists ? (doc.data() as Map<String, dynamic>)['title'] : null,
        },
      ));
  }

  /// Add a genre (admin only)
  Future<String> addGenre(String name) async {
    RateLimiter.instance.enforce(RateLimitPolicies.genreAdd);
    await _requireAdmin();
    final docRef = await _genresRef.add({
      'name': name,
      'moviesCount': 0,
    });
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.genreCreate,
      collection: AdminAuditCollection.genres,
      docId: docRef.id,
      details: {'name': name},
    ));
    return docRef.id;
  }

  /// Update a genre (admin only)
  Future<void> updateGenre(String id, String name) async {
    RateLimiter.instance.enforce(RateLimitPolicies.genreUpdate);
    await _requireAdmin();
    await _genresRef.doc(id).update({'name': name});
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.genreUpdate,
      collection: AdminAuditCollection.genres,
      docId: id,
      details: {'newName': name},
    ));
  }

  /// Delete a genre (admin only)
  Future<void> deleteGenre(String id) async {
    RateLimiter.instance.enforce(RateLimitPolicies.genreDelete);
    await _requireAdmin();
    await _genresRef.doc(id).delete();
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.genreDelete,
      collection: AdminAuditCollection.genres,
      docId: id,
    ));
  }

  /// Add a tag (admin only)
  Future<String> addTag(String name) async {
    RateLimiter.instance.enforce(RateLimitPolicies.tagAdd);
    await _requireAdmin();
    final docRef = await _tagsRef.add({
      'name': name,
      'moviesCount': 0,
    });
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.tagCreate,
      collection: AdminAuditCollection.tags,
      docId: docRef.id,
      details: {'name': name},
    ));
    return docRef.id;
  }

  /// Update a tag (admin only)
  Future<void> updateTag(String id, String name) async {
    RateLimiter.instance.enforce(RateLimitPolicies.tagUpdate);
    await _requireAdmin();
    await _tagsRef.doc(id).update({'name': name});
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.tagUpdate,
      collection: AdminAuditCollection.tags,
      docId: id,
      details: {'newName': name},
    ));
  }

  /// Delete a tag (admin only)
  Future<void> deleteTag(String id) async {
    RateLimiter.instance.enforce(RateLimitPolicies.tagDelete);
    await _requireAdmin();
    await _tagsRef.doc(id).delete();
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.tagDelete,
      collection: AdminAuditCollection.tags,
      docId: id,
    ));
  }

  /// Add a collection (admin only)
  Future<String> addCollection(String name) async {
    RateLimiter.instance.enforce(RateLimitPolicies.collectionAdd);
    await _requireAdmin();
    final docRef = await _collectionsRef.add({
      'name': name,
      'moviesCount': 0,
    });
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.collectionCreate,
      collection: AdminAuditCollection.collections,
      docId: docRef.id,
      details: {'name': name},
    ));
    return docRef.id;
  }

  /// Update a collection (admin only)
  Future<void> updateCollection(String id, String name) async {
    RateLimiter.instance.enforce(RateLimitPolicies.collectionUpdate);
    await _requireAdmin();
    await _collectionsRef.doc(id).update({'name': name});
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.collectionUpdate,
      collection: AdminAuditCollection.collections,
      docId: id,
      details: {'newName': name},
    ));
  }

  /// Delete a collection (admin only)
  Future<void> deleteCollection(String id) async {
    RateLimiter.instance.enforce(RateLimitPolicies.collectionDelete);
    await _requireAdmin();
    await _collectionsRef.doc(id).delete();
    unawaited(AdminAuditService.instance.record(
      action: AdminAuditAction.collectionDelete,
      collection: AdminAuditCollection.collections,
      docId: id,
    ));
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
    RateLimiter.instance.enforce(RateLimitPolicies.bannerUpdate);
    await _requireAdmin();
    try {
      await _firestore.collection('app_settings').doc('banner_config').set({
        'imageUrls': imageUrls,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // Phase 2.4 — audit-log the banner update. Record the count (not
      // the URLs themselves — URLs can be long and the count is enough
      // for accountability).
      unawaited(AdminAuditService.instance.record(
        action: AdminAuditAction.bannerUpdate,
        collection: AdminAuditCollection.appSettings,
        docId: 'banner_config',
        details: {'imageCount': imageUrls.length},
      ));
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
