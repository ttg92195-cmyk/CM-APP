import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cm_movies/app/core/models/movie.dart';

class RecentService {
  static const String _recentKey = 'recent_movies';
  static const int _maxRecent = 50;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<Movie>> getRecentMovies() async {
    final prefs = await _prefs;
    final String? data = prefs.getString(_recentKey);
    if (data == null || data.isEmpty) return [];
    final List<dynamic> decoded = json.decode(data) as List<dynamic>;
    return decoded
        .map((x) => Movie.fromMap(x as Map<String, dynamic>))
        .toList();
  }

  Future<void> addRecent(Movie movie) async {
    final recents = await getRecentMovies();
    recents.removeWhere((m) => m.id == movie.id);
    recents.insert(0, movie);
    if (recents.length > _maxRecent) {
      recents.removeRange(_maxRecent, recents.length);
    }
    await _saveRecents(recents);
  }

  Future<void> removeRecent(int movieId) async {
    final recents = await getRecentMovies();
    recents.removeWhere((m) => m.id == movieId);
    await _saveRecents(recents);
  }

  Future<void> clearRecents() async {
    final prefs = await _prefs;
    await prefs.remove(_recentKey);
  }

  Future<void> _saveRecents(List<Movie> recents) async {
    final prefs = await _prefs;
    final encoded = json.encode(recents.map((m) => m.toMap()).toList());
    await prefs.setString(_recentKey, encoded);
  }
}
