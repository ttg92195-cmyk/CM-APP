import 'package:cloud_firestore/cloud_firestore.dart';

class MovieDetail {
  final String id;
  final String title;
  final String slug;
  final String? year;
  final String? poster;
  final String? backdrop;
  final String? overview;
  final String? rating;
  final String? resolution;
  final String? duration;
  final String? format;
  final String? fileSize;
  final int? isAdult;
  final String? type;
  final bool isTrending;
  final int? views;
  final String? country;
  final List<String> directors;
  final List<CastMember> casts;
  final List<String> categories;
  final List<String> tags;
  final List<MovieDownloadLink> downloadLinks;
  final List<MovieWatchLink> watchLinks;
  // Series-specific: seasons with episodes
  final List<Season> seasons;
  final int? tmdbId;
  final DateTime? createdAt;

  MovieDetail({
    required this.id,
    required this.title,
    required this.slug,
    this.year,
    this.poster,
    this.backdrop,
    this.overview,
    this.rating,
    this.resolution,
    this.duration,
    this.format,
    this.fileSize,
    this.isAdult,
    this.type,
    this.isTrending = false,
    this.views,
    this.country,
    this.directors = const [],
    this.casts = const [],
    this.categories = const [],
    this.tags = const [],
    this.downloadLinks = const [],
    this.watchLinks = const [],
    this.seasons = const [],
    this.tmdbId,
    this.createdAt,
  });

  factory MovieDetail.fromMap(Map<String, dynamic> map, {String? docId}) {
    // =========================================================================
    // DEFENSIVE PARSING (Task 31, "An Error Occurred" on detail page)
    //
    // ROOT CAUSE: When a Batch Import JSON file updates an existing movie via
    // `addMovie()` → `_buildSafeUpdateMap()`, list-typed fields like `casts`
    // and `directors` get coerced to List<String>. But `MovieDetail.fromMap`
    // expected `casts` to be a List<Map<String, dynamic>> (for CastMember).
    // So opening the detail page of such a movie threw, and the page showed
    // "An Error Occurred".
    //
    // Same issue applied to: isAdult (int vs bool/string), tmdbId (int vs
    // string), isTrending (bool vs int/string), and nested lists whose
    // elements were not Maps (e.g., `casts: ["Actor A"]`).
    //
    // FIX: This factory now uses defensive parsing helpers that fall back
    // to sensible defaults instead of throwing. A doc with bad data still
    // renders (with some fields empty), so the user can SEE it. Mirrors
    // the same approach already used in `Movie.fromMap` (Task 27).
    // =========================================================================
    return MovieDetail(
      id: docId ?? map['id']?.toString() ?? '',
      title: _parseDetailString(map['title']),
      slug: _parseDetailString(map['slug']),
      year: map['year']?.toString(),
      poster: _parseDetailNullableString(map['poster']),
      backdrop: _parseDetailNullableString(map['backdrop']),
      overview: _parseDetailNullableString(map['overview']),
      rating: map['rating']?.toString(),
      resolution: _parseDetailNullableString(map['resolution']),
      duration: map['duration']?.toString(),
      format: _parseDetailNullableString(map['format']),
      fileSize: map['fileSize']?.toString(),
      isAdult: _parseDetailInt(map['isAdult']),
      type: _parseDetailNullableString(map['type']),
      isTrending: _parseDetailBool(map['isTrending']),
      views: _parseDetailInt(map['views']),
      country: _parseDetailNullableString(map['country']),
      directors: _parseDetailStringList(map['directors']),
      casts: _parseCastMembers(map['casts']),
      categories: _parseDetailStringList(map['categories']),
      tags: _parseDetailStringList(map['tags']),
      downloadLinks: _parseDownloadLinks(map['downloadLinks']),
      watchLinks: _parseWatchLinks(map['watchLinks']),
      seasons: _parseSeasons(map['seasons']),
      tmdbId: _parseDetailInt(map['tmdbId']),
      createdAt: _parseDateTimeDetail(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'slug': slug,
      'year': year,
      'poster': poster,
      'backdrop': backdrop,
      'overview': overview,
      'rating': rating,
      'resolution': resolution,
      'duration': duration,
      'format': format,
      'fileSize': fileSize,
      'isAdult': isAdult,
      'type': type,
      'isTrending': isTrending,
      'views': views,
      'country': country,
      'directors': directors,
      'casts': casts.map((x) => x.toMap()).toList(),
      'categories': categories,
      'tags': tags,
      'downloadLinks': downloadLinks.map((x) => x.toMap()).toList(),
      'watchLinks': watchLinks.map((x) => x.toMap()).toList(),
      'seasons': seasons.map((x) => x.toMap()).toList(),
      'tmdbId': tmdbId,
    };
  }

  String get fullPosterUrl {
    if (poster == null || poster!.isEmpty) return '';
    if (poster!.startsWith('http')) return poster!;
    return '';
  }
}

class CastMember {
  final String name;
  final String? profilePath;

