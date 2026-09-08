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
//   - Any failure (offline / pre-auth / doc missing) is silently tolerated
//     and leaves the app in direct mode (previous behavior).
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TmdbImageProxy {
  TmdbImageProxy._();

  static const String _httpsPrefix = 'https://image.tmdb.org';
  static const String _httpPrefix = 'http://image.tmdb.org';

  /// Proxy base URL (no trailing slash) once enabled, else null.
  static String? _baseUrl;

  /// True once a config read has SUCCEEDED (enabled or not). Failed reads
  /// leave this false so a later trigger (auth state change, next splash)
  /// can retry.
  static bool _loaded = false;

  /// Whether TMDB images are currently routed through the proxy.
  static bool get isEnabled => _baseUrl != null;

  /// The active proxy base URL (for Settings/diagnostics). Null if disabled.
  static String? get baseUrl => _baseUrl;

  /// Loads proxy config from Firestore `app_settings/tmdb_image_proxy`.
  ///
  /// Safe to call repeatedly — short-circuits after the first successful
  /// read. Tolerates every failure mode by staying in direct mode.
  static Future<void> loadFromFirestore() async {
    if (_loaded) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('tmdb_image_proxy')
          .get()
          .timeout(const Duration(milliseconds: 2500));
      // Read succeeded — never retry within this app session.
      _loaded = true;
      final data = doc.data();
      if (data == null) {
        // Doc not created yet — feature intentionally not configured.
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
        debugPrint('TmdbImageProxy: ENABLED via $base');
      } else {
        _baseUrl = null;
        debugPrint('TmdbImageProxy: config present but disabled');
      }
    } catch (e) {
      // Offline / pre-auth / rules rejection — stay in direct mode and
      // allow a later trigger to retry (do NOT set _loaded).
      debugPrint('TmdbImageProxy: load failed (direct mode): $e');
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
