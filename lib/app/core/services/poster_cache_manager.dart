import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Singleton CacheManager for movie poster / backdrop images.
///
/// WHY THIS EXISTS:
/// Bro reported that on poor / unstable networks, posters stop showing
/// after a while — even for movies the user has already viewed. The root
/// cause is that `cached_network_image` uses the default cache manager,
/// which expires entries after 30 days AND has a default max cache size
/// of ~200 files. Once the cache fills up, old entries are evicted, and
/// on poor network they can't be re-downloaded fast enough — so the user
/// sees a grey / red error placeholder.
///
/// This custom CacheManager:
///   - stalePeriod = 365 days: cached files stay on disk for a year
///   - maxCacheSize = 500 MB: roughly ~5000-10000 posters (avg 50-100 KB each)
///   - maxNrOfCacheObjects = 1000: more than enough for any browsing session
///
/// Usage in CachedNetworkImage:
///   CachedNetworkImage(
///     imageUrl: url,
///     cacheManager: PosterCacheManager.instance,  // ← use this
///     ...
///   )
///
/// Files are stored under the app's cache directory under a subfolder
/// called 'posterCache'. The cache is per-app-install — cleared when
/// the app is uninstalled or the user clears app data.
class PosterCacheManager extends CacheManager {
  static const String key = 'posterCache';

  // Singleton — one shared cache across the entire app.
  static final PosterCacheManager _instance = PosterCacheManager._();

  factory PosterCacheManager() => _instance;

  PosterCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 365),
          maxNrOfCacheObjects: 1000,
          maxCacheSize: 500 * 1024 * 1024, // 500 MB
        ));

  /// Convenience accessor used by CachedNetworkImage.cacheManager.
  static PosterCacheManager get instance => _instance;

  /// Removes all cached files for this manager. Called from
  /// Settings → Clear Cache. Returns the count of files removed.
  Future<int> clearAllPosters() async {
    try {
      int removed = 0;
      await for (final file in store.fileSystem.directory(key).list(recursive: true)) {
        if (file is dynamic && (file as dynamic).statSync != null) {
          try {
            await (file as dynamic).delete();
            removed++;
          } catch (_) {
            // best-effort
          }
        }
      }
      return removed;
    } catch (e) {
      debugPrint('PosterCacheManager.clearAllPosters failed: $e');
      return 0;
    }
  }
}
