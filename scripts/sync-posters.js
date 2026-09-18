#!/usr/bin/env node
// =============================================================================
// TMDB Poster Mirror Sync — Phase 4 hotfix (2026-09-16)
// =============================================================================
// WHY THIS EXISTS:
//   Cloud Functions (the tmdbImageProxy Google-infra proxy) requires the
//   Blaze (pay-as-you-go) plan, which needs an international credit card —
//   hard to get in Myanmar. Firebase HOSTING, however, is FREE on the Spark
//   plan, and its serving domain (<project>.web.app) is Google
//   infrastructure — the same network path the app already proves reachable
//   from Myanmar (Firestore data loads fine while image.tmdb.org hangs).
//
// WHAT THIS DOES:
//   1. Connects to Firestore with the project service account
//   2. Walks every content collection (movies, reels, genres, tags,
//      collections, notifications, app_settings, config … — everything
//      except user-private collections) incl. 1 level of subcollections
//   3. Extracts every TMDB image path (/t/p/<size>/<file>.jpg) from every
//      string field, recursively — posters, backdrops, cast profile photos,
//      episode stills — all of them are stored as full image.tmdb.org URLs
//      in the movie docs
//   4. Downloads each referenced image ONCE from image.tmdb.org (GitHub
//      runners are outside Myanmar, so TMDB is reachable) into hosting/<path>
//      — incremental: already-mirrored files are skipped
//      — most-visible sizes first (w500 posters before backdrops/original)
//   5. Rewrites hosting/index.html with sync stats + sample posters
//   6. Auto-points the APP at the mirror: sets
//      app_settings/tmdb_image_proxy = { enabled: true,
//      baseUrl: https://<project>.web.app } (merge — no manual Firestore
//      editing needed; the app picks it up on next launch / proxy-row tap)
//
// FIX HISTORY:
//   2026-09-18 — runPool was called WITHOUT its concurrency argument:
//     Math.min(undefined, N) = NaN → Array.from({length: NaN}) = ZERO worker
//     runners → the pool resolved instantly, downloading NOTHING while
//     reporting downloaded=0 failed=0. Both nightly runs "succeeded" with
//     an empty mirror (deploy log: "found 1 files"). Now: the call passes
//     the concurrency, runPool hardens invalid concurrency to >= 1 worker,
//     and a post-pool invariant (downloaded + failed === missing.length)
//     aborts loudly BEFORE deploy if a single item ever goes missing again.
//
//   The GitHub workflow (.github/workflows/sync-posters.yml) then commits
//   the new files and runs `firebase deploy --only hosting`.
//
// SERVED URLS (what the app requests after the Firestore config change):
//   https://cm-movies-dabab.web.app/t/p/w500/<file>.jpg
//   — identical path shape to image.tmdb.org, so the app-side rewrite in
//     TmdbImageProxy.resolve() works with ZERO app changes:
//     Firestore app_settings/tmdb_image_proxy.baseUrl
//       → https://cm-movies-dabab.web.app
//
// USAGE:
//   GitHub Actions (recommended — see the workflow file).
//   Local:  FIREBASE_SERVICE_ACCOUNT='<json>' node scripts/sync-posters.js
//           or GOOGLE_APPLICATION_CREDENTIALS=/path/sa.json node scripts/…
//   Self-test (no Firebase needed):  node scripts/sync-posters.js --selftest
//
// EXIT CODES:  0 = ok (or ok-with-download-failures — partial mirrors are
//              better than nothing),  1 = fatal (bad credentials / no access)
// =============================================================================

'use strict';

const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Configuration (env-overridable)
// ---------------------------------------------------------------------------
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'cm-movies-dabab';
const HOSTING_DIR = process.env.HOSTING_DIR
  ? path.resolve(process.env.HOSTING_DIR)
  : path.join(__dirname, '..', 'hosting');
const TMDB_ORIGIN = 'https://image.tmdb.org';

// User-private collections never contain TMDB paths — skip them (saves quota
// and keeps user data out of the runner logs).
const SKIP_COLLECTIONS = new Set([
  'users',
  'bookmarks',
  'watchlist',
  'devices',
  'device_sessions',
]);

