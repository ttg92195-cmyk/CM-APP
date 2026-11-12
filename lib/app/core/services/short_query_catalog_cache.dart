import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cm_movies/app/core/models/movie.dart';

/// Phase 4.43 — Local catalog cache powering SHORT-QUERY search (1–2 chars).
///
/// PROBLEM (leftover from the Phase 4.22 fix): queries of 1–2 characters
/// cannot use the Firestore prefix index ("o" must also match "Thor"), so
/// `FirestoreContentService._searchWithKeyword` falls back to a
/// FULL-COLLECTION SCAN — batches of 500 docs, cap 5000 docs, every batch a
/// SEQUENTIAL round trip. On a slow Myanmar mobile line that means 2–10+
/// seconds per short query, and every short query re-reads the whole catalog
/// from Firestore (up to 5000 document reads EACH time — exactly the
/// "Firebase usage spike" scenario Bro worried about).
///
/// FIX: the first scan still runs (results identical to the old behavior),
/// but its output is snapshotted to a local JSON file containing a
/// LIGHTWEIGHT projection of each movie (id + the few fields the search
/// pipeline filters/sorts on: title_lowercase, year, type, categories,
/// rating, certification, status, createdAt, updatedAt — no poster, no
/// description, no TMDB payloads). Repeat short queries within the TTL
/// filter LOCALLY (0 extra reads, 0 extra round trips) and only re-fetch
/// the ≤20 winning docs by ID so the UI still receives complete data.
///
/// FRESHNESS:
/// - TTL 24 h (savedAt timestamp). Expired cache → treated as missing →
///   the caller re-scans and rebuilds.
/// - `upsertMovies` merges newer full docs (e.g. movies Bro posted AFTER
///   the last rebuild — they are already returned by the prefix /
///   search_keywords server queries) into the cache, so brand-new posts
///   become findable by short queries without waiting for the TTL.
/// - A deleted movie can linger in the cache until the next rebuild; it
///   simply won't come back from the by-ID hydration fetch, so it never
///   reaches the UI.
///
/// All failures are swallowed and logged: the cache is a pure optimization.
/// If the file is corrupt, the directory is unavailable, or JSON is bad,
/// `load()` returns null and the caller falls back to the old scan path.
class ShortQueryCatalogCache {
  ShortQueryCatalogCache._();
  static final ShortQueryCatalogCache instance = ShortQueryCatalogCache._();

  static const int _version = 1;
  static const Duration defaultTtl = Duration(hours: 24);
  static const String _fileName = 'cm_short_query_catalog_v1.json';

  List<Map<String, dynamic>>? _entries;
  int? _savedAtMs;
  Future<List<Map<String, dynamic>>?>? _loading;
  Future<void>? _writing;

  /// Cached lightweight entries (maps directly consumable by
  /// `Movie.fromMap`), or null when the cache is missing / stale / corrupt.
  Future<List<Map<String, dynamic>>?> load({Duration ttl = defaultTtl}) {
    // De-duplicate concurrent loads (several searches firing at once).
    return _loading ??= _load(ttl).whenComplete(() => _loading = null);
  }

