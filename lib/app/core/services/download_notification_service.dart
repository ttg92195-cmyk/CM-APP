import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';
// Phase 4.17: Reuse the global navigatorKey defined in fcm_notification_service
// so notification taps can push the Downloads screen without needing a
// BuildContext. main.dart already wires this key into MaterialApp.
import 'package:cm_movies/app/core/services/fcm_notification_service.dart'
    show navigatorKey;
import 'package:cm_movies/app/ui/screens/download_page.dart';

/// Service that manages system-level notifications for download progress.
///
/// Shows persistent (ongoing) notifications in the Android notification shade
/// while downloads are active, with real-time progress updates. Shows
/// completion or failure notifications when downloads end.
///
/// Uses flutter_local_notifications — NOT a foreground service. These are
/// regular notifications that update in real-time.
class DownloadNotificationService {
  static DownloadNotificationService? _instance;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Track which task IDs have active notifications so we can cancel/update them
  final Set<String> _activeNotificationTasks = {};

  /// Whether the service has been initialized
  bool _isInitialized = false;

  /// Throttle notification updates to avoid overwhelming the notification manager
  final Map<String, int> _lastNotificationTime = {};
  static const int _notificationIntervalMs = 500; // Update max 2x per second

  /// Android notification channel details
  static const String _channelId = 'downloads';
  static const String _channelName = 'Downloads';
  static const String _channelDescription = 'Shows download progress and status';

  /// Singleton factory constructor
  factory DownloadNotificationService() {
    _instance ??= DownloadNotificationService._internal();
    return _instance!;
  }

  DownloadNotificationService._internal();

  /// Convenience getter for the singleton instance
  static DownloadNotificationService get instance => DownloadNotificationService();

  /// Initialize the notification plugin and create the Android notification channel.
  /// Must be called once before using any other methods (typically in main.dart or
  /// during DownloadManagerService.init()).
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Android initialization settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS initialization settings
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false, // Downloads don't need sound
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create the Android notification channel for downloads
    await _createDownloadChannel();

