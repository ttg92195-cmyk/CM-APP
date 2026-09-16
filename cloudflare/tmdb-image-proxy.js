// =============================================================================
// TMDB Image Proxy — Cloudflare Worker (Phase 4 hotfix, v2 2026-09-16)
// =============================================================================
// v2 FIX (why v1 showed "error code: 1101"):
//   v1 called the Cache API (caches.default) OUTSIDE its try/catch. On
//   workers.dev deployments the Cache API can throw (unavailable/limited
//   there), producing an unhandled exception → Cloudflare's generic
//   "error code: 1101" page instead of the image.
//   v2 changes:
//     1. The ENTIRE handler is wrapped in try/catch. Nothing can 1101.
//     2. The edge cache is a best-effort bonus — every cache call is
//        individually guarded; if the Cache API throws, the image is simply
//        proxied without edge caching.
//     3. Any unexpected error is returned AS TEXT in the response body, so
//        the reason is readable directly in the browser.
//     4. Added /__health for a quick "is the worker alive" check.
//
// Serves TMDB poster/backdrop images through Cloudflare's edge network so
// they are reachable from Myanmar, where image.tmdb.org is blocked or
// unresolvable on most ISPs (MPT / Atom / Ooredoo / Mytel).
//
// ── SETUP (one-time, ~5 minutes, free) ─────────────────────────────────────
//   1. Create a free Cloudflare account: https://dash.cloudflare.com/sign-up
//   2. Dashboard → Compute (Workers) → Create Worker → name it e.g.
//      "tmdb-images" → Deploy (default hello-world code first).
//   3. "Edit code" → select ALL the default code → delete → paste ALL of
//      this file → "Deploy".
//   4. Copy your worker URL, e.g.:
//        https://tmdb-images.<your-subdomain>.workers.dev
//   5. Test in a browser (exact poster that fails directly in Myanmar):
//        https://tmdb-images.<your-subdomain>.workers.dev/t/p/w500/yihdXomYb5kTeSivtFndMy5iDmf.jpg
//      Poster appears → the worker works.
//      Quick liveness check: https://...workers.dev/__health → "tmdb-image-proxy v2 OK"
//   6. Firebase Console → Firestore → collection "app_settings" → create
//      document "tmdb_image_proxy" with fields:
//        enabled : boolean = true
//        baseUrl : string  = https://tmdb-images.<your-subdomain>.workers.dev
//   7. Rebuild the app once. Posters now load through the proxy. After that,
//      proxy changes only require editing the Firestore doc (no rebuild).
//
// ── SECURITY ────────────────────────────────────────────────────────────────
//   - Only GET /t/p/* image paths are proxied → cannot be used as a generic
//     open proxy.
//   - Read-only: this worker never writes anything upstream.
//   - Edge cache is best-effort (7 days where available); clients also cache
//     7 days via the Cache-Control response header.
// =============================================================================

const TMDB_ORIGIN = 'https://image.tmdb.org';

export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);

      // Liveness check — proves the Worker itself runs (no upstream call).
      if (url.pathname === '/__health') {
        return new Response('tmdb-image-proxy v2 OK', {
          status: 200,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      // Only proxy TMDB image paths: /t/p/<size>/<file>.jpg
      if (request.method !== 'GET' || !url.pathname.startsWith('/t/p/')) {
        return new Response('CM Movies TMDB image proxy — usage: /t/p/<size>/<file>', {
          status: 404,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      // ---- Optional edge cache (best-effort, never fatal) -----------------
      // Query strings (the app's ?retry=N cache-busters) are NOT part of the
      // cache key — the image identity is the path alone.
      const cacheKey = new Request(url.origin + url.pathname, { method: 'GET' });
      let cached = null;
      try {
        cached = await caches.default.match(cacheKey);
      } catch (e) {
        cached = null; // Cache API unavailable here — fine, just proxy.
      }
      if (cached) {
        return cached;
      }

      // ---- Fetch from TMDB (path only; queries are meaningless upstream) --
      const upstream = await fetch(TMDB_ORIGIN + url.pathname, {
        method: 'GET',
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
          Accept: 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
        redirect: 'follow',
      });

      if (!upstream.ok) {
        return new Response('Upstream error ' + upstream.status, {
          status: upstream.status === 404 ? 404 : 502,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      // ---- Build the response (fresh headers; long client-side cache) -----
      const headers = new Headers();
      headers.set('Content-Type', upstream.headers.get('Content-Type') || 'image/jpeg');
      headers.set('Cache-Control', 'public, max-age=604800'); // 7 days
      headers.set('Access-Control-Allow-Origin', '*');
      headers.set('X-Proxy', 'tmdb-image-proxy/2');
      const response = new Response(upstream.body, { status: 200, headers });

      // ---- Store in the edge cache (best-effort, never fatal) -------------
      try {
        const putPromise = caches.default.put(cacheKey, response.clone());
        if (ctx && ctx.waitUntil) {
          ctx.waitUntil(putPromise);
        } else {
          putPromise.catch(() => {});
        }
      } catch (e) {
        // Cache unavailable — the image still goes through to the client.
      }

      return response;
    } catch (e) {
      // Any unexpected failure → return the REASON as text so it is visible
      // directly in the browser (never a generic "error code: 1101" again).
      let msg = 'unknown error';
      try {
        msg = (e && (e.stack || e.message)) ? String(e.stack || e.message) : String(e);
      } catch (e2) {
        msg = String(e);
      }
      return new Response('tmdb-image-proxy v2 error:\n' + msg, {
        status: 500,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }
  },
};
