// Firebase Cloud Function: Auto-send notification when a new movie is added
//
// SETUP INSTRUCTIONS:
// 1. Install Firebase CLI: npm install -g firebase-tools
// 2. Login: firebase login
// 3. Init functions: firebase init functions (select your project: cm-movies-fe7d4)
// 4. Replace the generated functions/index.js with this code
// 5. Deploy: firebase deploy --only functions
//
// PREREQUISITES:
// - Firebase Blaze plan (required for Cloud Functions)
// - Enable Cloud Messaging in Firebase Console
//
// This function listens to the 'movies' Firestore collection.
// When a new document is created, it sends a push notification
// to all users subscribed to the 'new_movies' topic.

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin (only once)
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Trigger: When a new movie document is created in Firestore
 * 
 * This function automatically sends a push notification to all devices
 * subscribed to the 'new_movies' FCM topic when a new movie is added.
 */
exports.sendNewMovieNotification = functions.firestore
  .document('movies/{movieId}')
  .onCreate(async (snap, context) => {
    const movieData = snap.data();
    
    // Skip if this is not a real movie (e.g., placeholder document)
    if (!movieData || !movieData.title) {
      console.log('Skipping notification: No title found');
      return null;
    }

    const movieTitle = movieData.title;
    const movieType = movieData.type || 'movie';
    const movieId = context.params.movieId;
    const movieYear = movieData.year || '';
    const movieRating = movieData.rating || '';
    const moviePoster = movieData.poster || '';

    // Build notification content
    const typeLabel = movieType === 'series' ? 'Series' : 'Movie';
    let body = `New ${typeLabel}: ${movieTitle}`;
    if (movieYear) body += ` (${movieYear})`;
    if (movieRating) body += ` | Rating: ${movieRating}`;

    // Notification message payload
    const message = {
      notification: {
        title: '🎬 New Movie Added!',
        body: body,
      },
      data: {
        type: 'new_movie',
        movieId: movieId,
        movieTitle: movieTitle,
        movieType: movieType,
        clickAction: 'MOVIE_DETAIL',
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'new_movies',
          icon: 'ic_launcher',
          color: '#E50914',
          sound: 'default',
          clickAction: 'MOVIE_DETAIL',
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
      topic: 'new_movies', // Send to all subscribers
    };

    try {
      const response = await admin.messaging().send(message);
      console.log(`✅ Notification sent for "${movieTitle}":`, response);
      return { success: true, messageId: response };
    } catch (error) {
      console.error('❌ Error sending notification:', error);
      return { success: false, error: error.message };
    }
  });

/**
 * Optional: Send notification for new series episodes
 * 
 * If you have a 'series' collection separate from 'movies',
 * uncomment this function.
 */
// exports.sendNewSeriesNotification = functions.firestore
//   .document('series/{seriesId}')
//   .onCreate(async (snap, context) => {
//     const seriesData = snap.data();
//     if (!seriesData || !seriesData.title) return null;
//
//     const message = {
//       notification: {
//         title: '📺 New Series Added!',
//         body: `New Series: ${seriesData.title} (${seriesData.year || ''})`,
//       },
//       data: {
//         type: 'new_series',
//         movieId: context.params.seriesId,
//         clickAction: 'MOVIE_DETAIL',
//       },
//       android: {
//         priority: 'high',
//         notification: {
//           channelId: 'new_movies',
//           icon: 'ic_launcher',
//           color: '#E50914',
//         },
//       },
//       topic: 'new_movies',
//     };
//
//     try {
//       const response = await admin.messaging().send(message);
//       console.log('Notification sent:', response);
//     } catch (error) {
//       console.error('Error:', error);
//     }
//   });

/**
 * Optional: HTTP endpoint to manually send notifications
 * 
 * Can be used by admin to send custom notifications
 * POST /sendNotification
 * Body: { title: string, body: string, topic?: string }
 */
exports.sendManualNotification = functions.https.onRequest(async (req, res) => {
  // Only allow POST requests
  if (req.method !== 'POST') {
    return res.status(405).send('Method Not Allowed');
  }

  const { title, body, topic } = req.body;

  if (!title || !body) {
    return res.status(400).json({ error: 'title and body are required' });
  }

  const message = {
    notification: { title, body },
    data: { type: 'manual' },
    android: {
      priority: 'high',
      notification: {
        channelId: 'new_movies',
        icon: 'ic_launcher',
        color: '#E50914',
      },
    },
    topic: topic || 'new_movies',
  };

  try {
    const response = await admin.messaging().send(message);
    return res.json({ success: true, messageId: response });
  } catch (error) {
    console.error('Error sending manual notification:', error);
    return res.status(500).json({ error: error.message });
  }
});
