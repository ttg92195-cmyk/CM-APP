// Phase 4.35: Premium styled SnackBar for app-wide notifications.
//
// Bro's brief:
//   "ရိုရိုဖြစ်နေလို့ သိပ်မလန်းတာဖြစ်နေပါတယ်။
//    ဒီထကါခေက်မိတယ် အလန်းစားတွေ့ပြောင်းလဲလုပ်ချင်တာဖြစ်ပါတယ်"
//   (The current plain orange SnackBar looks too plain / not premium.
//    Want to change it to a premium style.)
//
// Design (inspired by Spotify / Apple Music / Disney+ toast notifications):
//   - Dark gradient background (works in both light & dark app themes,
//     just like Netflix/Spotify toasts that always render dark)
//   - Left: circular icon container with accent color, white icon
//   - Middle: bold title + optional subtitle
//   - Rounded corners (14px), floating with 12px margin from screen edges
//   - Subtle elevation shadow for depth
//   - Optional action button (e.g. "Undo", "Login")
//
// Usage:
//   ScaffoldMessenger.of(context).showSnackBar(
//     PremiumSnackBar(
//       context: context,
//       icon: Icons.logout_rounded,
//       title: 'Logged out',
//       subtitle: 'You have been signed out.',
//       accentColor: const Color(0xFFE50914),
//     ).build(),
//   );

import 'package:flutter/material.dart';

class PremiumSnackBar {
  final BuildContext context;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accentColor;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;

  const PremiumSnackBar({
    required this.context,
    required this.icon,
    required this.title,
    this.subtitle,
    this.accentColor = const Color(0xFFE50914),
    this.actionLabel,
    this.onAction,
    this.duration = const Duration(seconds: 3),
  });

  SnackBar build() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Dark gradient background works in both light & dark app themes.
    // This is the same approach Netflix / Spotify / Apple Music use for
    // their toast notifications — always dark, regardless of app theme,
    // so the toast's visual identity stays consistent.
    const bgGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF1F1F1F), // near-black with slight warmth
        Color(0xFF0A0A0A), // deep black
      ],
    );

    // Accent color for the icon container + left edge bar.
    final accent = accentColor;

    // Text colors — always white-on-dark for maximum readability.
    const titleColor = Color(0xFFFFFFFF);
    const subtitleColor = Color(0xFFB3B3B3);

    // Build the content row.
    final content = Row(
      children: [
        // Left: circular icon container with accent color.
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: accent.withOpacity(0.45),
              width: 1.2,
            ),
          ),
          child: Icon(
            icon,
            color: accent,
            size: 20,
          ),
        ),
        const SizedBox(width: 14),
        // Middle: title + optional subtitle.
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: titleColor,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  decoration: TextDecoration.none,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: subtitleColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ],
          ),
        ),
        // Right: optional action button.
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accent.withOpacity(0.4),
                  width: 1,
                ),
              ),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: accent,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    // Wrap content in a Container with gradient background + rounded corners.
    // SnackBar's `padding` is set to zero so our Container controls all
    // internal padding.
    final decoratedContent = Container(
      // Gradient overlay using a Stack — SnackBar doesn't natively support
      // gradient backgrounds, so we paint it ourselves.
      decoration: BoxDecoration(
        gradient: bgGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      child: content,
    );

    return SnackBar(
      content: decoratedContent,
      // Remove SnackBar's default background — our Container provides it.
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Floating behavior with margin so the SnackBar appears as a
      // rounded floating card rather than a full-width bottom bar.
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      padding: EdgeInsets.zero,
      duration: duration,
      // Optional action — kept hidden because we render our own action
      // button inside the content (above) for full styling control.
      action: null,
      // Smooth slide-in curve.
      dismissDirection: DismissDirection.horizontal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
