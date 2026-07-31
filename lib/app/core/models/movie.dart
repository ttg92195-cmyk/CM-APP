import 'package:cloud_firestore/cloud_firestore.dart';

class Movie {
  final String id;
  final String title;
  final String titleLowercase; // For case-insensitive Firestore search
  final String slug;
  final String? year;
  final String? poster;
  final String? rating;
  final String? resolution;
  final String? duration;
  final String? seasons;
  final int? isAdult;
  final List<String> categories;
  final String? type;
  final bool isTrending;
  // Phase 4.23 — content rating (e.g. 'PG-13', 'R', 'TV-MA') + TMDB status
  // (e.g. 'Released', 'Returning Series', 'Ended'). Both are nullable for
  // backward compat with docs created before Task 38 Req 2.
  final String? certification;
  final String? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Movie({
    required this.id,
    required this.title,
    required this.titleLowercase,
    required this.slug,
    this.year,
    this.poster,
    this.rating,
    this.resolution,
    this.duration,
    this.seasons,
    this.isAdult,
    this.categories = const [],
    this.type,
    this.isTrending = false,
    this.certification,
    this.status,
    this.createdAt,
    this.updatedAt,
  });

  factory Movie.fromMap(Map<String, dynamic> map, {String? docId}) {
    // =========================================================================
    // DEFENSIVE PARSING (Task 27, "All Posts disappeared" bug)
    //
    // ROOT CAUSE: When a JSON Batch Import file contains a field with the
    // wrong type (e.g., `categories: "Action"` as a string instead of a
    // list, or `isAdult: true` as a bool instead of an int), `addMovie()`
    // writes the wrong-type value to Firestore. Then on the next
    // `getAllPosts()` call, the `.map((doc) => Movie.fromMap(...)).toList()`
    // chain throws on the FIRST corrupted doc — and the exception
    // propagates up. All three fallback tiers in getAllPosts() use the
    // same `Movie.fromMap`, so they ALL throw, and the function returns
    // an empty list. Net effect: ONE corrupted doc makes the ENTIRE
    // Admin Panel All Posts tab appear empty.
    //
    // The TMDB Sync workaround Bro discovered works because Sync
    // overwrites the corrupted fields with proper TMDB data — fixing
    // `Movie.fromMap` for that one doc, which un-breaks the chain.
    //
    // FIX: This factory now uses defensive parsing helpers that fall
    // back to sensible defaults instead of throwing. A doc with bad
    // data still renders (with some fields empty), so the admin can
    // SEE it in the grid and delete/fix it. The grid never goes empty
    // because of one bad doc.
    //
    // The original `as String?`, `as int?`, `as bool?`, `as List`
    // casts were the throwing culprits — they're all replaced below.
    // =========================================================================
    final title = _parseString(map['title']);
    return Movie(
      id: docId ?? map['id']?.toString() ?? '',
      title: title,
      titleLowercase: _parseString(map['title_lowercase'], title.toLowerCase()),
      slug: _parseString(map['slug']),
      year: map['year']?.toString(),
      poster: _parseNullableString(map['poster']),
      rating: map['rating']?.toString(),
      resolution: _parseNullableString(map['resolution']),
      duration: map['duration']?.toString(),
      seasons: map['seasons'] is List
          ? (map['seasons'] as List).length.toString()
          : map['seasons']?.toString(),
      isAdult: _parseInt(map['isAdult']),
      categories: _parseStringList(map['categories']),
      type: _parseNullableString(map['type']),
      isTrending: _parseBool(map['isTrending']),
      certification: _parseNullableString(map['certification']),
      status: _parseNullableString(map['status']),
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'title_lowercase': titleLowercase,
      'slug': slug,
      'year': year,
      'poster': poster,
      'rating': rating,
      'resolution': resolution,
      'duration': duration,
      'seasons': seasons,
      'isAdult': isAdult,
      'categories': categories,
      'type': type,
      'isTrending': isTrending,
      'certification': certification,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  String get fullPosterUrl {
    if (poster == null || poster!.isEmpty) return '';
    if (poster!.startsWith('http')) return poster!;
    return '';
  }

  /// Returns a human-readable time ago string (e.g., "1 day ago", "3 hours ago")
  String get timeAgo {
    if (createdAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(createdAt!);

    if (diff.inDays > 365) {
      final years = (diff.inDays / 365).floor();
      return '$years year${years > 1 ? 's' : ''} ago';
    } else if (diff.inDays > 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months > 1 ? 's' : ''} ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} min ago';
    } else {
      return 'Just now';
    }
  }

  /// Phase 4.21 — Post ကို admin ပြင်လိုက်ပြီလား (updatedAt > createdAt)။
  /// updatedAt နဲ့ createdAt နှစ်ခုလုံး server timestamp ဖြစ်တဲ့အတွက်
  /// ၁ စက္ကန့်ထက်ကွာတာမှ edited အဖြစ် သတ်မှတ်ပါမယ် (false positive ကာကွယ်)။
  bool get wasEdited {
    if (updatedAt == null) return false;
    if (createdAt == null) return true;
    return updatedAt!.difference(createdAt!) > const Duration(seconds: 1);
  }

  /// Phase 4.21 — "Edited 3h ago" စာသား။ edited မဖြစ်ရင် ဆိုင်ရာ display ကို
  /// ချန်ထားဖို့ empty string ပြန်ပါတယ်။
  String get editedAgo {
    if (!wasEdited || updatedAt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(updatedAt!);

    if (diff.inDays > 365) {
      final years = (diff.inDays / 365).floor();
      return 'Edited $years year${years > 1 ? 's' : ''} ago';
    } else if (diff.inDays > 30) {
      final months = (diff.inDays / 30).floor();
      return 'Edited $months month${months > 1 ? 's' : ''} ago';
    } else if (diff.inDays > 0) {
      return 'Edited ${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    } else if (diff.inHours > 0) {
      return 'Edited ${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else if (diff.inMinutes > 0) {
      return 'Edited ${diff.inMinutes} min ago';
    } else {
      return 'Edited just now';
    }
  }
}

/// Helper to parse DateTime from Firestore Timestamp, DateTime, Map, or String
DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is Map && value['_seconds'] != null) {
    return DateTime.fromMillisecondsSinceEpoch(
      (value['_seconds'] as int) * 1000 +
          ((value['_nanoseconds'] as int?) ?? 0) ~/ 1000000,
    );
  }
  return DateTime.tryParse(value.toString());
}

