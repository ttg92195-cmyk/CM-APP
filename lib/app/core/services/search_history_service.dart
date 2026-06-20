import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's search-history list in `shared_preferences` (local-only,
/// not synced to Firestore) to avoid consuming Firebase reads/writes quota.
///
/// Contract:
///   - Latest search appears at index 0.
///   - Duplicates are removed (existing entry is moved to top).
///   - History is capped to [maxItems] (default 10) — oldest entry dropped.
///   - All mutations are persisted to SharedPreferences under [_storageKey]
///     as a JSON-encoded list of strings.
class SearchHistoryService {
  SearchHistoryService({this.maxItems = 10});

  /// Maximum number of items kept in history. Older items beyond this are
  /// automatically evicted on insert.
  final int maxItems;

  static const String _storageKey = 'search_history_v1';

  // ---- Singleton accessor (handy for tests + simple callers) -------------
  static SearchHistoryService? _instance;
  static SearchHistoryService get instance {
    _instance ??= SearchHistoryService();
    return _instance!;
  }

  // ---- In-memory cache (so UI reads are synchronous after init) ----------
  List<String> _history = [];
  bool _initialized = false;

  /// Stream of history changes so multiple listeners (e.g. UI) can react.
  final StreamController<List<String>> _controller =
      StreamController<List<String>>.broadcast();
  Stream<List<String>> get changes => _controller.stream;

  /// Load history from local storage. Call once on app/screen init.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<List<String>> load() async {
    if (_initialized) return List.unmodifiable(_history);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_storageKey) ?? const [];
      _history = stored.whereType<String>().toList(growable: true);
    } catch (_) {
      _history = [];
    }
    _initialized = true;
    _controller.add(List.unmodifiable(_history));
    return List.unmodifiable(_history);
  }

  /// Returns the current history (must call [load] first; otherwise empty).
  List<String> get history => List.unmodifiable(_history);

  /// Adds [query] to the top of the history.
  /// - Empty / whitespace-only queries are ignored.
  /// - Duplicates are moved to the top (not duplicated).
  /// - List is capped at [maxItems].
  Future<void> add(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Remove any existing occurrence so we can re-insert at the top.
    _history.removeWhere((e) => e == trimmed);
    _history.insert(0, trimmed);

    // Cap the list size — drop oldest entries beyond maxItems.
    if (_history.length > maxItems) {
      _history = _history.sublist(0, maxItems);
    }

    await _persist();
  }

  /// Removes a single entry by exact match.
  Future<void> remove(String query) async {
    final before = _history.length;
    _history.removeWhere((e) => e == query);
    if (_history.length != before) {
      await _persist();
    }
  }

  /// Clears all history.
  Future<void> clear() async {
    if (_history.isEmpty) return;
    _history = [];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_storageKey, _history);
    } catch (_) {
      // Persistence failures are non-fatal — keep the in-memory cache.
    }
    _controller.add(List.unmodifiable(_history));
  }

  /// Release the stream controller (call from a parent dispose if you own
  /// a long-lived instance). The default singleton never disposes.
  void dispose() {
    _controller.close();
  }
}