  Future<List<Map<String, dynamic>>?> _load(Duration ttl) async {
    // In-memory fast path (same isolate session).
    if (_entries != null) {
      final saved = _savedAtMs ?? 0;
      final fresh =
          DateTime.now().millisecondsSinceEpoch - saved < ttl.inMilliseconds;
      return fresh ? _entries : null;
    }
    File? f;
    try {
      f = await _cacheFile();
      if (f == null || !f.existsSync()) return null;
      final raw = await f.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if ((map['v'] as int? ?? 0) != _version) return null;
      final savedAt = map['savedAt'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - savedAt >=
          ttl.inMilliseconds) {
        return null;
      }
      final list = map['entries'] as List? ?? const [];
      final entries = <Map<String, dynamic>>[];
      for (final e in list) {
        if (e is Map) entries.add(Map<String, dynamic>.from(e));
      }
      if (entries.isEmpty) return null;
      _entries = entries;
      _savedAtMs = savedAt;
      return entries;
    } catch (e) {
      debugPrint('ShortQueryCatalogCache: load failed (will rescan): $e');
      // Corrupt file — remove it so we don't keep failing every search.
      try {
        if (f != null && f.existsSync()) await f.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Rebuild the ENTIRE cache from a fresh full-collection scan.
  /// Called (fire-and-forget) right after a scan completes so the next
  /// short query can run locally.
  Future<void> rebuildFromMovies(List<Movie> movies) async {
    try {
      final entries = <Map<String, dynamic>>[];
      final seen = <String>{};
      for (final m in movies) {
        if (m.id.isEmpty || !seen.add(m.id)) continue;
        final entry = _entryFromMovie(m);
        if (entry != null) entries.add(entry);
      }
      if (entries.isEmpty) return;
      _entries = entries;
      _savedAtMs = DateTime.now().millisecondsSinceEpoch;
      await _persist();
    } catch (e) {
      debugPrint('ShortQueryCatalogCache: rebuild failed: $e');
    }
  }

  /// Merge newer full docs into the existing cache WITHOUT resetting the
  /// TTL (movies Bro posted after the last rebuild). No-op when the cache
  /// is not loaded yet — the next scan will rebuild it anyway.
  Future<void> upsertMovies(List<Movie> movies) async {
    try {
      final current = _entries;
      if (current == null || movies.isEmpty) return;
      final byId = {for (final e in current) e['id'] as String? ?? '': e};
      var changed = false;
      for (final m in movies) {
        if (m.id.isEmpty) continue;
        final entry = _entryFromMovie(m);
        if (entry == null) continue;
        final existing = byId[m.id];
        // Only insert/overwrite when the doc is newer than what we hold
        // (updatedAt missing on either side → just overwrite).
        if (existing == null) {
          byId[m.id] = entry;
          current.add(entry);
          changed = true;
        } else {
          final existingAt =
              DateTime.tryParse(existing['updatedAt']?.toString() ?? '');
          final incomingAt = m.updatedAt;
          if (incomingAt != null &&
              (existingAt == null || incomingAt.isAfter(existingAt))) {
            final idx = current.indexOf(existing);
            if (idx >= 0) current[idx] = entry;
            changed = true;
          }
        }
      }
      if (changed) await _persist();
    } catch (e) {
      debugPrint('ShortQueryCatalogCache: upsert failed: $e');
    }
  }

  /// Lightweight projection — ONLY the fields the short-query search
  /// pipeline touches: substring match (title_lowercase), name-token
  /// match (title_lowercase), filters (year/type/categories/rating/
  /// certification/status) and sorting (title, updatedAt, createdAt).
  /// Poster/description/TMDB payloads stay out to keep the file small.
  static Map<String, dynamic>? _entryFromMovie(Movie m) {
    if (m.titleLowercase.isEmpty) return null;
    return <String, dynamic>{
      'id': m.id,
      'title': m.title,
      'title_lowercase': m.titleLowercase,
      if (m.year != null) 'year': m.year,
      if (m.rating != null) 'rating': m.rating,
      if (m.type != null) 'type': m.type,
      if (m.certification != null) 'certification': m.certification,
      if (m.status != null) 'status': m.status,
      'categories': m.categories,
      'createdAt': m.createdAt?.toIso8601String(),
      'updatedAt': m.updatedAt?.toIso8601String(),
    };
  }

  Future<void> _persist() {
    // Serialize writes — a rebuild racing an upsert must not corrupt the
    // file (last writer wins is fine; interleaved writes are not).
    final previous = _writing ?? Future<void>.value();
    final next = previous.then((_) => _doWrite()).catchError((Object e) {
      debugPrint('ShortQueryCatalogCache: persist failed: $e');
    });
    _writing = next;
    return next;
  }

  Future<void> _doWrite() async {
    final entries = _entries;
    final savedAt = _savedAtMs;
    if (entries == null || savedAt == null) return;
    final f = await _cacheFile();
    if (f == null) return;
    final json = jsonEncode(<String, dynamic>{
      'v': _version,
      'savedAt': savedAt,
      'entries': entries,
    });
    await f.writeAsString(json, flush: true);
  }

  Future<File?> _cacheFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (e) {
      debugPrint('ShortQueryCatalogCache: cannot resolve app dir: $e');
      return null;
    }
  }
}
