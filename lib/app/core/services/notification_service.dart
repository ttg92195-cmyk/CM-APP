import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase for background isolate
  // If you need to show notifications in background, you'd initialize
  // flutter_local_notifications here too
  debugPrint('📱 Background message: ${message.messageId}');
}

class NotificationService extends ChangeNotifier {
  static const String _notifEnabledKey = 'notifications_enabled';
  static const String _newMoviesNotifKey = 'new_movies_notifications';
  static const String _fcmTokenKey = 'fcm_token';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _notificationsEnabled = true;
  bool _newMoviesEnabled = true;
  String? _fcmToken;
  bool _isInitialized = false;

  bool get notificationsEnabled => _notificationsEnabled;
  bool get newMoviesEnabled => _newMoviesEnabled;
  String? get fcmToken => _fcmToken;
  bool get isInitialized => _isInitialized;

  /// Initialize the notification service
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Load saved preferences
      await _loadPreferences();

      // Initialize local notifications (for foreground display)
      await _initLocalNotifications();

      // Initialize FCM
      await _initFCM();

      _isInitialized = true;
      debugPrint('📱 NotificationService initialized successfully');
    } catch (e) {
      debugPrint('📱 NotificationService init error: $e');
    }
  }

  /// Load saved notification preferences
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool(_notifEnabledKey) ?? true;
    _newMoviesEnabled = prefs.getBool(_newMoviesNotifKey) ?? true;
  }

  /// Initialize flutter_local_notifications for foreground notification display
  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('📱 Notification tapped: ${response.payload}');
        // Handle notification tap - navigate to movie detail
        // This would be handled via a callback from the UI
      },
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
          'new_movies',
          'New Movies',
          description: 'Notifications for new movie additions',
          importance: Importance.high,
        ));
      }
    }
  }

  /// Initialize Firebase Cloud Messaging
  Future<void> _initFCM() async {
    // Request permission (iOS + Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    debugPrint('📱 Notification permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _notificationsEnabled = false;
      notifyListeners();
      return;
    }

    // Get FCM token
    _fcmToken = await _messaging.getToken();
    debugPrint('📱 FCM Token: ${_fcmToken?.substring(0, 20)}...');

    // Save token to SharedPreferences
    if (_fcmToken != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_fcmTokenKey, _fcmToken!);
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((token) {
      _fcmToken = token;
      debugPrint('📱 FCM Token refreshed');
      _saveTokenToFirestore(token);
    });

    // Subscribe to topics based on preferences
    await _updateTopicSubscriptions();

    // Foreground message handler
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Background/tap message handler
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Check if app was opened from terminated state via notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  /// Handle foreground messages (show local notification)
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('📱 Foreground message: ${message.messageId}');

    final notification = message.notification;
    final data = message.data;

    if (notification != null) {
      _showLocalNotification(
        title: notification.title ?? 'CM Movies',
        body: notification.body ?? '',
        payload: data['movieId'] as String? ?? '',
      );
    }
  }

  /// Handle notification tap (when app is opened from notification)
  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('📱 Message opened app: ${message.messageId}');
    // This would be used to navigate to the movie detail page
    // The UI layer would set up a callback for this
    if (_onNotificationTap != null) {
      final data = message.data;
      _onNotificationTap!(data);
    }
  }

  /// Callback for notification tap - set by UI layer
  void Function(Map<String, dynamic> data)? _onNotificationTap;

  void setOnNotificationTap(void Function(Map<String, dynamic> data) callback) {
    _onNotificationTap = callback;
  }

  /// Show a local notification (for foreground FCM messages)
  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String payload = '',
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'new_movies',
      'New Movies',
      channelDescription: 'Notifications for new movie additions',
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

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Update topic subscriptions based on current preferences
  Future<void> _updateTopicSubscriptions() async {
    if (!_notificationsEnabled) {
      // Unsubscribe from all topics
      try {
        await _messaging.unsubscribeFromTopic('new_movies');
      } catch (e) {
        debugPrint('📱 Error unsubscribing: $e');
      }
      return;
    }

    try {
      if (_newMoviesEnabled) {
        await _messaging.subscribeToTopic('new_movies');
        debugPrint('📱 Subscribed to new_movies topic');
      } else {
        await _messaging.unsubscribeFromTopic('new_movies');
        debugPrint('📱 Unsubscribed from new_movies topic');
      }
    } catch (e) {
      debugPrint('📱 Error updating topic subscriptions: $e');
    }
  }

  /// Save FCM token to Firestore (for server-side targeting)
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      // Save to a tokens collection for server-side use
      await _firestore.collection('fcm_tokens').doc(token).set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
        'platform': Platform.isAndroid ? 'android' : 'ios',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('📱 Error saving FCM token: $e');
    }
  }

  /// Toggle notifications enabled
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notifEnabledKey, enabled);

    await _updateTopicSubscriptions();

    // Save/remove token from Firestore
    if (!enabled && _fcmToken != null) {
      try {
        await _firestore.collection('fcm_tokens').doc(_fcmToken).delete();
      } catch (e) {
        debugPrint('📱 Error removing FCM token: $e');
      }
    } else if (enabled && _fcmToken != null) {
      await _saveTokenToFirestore(_fcmToken!);
    }

    notifyListeners();
  }

  /// Toggle new movies notifications
  Future<void> setNewMoviesEnabled(bool enabled) async {
    _newMoviesEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_newMoviesNotifKey, enabled);

    if (_notificationsEnabled) {
      await _updateTopicSubscriptions();
    }

    notifyListeners();
  }

  /// Show a test notification (for debugging)
  Future<void> showTestNotification() async {
    await _showLocalNotification(
      title: 'CM Movies',
      body: '🔔 Notifications are working! New movies will be notified here.',
    );
  }
}