/// Defensive String parser — never throws. Returns [dflt] for non-String
/// values (e.g., int, bool, null). Used by `Movie.fromMap` so a single
/// bad doc doesn't break the entire `.map().toList()` chain.
/// See Task 27 ("All Posts disappeared" bug) for context.
String _parseString(dynamic value, [String dflt = '']) {
  if (value is String) return value;
  return dflt;
}

/// Defensive nullable String parser — never throws. Returns null for
/// non-String values OR empty strings. Used for optional string fields
/// like `poster`, `resolution`, `type` so a bad value just becomes null
/// instead of crashing the grid.
String? _parseNullableString(dynamic value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// Defensive int parser — never throws. Coerces common alternative
/// types (num, bool, numeric string) to int. Returns null for
/// unparseable values. Used for `isAdult` which JSON files sometimes
/// send as bool or string.
int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  if (value is String) return int.tryParse(value);
  return null;
}

/// Defensive bool parser — never throws. Coerces int (0/1), common
/// string forms ("true"/"false"/"1"/"0") to bool. Returns [dflt] for
/// unparseable values. Used for `isTrending` which JSON files sometimes
/// send as int or string.
bool _parseBool(dynamic value, [bool dflt = false]) {
  if (value == null) return dflt;
  if (value is bool) return value;
  if (value is int) return value != 0;
  if (value is String) {
    final s = value.toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return dflt;
}

/// Defensive List<String> parser — never throws. Used for `categories`
/// and `tags`. This is the BIG one — a JSON file with
/// `categories: "Action"` (string instead of list) used to crash the
/// entire Admin Panel All Posts tab. Now:
///   - List<String>           → returned as-is (after filtering empties)
///   - List with mixed types  → each element coerced via toString()
///   - String (non-empty)     → wrapped into a 1-element list (better
///                              than throwing; admin can still see/edit)
///   - null / empty / other   → empty list
List<String> _parseStringList(dynamic value) {
  if (value is List) {
    return value
        .map((e) => e?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    return [value.trim()];
  }
  return [];
}