  CastMember({
    required this.name,
    this.profilePath,
  });

  factory CastMember.fromMap(Map<String, dynamic> map) {
    return CastMember(
      name: map['name'] as String? ?? '',
      profilePath: map['profilePath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'profilePath': profilePath,
    };
  }

  String get fullProfileUrl {
    if (profilePath == null || profilePath!.isEmpty) return '';
    if (profilePath!.startsWith('http')) return profilePath!;
    return '';
  }
}

/// Download link - used for download quality/size/server entries
class MovieDownloadLink {
  final String serverName;
  final String url;
  final String? size;
  final String? quality;
  final String? fileName;

  MovieDownloadLink({
    required this.serverName,
    required this.url,
    this.size,
    this.quality,
    this.fileName,
  });

  factory MovieDownloadLink.fromMap(Map<String, dynamic> map) {
    return MovieDownloadLink(
      serverName: map['serverName'] as String? ?? '',
      url: map['url'] as String? ?? '',
      size: map['size']?.toString(),
      quality: map['quality']?.toString(),
      fileName: map['fileName'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'serverName': serverName,
      'url': url,
      'size': size,
      'quality': quality,
    };
    if (fileName != null) map['fileName'] = fileName;
    return map;
  }
}

/// Watch link - used for streaming quality/size/server entries
class MovieWatchLink {
  final String serverName;
  final String url;
  final String? size;
  final String? quality;

  MovieWatchLink({
    required this.serverName,
    required this.url,
    this.size,
    this.quality,
  });

  factory MovieWatchLink.fromMap(Map<String, dynamic> map) {
    return MovieWatchLink(
      serverName: map['serverName'] as String? ?? '',
      url: map['url'] as String? ?? '',
      size: map['size']?.toString(),
      quality: map['quality']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'serverName': serverName,
      'url': url,
      'size': size,
      'quality': quality,
    };
  }
}

class Season {
  final String name;
  final List<Episode> episodes;

  Season({
    required this.name,
    this.episodes = const [],
  });

