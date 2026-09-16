const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onRequest } = require('firebase-functions/v2/https');
const { onUserCreated } = require('firebase-functions/v2/auth');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

/**
 * Cloud Function: onUserCreated (Auth trigger)
 *
 * Phase 3.10 — Server-side user profile doc creation.
 *
 * WHY THIS EXISTS:
 *   Previously, the client-side registerUser() in app_config.dart tried to
 *   create the /users/{uid} Firestore doc immediately after
 *   createUserWithEmailAndPassword(). This was unreliable because the
 *   Firestore SDK needs 500-2000ms to propagate the new auth token to its
 *   internal request handlers — during that window, the create request
 *   fails with permission-denied (rules require isOwner(userId) which
 *   requires request.auth.uid == userId, but the SDK is still using
 *   anonymous auth state).
 *
 *   The client-side fix (Phase 3.9) added getIdToken(true) + 800ms delay
 *   + 5 retries with backoff (~5.8s total). This worked for MOST users
 *   but still failed occasionally, leaving orphaned Auth users with no
 *   Firestore profile doc — those users could never log in because
 *   _loadUserProfile couldn't find their doc AND auth propagation delay
 *   prevented the recovery create.
 *
 *   This Cloud Function is the bulletproof fix. It fires AUTOMATICALLY
 *   when Firebase Auth creates a new user, and writes the profile doc
 *   server-side using the Admin SDK (which bypasses Firestore rules
 *   entirely). No race condition, no propagation delay, no permission
 *   errors.
 *
 * BEHAVIOR:
 *   - Fires on every new Firebase Auth user creation.
 *   - Derives username from email: strips "@cmmovies.app" suffix if
 *     present (legacy/internal users), otherwise uses the email's
 *     local part (admin users with real emails).
 *   - Creates /users/{uid} with safe defaults:
 *       username, email, isAdmin: false, registrationDate, createdAt
 *   - Uses { merge: true } so it's idempotent — if the client-side
 *     registerUser also managed to create the doc, this won't overwrite.
 *   - Logs success/failure for debugging via `firebase functions:log`.
 *
 * SECURITY:
 *   - Admin SDK bypasses Firestore rules, so no rules change needed.
 *   - The doc is created with isAdmin: false — a malicious user cannot
 *     escalate via this function. Admin status is only granted by an
 *     existing admin updating the doc through the app (gated by
 *     isAdmin() rule).
 *   - safeSignupFields() in firestore.rules is satisfied: isAdmin != true,
 *     role != 'admin', isVip != true, isBanned != true, forceLogout != true.
 */
