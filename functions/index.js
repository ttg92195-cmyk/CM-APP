const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { onRequest } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
admin.initializeApp();

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