  factory Season.fromMap(Map<String, dynamic> map) {
    return Season(
      name: map['name'] as String? ?? 'Season 1',
      episodes: map['episodes'] != null
          ? List<Episode>.from(
              (map['episodes'] as List).map(
                (x) => Episode.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'episodes': episodes.map((x) => x.toMap()).toList(),
    };
  }
}

class Episode {
  final String name;
  final String? videoUrl;
  final String? downloadUrl;
  final List<MovieDownloadLink> downloadLinks;
  final List<MovieWatchLink> watchLinks;

  Episode({
    required this.name,
    this.videoUrl,
    this.downloadUrl,
    this.downloadLinks = const [],
    this.watchLinks = const [],
  });

  factory Episode.fromMap(Map<String, dynamic> map) {
    return Episode(
      name: map['name'] as String? ?? 'Episode 1',
      videoUrl: map['videoUrl'] as String?,
      downloadUrl: map['downloadUrl'] as String?,
      downloadLinks: map['downloadLinks'] != null
          ? List<MovieDownloadLink>.from(
              (map['downloadLinks'] as List).map(
                (x) => MovieDownloadLink.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
      watchLinks: map['watchLinks'] != null
          ? List<MovieWatchLink>.from(
              (map['watchLinks'] as List).map(
                (x) => MovieWatchLink.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'downloadLinks': downloadLinks.map((x) => x.toMap()).toList(),
      'watchLinks': watchLinks.map((x) => x.toMap()).toList(),
    };
    if (videoUrl != null) map['videoUrl'] = videoUrl;
    if (downloadUrl != null) map['downloadUrl'] = downloadUrl;
    return map;
  }
}

/// Helper to parse DateTime from Firestore Timestamp, DateTime, Map, or String
DateTime? _parseDateTimeDetail(dynamic value) {
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

// =========================================================================
// DEFENSIVE PARSING HELPERS (Task 31)
//
// Mirrors the helpers in movie.dart but for MovieDetail. Every helper
// here is total — it NEVER throws. Bad input becomes a sensible default
// (empty string, empty list, null, false) so a single corrupted field
// in a Firestore doc can't take down the whole detail page.
// =========================================================================

/// Defensive String parser — never throws. Returns [dflt] for non-String
/// values (e.g., int, bool, null).
String _parseDetailString(dynamic value, [String dflt = '']) {
  if (value is String) return value;
  return dflt;
}

/// Defensive nullable String parser — never throws. Returns null for
/// non-String values OR empty strings.
String? _parseDetailNullableString(dynamic value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// Defensive int parser — never throws. Coerces num/bool/numeric string.
int? _parseDetailInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is bool) return value ? 1 : 0;
  if (value is String) return int.tryParse(value);
  return null;
}

/// Defensive bool parser — never throws. Coerces int/string.
bool _parseDetailBool(dynamic value, [bool dflt = false]) {
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

/// Defensive List<String> parser — never throws.
///   - List<String>           → returned as-is (after filtering empties)
///   - List with mixed types  → each element coerced via toString()
///   - String (non-empty)     → wrapped into a 1-element list
///   - null / empty / other   → empty list
List<String> _parseDetailStringList(dynamic value) {
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

/// Defensive CastMember list parser — never throws.
/// Handles all the bad shapes that Batch Import can leave behind:
///   - List<Map<String, dynamic>>  → proper CastMember list
///   - List<String>                → each string becomes CastMember(name: s)
///   - List with mixed types       → each element coerced to CastMember
///   - String (non-empty)          → 1-element list
///   - null / empty / other        → empty list
///
/// This is the critical fix for the "An Error Occurred" bug: the old code
/// did `(map['casts'] as List).map((x) => CastMember.fromMap(x as Map...))`
/// which throws when `x` is a String (because Batch Import coerced
/// `casts: "Actor A"` to `["Actor A"]`).
List<CastMember> _parseCastMembers(dynamic value) {
  if (value is List) {
    final result = <CastMember>[];
    for (final e in value) {
      if (e == null) continue;
      if (e is Map<String, dynamic>) {
        result.add(CastMember.fromMap(e));
      } else if (e is Map) {
        // Loose Map — copy to Map<String, dynamic> for CastMember.fromMap.
        final cast = <String, dynamic>{};
        e.forEach((k, v) => cast[k.toString()] = v);
        result.add(CastMember.fromMap(cast));
      } else {
        // String, int, etc. — treat the toString() as the actor name.
        final name = e.toString().trim();
        if (name.isNotEmpty) {
          result.add(CastMember(name: name));
        }
      }
    }
    return result;
  }
  if (value is String && value.trim().isNotEmpty) {
    return [CastMember(name: value.trim())];
  }
  return [];
}

/// Defensive MovieDownloadLink list parser — never throws.
/// Same rationale as _parseCastMembers: handles List<Map> (proper),
/// List<String> (loose), and anything else (skipped).
List<MovieDownloadLink> _parseDownloadLinks(dynamic value) {
  if (value is List) {
    final result = <MovieDownloadLink>[];
    for (final e in value) {
      if (e is Map<String, dynamic>) {
        result.add(MovieDownloadLink.fromMap(e));
      } else if (e is Map) {
        final m = <String, dynamic>{};
        e.forEach((k, v) => m[k.toString()] = v);
        result.add(MovieDownloadLink.fromMap(m));
      }
      // String/int — skip; can't coerce to a download link safely.
    }
    return result;
  }
  return [];
}

/// Defensive MovieWatchLink list parser — never throws.
List<MovieWatchLink> _parseWatchLinks(dynamic value) {
  if (value is List) {
    final result = <MovieWatchLink>[];
    for (final e in value) {
      if (e is Map<String, dynamic>) {
        result.add(MovieWatchLink.fromMap(e));
      } else if (e is Map) {
        final m = <String, dynamic>{};
        e.forEach((k, v) => m[k.toString()] = v);
        result.add(MovieWatchLink.fromMap(m));
      }
    }
    return result;
  }
  return [];
}

/// Defensive Season list parser — never throws.
List<Season> _parseSeasons(dynamic value) {
  if (value is List) {
    final result = <Season>[];
    for (final e in value) {
      if (e is Map<String, dynamic>) {
        result.add(Season.fromMap(e));
      } else if (e is Map) {
        final m = <String, dynamic>{};
        e.forEach((k, v) => m[k.toString()] = v);
        result.add(Season.fromMap(m));
      }
    }
    return result;
  }
  return [];
}
