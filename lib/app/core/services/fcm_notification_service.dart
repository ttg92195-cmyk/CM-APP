import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
/// Architecture (post Task 43.1, 2026-06-28):
/// - **Receiving**: OneSignal SDK handles FCM push delivery on the device
/// - **Sending**: Admin sends via OneSignal Dashboard (browser) — the
///   OneSignal REST API key is NO LONGER bundled in the APK. The old
///   in-app composer was removed because it required the REST API key
///   in client .env, which leaked via APK decompilation. See
///   AdminNotificationPage for the new flow.
/// - **Deep linking**: Notification tap navigates to MovieDetailScreen
///   (the OneSignal dashboard custom-data fields `movieSlug` / `movieId`
///   are read here in `_handleNotificationClick`)
/// - **History**: Past notifications stored in Firestore `notifications`
///   collection (read-only going forward — new sends go through the
///   dashboard and are not auto-logged here)
class FcmNotificationService {
  static final FcmNotificationService _instance = FcmNotificationService._();
  factory FcmNotificationService() => _instance;
  FcmNotificationService._();

  bool _initialized = false;
  String? _oneSignalAppId;

  /// Initialize OneSignal: request permission, setup foreground/click handlers
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Load OneSignal App ID from .env (App ID is safe to ship in APK —
      // it identifies which OneSignal app to subscribe to; it cannot be
      // used to send notifications. Only the REST API key can do that,
      // and that key is no longer in the client.)
      _oneSignalAppId = dotenv.env['ONE_SIGNAL_APP_ID'] ?? '';

      if (_oneSignalAppId!.isEmpty || _oneSignalAppId == 'YOUR_ONE_SIGNAL_APP_ID_HERE') {
        debugPrint('OneSignal: App ID not configured — skipping initialization');
        debugPrint('OneSignal: Set ONE_SIGNAL_APP_ID in .env file to enable push notifications');
        return;
      }

      // Initialize OneSignal SDK
      OneSignal.initialize(_oneSignalAppId!);
      debugPrint('OneSignal: Initialized with App ID: $_oneSignalAppId');

      // Request notification permission.
      //
      // CRITICAL FIX (Phase 4.30, 2026-07-26):
      // On Oppo A16 / ColorOS 11 and several other Chinese OEM Android
      // variants, `requestPermission(true)` can HANG INDEFINITELY when
      // notifications are disabled at the system level. ColorOS's custom
      // permission UI does not respond like stock Android 13+ — the
      // underlying platform channel call may never return. Previously
      // this blocked the entire app startup (white screen). The main.dart
      // fix moves the FCM init off the critical path, and this timeout
      // is the second safety net: even if the call hangs, we abort after
      // 4 seconds and let the rest of init proceed. Push simply won't
      // work until the user grants permission via system Settings.
      //
      // Note: requestPermission(false) would skip the system prompt
      // entirely, but we keep `true` so users on stock Android still get
      // the prompt. The timeout only fires on OEMs that misbehave.
      try {
        await OneSignal.Notifications.requestPermission(true)
            .timeout(const Duration(seconds: 4), onTimeout: () {
          debugPrint('OneSignal: requestPermission timed out after 4s — '
              'likely ColorOS/OEM permission UI hang. Continuing without '
              'push permission; user can grant via system Settings.');
          return false;
        });
      } catch (e) {
        debugPrint('OneSignal: requestPermission error (non-fatal): $e');
      }
      debugPrint('OneSignal: Permission request flow complete');

      // Setup foreground notification display handler
      // In onesignal_flutter 5.5.x, method renamed from addForegroundWillShowListener
      // to addForegroundWillDisplayListener. Notification displays automatically
      // unless event.preventDefault() is called.
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        debugPrint('OneSignal: Foreground notification received: ${event.notification.title}');
        // Do not call preventDefault() — let the notification display automatically
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

  /// Handle notification click — navigate to movie detail if slug is present.
  ///
  /// Reads `movieSlug` / `movieId` from the OneSignal notification's
  /// additional_data (set via the OneSignal Dashboard's "Additional Data"
  /// field when composing a push). Either field, if present, will trigger
  /// navigation to the movie detail page.
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

  /// Get OneSignal Player ID (for debugging)
  String? get playerId => OneSignal.User.pushSubscription.id;

  /// Check if OneSignal is initialized
  bool get isInitialized => _initialized;
}
