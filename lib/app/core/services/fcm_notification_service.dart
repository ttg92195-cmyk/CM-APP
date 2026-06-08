import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:dio/dio.dart';

/// Global navigator key for notification tap navigation.
/// Set from main.dart's MaterialApp navigatorKey.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Service class for managing Firebase Cloud Messaging (FCM) push notifications.
/// Handles permission requests, topic subscriptions, foreground message display,
/// notification tap navigation, FCM token storage, and Cloud Function integration.
class FcmNotificationService {
  static final FcmNotificationService _instance = FcmNotificationService._();
  factory FcmNotificationService() => _instance;
  FcmNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  String? _currentToken;

  /// Initialize FCM: request permission, subscribe to topic, setup handlers,
  /// save token to Firestore, and setup foreground/background message handling.
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

      // Get FCM token, save to Firestore, and listen for refresh
      await _saveTokenToFirestore();
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: $newToken');
        _saveTokenToFirestore(newToken: newToken);
      });

      _initialized = true;
    } catch (e) {
      debugPrint('FCM initialization error: $e');
    }
  }

  /// Save FCM token to Firestore `users/{uid}` document.
  /// This allows Cloud Functions to target specific devices if needed.
  Future<void> _saveTokenToFirestore({String? newToken}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('FCM: Cannot save token — user not logged in');
        return;
      }

      final token = newToken ?? await _messaging.getToken();
      if (token == null) {
        debugPrint('FCM: Token is null, cannot save');
        return;
      }

      _currentToken = token;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'platform': Platform.isAndroid ? 'android' : 'ios',
      }, SetOptions(merge: true));

      debugPrint('FCM: Token saved to Firestore for user ${user.uid}');
    } catch (e) {
      debugPrint('FCM: Error saving token to Firestore: $e');
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
        payload: message.data['movieSlug']?.toString() ?? message.data['movieId']?.toString(),
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
    final movieSlug = message.data['movieSlug']?.toString();
    final movieId = message.data['movieId']?.toString();
    _handleNotificationTap(movieSlug ?? movieId);
  }

  /// Handle notification tap — navigate to movie detail if slug/id is present.
  /// Uses the global navigator key set from main.dart.
  void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    debugPrint('FCM Notification tap - payload: $payload');

    // Navigate to movie detail screen using the global navigator key
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Import MovieDetailScreen dynamically to avoid circular imports
      Navigator.of(context).pushNamed(
        '/movie-detail',
        arguments: payload,
      );
    } else {
      debugPrint('FCM: Navigator context not available yet — will retry on next frame');
      // Retry after a short delay when the widget tree is ready
      Future.delayed(const Duration(milliseconds: 500), () {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          Navigator.of(ctx).pushNamed('/movie-detail', arguments: payload);
        }
      });
    }
  }

  /// Send FCM notification via Cloud Function HTTP endpoint.
  /// The Cloud Function uses Firebase Admin SDK to send to `movies_all` topic.
  /// Uses HTTP POST with Firebase Auth ID token for authentication.
  Future<bool> sendNotificationViaCloudFunction({
    required String notificationId,
    required String title,
    required String body,
    String? movieId,
    String? movieSlug,
  }) async {
    try {
      // Get the current user's ID token for authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('FCM: User not authenticated — cannot call Cloud Function');
        return false;
      }

      final idToken = await user.getIdToken();

      // Call the Cloud Function HTTP endpoint
      // URL will be: https://<region>-<project-id>.cloudfunctions.net/sendNotification
      // Replace with your actual Cloud Function URL after deployment
      const functionUrl = 'https://us-central1-cm-movies-dabab.cloudfunctions.net/sendNotification';

      final dio = Dio();
      final response = await dio.post(
        functionUrl,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
        ),
        data: {
          'notificationId': notificationId,
          'title': title,
          'body': body,
          'movieId': movieId,
          'movieSlug': movieSlug,
        },
      );

      if (response.statusCode == 200) {
        debugPrint('FCM: Cloud Function success: ${response.data}');
        return true;
      } else {
        debugPrint('FCM: Cloud Function failed (${response.statusCode}): ${response.data}');
        return false;
      }
    } catch (e) {
      debugPrint('FCM: Cloud Function call failed: $e');
      return false;
    }
  }

  /// Legacy method — kept for backward compatibility.
  /// In production, use Cloud Functions to send FCM to topic.
  Future<void> sendNewMovieNotification(String movieTitle, String movieId) async {
    try {
      debugPrint('FCM: New movie notification - "$movieTitle" (ID: $movieId)');
      debugPrint('FCM: In production, send via Cloud Function to topic "movies_all"');
    } catch (e) {
      debugPrint('FCM: Error sending notification: $e');
    }
  }

  /// Get current FCM token (useful for debugging)
  String? get currentToken => _currentToken;
}

/// Top-level background message handler (MUST be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for background isolate
  // Note: You need firebase_core for this
  debugPrint('FCM Background message: ${message.messageId}');
}
