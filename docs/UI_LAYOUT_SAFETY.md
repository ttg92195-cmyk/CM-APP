# UI Layout Safety Guidelines (Task 33 / Phase 2)

> Goal: never let text silently overflow, clip, or break a card layout —
> regardless of language, screen size, or content length.

## Why this matters

After Task 32 (Localization), the app supports Myanmar (`my`) in addition
to English (`en`). Myanmar text is **denser** than English:

| English              | Myanmar              | Glyphs |
| -------------------- | -------------------- | ------ |
| Continue Watching    | ဆက်ကြည့်ရန်            | ~6     |
| Trending Now         | လူကြည့်အများဆုံး        | ~10    |
| Download             | ဒေါင်းလုဒ်              | ~5     |

A single English word can expand to a multi-word Myanmar phrase, and
the visual width grows accordingly. Plain `Text` widgets that fit
perfectly in English can suddenly overflow in Myanmar — and the
overflow is **completely silent in release builds** (the user just sees
clipped text or a misaligned card with no error reported).

## The four rules

### Rule 1 — Every dynamic `Text` gets `maxLines` + `overflow`

```dart
// ❌ Bad — text can wrap indefinitely or clip silently
Text(
  movie.title,
  style: theme.textTheme.titleMedium,
)

// ✅ Good — predictable truncation
Text(
  movie.title,
  maxLines: 2,
  overflow: TextOverflow.ellipsis,
  style: theme.textTheme.titleMedium,
)

// ✅ Best — use SafeText helper (defaults: maxLines=2, overflow=ellipsis)
SafeText(
  movie.title,
  style: theme.textTheme.titleMedium,
  maxLines: 1, // override default if needed
)
```

**When to apply:**
- Any string from `appConfig.translate('...')` (translations).
- Any string from Firestore (movie titles, descriptions, cast names).
- Any string from user input.
- Any `Text` inside a `Row` + `Expanded` / `Flexible`.
- Any `Text` inside a grid cell or list item with bounded width.

**When plain `Text` is OK:**
- Short static labels with known English length that fit comfortably.
- Headlines that are intentionally allowed to wrap to multiple lines
  inside a wide column (e.g., article body text).

### Rule 2 — `Row` + `Text` always needs `Expanded` or `Flexible`

```dart
// ❌ Bad — RenderFlex overflow when text is wider than remaining space
Row(
  children: [
    Icon(Icons.star),
    Text(movie.title), // ← unbounded in a Row → overflow
  ],
)

// ✅ Good
Row(
  children: [
    Icon(Icons.star),
    Expanded(
      child: SafeText(movie.title, maxLines: 1),
    ),
  ],
)
```

### Rule 3 — Use `Wrap` for variable-count chips

```dart
// ❌ Bad — Row will overflow when there are 6+ categories
Row(
  children: movie.categories.map((c) => Chip(label: Text(c))).toList(),
)

// ✅ Good — Wrap flows to next line
Wrap(
  spacing: 6,
  runSpacing: 4,
  children: movie.categories.map((c) => Chip(label: Text(c))).toList(),
)
```

### Rule 4 — Test in both languages

Before merging any UI change:
1. Switch language to Myanmar (Settings → Language → မြန်မာ).
2. Navigate to the affected screen.
3. Verify no truncation surprises, no clipped text, no misaligned cards.
4. Switch back to English and confirm it still fits.

## Helpers provided

### `SafeText` — `lib/app/ui/components/safe_text.dart`

Drop-in replacement for `Text` with safe defaults:

```dart
SafeText(
  'Some text that might be long',
  style: theme.textTheme.bodyMedium,
  maxLines: 2,           // default
  overflow: TextOverflow.ellipsis,  // default
)
```

Use this for any new UI code. Existing `Text` widgets are not
auto-migrated — migrate them when you touch the surrounding widget
and can verify the change visually.

### `DebugOverflowDetector` — `lib/app/core/services/debug_overflow_detector.dart`

Captures `RenderFlex` overflow errors in **debug mode only**. For each
unique overflow per session:

