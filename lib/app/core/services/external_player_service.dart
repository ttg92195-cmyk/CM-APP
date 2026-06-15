import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class ExternalPlayerService {
  /// Open a video URL in an external player (VLC, MX Player, etc.)
  /// Uses Android intent system via url_launcher
  static Future<bool> playWithExternalPlayer(String videoUrl) async {
    try {
      final uri = Uri.parse(videoUrl);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      }
      return false;
    } catch (e) {
      debugPrint('External player error: $e');
      return false;
    }
  }
}
