import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cm_movies/app/core/models/movie.dart';

/// Recently-viewed movies service.
///
/// STORAGE ISOLATION (privacy fix):
/// Recents are stored in SharedPreferences under a per-UID key
/// (`recent_movies_{uid}`) when the user is logged in, or under
/// `recent_movies_anon` when no user is signed in. This guarantees
/// that one account's recently-viewed list never leaks to another
/// account on the same device.
///
/// On logout, [clearAllForLogout] should be called to wipe every
/// `recent_movies_*` key (including the anon key) so the next user
/// starts from a clean state.
class RecentService {
  static const String _recentKeyPrefix = 'recent_movies_';
  static const String _anonKey = 'recent_movies_anon';
  static const int _maxRecent = 50;

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Per-UID storage key — falls back to anon when no user is signed in.
  String get _currentKey {
    final uid = _auth.currentUser?.uid;
    return (uid != null && uid.isNotEmpty)
        ? '$_recentKeyPrefix$uid'
        : _anonKey;
  }

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<Movie>> getRecentMovies() async {
    final prefs = await _prefs;
    final String? data = prefs.getString(_currentKey);
    if (data == null || data.isEmpty) return [];
    try {
      final List<dynamic> decoded = json.decode(data) as List<dynamic>;
      return decoded
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
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

  Future<void> clearRecents() async {
    final prefs = await _prefs;
    await prefs.remove(_currentKey);
  }

  /// Wipe EVERY recently-viewed list from SharedPreferences
  /// (all per-UID keys + the anon key). Called by AppConfig.logoutUser()
  /// and friends so that user A's recents never appear under user B's
  /// Recently Viewed tab after a logout/login switch on the same device.
  Future<void> clearAllForLogout() async {
    final prefs = await _prefs;
    final keys = prefs
        .getKeys()
        .where((k) => k.startsWith(_recentKeyPrefix) || k == _anonKey)
        .toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  Future<void> _saveRecents(List<Movie> recents) async {
    final prefs = await _prefs;
    final encoded = json.encode(recents.map((m) => m.toMap()).toList());
    await prefs.setString(_currentKey, encoded);
  }
}
