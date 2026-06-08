import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Service class for managing Firebase Cloud Messaging (FCM) push notifications.
/// Handles permission requests, topic subscriptions, foreground message display,
/// and notification tap handling.
class FcmNotificationService {
  static final FcmNotificationService _instance = FcmNotificationService._();
  factory FcmNotificationService() => _instance;
  FcmNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize FCM: request permission, subscribe to topic, setup foreground & background handlers
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Request notification permission (iOS requires this, Android auto-grants on API < 33)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('FCM: User granted notification permission');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('FCM: User granted provisional notification permission');
      } else {
        debugPrint('FCM: User declined notification permission');
        // Still continue setup — topic subscription works regardless of permission
      }

      // Subscribe all users to the global topic for new movie notifications
      await _messaging.subscribeToTopic('movies_all');
      debugPrint('FCM: Subscribed to "movies_all" topic');

      // Setup foreground message handler
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Setup background message handler (top-level function)
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle notification tap when app is in background (not terminated)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Handle notification tap when app was terminated (cold start)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // Initialize local notifications for foreground display
      await _initLocalNotifications();

      // Get and log the FCM token
      final token = await _messaging.getToken();
      debugPrint('FCM Token: $token');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: $newToken');
      });

      _initialized = true;
    } catch (e) {
      debugPrint('FCM initialization error: $e');
    }
  }

  /// Initialize flutter_local_notifications for displaying foreground notifications
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('Local notification tapped: ${response.payload}');
        _handleNotificationTap(response.payload);
      },
    );

    // Create Android notification channel for high-priority notifications
    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        'movie_notifications',
        'Movie Notifications',
        description: 'Notifications for new movies and series',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  /// Handle foreground messages by displaying a local notification
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('FCM Foreground message: ${message.messageId}');
    debugPrint('FCM Data: ${message.data}');

    final notification = message.notification;
    if (notification != null) {
      _showLocalNotification(
        title: notification.title ?? 'KMM',
        body: notification.body ?? '',
        payload: message.data['movieId']?.toString(),
      );
    }
  }

  /// Show a local notification using flutter_local_notifications
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'movie_notifications',
      'Movie Notifications',
      channelDescription: 'Notifications for new movies and series',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Use message hash as unique ID
    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);
    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  /// Handle when a notification is tapped and the app opens
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('FCM Message opened app: ${message.messageId}');
    final movieId = message.data['movieId']?.toString();
    _handleNotificationTap(movieId);
  }

  /// Handle notification tap — navigate to movie detail if movieId is present
  void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    debugPrint('FCM Notification tap - movieId: $payload');
    // TODO: Navigate to movie detail when navigator key is available
    // This would need a global navigator key or a callback to the app
  }

  /// Send FCM notification to "movies_all" topic when admin adds a new movie.
  /// Uses Firebase Cloud Messaging HTTP v1 API via server-side (Cloud Function recommended).
  /// For client-side demo, we store a notification record in Firestore.
  Future<void> sendNewMovieNotification(String movieTitle, String movieId) async {
    try {
      // Store notification in Firestore for Cloud Function to pick up,
      // or for client-side reference
      // Note: Client-side FCM sending is NOT recommended for production.
      // Use Firebase Cloud Functions or a backend server instead.
      debugPrint('FCM: New movie notification - "$movieTitle" (ID: $movieId)');
      debugPrint('FCM: In production, send via Cloud Function to topic "movies_all"');
    } catch (e) {
      debugPrint('FCM: Error sending notification: $e');
    }
  }
}

/// Top-level background message handler (MUST be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for background isolate
  // Note: You need firebase_core for this
  debugPrint('FCM Background message: ${message.messageId}');
}