exports.onUserCreated = onUserCreated(
  { region: 'us-central1' },
  async (event) => {
    const user = event.data;
    if (!user) {
      logger.warn('onUserCreated: no user data in event');
      return null;
    }

    const uid = user.uid;
    const email = user.email || '';
    const now = new Date();
    const regDate = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

    // Derive username from email.
    // - Internal users: "bro" + "@cmmovies.app" → "bro"
    // - Admin users with real emails: "bro@gmail.com" → "bro"
    let username = '';
    if (email.endsWith('@cmmovies.app')) {
      username = email.slice(0, -'@cmmovies.app'.length);
    } else if (email.includes('@')) {
      username = email.split('@')[0];
    } else {
      // No email (shouldn't happen for password auth, but defensive)
      username = uid.substring(0, 8);
    }

    const userDoc = {
      username: username,
      email: email,
      isAdmin: false,
      registrationDate: regDate,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    try {
      // merge: true so this is idempotent. If the client-side registerUser
      // already created the doc (race), this update preserves any fields
      // the client set that aren't in our userDoc above (none currently,
      // but future-proof).
      await admin.firestore().collection('users').doc(uid).set(userDoc, { merge: true });
      logger.info(`onUserCreated: created/merged profile doc for uid=${uid} username=${username}`);
      return { success: true, uid, username };
    } catch (error) {
      logger.error(`onUserCreated: FAILED to create profile doc for uid=${uid}:`, error);
      // Don't throw — throwing would retry the function, but the Admin
      // SDK write should rarely fail. If it does, the client-side
      // registerUser fallback will try to create the doc itself.
      return { success: false, uid, error: error.message };
    }
  }
);

/**
 * Cloud Function: sendNotification (HTTP endpoint)
 *
 * Called from the admin app when sending a push notification.
 * Verifies the caller is an admin, then sends FCM message to 'movies_all' topic.
 *
 * Request body:
 *   - notificationId: Firestore document ID of the notification
 *   - title: Notification title
 *   - body: Notification body text
 *   - movieId: (optional) Movie document ID for deep linking
 *   - movieSlug: (optional) Movie slug for deep linking
 */
exports.sendNotification = onRequest(
  { cors: true, region: 'us-central1' },
  async (req, res) => {
    // Only accept POST requests
    if (req.method !== 'POST') {
      return res.status(405).json({ error: 'Method not allowed' });
    }

    try {
      // Verify the Firebase Auth ID token from the Authorization header
      const authHeader = req.headers.authorization;
      if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({ error: 'Unauthorized — missing auth token' });
      }

      const idToken = authHeader.split('Bearer ')[1];
      const decodedToken = await admin.auth().verifyIdToken(idToken);
      const uid = decodedToken.uid;

      // Check if the user is an admin
      const userDoc = await admin.firestore().collection('users').doc(uid).get();
      if (!userDoc.exists) {
        return res.status(403).json({ error: 'Forbidden — user not found' });
      }

      const userData = userDoc.data();
      const isAdmin = userData.role === 'admin' || userData.isAdmin === true;
      if (!isAdmin) {
        return res.status(403).json({ error: 'Forbidden — not an admin' });
      }

      // Extract notification data from request body
      const { notificationId, title, body, movieId, movieSlug } = req.body;

      if (!title || !body) {
        return res.status(400).json({ error: 'Title and body are required' });
      }

      // Build the FCM message
      const message = {
        notification: {
          title: title,
          body: body,
        },
        data: {
          movieId: movieId || '',
          movieSlug: movieSlug || '',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
        topic: 'movies_all',
        android: {
          priority: 'high',
          notification: {
            channelId: 'movie_notifications',
            icon: '@mipmap/ic_launcher',
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
              badge: 1,
            },
          },
        },
      };

      // Send the FCM message
      const messageId = await admin.messaging().send(message);
      logger.info('FCM message sent successfully:', messageId);

      // Update the notification document in Firestore with send status
      if (notificationId) {
        await admin.firestore().collection('notifications').doc(notificationId).update({
          isSent: true,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          fcmMessageId: messageId,
        });
      }

      return res.status(200).json({
        success: true,
        messageId: messageId,
        message: 'Notification sent to all subscribers',
      });
    } catch (error) {
      logger.error('Error sending notification:', error);
      return res.status(500).json({
        error: 'Internal server error',
        details: error.message,
      });
    }
  }
);

/**
 * Cloud Function: onNotificationCreated (Firestore trigger)
 *
 * Automatically triggers when a new notification document is created in Firestore.
 * Sends FCM push to 'movies_all' topic.
 * This is a backup — the HTTP function above is the primary sender.
 */
