import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// ===========================================================================
/// LocalizationService — Task 32 (Phase 1: JSON-driven translations)
/// ===========================================================================
///
/// Architecture (System Architect's strategy):
///
///   ┌──────────────────────┐    rootBundle.loadString    ┌─────────────┐
///   │  assets/lang/en.json │ ──────────────────────────▶ │  Localizer  │
///   │  assets/lang/my.json │ ──────────────────────────▶ │   Service   │
///   └──────────────────────┘                              └──────┬──────┘
///                                                                │ translate(key)
///                                                                ▼
///                                                        ┌──────────────┐
///                                                        │ AppConfig    │
///                                                        │ .translate() │  ← back-compat
///                                                        └──────────────┘
///                                                                │
///                                                                ▼
///                                                        ┌──────────────┐
///                                                        │  UI Widgets  │
///                                                        └──────────────┘
///
/// Why JSON instead of Dart map literals?
///
///   1. Translator-friendliness: non-dev team members can edit translations
///      without touching code.
///   2. Code review hygiene: translation changes don't pollute .dart diffs.
///   3. Hot reload: edit JSON, restart app — no compile needed.
///   4. Future-proof: easy to add new languages (just drop a new file).
///   5. Versioning: each file has `_meta.version` for migration tracking.
///
/// Migration risk mitigation (Bro's concern about losing keys during
/// migration):
///
///   - All 198 keys extracted from app_config.dart via Python script
///     (task32_extract_translations.py), with key-set parity verified
///     between en.json and my.json before write.
///   - Unit test (task32_verify_translations.py) re-runs on every commit
///     to catch any drift.
///   - LocalizationService.translate() logs a warning in dev mode if a
///     key is missing — silent fallback to English value (or key itself).
///   - Existing AppConfig.translate() signature is preserved; all callers
///     in the app keep working without changes.
///
class LocalizationService {
  LocalizationService._();
  static final LocalizationService _instance = LocalizationService._();
  factory LocalizationService() => _instance;

  /// Currently-loaded translations: key → translated string.
  Map<String, String> _translations = {};

  /// English translations — used as fallback if the current language
  /// is missing a key.
  Map<String, String> _englishFallback = {};

  /// Currently active language code ('en' or 'my').
  String _languageCode = 'en';

  /// Version of the currently-loaded translation file (from `_meta.version`).
  /// Used for migration tracking — Bro's versioning concern.
  String _version = '';

  /// Last-updated date stamp from `_meta.lastUpdated`.
  String _lastUpdated = '';

  /// Track which keys have been requested but were missing in the current
  /// language. In dev mode, these are logged once per key to avoid spam.
  /// In release mode, this set still grows (cheap) but logs are suppressed.
  final Set<String> _missingKeyWarnings = {};

  /// True once [_load] has succeeded at least once.
  bool _isInitialized = false;

  /// Supported language codes (for `MaterialApp.supportedLocales`).
  static const supportedLocales = ['en', 'my'];

  /// English (source language) — used as the canonical key list.
  static const String defaultLanguage = 'en';

  // ------------------- Public API -------------------

  /// Current language code.
  String get languageCode => _languageCode;

  /// Version of the currently-loaded translation file.
  String get version => _version;

  /// Last-updated stamp of the currently-loaded translation file.
  String get lastUpdated => _lastUpdated;

  /// Whether [load] has completed at least once.
  bool get isInitialized => _isInitialized;

