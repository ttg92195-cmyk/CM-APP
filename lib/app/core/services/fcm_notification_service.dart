import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';

/// Global navigator key for notification tap navigation.
/// Set from main.dart's MaterialApp navigatorKey.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Service class for managing push notifications using OneSignal.
///
/// OneSignal is 100% free (up to 10K subscribers) and does NOT require:
/// - Firebase Blaze Plan (no credit card)
/// - Cloud Functions
/// - Any server-side code
///
/// Architecture:
/// - **Receiving**: OneSignal SDK handles FCM push delivery on the device
/// - **Sending**: Admin uses OneSignal REST API via Dio (no server needed)
/// - **Deep linking**: Notification tap navigates to MovieDetailScreen
/// - **History**: Notifications stored in Firestore `notifications` collection
class FcmNotificationService {
  static final FcmNotificationService _instance = FcmNotificationService._();
  factory FcmNotificationService() => _instance;
  FcmNotificationService._();

  bool _initialized = false;
  String? _oneSignalAppId;
  String? _oneSignalRestApiKey;

  /// Initialize OneSignal: request permission, setup foreground/click handlers
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Load OneSignal credentials from .env
      _oneSignalAppId = dotenv.env['ONE_SIGNAL_APP_ID'] ?? '';
      _oneSignalRestApiKey = dotenv.env['ONE_SIGNAL_REST_API_KEY'] ?? '';

      if (_oneSignalAppId!.isEmpty || _oneSignalAppId == 'YOUR_ONE_SIGNAL_APP_ID_HERE') {
        debugPrint('OneSignal: App ID not configured — skipping initialization');
        debugPrint('OneSignal: Set ONE_SIGNAL_APP_ID in .env file to enable push notifications');
        return;
      }

      // Initialize OneSignal SDK
      OneSignal.initialize(_oneSignalAppId!);
      debugPrint('OneSignal: Initialized with App ID: $_oneSignalAppId');

      // Request notification permission
      final granted = await OneSignal.Notifications.requestPermission(true);
      debugPrint('OneSignal: Permission granted: $granted');

      // Setup foreground notification handler
      OneSignal.Notifications.addForegroundWillShowListener((event) {
        debugPrint('OneSignal: Foreground notification received');
        // Let OneSignal display the notification automatically
        event.notification.complete();
      });

      // Setup notification click handler (tap)
      OneSignal.Notifications.addClickListener((event) {
        debugPrint('OneSignal: Notification clicked');
        _handleNotificationClick(event.notification);
      });

      // Setup notification permission change listener
      OneSignal.Notifications.addPermissionObserver((state) {
        debugPrint('OneSignal: Permission changed to: $state');
      });

      // Log the OneSignal player/user ID for debugging
      final playerId = OneSignal.User.pushSubscription.id;
      debugPrint('OneSignal: Player ID: $playerId');

      // Save OneSignal player ID to Firestore for potential targeting
      await _savePlayerIdToFirestore(playerId);

      // Also save FCM token to Firestore (OneSignal manages FCM under the hood)
      _saveFcmTokenToFirestore();

      _initialized = true;
      debugPrint('OneSignal: Initialization complete');
    } catch (e) {
      debugPrint('OneSignal: Initialization error: $e');
    }
  }

  /// Save OneSignal Player ID to Firestore users/{uid} document.
  /// This allows targeting specific users if needed.
  Future<void> _savePlayerIdToFirestore(String? playerId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || playerId == null || playerId.isEmpty) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'oneSignalPlayerId': playerId,
        'oneSignalUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('OneSignal: Player ID saved to Firestore');
    } catch (e) {
      debugPrint('OneSignal: Error saving Player ID: $e');
    }
  }

  /// Save FCM token to Firestore (OneSignal manages FCM under the hood).
  Future<void> _saveFcmTokenToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // OneSignal doesn't expose the raw FCM token, but we can save the player ID
      // The player ID is the OneSignal equivalent for device targeting
      debugPrint('OneSignal: FCM token managed by OneSignal SDK');
    } catch (e) {
      debugPrint('OneSignal: Error in FCM token management: $e');
    }
  }

  /// Handle notification click — navigate to movie detail if slug is present
  void _handleNotificationClick(OSNotification notification) {
    try {
      final data = notification.additionalData;
      if (data == null) return;

      final movieSlug = data['movieSlug']?.toString();
      final movieId = data['movieId']?.toString();
      final slug = movieSlug ?? movieId;

      if (slug == null || slug.isEmpty) return;

      debugPrint('OneSignal: Click — navigating to movie: $slug');

      // Navigate to movie detail using the global navigator key
      final context = navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).pushNamed('/movie-detail', arguments: slug);
      } else {
        // Retry after a short delay when the widget tree is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) {
            Navigator.of(ctx).pushNamed('/movie-detail', arguments: slug);
          }
        });
      }
    } catch (e) {
      debugPrint('OneSignal: Error handling notification click: $e');
    }
  }

  /// Send push notification to all users via OneSignal REST API.
  /// No server needed — calls OneSignal directly from the admin app.
  ///
  /// Returns true if the notification was sent successfully.
  Future<bool> sendNotificationToAll({
    required String title,
    required String body,
    String? movieId,
    String? movieSlug,
  }) async {
    try {
      if (_oneSignalRestApiKey == null || _oneSignalRestApiKey!.isEmpty ||
          _oneSignalRestApiKey == 'YOUR_ONE_SIGNAL_REST_API_KEY_HERE') {
        debugPrint('OneSignal: REST API Key not configured');
        return false;
      }

      if (_oneSignalAppId == null || _oneSignalAppId!.isEmpty) {
        debugPrint('OneSignal: App ID not configured');
        return false;
      }

      // Build OneSignal notification payload
      final payload = <String, dynamic>{
        'app_id': _oneSignalAppId,
        'included_segments': ['Subscribed Users'], // Send to all subscribed users
        'headings': {'en': title},
        'contents': {'en': body},
        'data': {
          'movieId': movieId ?? '',
          'movieSlug': movieSlug ?? '',
        },
        'android_channel_id': 'movie_notifications',
        'priority': 10, // High priority
        'small_icon': '@mipmap/ic_launcher',
      };

      // Call OneSignal REST API using Dio
      final dio = Dio();
      final response = await dio.post(
        'https://onesignal.com/api/v1/notifications',
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Basic $_oneSignalRestApiKey',
          },
        ),
        data: payload,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        debugPrint('OneSignal: Notification sent successfully! ID: ${data['id']}');
        debugPrint('OneSignal: Recipients: ${data['recipients']}');
        return true;
      } else {
        debugPrint('OneSignal: Send failed (${response.statusCode}): ${response.data}');
        return false;
      }
    } catch (e) {
      debugPrint('OneSignal: Error sending notification: $e');
      return false;
    }
  }

  /// Legacy method — kept for backward compatibility.
  /// Now uses OneSignal instead of Cloud Functions.
  Future<void> sendNewMovieNotification(String movieTitle, String movieId) async {
    await sendNotificationToAll(
      title: 'New Movie Added!',
      body: movieTitle,
      movieId: movieId,
    );
  }

  /// Get OneSignal Player ID (for debugging)
  String? get playerId => OneSignal.User.pushSubscription.id;

  /// Check if OneSignal is initialized
  bool get isInitialized => _initialized;
}
