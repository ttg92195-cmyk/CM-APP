import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ===========================================================================
/// DebugOverflowDetector — Task 33 (Phase 2: UI Layout Safety)
/// ===========================================================================
///
/// Captures Flutter [RenderFlex] overflow errors in **debug mode only**
/// and surfaces them in two ways:
///
///   1. A formatted log line prefixed with `[Overflow]` containing the
///      error message — visible in `flutter run` console, `adb logcat`,
///      and any crash reporter wired to `debugPrint`.
///   2. (Optional) An in-app [SnackBar] that pops the first time each
///      unique overflow signature is seen — so devs notice even when
///      they're not watching the console.
///
/// ## Why this exists
///
/// Flutter's built-in behavior for `RenderFlex` overflow is to paint a
/// yellow-and-black striped rectangle under the overflowing widget,
/// visible only in debug mode and only if you happen to scroll to that
/// part of the screen. In release builds, the overflow is **completely
/// silent** — the user just sees clipped text or a broken layout with
/// no error reported.
///
/// This detector catches those silent overflow errors at the
/// `FlutterError.onError` level so they're never lost.
///
/// ## How it works
///
/// Flutter routes non-fatal framework errors (including RenderFlex
/// overflow) through `FlutterError.onError`. We install a handler that:
///   - Forwards to the previous handler (so nothing is suppressed).
///   - Inspects the error message for overflow-related signatures
///     ("overflowed by N pixels" / "RenderFlex").
///   - Deduplicates per session (one log per unique message).
///   - Logs via `debugPrint` with a clear `[Overflow]` prefix.
///   - If a [GlobalKey<ScaffoldMessengerState>] is provided, shows a
///     one-time SnackBar per unique overflow.
///
/// ## Wiring
///
/// In `main.dart`:
///
/// ```dart
/// final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
///
/// void main() {
///   DebugOverflowDetector().install(scaffoldMessengerKey: scaffoldMessengerKey);
///   runApp(CMMoviesApp(scaffoldMessengerKey: scaffoldMessengerKey));
/// }
/// ```
///
/// And in `MaterialApp`:
///
/// ```dart
/// MaterialApp(
///   scaffoldMessengerKey: scaffoldMessengerKey,
///   ...
/// )
/// ```
///
/// ## Release mode
///
/// In release builds (`kDebugMode == false`), [install] is a no-op.
/// No handlers are attached, no SnackBars are shown. The class itself
/// remains in the binary (it's tiny) but does nothing.
class DebugOverflowDetector {
  DebugOverflowDetector._();
  static final DebugOverflowDetector instance = DebugOverflowDetector._();

  /// Previously-installed `FlutterError.onError` handler, so we can
  /// forward to it without clobbering other error handlers (e.g.,
  /// crash reporters, PlatformDispatcher.onError).
  FlutterExceptionHandler? _previousHandler;

  /// Set of overflow messages we've already logged this session —
  /// prevents log spam when the same overflow fires on every rebuild.
  final Set<String> _seenMessages = {};

  /// Optional scaffold messenger for in-app SnackBars. Null = log only.
  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  /// Whether the detector is currently installed.
  bool _installed = false;

  /// Install the FlutterError.onError handler. Safe to call once at
  /// app startup; subsequent calls are no-ops.
  ///
  /// In release builds, this is a no-op.
  void install({
    GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey,
  }) {
    if (!kDebugMode) {
      // Silent no-op in release. We keep the class in the binary so
      // dev builds and prod builds have identical Dart code paths
      // (no risk of "works in dev, fails in prod" surprises).
      return;
    }
    if (_installed) {
      debugPrint('[DebugOverflowDetector] already installed — ignoring duplicate call.');
      return;
    }

    _scaffoldMessengerKey = scaffoldMessengerKey;
    _previousHandler = FlutterError.onError;
    FlutterError.onError = _handleFlutterError;
    _installed = true;

    debugPrint(
      '[DebugOverflowDetector] installed. RenderFlex overflow errors will be '
      'logged with "[Overflow]" prefix${scaffoldMessengerKey != null ? ' and surfaced via SnackBar' : ''}.',
    );
  }

  /// Restore the previous FlutterError handler. Safe to call even if
  /// [install] was never called.
  void uninstall() {
    if (!_installed) return;
    FlutterError.onError = _previousHandler;
    _previousHandler = null;
    _scaffoldMessengerKey = null;
    _seenMessages.clear();
    _installed = false;
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    // Always forward to the previous handler first — never swallow errors.
    if (_previousHandler != null) {
      _previousHandler!(details);
    } else {
      FlutterError.presentError(details);
    }

    final exception = details.exception;
    if (exception is! FlutterError) return;

    final message = exception.toString();

    // Heuristic: RenderFlex overflow errors contain "overflowed by N pixels".
    // We match loosely so we catch both the standard message format and
    // any future variants.
    if (!_isOverflowMessage(message)) return;

    // Deduplicate per session.
    final signature = _signatureOf(message);
    if (_seenMessages.contains(signature)) return;
    _seenMessages.add(signature);

    // Log with a clear prefix.
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('[Overflow] $message');
    if (details.stack != null) {
      // Print just the first 5 stack frames to keep log readable.
      final stackString = details.stack.toString();
      final lines = stackString.split('\n').take(8).join('\n');
      debugPrint('[Overflow] stack (first 8 frames):\n$lines');
    }
    debugPrint('═══════════════════════════════════════════════════════');

    // Show in-app SnackBar if a messenger is wired.
    _maybeShowSnackBar(message);
  }

  /// Heuristic check: is this FlutterError message a RenderFlex overflow?
  /// Matches strings like:
  ///   "RenderFlex overflowed by 12 pixels on the right edge."
  ///   "RenderFlex overflowed by 34 pixels on the bottom."
  static bool _isOverflowMessage(String message) {
    return message.contains('RenderFlex') &&
        message.contains('overflowed by');
  }

  /// Build a stable signature for deduplication. Strips the pixel count
  /// so "overflowed by 12 pixels" and "overflowed by 13 pixels" are
  /// treated as the same issue (we don't want one SnackBar per pixel
  /// of drift).
  static String _signatureOf(String message) {
    // Replace any "N pixels" with "X pixels" for dedup.
    final normalized = message.replaceAll(
      RegExp(r'\d+ pixels'),
      'X pixels',
    );
    return normalized;
  }

  void _maybeShowSnackBar(String message) {
    final messengerKey = _scaffoldMessengerKey;
    if (messengerKey == null) return;
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    final shortMessage = message.length > 120
        ? '${message.substring(0, 120)}…'
        : message;

    try {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ Layout overflow detected:\n$shortMessage',
            style: const TextStyle(fontSize: 12),
          ),
          duration: const Duration(seconds: 6),
          backgroundColor: Colors.red[900],
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Logs',
            textColor: Colors.white,
            onPressed: () {
              debugPrint('[Overflow] full session overflow log:');
              for (final m in _seenMessages) {
                debugPrint('  • $m');
              }
            },
          ),
        ),
      );
    } catch (e) {
      // SnackBar can fail if the messenger is in a transient state
      // (e.g., between route pushes). Don't crash — the log is the
      // authoritative record anyway.
      debugPrint('[DebugOverflowDetector] SnackBar failed: $e');
    }
  }
}
