import 'package:flutter/material.dart';

/// ===========================================================================
/// SafeText — Task 33 (Phase 2: UI Layout Safety)
/// ===========================================================================
///
/// A drop-in replacement for [Text] that enforces safe defaults for
/// `maxLines` and `overflow`. Designed for use anywhere a Text widget sits
/// inside a constrained box, Row + Expanded, grid cell, or list item —
/// the situations where unbounded text length can silently break layout
/// (clipping, RenderFlex overflow, misaligned cards).
///
/// ## Why this exists
///
/// Myanmar text is denser than English — a single English word like
/// "Continue Watching" becomes "ဆက်ကြည့်ရန်" which has more glyphs and
/// wider ink. After Task 32 (Localization), translation lengths are no
/// longer predictable from the English source. The safest assumption is
/// that **any** translated string may overflow its allotted space.
///
/// Plain `Text` widgets default to:
///   - `maxLines: null` (unlimited)
///   - `overflow: TextOverflow.clip`
///
/// That means long text either wraps indefinitely (pushing siblings) or
/// silently clips. Neither is acceptable in a tightly-designed card grid.
///
/// ## Defaults
///
///   - `maxLines: 2` (configurable)
///   - `overflow: TextOverflow.ellipsis` (configurable)
///   - `softWrap: true`
///
/// ## When to use
///
/// Use `SafeText` instead of `Text` for **any** string that:
///   1. Comes from a translation key (`appConfig.translate('...')`).
///   2. Comes from user input or Firestore (movie titles, descriptions,
///      cast names, etc.).
///   3. Sits inside a Row + Expanded / Flexible combo.
///   4. Sits inside a grid cell or list item with bounded width.
///
/// Plain `Text` is still fine for:
///   - Short static labels whose English length is known to fit (e.g.,
///     icon-only button tooltips, fixed-width date stamps).
///   - Headlines that are intentionally allowed to wrap.
///
/// ## Example
///
/// ```dart
/// // Before:
/// Text(
///   movie.title,
///   style: theme.textTheme.titleMedium,
/// )
///
/// // After:
/// SafeText(
///   movie.title,
///   style: theme.textTheme.titleMedium,
///   maxLines: 1, // override default of 2
/// )
/// ```
///
/// ## Migration note
///
/// This widget is opt-in. Existing `Text` widgets are NOT auto-migrated.
/// Developers should use `SafeText` for new code and when touching
/// existing widgets that have shown overflow issues. See
/// `docs/UI_LAYOUT_SAFETY.md` for full guidelines.
class SafeText extends StatelessWidget {
  /// The text to display.
  final String data;

  /// Optional text style. Inherited from [DefaultTextStyle] if not given.
  final TextStyle? style;

  /// Maximum number of lines before truncation. Defaults to 2 — enough
  /// for a 2-line title or label without dominating card height.
  final int? maxLines;

  /// Truncation behavior when text exceeds [maxLines]. Defaults to
  /// [TextOverflow.ellipsis] so the user sees "..." indicating truncation.
  final TextOverflow? overflow;

  /// Whether text wraps to the next line. Defaults to true (matches
  /// Flutter's default). Set to false for single-line forced text.
  final bool softWrap;

  /// Text alignment within the available width. Defaults to
  /// [TextAlign.start] (matches Flutter's default).
  final TextAlign? textAlign;

  /// Text direction. Defaults to inherited from [Directionality] (LTR
  /// for the whole app). Override only for RTL languages.
  final TextDirection? textDirection;

  /// Locale for locale-sensitive glyph selection. Rarely needed.
  final Locale? locale;

  /// How visual letters are shaped. Defaults to
  /// [TextHeightBehavior.applyLeadingToFirstAscent] (Flutter default).
  final TextHeightBehavior? textHeightBehavior;

  /// Color of the text selection highlight. Defaults to theme.
  final Color? selectionColor;

  /// Creates a SafeText widget with safe defaults for layout stability.
  const SafeText(
    this.data, {
    super.key,
    this.style,
    this.maxLines = 2,
    this.overflow = TextOverflow.ellipsis,
    this.softWrap = true,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.textHeightBehavior,
    this.selectionColor,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