// Subcollections are walked this many levels deep below each top-level
// collection (movie docs embed seasons/episodes as fields, but a level of
// walking future-proofs against subcollection-based layouts).
const SUBCOLLECTION_DEPTH = 1;

// 10 parallel downloads — TMDB's image CDN handles this comfortably and it
// keeps a ~3700-image first sync inside a few minutes.
const DOWNLOAD_CONCURRENCY = 10;
const FETCH_TIMEOUT_MS = 20000;
const MAX_SAMPLES_IN_INDEX = 12;

// Mirror the sizes the app actually renders on its main screens FIRST, so an
// interrupted/capped run still leaves movie-card posters live. 'original'
// (big backdrops) goes last.
const SIZE_PRIORITY = ['w500', 'w342', 'w185', 'w780', 'w300', 'w154', 'w92'];
function sizeRank(p) {
  const m = /\/t\/p\/([A-Za-z0-9_-]+)\//.exec(p);
  const size = m ? m[1] : '';
  const i = SIZE_PRIORITY.indexOf(size);
  if (i >= 0) return i;
  return size === 'original' ? 98 : 50;
}

// Matches /t/p/<size>/<file>.<ext> with an optional https://image.tmdb.org
// prefix. Stops at the extension, so query strings (?retry=N) are ignored.
const TMDB_PATH_RE =
  /(?:https?:\/\/image\.tmdb\.org)?(\/t\/p\/[A-Za-z0-9_-]+\/[A-Za-z0-9_-]+\.(?:jpg|jpeg|png|webp|svg|gif))/gi;

