import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/app/core/models/movie.dart';

class BookmarkService {
  static const String _bookmarkKey = 'bookmarked_movies';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Check if user is logged in
  bool get _isLoggedIn => _auth.currentUser != null;
  String? get _userId => _auth.currentUser?.uid;

  // Get bookmarks - from Firestore if logged in, else from local
  Future<List<Movie>> getBookmarks() async {
    if (_isLoggedIn && _userId != null) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('bookmarks')
            .orderBy('addedAt', descending: true)
            .get();

        return snapshot.docs
            .map((doc) => Movie.fromMap(doc.data(), docId: doc.id))
            .toList();
      } catch (e) {
        // Fall back to local storage if Firestore fails
        return _getLocalBookmarks();
      }
    }
    return _getLocalBookmarks();
  }

  // Get local bookmarks from SharedPreferences
  Future<List<Movie>> _getLocalBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_bookmarkKey);
    if (data == null || data.isEmpty) return [];
    final List<dynamic> decoded = json.decode(data) as List<dynamic>;
    return decoded
        .map((x) => Movie.fromMap(x as Map<String, dynamic>))
        .toList();
  }

  // Check if movie is bookmarked - O(1) for Firestore, O(1) for local with Set cache
  Future<bool> isBookmarked(String movieId) async {
    if (_isLoggedIn && _userId != null) {
      try {
        // Direct document read - O(1) instead of fetching all bookmarks
        final doc = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('bookmarks')
            .doc(movieId)
            .get();
        return doc.exists;
      } catch (e) {
        // Fall back to local check
      }
    }
    // Local: check with Set for O(1) lookup
    final ids = await _getLocalBookmarkIds();
    return ids.contains(movieId);
  }

  /// Get local bookmark IDs as a Set for O(1) lookups
  Future<Set<String>> _getLocalBookmarkIds() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_bookmarkKey);
    if (data == null || data.isEmpty) return {};
    final List<dynamic> decoded = json.decode(data) as List<dynamic>;
    return decoded
        .map((x) => (x as Map<String, dynamic>)['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  // Add bookmark - to Firestore if logged in, else local
  Future<void> addBookmark(Movie movie) async {
    if (_isLoggedIn && _userId != null) {
      try {
        await _firestore
            .collection('users')
            .doc(_userId)
            .collection('bookmarks')
            .doc(movie.id)
            .set({
          ...movie.toMap(),
          'addedAt': FieldValue.serverTimestamp(),
        });
        return;
      } catch (e) {
        // Fall back to local
      }
    }
    // Local storage fallback
    final bookmarks = await _getLocalBookmarks();
    if (!bookmarks.any((m) => m.id == movie.id)) {
      bookmarks.insert(0, movie);
      await _saveLocalBookmarks(bookmarks);
    }
  }

  // Remove bookmark - from Firestore if logged in, else local
  Future<void> removeBookmark(String movieId) async {
    if (_isLoggedIn && _userId != null) {
      try {
        await _firestore
            .collection('users')
            .doc(_userId)
            .collection('bookmarks')
            .doc(movieId)
            .delete();
        return;
      } catch (e) {
        // Fall back to local
      }
    }
    // Local storage fallback
    final bookmarks = await _getLocalBookmarks();
    bookmarks.removeWhere((m) => m.id == movieId);
    await _saveLocalBookmarks(bookmarks);
  }

  // Toggle bookmark
  Future<void> toggleBookmark(Movie movie) async {
    if (await isBookmarked(movie.id)) {
      await removeBookmark(movie.id);
    } else {
      await addBookmark(movie);
    }
  }

  // Save bookmarks to local SharedPreferences
  Future<void> _saveLocalBookmarks(List<Movie> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(bookmarks.map((m) => m.toMap()).toList());
    await prefs.setString(_bookmarkKey, encoded);
  }

  // Clear all bookmarks
  Future<void> clearBookmarks() async {
    if (_isLoggedIn && _userId != null) {
      try {
        final snapshot = await _firestore
            .collection('users')
            .doc(_userId)
            .collection('bookmarks')
            .get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
        return;
      } catch (e) {
        // Fall back to local
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bookmarkKey);
  }

  // Merge local bookmarks to Firestore (call after login)
  Future<void> mergeLocalBookmarksToCloud() async {
    if (!_isLoggedIn || _userId == null) return;

    try {
      final localBookmarks = await _getLocalBookmarks();
      if (localBookmarks.isEmpty) return;

      for (final movie in localBookmarks) {
        final docRef = _firestore
            .collection('users')
            .doc(_userId)
            .collection('bookmarks')
            .doc(movie.id);

        final doc = await docRef.get();
        if (!doc.exists) {
          await docRef.set({
            ...movie.toMap(),
            'addedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // Clear local bookmarks after successful merge
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bookmarkKey);
    } catch (e) {
      // Silently fail - local bookmarks remain
    }
  }
}