1. Logs to `debugPrint` with `[Overflow]` prefix + first 8 stack frames.
2. Shows a floating red `SnackBar` (one per unique overflow signature).
3. Deduplicates — same overflow on every rebuild → one log entry, one
   SnackBar.

**Wired in `main.dart`:**
- `scaffoldMessengerKey` global key for SnackBar access.
- `DebugOverflowDetector.instance.install(scaffoldMessengerKey: ...)` is
  called at the top of `main()`, before `FlutterError.onError` is set.
- The detector saves and forwards to the previously-installed
  `FlutterError.onError` handler, so existing error logging is
  preserved.

**Release mode:** `install()` is a silent no-op. No handler attached,
no SnackBar ever shown. The class remains in the binary (tiny) so dev
and prod have identical Dart code paths — no "works in dev, fails in
prod" surprises.

## What to do when the SnackBar pops

If you see `⚠️ Layout overflow detected:` during development:

1. **Read the message** — it tells you which `RenderFlex` overflowed and
   by how many pixels, plus the direction (`on the right edge` /
   `on the bottom`).
2. **Tap "Logs"** on the SnackBar to dump all overflow signatures seen
   this session.
3. **Find the source widget** — the printed stack trace's first 8
   frames usually point at the offending `Row`, `Column`, or `Flex`.
4. **Apply the rules above** — usually it's a missing `Expanded` or a
   missing `maxLines` on a dynamic `Text`.
5. **Hot reload** — the SnackBar will not reappear for the same
   signature once fixed (the dedup set clears only on app restart).

## Known risky spots (audit notes)

The following spots were audited in Task 33 and **already** follow the
rules — keep them in mind as reference examples:

- `lib/app/ui/components/movie_card.dart` — title, year, season, duration,
  watch progress all use `maxLines: 1, overflow: TextOverflow.ellipsis`
  inside `Flexible` wrappers.
- `lib/app/ui/screens/movie_detail_screen.dart` — title uses `maxLines: 2`
  + `ellipsis`; `_detailRow()` was patched to use `maxLines: 1` for label
  and `maxLines: 3` for value; cast names use `maxLines: 2`.
- `lib/app/ui/screens/series_detail_screen.dart` — title uses `maxLines: 2`;
  related-series cards use `maxLines: 2`.

The following spot was **patched** in Task 33:

- `lib/app/ui/home/trending_movie_component.dart` — section title and
  "More" button label were plain `Text` inside `Expanded` without
  `maxLines`. Switched to `SafeText(maxLines: 1)`.

## Migration backlog

The following files have `Text` widgets that **may** need migration but
were not touched in Task 33 because they currently render fine and the
churn was too risky for a single commit. Migrate opportunistically:

- `lib/app/ui/screens/profile_page.dart` — 46 `Text` widgets, several
  without `maxLines` in profile rows.
- `lib/app/ui/screens/admin_panel_page.dart` — 59 `Text` widgets, mostly
  admin-only so lower priority.
- `lib/app/ui/screens/edit_movie_page.dart` — 98 `Text` widgets (admin
  form labels — usually short).
- `lib/app/ui/screens/add_movie_page.dart`, `add_series_page.dart` —
  similar admin form labels.

The dev-mode `DebugOverflowDetector` will surface any actual overflow
when Bro tests the app in Myanmar — at that point we patch the specific
widget rather than mass-migrating.

## Lint aspiration (future)

Dart's built-in linter does not have a "Text must have maxLines" rule.
A custom lint could enforce this, but the cost (custom lint package,
CI integration, false positives on intentionally-wrapping headlines)
outweighs the benefit for a small team. The `SafeText` helper +
`DebugOverflowDetector` SnackBar + this document is the practical
middle ground.

If a future team member wants stronger enforcement, the path is:

1. Write a custom lint in a separate package using
   `custom_lint` (pub.dev/packages/custom_lint).
2. Add it to `analysis_options.yaml`.
3. Run in CI on every PR.

For now: code review + dev-mode SnackBar catches issues early enough.