    debugPrint('DownloadNotificationService initialized');
  }

  /// Request notification permission (required for Android 13+ / API 33+).
  /// Should be called before starting downloads, ideally at app startup
  /// or when the user first navigates to the downloads screen.
  /// Returns true if permission is granted.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        // Request notification permission (Android 13+ requires this)
        final granted = await androidPlugin.requestNotificationsPermission();
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
    }

    return true; // Assume granted on older Android versions
  }

  /// Check if notification permission has been granted.
  Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return true;

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        return await androidPlugin.areNotificationsEnabled() ?? false;
      }
    } catch (e) {
      debugPrint('Error checking notification permission: $e');
    }

    return true;
  }

  /// Show a notification when a download starts.
  /// The notification is ongoing (non-dismissible) with 0% progress.
  Future<void> showDownloadStarted(DownloadTask task) async {
    if (!_isInitialized) await init();

    final notificationId = _getNotificationId(task.id);
    _activeNotificationTasks.add(task.id);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low, // Low importance: no sound for progress
      priority: Priority.low,
      ongoing: true, // Non-dismissible while downloading
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: 0,
      onlyAlertOnce: true, // Don't re-alert on updates
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
      // Show quality info in subtext
      subText: task.quality,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notificationId,
      'Downloading ${task.movieTitle}',
      '0% · ${task.quality}',
      details,
      payload: 'downloads', // Phase 4.17: tap → Downloads screen
    );

    debugPrint('Notification shown: download started for ${task.movieTitle} (${task.quality})');
  }

  /// Update the notification with current download progress.
  /// Throttled to avoid excessive notification updates.
  Future<void> updateDownloadProgress(DownloadTask task) async {
    if (!_isInitialized) return;
    if (!_activeNotificationTasks.contains(task.id)) return;

    // Throttle: don't update more often than _notificationIntervalMs
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastTime = _lastNotificationTime[task.id] ?? 0;
    if (now - lastTime < _notificationIntervalMs) return;
    _lastNotificationTime[task.id] = now;

    final notificationId = _getNotificationId(task.id);
    final progressPercent = (task.progress * 100).round().clamp(0, 100);

    // Build body text with useful info
    String body = '$progressPercent%';
    if (task.speedText.isNotEmpty) {
      body += ' · ${task.speedText}';
    }
    if (task.etaText.isNotEmpty) {
      body += ' · ${task.etaText}';
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
      subText: task.quality,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notificationId,
      'Downloading ${task.movieTitle}',
      body,
      details,
      payload: 'downloads', // Phase 4.17: tap → Downloads screen
    );
  }

  /// Show a completion notification when a download finishes successfully.
  /// This replaces the ongoing progress notification with a regular
  /// (dismissible) notification.
  Future<void> showDownloadCompleted(DownloadTask task) async {
    if (!_isInitialized) return;

    final notificationId = _getNotificationId(task.id);
    _activeNotificationTasks.remove(task.id);
    _lastNotificationTime.remove(task.id);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false, // Dismissible
      autoCancel: true,
      showProgress: false,
      category: AndroidNotificationCategory.status,
      visibility: NotificationVisibility.public,
      subText: task.quality,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notificationId,
      'Download complete',
      '${task.movieTitle} (${task.quality})',
      details,
      payload: 'downloads', // Phase 4.17: tap → Downloads screen
    );

    // Phase 4.17: removed the auto-cancel Future.delayed — it was dismissing
    // the completion notification after 5s, which left users almost no time
    // to tap it. The notification now stays until the user swipes it away
    // (autoCancel: true above handles tap-to-dismiss). Failed notifications
    // below likewise stay until dismissed.

    debugPrint('Notification: download completed for ${task.movieTitle}');
  }

  /// Show a failure notification when a download fails.
  /// The notification is dismissible and shows the error message.
  Future<void> showDownloadFailed(DownloadTask task) async {
    if (!_isInitialized) return;

    final notificationId = _getNotificationId(task.id);
    _activeNotificationTasks.remove(task.id);
    _lastNotificationTime.remove(task.id);

    final errorMsg = task.errorMessage ?? 'Download failed';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high, // High importance so user notices
      priority: Priority.high,
      ongoing: false,
      autoCancel: true,
      showProgress: false,
      category: AndroidNotificationCategory.error,
      visibility: NotificationVisibility.public,
      subText: task.quality,
    );

    const iosDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notificationId,
      'Download failed',
      '${task.movieTitle} (${task.quality}): $errorMsg',
      details,
      payload: 'downloads', // Phase 4.17: tap → Downloads screen
    );

    // Phase 4.17: removed the auto-cancel Future.delayed — failed downloads
    // are user-actionable (tap to retry from the Downloads screen), so the
    // notification should stay until the user dismisses it.

    debugPrint('Notification: download failed for ${task.movieTitle}');
  }

  /// Cancel the notification for a download (used when download is paused
  /// or removed by the user).
  Future<void> cancelNotification(String taskId) async {
    if (!_isInitialized) return;

    final notificationId = _getNotificationId(taskId);
    _activeNotificationTasks.remove(taskId);
    _lastNotificationTime.remove(taskId);

    try {
      await _plugin.cancel(notificationId);
      debugPrint('Notification cancelled for task $taskId');
    } catch (e) {
      debugPrint('Error cancelling notification for $taskId: $e');
    }
  }

  /// Cancel all active download notifications (e.g., on app cleanup).
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;

    for (final taskId in _activeNotificationTasks.toList()) {
      await cancelNotification(taskId);
    }
  }

  // ===== Private helpers =====

  /// Generate a unique notification ID from the task ID using a stable hash.
  /// The result is a positive integer suitable for Android notification IDs.
  int _getNotificationId(String taskId) {
    // Use a simple hash to generate a unique but consistent ID
    // Keep it in a reasonable range (1-9999) to avoid issues
    var hash = 0;
    for (int i = 0; i < taskId.length; i++) {
      hash = ((hash << 5) - hash) + taskId.codeUnitAt(i);
      hash = hash & 0x7FFFFFFF; // Keep it positive
    }
    return (hash % 9999) + 1; // Range: 1-9999
  }

  /// Create the Android notification channel for download progress.
  Future<void> _createDownloadChannel() async {
    if (!Platform.isAndroid) return;

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        const channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.low, // Low importance: no sound for progress
          showBadge: false,
        );

        await androidPlugin.createNotificationChannel(channel);
        debugPrint('Download notification channel created');
      }
    } catch (e) {
      debugPrint('Error creating download notification channel: $e');
    }
  }

  /// Handle notification tap — navigate to the Downloads screen.
  ///
  /// Phase 4.17: When the user taps any download notification (start /
  /// progress / complete / failed), the app opens (if backgrounded) and
  /// pushes the DownloadPage on top of the current route. The payload
  /// is the literal string 'downloads', set by all show*() methods below.
  ///
  /// We use push(MaterialPageRoute(...)) instead of pushNamed because
  /// the app does not declare a '/downloads' named route in main.dart's
  /// routes table. Direct push is also what the rest of the codebase
  /// uses when opening the Downloads screen (home_page.dart:343,
  /// movie_download_screen.dart:140, series_download_screen.dart:135).
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Download notification tapped: ${response.id}');
    final payload = response.payload;
    if (payload == 'downloads') {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        debugPrint('Phase 4.17: navigatorKey.currentState is null — '
            'app likely not yet mounted. Tap ignored.');
        return;
      }
      nav.push(MaterialPageRoute(builder: (_) => const DownloadPage()));
    }
  }
}
