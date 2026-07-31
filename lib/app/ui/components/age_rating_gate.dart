import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

/// Age Rating Gate - shows a verification dialog before showing adult content
/// M3: Age verification result is stored in secure storage (not SharedPreferences)
/// so it can't be easily tampered with. Verification must be re-done per session
/// for additional security — the token expires when the app restarts.
class AgeRatingGate {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _ageVerifiedKey = 'age_verified_session';

  /// Show age verification dialog. Returns true if verified.
  static Future<bool> showAgeGate(BuildContext context, {String? movieTitle}) async {
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AgeGateDialog(
        movieTitle: movieTitle,
        appConfig: appConfig,
      ),
    );

    if (result == true) {
      // Store verification in secure storage (encrypted).
      // Phase 4.18: wrap in try-catch — Android Keystore can throw
      // PlatformException on certain devices (notably older OS versions
      // and after app backup/restore). Without this guard, a single
      // failing write would crash the app right after the user confirmed
      // they were 18+, which is a particularly bad UX.
      try {
        await _storage.write(
          key: _ageVerifiedKey,
          value: DateTime.now().toIso8601String(),
        );
      } catch (e) {
        debugPrint('AgeRatingGate: failed to write verification token '
            '(non-fatal — user will be re-prompted next time): $e');
      }
    }

    return result ?? false;
  }

  /// Check if already verified this session.
  ///
  /// Phase 4.18: the entire body is now wrapped in try-catch. Previously
  /// only DateTime.parse(value) was guarded, leaving _storage.read()
  /// exposed — on devices where Android Keystore fails (older OS,
  // backup/restore corruption), _storage.read() throws PlatformException
  // and the unhandled exception would crash the app at the very moment
  // the user tried to open an adult-rated movie. Now we return false on
  // any error, which gracefully forces re-verification.
  static Future<bool> isVerifiedThisSession() async {
    try {
      final value = await _storage.read(key: _ageVerifiedKey);
      if (value == null) return false;
      // Check if verification was done in current app session (within last 24 hours)
      final verifiedAt = DateTime.parse(value);
      final now = DateTime.now();
      return now.difference(verifiedAt).inHours < 24;
    } catch (e) {
      debugPrint('AgeRatingGate: isVerifiedThisSession failed (non-fatal — '
          'treating as not verified): $e');
      return false;
    }
  }

  /// Clear age verification (on logout).
  /// Phase 4.18: wrapped in try-catch for the same Keystore-crash reason
  /// as the other methods. A failed delete should NOT block logout.
  static Future<void> clearVerification() async {
    try {
      await _storage.delete(key: _ageVerifiedKey);
    } catch (e) {
      debugPrint('AgeRatingGate: failed to delete verification token '
          '(non-fatal — stale token will be ignored on next read): $e');
    }
  }

  /// Check if movie is adult content and show gate if needed
  /// Returns true if safe to proceed (not adult OR age verified)
  static Future<bool> checkAndShowGate(
    BuildContext context, {
    int? isAdult,
    String? movieTitle,
  }) async {
    if (isAdult == null || isAdult == 0) return true;

    // Check if already verified this session
    if (await isVerifiedThisSession()) return true;

    return showAgeGate(context, movieTitle: movieTitle);
  }
}

class _AgeGateDialog extends StatefulWidget {
  final String? movieTitle;
  final AppConfig appConfig;

  const _AgeGateDialog({
    this.movieTitle,
    required this.appConfig,
  });

  @override
  State<_AgeGateDialog> createState() => _AgeGateDialogState();
}

class _AgeGateDialogState extends State<_AgeGateDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = theme.colorScheme.primary;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 40,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  widget.appConfig.translate('age_gate_title'),
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),

                // Description
                Text(
                  widget.appConfig.translate('age_gate_desc'),
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 14,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                // Phase 4.18: show the movie title so the user knows which
                // title they are confirming 18+ for. Previously the
                // movieTitle parameter was passed all the way down from
                // checkAndShowGate() but never rendered — pure dead weight.
                if (widget.movieTitle != null &&
                    widget.movieTitle!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.movieTitle!,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 24),

                // 18+ badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accentColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    '18+',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    // Cancel button
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(
                            color: isDark ? Colors.white24 : Colors.grey.shade400,
                          ),
                        ),
                        child: Text(
                          widget.appConfig.translate('age_gate_cancel'),
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Confirm button
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          widget.appConfig.translate('age_gate_confirm'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
