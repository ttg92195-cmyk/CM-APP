import 'dart:convert';
import 'package:flutter/foundation.dart';
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
        debugPrint('BookmarkService.getBookmarks Firestore failed: $e');
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
        debugPrint('BookmarkService.isBookmarked Firestore failed: $e');
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

  /// Add bookmark.
  ///
  /// H7 FIX (silent Firestore failures): Previously this method caught
  /// Firestore write failures and silently fell back to local storage
  /// without surfacing the failure to the caller. The user saw
  /// "Added to bookmarks" but the bookmark was only in local storage,
  /// not synced. On next login from another device, the bookmark was
  /// missing — silent data loss.
  ///
  /// Now returns `true` if the PRIMARY write target succeeded:
  ///   - Logged in  → Firestore write succeeded.
  ///   - Logged out → Local write succeeded (local IS primary).
  /// Returns `false` if the primary target failed and we had to fall
  /// back (logged-in Firestore failure → local fallback). Callers
  /// should show a "Saved locally — will sync when online" snackbar
  /// when this method returns `false` and the user is logged in.
  Future<bool> addBookmark(Movie movie) async {
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
        return true;
      } catch (e) {
        debugPrint('BookmarkService.addBookmark Firestore failed: $e — falling back to local');
        // Fall back to local — return false so caller knows it's not synced.
        await _addLocalBookmark(movie);
        return false;
      }
    }
    // Logged-out: local IS primary.
    await _addLocalBookmark(movie);
    return true;
  }

  Future<void> _addLocalBookmark(Movie movie) async {
    final bookmarks = await _getLocalBookmarks();
    if (!bookmarks.any((m) => m.id == movie.id)) {
      bookmarks.insert(0, movie);
      await _saveLocalBookmarks(bookmarks);
    }
  }

  /// Remove bookmark.
  ///
  /// H7 FIX: same silent-failure issue as addBookmark. Returns `true`
  /// if primary target succeeded, `false` if Firestore failed and we
  /// fell back to local removal (which is correct — we don't want a
  /// stale bookmark persisting in the cloud; next sync will retry).
  Future<bool> removeBookmark(String movieId) async {
    if (_isLoggedIn && _userId != null) {
      try {
        await _firestore
            .collection('users')
            .doc(_userId)
            .collection('bookmarks')
            .doc(movieId)
            .delete();
        return true;
      } catch (e) {
        debugPrint('BookmarkService.removeBookmark Firestore failed: $e — falling back to local');
        await _removeLocalBookmark(movieId);
        return false;
      }
    }
    // Logged-out: local IS primary.
    await _removeLocalBookmark(movieId);
    return true;
  }

  Future<void> _removeLocalBookmark(String movieId) async {
    final bookmarks = await _getLocalBookmarks();
    bookmarks.removeWhere((m) => m.id == movieId);
    await _saveLocalBookmarks(bookmarks);
  }

  /// Toggle bookmark. Returns the result of whichever internal
  /// operation ran (add or remove). See [addBookmark] / [removeBookmark]
  /// for return-value semantics.
  Future<bool> toggleBookmark(Movie movie) async {
    if (await isBookmarked(movie.id)) {
      return await removeBookmark(movie.id);
    } else {
      return await addBookmark(movie);
    }
  }

  // Save bookmarks to local SharedPreferences
  Future<void> _saveLocalBookmarks(List<Movie> bookmarks) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = json.encode(bookmarks.map((m) => m.toMap()).toList());
    await prefs.setString(_bookmarkKey, encoded);
  }

  /// Wipe the LOCAL (logged-out) bookmark cache from SharedPreferences.
  /// Called on logout to prevent one user's local-only bookmarks from
  /// leaking to another user on the same device. Firestore bookmarks
  /// (under /users/{uid}/bookmarks) are per-UID by design and need no
  /// clearing here — they simply disappear with the auth session.
  Future<void> clearAllLocalForLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bookmarkKey);
  }

  /// Clear all bookmarks.
  ///
  /// H7 FIX: same silent-failure issue. Returns `true` if primary
  /// target succeeded (Firestore batch cleared, or local-only cleared
  /// when logged out). Returns `false` if Firestore failed — in that
  /// case the local store is still cleared to honor the user's intent,
  /// but cloud bookmarks remain and will reappear on next sync.
  /// Callers should warn the user when this returns `false`.
  ///
  /// (H8 will refactor this to use WriteBatch instead of N+1 deletes.
  /// For now the per-doc delete loop is preserved to keep H7 diff
  /// focused on the silent-failure surface.)
  Future<bool> clearBookmarks() async {
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
        return true;
      } catch (e) {
        debugPrint('BookmarkService.clearBookmarks Firestore failed: $e — falling back to local clear');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_bookmarkKey);
        return false;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bookmarkKey);
    return true;
  }

  /// Merge local bookmarks to Firestore (call after login).
  ///
  /// H7 FIX: previously this method had a bare `catch (e) {}` block
  /// that swallowed ALL failures, including partial merges. If the
  /// network dropped mid-merge, some bookmarks were synced to Firestore
  /// but the local cache was still cleared (line 203), losing the
  /// un-synced ones entirely.
  ///
  /// Now returns `true` if the merge fully succeeded AND local cache
  /// was cleared. Returns `false` if any step failed — local cache is
  /// PRESERVED so the merge can be retried on next login. Callers
  /// (login_page.dart) should warn the user when this returns `false`.
  Future<bool> mergeLocalBookmarksToCloud() async {
    if (!_isLoggedIn || _userId == null) return true;

    try {
      final localBookmarks = await _getLocalBookmarks();
      if (localBookmarks.isEmpty) return true;

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

      // Clear local bookmarks only after the full merge succeeds.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bookmarkKey);
      return true;
    } catch (e) {
      debugPrint('BookmarkService.mergeLocalBookmarksToCloud failed: $e — local bookmarks preserved');
      return false;
    }
  }
}
