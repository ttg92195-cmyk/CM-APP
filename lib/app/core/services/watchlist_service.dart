import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/app/core/models/movie.dart';

/// Watchlist Service - "Watch Later" list, separate from Bookmarks
/// Bookmarks = favorite/saved movies
/// Watchlist = movies you want to watch later
class WatchlistService {
  static const String _watchlistKey = 'watchlist_movies';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool get _isLoggedIn => _auth.currentUser != null;
  String? get _userId => _auth.currentUser?.uid;

  /// Get all watchlist movies
  Future<List<Movie>> getWatchlist() async {
    if (_isLoggedIn && _userId != null) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('watchlist')
            .orderBy('addedAt', descending: true)
            .get();

        return snapshot.docs
            .map((doc) => Movie.fromMap(doc.data(), docId: doc.id))
            .toList();
      } catch (e) {
        debugPrint('WatchlistService.getWatchlist Firestore failed: $e');
        return _getLocalWatchlist();
      }
    }
    return _getLocalWatchlist();
  }

  Future<List<Movie>> _getLocalWatchlist() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_watchlistKey);
    if (data == null || data.isEmpty) return [];
    final List<dynamic> decoded = json.decode(data) as List<dynamic>;
    return decoded
        .map((x) => Movie.fromMap(x as Map<String, dynamic>))
        .toList();
  }

  /// Check if movie is in watchlist - O(1) for Firestore, O(1) for local with Set cache
  Future<bool> isInWatchlist(String movieId) async {
    if (_isLoggedIn && _userId != null) {
      try {
        // Direct document read - O(1) instead of fetching all watchlist items
        final doc = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('watchlist')
            .doc(movieId)
            .get();
        return doc.exists;
      } catch (e) {
        // Fall back to local check
        debugPrint('WatchlistService.isInWatchlist Firestore failed: $e');
      }
    }
    // Local: check with Set for O(1) lookup
    final ids = await _getLocalWatchlistIds();
    return ids.contains(movieId);
  }

  /// Get local watchlist IDs as a Set for O(1) lookups
  Future<Set<String>> _getLocalWatchlistIds() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_watchlistKey);
    if (data == null || data.isEmpty) return {};
    final List<dynamic> decoded = json.decode(data) as List<dynamic>;
    return decoded
        .map((x) => (x as Map<String, dynamic>)['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  /// Add movie to watchlist.
  ///
  /// H7 FIX (silent Firestore failures): same fix as
  /// BookmarkService.addBookmark. Returns `true` if primary write
  /// target succeeded, `false` if Firestore failed and we fell back
  /// to local. Callers should show a "Saved locally — will sync when
  /// online" snackbar when this returns `false` and the user is
  /// logged in.
  Future<bool> addToWatchlist(Movie movie) async {
    if (_isLoggedIn && _userId != null) {
      try {
        await _firestore
            .collection('users')
            .doc(_userId)
            .collection('watchlist')
            .doc(movie.id)
            .set({
          ...movie.toMap(),
          'addedAt': FieldValue.serverTimestamp(),
        });
        return true;
      } catch (e) {
        debugPrint('WatchlistService.addToWatchlist Firestore failed: $e — falling back to local');
        await _addLocalWatchlist(movie);
        return false;
      }
    }
    // Logged-out: local IS primary.
    await _addLocalWatchlist(movie);
    return true;
  }

  Future<void> _addLocalWatchlist(Movie movie) async {
    final watchlist = await _getLocalWatchlist();
    if (!watchlist.any((m) => m.id == movie.id)) {
      watchlist.insert(0, movie);
      await _saveLocalWatchlist(watchlist);
    }
  }

  /// Remove movie from watchlist.
  ///
  /// H7 FIX: same as addToWatchlist. Returns `true` if primary target
  /// succeeded, `false` if Firestore failed and we fell back to local.
  Future<bool> removeFromWatchlist(String movieId) async {
    if (_isLoggedIn && _userId != null) {
      try {
        await _firestore
            .collection('users')
            .doc(_userId)
            .collection('watchlist')
            .doc(movieId)
            .delete();
        return true;
      } catch (e) {
        debugPrint('WatchlistService.removeFromWatchlist Firestore failed: $e — falling back to local');
        await _removeLocalWatchlist(movieId);
        return false;
      }
    }
    // Logged-out: local IS primary.
    await _removeLocalWatchlist(movieId);
    return true;
  }

  Future<void> _removeLocalWatchlist(String movieId) async {
    final watchlist = await _getLocalWatchlist();
    watchlist.removeWhere((m) => m.id == movieId);
    await _saveLocalWatchlist(watchlist);
  }

  /// Toggle watchlist status. Returns the result of whichever
  /// internal op ran. See [addToWatchlist] / [removeFromWatchlist]
  /// for return-value semantics.
  Future<bool> toggleWatchlist(Movie movie) async {
    if (await isInWatchlist(movie.id)) {
      return await removeFromWatchlist(movie.id);
    } else {
      return await addToWatchlist(movie);
    }
  }

  /// Wipe the LOCAL (logged-out) watchlist cache from SharedPreferences.
  /// Called on logout to prevent one user's local-only watchlist from
  /// leaking to another user on the same device. Firestore watchlist
  /// (under /users/{uid}/watchlist) is per-UID by design and needs no
  /// clearing here — it simply disappears with the auth session.
  Future<void> clearAllLocalForLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_watchlistKey);
  }

  Future<void> _saveLocalWatchlist(List<Movie> watchlist) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(watchlist.map((m) => m.toMap()).toList());
    await prefs.setString(_watchlistKey, encoded);
  }

}