exports.onNotificationCreated = onDocumentCreated(
  {
    document: 'notifications/{notificationId}',
    region: 'us-central1',
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn('No data associated with the event');
      return null;
    }

    const data = snapshot.data();

    // Skip if already sent (by the HTTP function)
    if (data.isSent === true) {
      logger.info('Notification already sent, skipping Firestore trigger');
      return null;
    }

    const title = data.title;
    const body = data.body;
    const movieId = data.movieId || '';
    const movieSlug = data.movieSlug || '';

    if (!title || !body) {
      logger.warn('Notification missing title or body, skipping');
      return null;
    }

    // Build the FCM message
    const message = {
      notification: {
        title: title,
        body: body,
      },
      data: {
        movieId: movieId,
        movieSlug: movieSlug,
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
      topic: 'movies_all',
      android: {
        priority: 'high',
        notification: {
          channelId: 'movie_notifications',
          icon: '@mipmap/ic_launcher',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    try {
      const messageId = await admin.messaging().send(message);
      logger.info('FCM message sent via Firestore trigger:', messageId);

      // Update the notification document
      await snapshot.ref.update({
        isSent: true,
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
        fcmMessageId: messageId,
      });

      return { success: true, messageId };
    } catch (error) {
      logger.error('Error sending FCM via Firestore trigger:', error);

      // Update with error status
      await snapshot.ref.update({
        isSent: false,
        error: error.message,
      });

      return { success: false, error: error.message };
    }
  }
);

// ============================================================================
// Cloud Function: tmdbImageProxy (HTTPS, Phase 4 hotfix 2026-09-16)
// ============================================================================
// WHY THIS EXISTS:
//   Myanmar ISPs block/blackhole image.tmdb.org, so every TMDB poster URL
//   stored in Firestore fails to load inside the app (posters show endless
//   shimmer placeholders). The first fix routed posters through a
//   Cloudflare Worker (tmdb-images.guyg20985.workers.dev) — that Worker
//   works from a desktop/phone BROWSER, but the app's own HTTP requests to
//   *.workers.dev still hang (ISP DNS blackholing of the workers.dev
//   domain — Chrome bypasses it via DNS-over-HTTPS, Dart's HttpClient
//   cannot). Meanwhile Google/Firebase endpoints are PROVEN reachable
//   in-app: Firestore data (titles, ratings, metadata) loads fine on the
//   same screen where posters fail.
//
//   So this function serves the same images from Google's own
//   infrastructure (Cloud Functions / Cloud Run), which the app can
//   already reach.
//
// BEHAVIOR:
//   GET https://us-central1-cm-movies-dabab.cloudfunctions.net/tmdbImageProxy/t/p/w500/<file>.jpg
//     → fetches https://image.tmdb.org/t/p/w500/<file>.jpg server-side
//     → returns the image bytes with 7-day Cache-Control.
//   - Only /t/p/* paths (TMDB image paths) — NOT an open proxy.
//   - Only GET/HEAD methods.
//   - Path is validated (charset + length + no traversal) before fetch.
//   - Size-capped in-memory LRU cache (~300 images ≈ 15-30MB) per warm
//     instance — repeat requests never re-hit TMDB; cold starts fetch
//     fresh (TMDB CDN is fast from Google's network).
//   - 15s abort timeout on the upstream fetch.
//   - CORS: open (images are public content).
//
// APP WIRING (NO app rebuild needed):
//   The app already rewrites image.tmdb.org URLs through whatever host is
//   configured in Firestore app_settings/tmdb_image_proxy.baseUrl
//   (TmdbImageProxy, display-time rewrite only). To switch from the
//   Cloudflare Worker to this function, edit ONE Firestore doc:
//     app_settings/tmdb_image_proxy.baseUrl =
//       https://us-central1-cm-movies-dabab.cloudfunctions.net/tmdbImageProxy
//   then in the app: Settings → About → "TMDB Poster Proxy" → tap to
//   re-check (no restart, no rebuild). The app's PosterCacheManager keys
//   images by URL, so the new host is fetched fresh.
//
// COST (Blaze plan):
//   Posters are ~30-100KB. Free tier = 2M invocations/month; egress is
//   billed after free allowance at ~$0.12/GB — for a typical catalog
//   (2-3k unique posters) + daily users this is well under $2/month,
//   and in-memory + client-side caching keep repeat traffic near zero.
//
// SECURITY:
//   - Read-only, path-restricted image proxy — cannot be used to fetch
//     arbitrary origins, only image.tmdb.org/t/p/*.
//   - No auth required (posters are public; CachedNetworkImage cannot
//     attach Firebase auth headers).
//   - 5MB response cap rejects absurd upstream payloads.
// ============================================================================

const TMDB_PROXY_ORIGIN = 'https://image.tmdb.org';
const TMDB_PROXY_CACHE = new Map(); // path -> { buf, ctype }
const TMDB_PROXY_CACHE_MAX = 300; // entries (~15-30MB) per warm instance

function tmdbProxyCacheGet(p) {
  const hit = TMDB_PROXY_CACHE.get(p);
  if (hit) {
    // LRU refresh: move to most-recently-used position.
    TMDB_PROXY_CACHE.delete(p);
    TMDB_PROXY_CACHE.set(p, hit);
  }
  return hit;
}

function tmdbProxyCachePut(p, entry) {
  if (TMDB_PROXY_CACHE.size >= TMDB_PROXY_CACHE_MAX) {
    const oldest = TMDB_PROXY_CACHE.keys().next().value;
    TMDB_PROXY_CACHE.delete(oldest);
  }
  TMDB_PROXY_CACHE.set(p, entry);
}

exports.tmdbImageProxy = onRequest(
  { cors: true, region: 'us-central1', timeoutSeconds: 30, memory: '128MB' },
  async (req, res) => {
    // Only GET/HEAD (browsers/probes sometimes send OPTIONS — cors:true
    // already handles that before we get here).
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.set('Allow', 'GET, HEAD');
      return res.status(405).send('Method not allowed');
    }

    // Path after the function name, e.g. /t/p/w500/<file>.jpg.
    // Query strings (the app appends ?retry=N cache-busters) are ignored —
    // the image identity is the path alone.
    const path = (req.path || '/').split('?')[0];

    if (!path.startsWith('/t/p/')) {
      return res
        .status(404)
        .send('CM Movies TMDB image proxy — usage: /t/p/<size>/<file>');
    }

    // Path safety: TMDB paths are ASCII [a-zA-Z0-9._/-] only, always short.
    if (
      path.length > 200 ||
      path.includes('..') ||
      /[^a-zA-Z0-9._/-]/.test(path)
    ) {
      return res.status(400).send('Bad path');
    }

    // Serve from the warm-instance memory cache when possible.
    const cached = tmdbProxyCacheGet(path);
    if (cached) {
      res.set('Content-Type', cached.ctype);
      res.set('Content-Length', String(cached.buf.length));
      res.set('Cache-Control', 'public, max-age=604800'); // 7 days
      res.set('Access-Control-Allow-Origin', '*');
      res.set('X-Proxy', 'tmdb-image-proxy/gcf');
      return res.status(200).send(cached.buf);
    }

    // Fetch upstream with a hard 15s abort.
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 15000);
    try {
      const upstream = await fetch(TMDB_PROXY_ORIGIN + path, {
        method: 'GET',
        redirect: 'follow',
        signal: controller.signal,
        headers: {
          'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36',
          Accept: 'image/webp,image/apng,image/*,*/*;q=0.8',
        },
      });

      if (!upstream.ok) {
        return res
          .status(upstream.status === 404 ? 404 : 502)
          .send('Upstream error ' + upstream.status);
      }

      const ctype = upstream.headers.get('content-type') || 'image/jpeg';
      const buf = Buffer.from(await upstream.arrayBuffer());

      if (buf.length === 0 || buf.length > 5 * 1024 * 1024) {
        return res.status(502).send('Unexpected image size');
      }

      tmdbProxyCachePut(path, { buf, ctype });

      res.set('Content-Type', ctype);
      res.set('Content-Length', String(buf.length));
      res.set('Cache-Control', 'public, max-age=604800'); // 7 days
      res.set('Access-Control-Allow-Origin', '*');
      res.set('X-Proxy', 'tmdb-image-proxy/gcf');
      return res.status(200).send(buf);
    } catch (err) {
      const aborted = err && err.name === 'AbortError';
      logger.error('tmdbImageProxy fetch failed:', path, err && err.message);
      return res
        .status(502)
        .send(aborted ? 'Upstream timeout' : 'Proxy fetch failed');
    } finally {
      clearTimeout(timer);
    }
  }
);
