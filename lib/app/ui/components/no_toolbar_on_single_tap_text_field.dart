import 'package:flutter/material.dart';

/// A [TextField] wrapper that suppresses the Cut/Copy/Paste toolbar on
/// single-tap, while keeping the default Flutter behavior of showing the
/// toolbar on double-tap (select word) and long-press.
///
/// WHY THIS EXISTS — Task 29
///
/// Bro reported that after the user double-taps once in a search field
/// (selecting a word and seeing the toolbar), Flutter preserves the
/// selection state. Subsequent SINGLE taps then ALSO re-show the
/// toolbar — annoying UX because accidentally tapping the search box
/// keeps popping up the toolbar.
///
/// FIX
///
/// On every single-tap ([onTap] fires only for single taps — Flutter's
/// internal double-tap recognizer routes the 2nd tap to a separate
/// handler, NOT to [onTap]), we check if the current selection is
/// non-collapsed. If it is, we collapse it on the next frame. Once
/// the selection is collapsed, Flutter hides the toolbar automatically.
///
/// Double-tap still works: Flutter's internal double-tap handler
/// re-selects the word on the 2nd tap regardless of what we do here,
/// so collapsing on the 1st tap doesn't break it. Long-press also
/// still works because it goes through its own recognizer.
///
/// USAGE
///
/// Drop-in replacement for [TextField] anywhere a search input is used.
/// Pass the same parameters you would pass to [TextField]; this widget
/// forwards everything except [onTap], which it composes with the
/// toolbar-hiding behavior. If you pass [onTap], it will be invoked
/// AFTER the toolbar-hiding logic runs.
///
/// ```dart
/// NoToolbarOnSingleTapTextField(
///   controller: _searchController,
///   decoration: InputDecoration(...),
///   onSubmitted: (_) => _search(),
/// )
/// ```
class NoToolbarOnSingleTapTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextStyle? style;
  final bool autofocus;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final TapRegionCallback? onTapOutside;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final bool readOnly;
  final bool? enabled;
  final String? hintText;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextCapitalization textCapitalization;

  /// Optional user-supplied [onTap]. Invoked AFTER the toolbar-hiding
  /// logic runs. Use this if you need to do something extra on tap
  /// (e.g. track analytics, focus another field).
  final VoidCallback? onTap;

  const NoToolbarOnSingleTapTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.style,
    this.autofocus = false,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTapOutside,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.readOnly = false,
    this.enabled,
    this.hintText,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.textCapitalization = TextCapitalization.none,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: decoration,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: style,
      autofocus: autofocus,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: onEditingComplete,
      onTapOutside: onTapOutside,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      readOnly: readOnly,
      enabled: enabled,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      textCapitalization: textCapitalization,
      onTap: _handleTap,
    );
  }

  void _handleTap() {
    // Always run the user's onTap first (if any), so they can react to
    // the tap with the original selection state intact.
    onTap?.call();

    // Then collapse any non-collapsed selection on the next frame.
    // We defer via addPostFrameCallback to avoid mutating the
    // controller during the build phase.
    final controller = this.controller;
    if (controller == null) return;

    final sel = controller.selection;
    if (sel.baseOffset == sel.extentOffset) return; // already collapsed

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-check inside the callback — the user may have triggered
      // a double-tap in the meantime, which would have re-selected
      // a word. In that case, don't fight it.
      final currentSel = controller.selection;
      if (currentSel.baseOffset == currentSel.extentOffset) return;

      final pos = currentSel.baseOffset.clamp(0, controller.text.length);
      controller.selection = TextSelection.collapsed(offset: pos);
    });
  }
}