// ---------------------------------------------------------------------------
// Extraction (pure functions — unit-tested via --selftest)
// ---------------------------------------------------------------------------
function collectTmdbPaths(value, out) {
  if (value == null) return;
  if (typeof value === 'string') {
    let m;
    TMDB_PATH_RE.lastIndex = 0;
    while ((m = TMDB_PATH_RE.exec(value)) !== null) {
      out.add(m[1]);
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectTmdbPaths(item, out);
    return;
  }
  if (typeof value === 'object') {
    for (const key of Object.keys(value)) collectTmdbPaths(value[key], out);
  }
}

// ---------------------------------------------------------------------------
// Self-test
// ---------------------------------------------------------------------------
async function selfTest() {
  const cases = [
    {
      name: 'plain full https URL',
      input: 'https://image.tmdb.org/t/p/w500/yihdXomYb5kTeSivtFndMy5iDmf.jpg',
      expect: ['/t/p/w500/yihdXomYb5kTeSivtFndMy5iDmf.jpg'],
    },
    {
      name: 'http prefix + query string',
      input: 'http://image.tmdb.org/t/p/w780/abcXYZ123.jpg?retry=3',
      expect: ['/t/p/w780/abcXYZ123.jpg'],
    },
    {
      name: 'bare path',
      input: '/t/p/original/zzz.png',
      expect: ['/t/p/original/zzz.png'],
    },
    {
      name: 'nested object + array (cast list shape)',
      input: {
        poster: 'https://image.tmdb.org/t/p/w500/a.jpg',
        casts: [
          { name: 'A', profile: 'https://image.tmdb.org/t/p/w185/p1.webp' },
          { name: 'B', profile: '/t/p/w185/p2.webp' },
        ],
        seasons: [{ episodes: [{ still: '/t/p/w300/e1.jpg' }] }],
      },
      expect: [
        '/t/p/w500/a.jpg',
        '/t/p/w185/p1.webp',
        '/t/p/w185/p2.webp',
        '/t/p/w300/e1.jpg',
      ],
    },
    {
      name: 'non-TMDB image untouched',
      input: 'https://i.ytimg.com/vi/abc/hqdefault.jpg',
      expect: [],
    },
    {
      name: 'dedupes same path via URL and bare path',
      input: ['https://image.tmdb.org/t/p/w500/a.jpg', '/t/p/w500/a.jpg'],
      expect: ['/t/p/w500/a.jpg'],
    },
  ];

  let failed = 0;
  for (const c of cases) {
    const out = new Set();
    collectTmdbPaths(c.input, out);
    const got = Array.from(out).sort();
    const want = c.expect.slice().sort();
    const ok = JSON.stringify(got) === JSON.stringify(want);
    console.log(`${ok ? 'PASS' : 'FAIL'}  ${c.name}`);
    if (!ok) {
      failed++;
      console.log(`      want: ${JSON.stringify(want)}`);
      console.log(`      got : ${JSON.stringify(got)}`);
    }
  }

  // --- runPool regression tests (the 2026-09-18 bug) ---
  // A pool MUST process every item even when concurrency is omitted.
  {
    const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    let processed = 0;
    await runPool(items, async () => {
      await new Promise((r) => setTimeout(r, 1));
      processed++;
    });
    const ok = processed === items.length;
    console.log(
      `${ok ? 'PASS' : 'FAIL'}  runPool processes all items without concurrency arg (regression: 0 processed)`
    );
    if (!ok) {
      failed++;
      console.log(`      want: ${items.length} processed`);
      console.log(`      got : ${processed} processed`);
    }
  }
  // Concurrency must be honored (never more than N workers alive).
  {
    const items = Array.from({ length: 20 }, (_, i) => i);
    let processed = 0;
    let live = 0;
    let maxLive = 0;
    await runPool(
      items,
      async () => {
        live++;
        maxLive = Math.max(maxLive, live);
        await new Promise((r) => setTimeout(r, 2));
        processed++;
        live--;
      },
      4
    );
    const ok = processed === 20 && maxLive > 0 && maxLive <= 4;
    console.log(
      `${ok ? 'PASS' : 'FAIL'}  runPool honors concurrency (max live ${maxLive} <= 4)`
    );
    if (!ok) failed++;
  }

  return failed === 0;
}

// ---------------------------------------------------------------------------
// Firebase walk
// ---------------------------------------------------------------------------
function initAdmin(admin) {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (inline && inline.trim().startsWith('{')) {
    admin.initializeApp({ credential: admin.credential.cert(JSON.parse(inline)) });
    return 'inline FIREBASE_SERVICE_ACCOUNT';
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
    return 'GOOGLE_APPLICATION_CREDENTIALS file';
  }
  throw new Error(
    'No credentials found. Set FIREBASE_SERVICE_ACCOUNT (inline JSON) or ' +
      'GOOGLE_APPLICATION_CREDENTIALS (path to a service account key file).'
  );
}

async function walkCollection(collRef, depth, paths, stats) {
  const snap = await collRef.get();
  for (const doc of snap.docs) {
    collectTmdbPaths(doc.data(), paths);
    stats.docsRead++;
    if (depth > 0) {
      try {
        const subs = await doc.ref.listCollections();
        for (const sub of subs) {
          await walkCollection(sub, depth - 1, paths, stats);
        }
      } catch (_e) {
        // Best effort — some security configs deny listCollections on docs.
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Download pool
// ---------------------------------------------------------------------------
async function fetchImage(tmdbPath) {
  let lastErr = null;
  for (let attempt = 1; attempt <= 2; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
    try {
      const res = await fetch(TMDB_ORIGIN + tmdbPath, {
        headers: {
          'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 CM-Movies-Poster-Sync/1.0',
          Accept: 'image/*,*/*;q=0.8',
        },
        signal: controller.signal,
      });
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const buf = Buffer.from(await res.arrayBuffer());
      if (buf.length === 0) throw new Error('empty body');
      return buf;
    } catch (e) {
      lastErr = e;
    } finally {
      clearTimeout(timer);
    }
  }
  throw lastErr;
}

async function runPool(items, worker, concurrency) {
  const queue = items.slice();
  // HARDENING (2026-09-18): a missing/invalid concurrency used to yield
  // Math.min(undefined, N) = NaN → Array.from({length: NaN}) = [] → ZERO
  // runners → instant no-op. Force at least one worker so this class of
  // bug can never silently skip the whole workload again.
  const workerCount = Math.max(
    1,
    Math.min(Number(concurrency) || 1, Math.max(items.length, 1))
  );
  const runners = Array.from({ length: workerCount }, async () => {
    while (queue.length) {
      const item = queue.shift();
      await worker(item);
    }
  });
  await Promise.all(runners);
}

// ---------------------------------------------------------------------------
// Status page (hosting/index.html)
// ---------------------------------------------------------------------------
function writeIndexHtml(paths, stats, appConfig, mirrorBaseUrl) {
  if (paths.size === 0) return false;
  const samples = Array.from(paths).slice(0, MAX_SAMPLES_IN_INDEX);
  const sampleImgs = samples
    .map((p) => `      <img src="${p}" alt="poster" loading="lazy">`)
    .join('\n');
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CM Movies — Poster Mirror</title>
<style>
  body { font-family: system-ui, sans-serif; background: #101418; color: #e6e9ee;
         margin: 0; padding: 32px 16px; text-align: center; }
  h1 { font-size: 20px; margin: 0 0 6px; }
  p  { color: #9aa4b2; margin: 4px 0 20px; font-size: 14px; }
  .grid { display: flex; flex-wrap: wrap; gap: 10px; justify-content: center; }
  img  { width: 120px; border-radius: 8px; background: #1c232b; min-height: 160px; }
</style>
</head>
<body>
  <h1>CM Movies — TMDB Poster Mirror</h1>
  <p>${paths.size} unique images mirrored &middot; ${stats.downloaded} new this run &middot; ${stats.failed} failed</p>
  <p>last sync: ${stats.finishedAt} UTC</p>
  <p>app poster proxy: ${
    appConfig
      ? mirrorBaseUrl + ' (enabled — set automatically by sync)'
      : 'NOT SET — set app_settings/tmdb_image_proxy.baseUrl = ' + mirrorBaseUrl
  }</p>
  <div class="grid">
${sampleImgs}
  </div>
</body>
</html>
`;
  fs.writeFileSync(path.join(HOSTING_DIR, 'index.html'), html);
  return true;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  console.log('=== CM Movies poster mirror sync ===');
  console.log('project :', PROJECT_ID);
  console.log('hosting :', HOSTING_DIR);

  // Credential bootstrap
  let admin;
  try {
    admin = require('firebase-admin');
  } catch (e) {
    console.error(
      'firebase-admin not found. Install it next to this script:\n' +
        '  npm install --prefix <deps-dir> firebase-admin@12\n' +
        '  NODE_PATH=<deps-dir>/node_modules node scripts/sync-posters.js'
    );
    process.exit(1);
  }
  let credSource;
  try {
    credSource = initAdmin(admin);
  } catch (e) {
    console.error('FATAL:', e.message);
    process.exit(1);
  }
  console.log('creds   :', credSource);

  const db = admin.firestore();

  // 1. Discover collections
  let topCollections;
  try {
    topCollections = await db.listCollections();
  } catch (e) {
    console.error('FATAL: cannot list collections:', e.message);
    console.error('(Check that the service account has Firestore access.)');
    process.exit(1);
  }
  const names = topCollections
    .map((c) => c.id)
    .filter((id) => !SKIP_COLLECTIONS.has(id));
  console.log('collections to scan:', names.join(', ') || '(none)');

  // 2. Extract TMDB paths
  const paths = new Set();
  const stats = { docsRead: 0, downloaded: 0, skipped: 0, failed: 0, finishedAt: '' };
  for (const coll of topCollections) {
    if (SKIP_COLLECTIONS.has(coll.id)) continue;
    await walkCollection(coll, SUBCOLLECTION_DEPTH, paths, stats);
  }
  console.log(`scanned ${stats.docsRead} docs → ${paths.size} unique TMDB image paths`);
  if (paths.size === 0) {
    console.log(
      'WARN: no TMDB paths found — nothing to mirror. (If the app has movies,' +
        ' check the service account can read the movies collection.)'
    );
    process.exit(0);
  }

  // 3. Download missing ones (incremental)
  fs.mkdirSync(HOSTING_DIR, { recursive: true });
  const missing = [];
  for (const p of paths) {
    const file = path.join(HOSTING_DIR, p);
    try {
      const st = fs.statSync(file);
      if (st.size > 0) {
        stats.skipped++;
        continue;
      }
    } catch (_e) {
      /* not present */
    }
    missing.push(p);
  }
  console.log(`already mirrored: ${stats.skipped}  to download: ${missing.length}`);

  // Poster-critical sizes first (see SIZE_PRIORITY) — an interrupted run
  // still leaves the most visible images mirrored and deployed.
  missing.sort((a, b) => sizeRank(a) - sizeRank(b));

  const failures = [];
  await runPool(
    missing,
    async (p) => {
      const file = path.join(HOSTING_DIR, p);
      let tmp = null;
      try {
        const buf = await fetchImage(p);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        tmp = file + '.tmp-' + process.pid;
        fs.writeFileSync(tmp, buf);
        fs.renameSync(tmp, file);
        tmp = null;
        stats.downloaded++;
        process.stdout.write('.');
      } catch (e) {
        if (tmp) {
          try { fs.unlinkSync(tmp); } catch (_e) { /* best effort */ }
        }
        stats.failed++;
        failures.push(`${p} → ${e.message}`);
        process.stdout.write('x');
      }
    },
    DOWNLOAD_CONCURRENCY // ← was missing entirely: the 2026-09-18 bug
  );
  if (missing.length) console.log('');

  // INVARIANT: every queued item must have been accounted for. If this ever
  // trips, abort BEFORE the commit/deploy steps so the failure is visible
  // instead of silently "succeeding" with an incomplete mirror.
  const processed = stats.downloaded + stats.failed;
  if (processed !== missing.length) {
    console.error('');
    console.error(
      `!!! POOL SANITY FAILURE: processed ${processed} of ${missing.length} ` +
        `queued items — a download pool bug lost work. Aborting before deploy.`
    );
    process.exit(1);
  }

  if (failures.length) {
    console.log('failed downloads (upstream 404s are normal for removed media):');
    for (const f of failures.slice(0, 20)) console.log('  ' + f);
    if (failures.length > 20) console.log(`  … and ${failures.length - 20} more`);
  }

  // 4. Status page
  stats.finishedAt = new Date().toISOString().replace('T', ' ').slice(0, 16);

  // 5. Point the APP at this mirror — remote config, zero app changes.
  //    merge: true keeps any other fields an admin may have set.
  const mirrorBaseUrl = `https://${PROJECT_ID}.web.app`;
  let appConfig = false;
  try {
    await db.doc('app_settings/tmdb_image_proxy').set(
      {
        enabled: true,
        baseUrl: mirrorBaseUrl,
        posterMirror: {
          files: paths.size,
          newThisRun: stats.downloaded,
          syncedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        updatedBy: 'sync-posters-bot',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    appConfig = true;
    console.log(
      `APP CONFIG SET: app_settings/tmdb_image_proxy → enabled:true, baseUrl:${mirrorBaseUrl}`
    );
  } catch (e) {
    console.error(
      'WARN: could not set app_settings/tmdb_image_proxy — set it manually in Firestore:',
      e.message
    );
  }

  writeIndexHtml(paths, stats, appConfig, mirrorBaseUrl);

  // 6. Summary (also parsed by humans — keep the last line greppable)
  console.log(
    `SUMMARY: unique=${paths.size} downloaded=${stats.downloaded} ` +
      `skipped=${stats.skipped} failed=${stats.failed} docsRead=${stats.docsRead} ` +
      `appConfig=${appConfig ? 'yes' : 'NO'} mirror=${mirrorBaseUrl}`
  );
  process.exit(0);
}

if (process.argv.includes('--selftest')) {
  selfTest().then(
    (ok) => process.exit(ok ? 0 : 1),
    (e) => {
      console.error('SELFTEST CRASHED:', e);
      process.exit(1);
    }
  );
} else {
  main().catch((e) => {
    console.error('FATAL:', e && e.message ? e.message : e);
    process.exit(1);
  });
}
