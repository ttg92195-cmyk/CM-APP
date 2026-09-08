// =============================================================================
// TMDB Image Proxy — Cloudflare Worker (Phase 4 hotfix, 2026-08-28)
// =============================================================================
// Serves TMDB poster/backdrop images through Cloudflare's edge network so
// they are reachable from Myanmar, where image.tmdb.org is blocked or
// unresolvable on most ISPs (MPT / Atom / Ooredoo / Mytel).
//
// ── SETUP (one-time, ~5 minutes, free) ─────────────────────────────────────
//   1. Create a free Cloudflare account: https://dash.cloudflare.com/sign-up
//   2. Dashboard → Compute (Workers) → Create Worker → give it a name like
//      "tmdb-images" → Deploy (with the default hello-world code first).
//   3. Click "Edit code" → delete the default code → paste ALL of this file
//      → click "Deploy" again.
//   4. Copy your worker URL, e.g.:
//        https://tmdb-images.<your-subdomain>.workers.dev
//   5. Test it in a browser (this exact poster failed for Bro directly):
//        https://tmdb-images.<your-subdomain>.workers.dev/t/p/w500/yihdXomYb5kTeSivtFndMy5iDmf.jpg
//      If the poster appears → the worker works.
//   6. Firebase Console → Firestore → collection "app_settings" → create
//      document "tmdb_image_proxy" with fields:
//        enabled : boolean = true
//        baseUrl : string  = https://tmdb-images.<your-subdomain>.workers.dev
//   7. Restart the app. Posters now load through the proxy. (The app must be
//      rebuilt ONCE with the TmdbImageProxy code; after that, proxy changes
//      only require editing the Firestore doc.)
//
// ── SECURITY ────────────────────────────────────────────────────────────────
//   - Only /t/p/* image paths are proxied (TMDB images live under /t/p/).
//     Everything else → 404, so the worker cannot be used as a generic
//     open proxy.
//   - Responses are cached at the edge for 7 days (Cache API) — repeat
//     loads are fast and do not re-hit TMDB.
//   - Read-only: this worker never writes anything upstream.
// =============================================================================

const TMDB_ORIGIN = 'https://image.tmdb.org';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Only proxy TMDB image paths: /t/p/<size>/<file>.jpg
    if (request.method !== 'GET' || !url.pathname.startsWith('/t/p/')) {
      return new Response('CM Movies TMDB image proxy — usage: /t/p/<size>/<file>', {
        status: 404,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }

    // Serve from the edge cache when possible (ignore query strings such as
    // the app's ?retry=N cache-busters — the image identity is the path).
    const cache = caches.default;
    let response = await cache.match(request, { ignoreSearch: true });

    if (response) {
      return response;
    }

    try {
      // Fetch only the path from TMDB (query params are meaningless there
      // and forwarding them would fragment the upstream cache).
      const upstream = await fetch(TMDB_ORIGIN + url.pathname, {
        method: 'GET',
        headers: { 'User-Agent': 'cm-movies-proxy/1.0' },
        redirect: 'follow',
      });

      if (!upstream.ok) {
        return new Response('Upstream error', {
          status: upstream.status === 404 ? 404 : 502,
          headers: { 'Content-Type': 'text/plain; charset=utf-8' },
        });
      }

      // Copy the image through, with a long cache lifetime.
      response = new Response(upstream.body, upstream);
      response.headers.set('Cache-Control', 'public, max-age=604800'); // 7 days
      response.headers.set('Access-Control-Allow-Origin', '*');
      response.headers.set('X-Proxy', 'tmdb-image-proxy');

      // Store in the edge cache for future requests (clone BEFORE returning).
      ctx.waitUntil(cache.put(request, response.clone()));
      return response;
    } catch (e) {
      return new Response('Proxy fetch failed', {
        status: 502,
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
      });
    }
  },
};
