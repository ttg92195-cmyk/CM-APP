import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Advanced External Player Service
///
/// Supports launching video URLs in external players like VLC and MX Player
/// using Android's intent system. Falls back to url_launcher for non-Android
/// platforms or when no specific player app is found.
///
/// For 4K video support: VLC and MX Player both support 4K HEVC/H.265
/// playback with hardware acceleration. The intent approach passes the
/// video URL directly to the player, allowing the external player to
/// handle its own buffering, decoding, and rendering pipeline.
class ExternalPlayerService {
  // Common Android package names for video players
  static const String _vlcPackage = 'org.videolan.vlc';
  static const String _mxPlayerPackage = 'com.mxtech.videoplayer.ad';
  static const String _mxPlayerProPackage = 'com.mxtech.videoplayer.pro';

  /// Open a video URL in an external player (VLC, MX Player, etc.)
  ///
  /// Strategy:
  /// 1. On Android: Try to launch with ACTION_VIEW intent targeting video players
  /// 2. Fall back to url_launcher which also uses the intent system
  /// 3. The external player handles its own process lifecycle, preventing
  ///    crashes in the host app since video decoding runs in the player's process
  static Future<bool> playWithExternalPlayer(String videoUrl) async {
    try {
      if (Platform.isAndroid) {
        return await _launchWithAndroidIntent(videoUrl);
      }
      // Non-Android: use url_launcher
      return await _launchWithUrlLauncher(videoUrl);
    } catch (e) {
      debugPrint('External player error: $e');
      return false;
    }
  }

  /// Android-specific: Launch video with an explicit intent
  ///
  /// Uses a custom intent URI that targets video player apps.
  /// This is more reliable than url_launcher for video playback
  /// because it explicitly sets the MIME type and category.
  static Future<bool> _launchWithAndroidIntent(String videoUrl) async {
    // Try VLC first (best 4K/codec support)
    final vlcSuccess = await _tryLaunchSpecificPlayer(
      videoUrl,
      _vlcPackage,
      'org.videolan.vlc.gui.video.VideoPlayerActivity',
    );
    if (vlcSuccess) return true;

    // Try MX Player (free version)
    final mxSuccess = await _tryLaunchSpecificPlayer(
      videoUrl,
      _mxPlayerPackage,
      'com.mxtech.videoplayer.ad.ActivityScreen',
    );
    if (mxSuccess) return true;

    // Try MX Player Pro
    final mxProSuccess = await _tryLaunchSpecificPlayer(
      videoUrl,
      _mxPlayerProPackage,
      'com.mxtech.videoplayer.pro.ActivityScreen',
    );
    if (mxProSuccess) return true;

    // Fallback: Use generic ACTION_VIEW intent via url_launcher
    // This will show a chooser dialog if multiple video players are installed
    return await _launchWithUrlLauncher(videoUrl);
  }

  /// Try to launch a specific player by package name
  ///
  /// Constructs an Android intent URI that targets a specific video player app.
  /// If the app is not installed, this returns false without crashing.
  ///
  /// Phase 4.37: Removed the `canLaunchUrl` pre-check. The check was a
  /// separate platform-channel round-trip (~100-300ms on low-end devices)
  /// that essentially duplicated work the subsequent `launchUrl` already
  /// does. Bro reported the cumulative stutter of 3-4 such pre-checks
  /// (VLC, MX, MX-Pro, fallback) as "ထစ်နေတာ" when opening a video with
  /// External Player selected.
  ///
  /// The new flow: try `launchUrl` directly. If the player is not
  /// installed, launchUrl returns false (or throws) — same outcome as
  /// canLaunchUrl returning false, but with one fewer platform-channel
  /// hop per attempt.
  static Future<bool> _tryLaunchSpecificPlayer(
    String videoUrl,
    String packageName,
    String activityName,
  ) async {
    try {
      // Build an intent URI for Android:
      // intent:#Intent;action=android.intent.action.VIEW;data=<url>;type=video/*;package=<pkg>;component=<pkg>/<activity>;end
      final intentUri = Uri.parse(
        'intent:$videoUrl#Intent;'
        'action=android.intent.action.VIEW;'
        'data=$videoUrl;'
        'type=video/*;'
        'package=$packageName;'
        'S.title=CM_Movies_Video;'
        'end',
      );

      // Directly attempt launch. On Android, launchUrl with an
      // `intent:` URI will resolve the intent via the PackageManager
      // and return false if no matching activity is found. This saves
      // a separate canLaunchUrl platform-channel round-trip per player
      // we probe (we probe up to 3 players + 1 fallback = 4 hops saved).
      final launched = await launchUrl(
        intentUri,
        mode: LaunchMode.externalApplication,
      );
      return launched;
    } catch (e) {
      debugPrint('Failed to launch $packageName: $e');
      return false;
    }
  }

  /// Generic fallback using url_launcher
  ///
  /// Phase 4.37: Also removed the `canLaunchUrl` pre-check here for the
  /// same reason — saves a platform-channel round-trip.
  static Future<bool> _launchWithUrlLauncher(String videoUrl) async {
    try {
      final uri = Uri.parse(videoUrl);
      return await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('url_launcher fallback error: $e');
      return false;
    }
  }
}
