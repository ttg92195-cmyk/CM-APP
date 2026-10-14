// =============================================================================
// Phase 4 hotfix (2026-08-28) — TMDB Image Proxy
// =============================================================================
// WHY THIS EXISTS:
//   Myanmar ISPs (MPT / Atom / Ooredoo / Mytel) frequently block or fail to
//   resolve image.tmdb.org — the CDN that serves every TMDB poster/backdrop.
//   Movie posters stored in Firestore (e.g. https://image.tmdb.org/t/p/w500/
//   yihdXomYb5kTeSivtFndMy5iDmf.jpg) return 200 from outside Myanmar but
//   simply never load on Myanmar networks, so users see broken poster
//   placeholders everywhere (movie cards, details, watchlist, reels).
//
// THE FIX:
//   A Cloudflare Worker (code: cloudflare/tmdb-image-proxy.js in this repo)
//   acts as a caching reverse-proxy for image.tmdb.org. Cloudflare's edge
//   network is reachable from Myanmar, so posters load through the proxy.
//
//   This class rewrites TMDB URLs → proxy URLs AT DISPLAY TIME only:
//     https://image.tmdb.org/t/p/w500/abc.jpg
//       → https://<worker>.workers.dev/t/p/w500/abc.jpg
//
//   Firestore keeps storing the CANONICAL image.tmdb.org URLs (we never
//   write proxied URLs to the database) — so the proxy can be swapped,
//   disabled, or pointed at a different host later by editing one config
//   document, with zero data migration.
//
// CONFIGURATION (remote — no app rebuild needed after this update):
//   Firestore doc: app_settings/tmdb_image_proxy
//     enabled : bool   → true to route TMDB images through the proxy
//     baseUrl : string → e.g. "https://tmdb-images.yourname.workers.dev"
//   (Rules already allow: authenticated read / admin write. The doc can be
//   created directly in Firebase Console, which bypasses rules anyway.)
//   While the doc is missing or enabled:false, resolve() is a pure
//   passthrough — zero behavior change from before this feature.
//
// LOADING:
//   - Registered listener in main.dart: FirebaseAuth.authStateChanges fires
//     the load as soon as a user is signed in (app_settings reads require
//     authentication).
//   - The splash screen also awaits the load (short-circuits if loaded).
//   - Any failure (offline / pre-auth / doc missing) is tolerated.
//
// PERSISTENCE (2026-10-14 — "always ON" fix):
//   The old build kept the proxy config in MEMORY ONLY, so every failed
//   Firestore read (slow Myanmar line, cold-start 2.5s timeout, pre-auth
//   denial) silently dropped the app back to direct mode — all posters
//   broke and the admin had to tap the Settings tile to retry
//   ("Load failed — tap to retry"). Now the last-known-good enabled
//   baseUrl is cached in SharedPreferences (key: tmdb_image_proxy_base_url):
//     - Every load attempt restores the cache FIRST, before touching
//       Firestore → the proxy is ON from the very first frame after the
//       first-ever successful read, on every subsequent app start.
//     - A FAILED Firestore read now KEEPS the cached state (only sets
//       lastError) — network hiccups can no longer turn the proxy off.
//     - Only a SUCCESSFUL read that says disabled / doc-missing clears the
//       cache (admin intent), so the Firestore doc remains the single
//       source of truth for disabling or moving the proxy.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TmdbImageProxy {
  TmdbImageProxy._();

  static const String _httpsPrefix = 'https://image.tmdb.org';
  static const String _httpPrefix = 'http://image.tmdb.org';

  /// SharedPreferences key holding the last-known-good enabled baseUrl
  /// (the "always ON" cache — survives Firestore hiccups and app restarts).
  static const String _prefsKey = 'tmdb_image_proxy_base_url';

  /// Proxy base URL (no trailing slash) once enabled, else null.
  static String? _baseUrl;

  /// True once a config read has SUCCEEDED (enabled or not). Failed reads
  /// leave this false so a later trigger (auth state change, next splash)
  /// can retry.
  static bool _loaded = false;

  /// Guards the one-time-per-session SharedPreferences restore.
  static bool _cacheRestored = false;

  /// Last load failure reason (TimeoutException / permission-denied / ...).
  /// Null when the last attempt succeeded. Exposed for the Settings
  /// diagnostics tile — makes proxy problems visible without adb logs.
  static String? lastError;

  /// True when the ACTIVE config came from the local SharedPreferences
  /// cache because the most recent Firestore read FAILED (offline /
  /// timeout / pre-auth). Exposed so the Settings diagnostics tile can
  /// show "ON (cached)" instead of silently pretending the live read
  /// succeeded. Reset to false by every successful read.
  static bool lastReadFromCache = false;

  /// Whether TMDB images are currently routed through the proxy.
  static bool get isEnabled => _baseUrl != null;

  /// The active proxy base URL (for Settings/diagnostics). Null if disabled.
  static String? get baseUrl => _baseUrl;

  /// Loads proxy config from Firestore `app_settings/tmdb_image_proxy`.
  ///
  /// Safe to call repeatedly — short-circuits after the first successful
  /// read. A LOCAL CACHE of the last-known-good enabled baseUrl is restored
  /// before every attempt, and a FAILED read keeps that cache active
  /// ("always ON"): only a successful read that says disabled / doc-missing
  /// clears it. Once the proxy has been enabled once, transient Firestore
  /// /network failures can no longer drop the app into direct mode (which
  /// used to break every poster on Myanmar lines until the admin tapped
  /// the Settings tile to retry).
  ///
  /// [force] re-reads even after a successful earlier load (used by the
  /// Settings diagnostics tile right after the admin edits the Firestore
  /// doc — no app restart needed to pick up a config change). A failed
  /// forced re-check keeps serving the previously active config.
  /// [timeout] bounds the read (auto-load keeps the snappy 2.5s splash
  /// budget; manual reloads from Settings use a longer 8s budget).
  static Future<void> loadFromFirestore({
    bool force = false,
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    // Restore the cached last-known-good config FIRST (cheap local read,
    // no auth needed) so the proxy is already active even if/while the
    // Firestore read fails, times out, or is denied pre-auth.
    await _restoreCachedBaseUrl();
    if (_loaded && !force) return;
    if (force) {
      // Re-check with the current config still active — a failed re-check
      // must NOT flip the proxy off (that regression is exactly what the
      // admin kept having to fix by tapping this tile again and again).
      _loaded = false;
    }
    lastError = null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('tmdb_image_proxy')
          .get()
          .timeout(timeout);
      // Read succeeded — never retry within this app session.
      _loaded = true;
      final data = doc.data();
      if (data == null) {
        // Doc removed — admin intent: feature no longer configured.
        _baseUrl = null;
        lastReadFromCache = false;
        await _forgetCachedBaseUrl();
        debugPrint('TmdbImageProxy: no config doc (direct mode)');
        return;
      }
      final enabled = data['enabled'] == true;
      final raw = data['baseUrl'];
      if (enabled && raw is String && raw.trim().isNotEmpty) {
        var base = raw.trim();
        while (base.endsWith('/')) {
          base = base.substring(0, base.length - 1);
        }
        _baseUrl = base;
        lastReadFromCache = false;
        await _rememberCachedBaseUrl(base);
        debugPrint('TmdbImageProxy: ENABLED via $base');
      } else {
        // Explicit enabled:false — admin intent: drop proxy AND cache.
        _baseUrl = null;
        lastReadFromCache = false;
        await _forgetCachedBaseUrl();
        debugPrint('TmdbImageProxy: config present but disabled');
      }
    } catch (e) {
      // Offline / pre-auth / rules rejection / timeout — KEEP the cached
      // (or previously loaded) config active. The app only falls back to
      // direct mode if there has never been a successful read anywhere.
      lastError = e.toString();
      if (_baseUrl != null) lastReadFromCache = true;
      debugPrint(
        'TmdbImageProxy: load failed — keeping '
        '${_baseUrl != null ? "proxy ($_baseUrl)" : "direct"} mode: $e',
      );
    }
  }

  /// Restores the last-known-good enabled baseUrl from SharedPreferences
  /// (written by every successful enabled read). Never overrides a value
  /// that is already active. One-shot per app session — subsequent reads
  /// come from Firestore success paths or stay from memory.
  static Future<void> _restoreCachedBaseUrl() async {
    if (_cacheRestored) return;
    _cacheRestored = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.trim().isNotEmpty && _baseUrl == null) {
        _baseUrl = saved.trim();
        lastReadFromCache = true;
        debugPrint('TmdbImageProxy: restored cached proxy ($_baseUrl)');
      }
    } catch (e) {
      debugPrint('TmdbImageProxy: cache restore failed: $e');
    }
  }

  /// Persists the last-known-good enabled baseUrl (the always-ON cache).
  static Future<void> _rememberCachedBaseUrl(String base) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, base);
    } catch (e) {
      debugPrint('TmdbImageProxy: cache save failed: $e');
    }
  }

  /// Clears the cached baseUrl — only called after a SUCCESSFUL read that
  /// says the proxy is disabled or the config doc was removed (admin intent).
  static Future<void> _forgetCachedBaseUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('TmdbImageProxy: cache clear failed: $e');
    }
  }

  /// Rewrites an image URL through the proxy when enabled.
  ///
  /// - null / empty → '' (never null)
  /// - non-TMDB URLs → passed through untouched (reels posters, banners,
  ///   any custom-hosted image are unaffected)
  /// - TMDB URLs → scheme+host replaced with the proxy base, path and
  ///   query (e.g. ?retry=N cache-busters from movie_card) preserved.
  static String resolve(String? url) {
    if (url == null || url.isEmpty) return '';
    if (_baseUrl == null) return url;
    if (url.startsWith(_httpsPrefix)) {
      return '$_baseUrl${url.substring(_httpsPrefix.length)}';
    }
    if (url.startsWith(_httpPrefix)) {
      return '$_baseUrl${url.substring(_httpPrefix.length)}';
    }
    return url;
  }
}
