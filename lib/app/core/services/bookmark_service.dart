import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cm_movies/app/core/models/movie.dart';

class BookmarkService {
  static const String _bookmarkKey = 'bookmarked_movies';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<Movie>> getBookmarks() async {
    final prefs = await _prefs;
    final String? data = prefs.getString(_bookmarkKey);
    if (data == null || data.isEmpty) return [];
    final List<dynamic> decoded = json.decode(data) as List<dynamic>;
    return decoded
        .map((x) => Movie.fromMap(x as Map<String, dynamic>))
        .toList();
  }

  Future<bool> isBookmarked(int movieId) async {
    final bookmarks = await getBookmarks();
    return bookmarks.any((m) => m.id == movieId);
  }

  Future<void> addBookmark(Movie movie) async {
    final bookmarks = await getBookmarks();
    if (!bookmarks.any((m) => m.id == movie.id)) {
      bookmarks.insert(0, movie);
      await _saveBookmarks(bookmarks);
    }
  }

  Future<void> removeBookmark(int movieId) async {
    final bookmarks = await getBookmarks();
    bookmarks.removeWhere((m) => m.id == movieId);
    await _saveBookmarks(bookmarks);
  }

  Future<void> toggleBookmark(Movie movie) async {
    if (await isBookmarked(movie.id)) {
      await removeBookmark(movie.id);
    } else {
      await addBookmark(movie);
    }
  }

  Future<void> _saveBookmarks(List<Movie> bookmarks) async {
    final prefs = await _prefs;
    final encoded = json.encode(bookmarks.map((m) => m.toMap()).toList());
    await prefs.setString(_bookmarkKey, encoded);
  }

  Future<void> clearBookmarks() async {
    final prefs = await _prefs;
    await prefs.remove(_bookmarkKey);
  }
}