  /// Load translations for the given language code from the asset bundle.
  ///
  /// This is safe to call multiple times — each call replaces the
  /// currently-loaded translations. Called by AppConfig on startup and
  /// whenever the user changes language via Settings.
  Future<void> load(String languageCode) async {
    _languageCode = languageCode;

    // Always load English as fallback, even if current language is English.
    // (If user is on 'en' already, this is a no-op cache-wise.)
    if (_englishFallback.isEmpty || languageCode != 'en') {
      _englishFallback = await _loadJsonForLanguage('en');
    }

    if (languageCode == 'en') {
      _translations = _englishFallback;
    } else {
      _translations = await _loadJsonForLanguage(languageCode);
    }

    // Extract _meta block (Task 32-f: versioning).
    // _loadJsonForLanguage() already strips _meta and returns Map<String,String>,
    // so we re-read the raw JSON to access _meta while it's still dynamic.
    // The rootBundle cache makes this second load negligible.
    _version = '';
    _lastUpdated = '';
    try {
      final raw = await rootBundle.loadString('assets/lang/$languageCode.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final meta = decoded['_meta'];
      if (meta is Map) {
        _version = meta['version']?.toString() ?? '';
        _lastUpdated = meta['lastUpdated']?.toString() ?? '';
      }
    } catch (e) {
      debugPrint('[LocalizationService] Failed to extract _meta: $e');
    }

    _isInitialized = true;
    debugPrint(
      '[LocalizationService] Loaded "$languageCode": ${_translations.length} keys, '
      'version=$_version, lastUpdated=$_lastUpdated',
    );
  }

  /// Translate a key. Returns the translated string for the current
  /// language, or the English value if missing, or the key itself if
  /// missing in both.
  ///
  /// Optional named arguments support parameter substitution:
  ///   translate('vip_expires_on', namedArgs: {'date': '2026-12-31'})
  ///   → "Expires: 2026-12-31"   (en)
  ///   → "သက်တမ်း: 2026-12-31"   (my)
  ///
  /// The placeholder syntax in JSON is `{name}` (single-brace) — matches
  /// the existing convention already used by `vip_expires_on` and
  /// `too_many_attempts` in the original translations.
  String translate(String key, {Map<String, String>? namedArgs}) {
    var value = _translations[key];
    if (value == null) {
      // Try English fallback.
      value = _englishFallback[key];
      if (value == null) {
        // Key missing from both — log in dev mode, return the key as-is.
        if (kDebugMode && !_missingKeyWarnings.contains(key)) {
          _missingKeyWarnings.add(key);
          debugPrint(
            '[LocalizationService] WARNING: missing translation key "$key" '
            'in both "$_languageCode" and "en". Returning key as-is.',
          );
        }
        return key;
      }
      // Key missing in current language but present in English — log once.
      if (kDebugMode && !_missingKeyWarnings.contains(key)) {
        _missingKeyWarnings.add(key);
        debugPrint(
          '[LocalizationService] NOTE: key "$key" missing in '
          '"$_languageCode", fell back to English.',
        );
      }
    }

    // Parameter substitution: replace {name} placeholders.
    if (namedArgs != null && namedArgs.isNotEmpty) {
      namedArgs.forEach((argKey, argValue) {
        value = value!.replaceAll('{$argKey}', argValue);
      });
    }
    return value!;
  }

  /// Returns true if the key exists in the current language OR in English.
  bool hasKey(String key) {
    return _translations.containsKey(key) || _englishFallback.containsKey(key);
  }

  /// All keys in the current language (excludes `_meta`).
  /// Useful for the parity-check unit test.
  Set<String> get keys => _translations.keys.toSet();

  /// All keys in the English fallback file (excludes `_meta`).
  /// This is the canonical key set.
  Set<String> get englishKeys => _englishFallback.keys.toSet();

  // ------------------- Internals -------------------

  Future<Map<String, String>> _loadJsonForLanguage(String code) async {
    try {
      final raw = await rootBundle.loadString('assets/lang/$code.json');
      final decoded = json.decode(raw) as Map<String, dynamic>;
      // Coerce all values to String — JSON values are always String in our
      // translation files, but be defensive in case a future editor adds
      // a number/bool by mistake.
      final result = <String, String>{};
      decoded.forEach((k, v) {
        if (k == '_meta') return; // skip meta block
        result[k] = v?.toString() ?? '';
      });
      return result;
    } catch (e) {
      debugPrint(
        '[LocalizationService] FATAL: failed to load assets/lang/$code.json: $e',
      );
      // Return empty map — translate() will fall back to keys as-is.
      // This is degraded behavior but never crashes the app.
      return {};
    }
  }
}
