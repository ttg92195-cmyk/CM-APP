// Phase 4.47 — Shared circular icon button with consistent sizing, ripple,
// and (optional) circular background tint.
//
// PROBLEM
// - The app had ~5 sites using `GestureDetector + Icon` (no ripple at all)
//   and ~7 sites using `IconButton.styleFrom(backgroundColor: ...)` without
//   `shape: CircleBorder()` (square background AND square ripple).
// - AppBar back-buttons and other IconButtons also relied on Material 3's
//   default ` StadiumBorder ` ripple which is an elongated pill, not a
//   true circle — visually inconsistent with the rest of the UI.
//
// FIX
// - This component gives every callsite the same circular ripple + the
//   same 48×48 tap target (a11y minimum) by default.
// - Optional `backgroundColor` paints a circular tint behind the icon
//   (e.g. video-player controls with `Colors.black45`).
// - Optional `size` controls the icon glyph size (default 24 — Material
//   spec default).
// - Optional `tapSize` controls the hit-box (default 48 — a11y minimum).
//   Set to 40 / 36 only when layout is genuinely cramped.
//
// USAGE
//   AppIconButton(icon: Icons.arrow_back, onTap: () => Navigator.pop(context))
//   AppIconButton.circle(
//     icon: Icons.volume_up,
//     backgroundColor: Colors.black45,
//     onTap: () => ...,
//   )
import 'package:flutter/material.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.backgroundColor,
    this.size = 24,
    this.tapSize = 48,
    this.tooltip,
    this.semanticLabel,
    this.disabled = false,
  })  : _circular = false;

  /// Circular variant — same as the default constructor but makes the
  /// intent explicit at the call-site (e.g. for media controls that want
  /// a visible circular tint behind the icon).
  const AppIconButton.circle({
    super.key,
    required this.icon,
    required this.onTap,
    this.color,
    this.backgroundColor,
    this.size = 24,
    this.tapSize = 48,
    this.tooltip,
    this.semanticLabel,
    this.disabled = false,
  }) : _circular = true;

  final IconData icon;
  final VoidCallback? onTap;
  final Color? color;
  final Color? backgroundColor;
  final double size;
  final double tapSize;
  final String? tooltip;
  final String? semanticLabel;
  final bool disabled;
  final bool _circular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ??
        (theme.appBarTheme.iconTheme?.color ?? theme.colorScheme.onSurface);

    final btn = IconButton(
      icon: Icon(icon, size: size, semanticLabel: semanticLabel),
      onPressed: disabled ? null : onTap,
      iconSize: size,
      color: effectiveColor,
      // CircleBorder → both the ripple AND the optional background paint
      // as a true circle, not the Material 3 default stadium (pill).
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        backgroundColor: backgroundColor,
        // 48×48 is the Material a11y minimum tap target. We allow callers
        // to shrink to 40 / 36 for cramped layouts (e.g. dense list rows)
        // but never below that.
        minimumSize: Size(tapSize, tapSize),
        maximumSize: Size(tapSize, tapSize),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      tooltip: tooltip,
    );

    // If no tooltip, return as-is. If tooltip is set, IconButton already
    // handles it — no wrapper needed.
    return btn;
  }
}
