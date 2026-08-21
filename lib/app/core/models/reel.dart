// =============================================================================
// Phase 4 Step A — Reels Data Model
// =============================================================================
// A "Reel" is a short-form vertical-video post designed for the new "Reels"
// tab in the app's bottom navigation. Reels are stored in a SEPARATE
// Firestore collection (`reels`) from regular Movies/Series — they are
// not catalogued content, they are social-media-style snackable clips
// that the admin curates independently.
//
// Schema (Firestore `reels/{reelId}`):
//   id              : string  (auto from docId)
//   title           : string  (required, non-empty)
//   title_lowercase : string  (required, for case-insensitive search)
//   slug            : string  (optional, URL-safe identifier)
//   description     : string  (optional, longer caption)
//   posterUrl       : string  (optional, thumbnail shown in 3-col grid)
//   videoUrl        : string  (required, the main vertical video URL)
//   episodes        : list<map> optional — multi-episode reels (see ReelEpisode)
//                       [{title:string, videoUrl:string, thumbnailUrl:string?}]
//   downloadLinks   : list<string> optional — direct download URLs
//   likeCount       : int     (optional, default 0; denormalized for fast UI)
//   isTrending      : bool    (optional, default false)
//   createdAt       : timestamp (serverTimestamp when admin creates)
//   updatedAt       : timestamp (serverTimestamp on edit)
//
// Defensive parsing follows the same pattern as Movie.fromMap() so a
// single bad doc never breaks the grid. See Movie model for the rationale.
// =============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// A single episode within a Reel. Reels can be either single-video (no
/// episodes) or multi-episode (e.g. "Episode 1", "Episode 2", ...).
/// When the user taps the Episodes icon on the Reels video player, a
/// bottom-sheet modal lists all episodes; selecting one switches the
/// player's video URL and auto-plays.
class ReelEpisode {
  final String title;
  final String videoUrl;
  final String? thumbnailUrl;

  const ReelEpisode({
    required this.title,
    required this.videoUrl,
    this.thumbnailUrl,
  });

  factory ReelEpisode.fromMap(Map<String, dynamic> map) {
    return ReelEpisode(
      title: _parseString(map['title'], 'Episode'),
      videoUrl: _parseString(map['videoUrl']),
      thumbnailUrl: _parseNullableString(map['thumbnailUrl']),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'videoUrl': videoUrl,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      };
}

/// The main Reel model. See file header for schema documentation.
class Reel {
  final String id;
  final String title;
  final String titleLowercase;
  final String? slug;
  final String? description;
  final String? posterUrl;
  final String videoUrl;
  final List<ReelEpisode> episodes;
  final List<String> downloadLinks;
  final int likeCount;
  final bool isTrending;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Reel({
    required this.id,
    required this.title,
    required this.titleLowercase,
    this.slug,
    this.description,
    this.posterUrl,
    required this.videoUrl,
    this.episodes = const [],
    this.downloadLinks = const [],
    this.likeCount = 0,
    this.isTrending = false,
    this.createdAt,
    this.updatedAt,
  });

  /// True if this Reel has more than one episode. Used by the UI to decide
  /// whether to show the Episodes icon on the player overlay.
  bool get hasEpisodes => episodes.length > 1;

  /// Total number of episodes (minimum 1 — the main videoUrl counts as
  /// episode 1 when no explicit episodes list is provided).
  int get episodeCount => episodes.isNotEmpty ? episodes.length : 1;

  /// Returns the video URL for [index]. If [episodes] is empty, the main
  /// [videoUrl] is returned for index 0 and null for any other index.
  /// Used by the Reels video player when switching episodes.
  String? videoUrlForEpisode(int index) {
    if (episodes.isEmpty) {
      return index == 0 ? videoUrl : null;
    }
    if (index < 0 || index >= episodes.length) return null;
    return episodes[index].videoUrl;
  }

  /// Returns the episode title for [index]. Falls back to "Episode N"
  /// when no explicit episodes list exists.
  String episodeTitleForIndex(int index) {
    if (episodes.isEmpty) {
      return index == 0 ? title : 'Episode ${index + 1}';
    }
    if (index < 0 || index >= episodes.length) return 'Episode ${index + 1}';
    return episodes[index].title;
  }

  factory Reel.fromMap(Map<String, dynamic> map, {String? docId}) {
    final title = _parseString(map['title']);
    final videoUrl = _parseString(map['videoUrl']);
    return Reel(
      id: docId ?? map['id']?.toString() ?? '',
      title: title,
      titleLowercase: _parseString(map['title_lowercase'], title.toLowerCase()),
      slug: _parseNullableString(map['slug']),
      description: _parseNullableString(map['description']),
      posterUrl: _parseNullableString(map['posterUrl']),
      videoUrl: videoUrl,
      episodes: _parseEpisodeList(map['episodes']),
      downloadLinks: _parseStringList(map['downloadLinks']),
      likeCount: _parseInt(map['likeCount']) ?? 0,
      isTrending: _parseBool(map['isTrending']),
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'title_lowercase': titleLowercase,
      if (slug != null) 'slug': slug,
      if (description != null) 'description': description,
      if (posterUrl != null) 'posterUrl': posterUrl,
      'videoUrl': videoUrl,
      'episodes': episodes.map((e) => e.toMap()).toList(),
      'downloadLinks': downloadLinks,
      'likeCount': likeCount,
      'isTrending': isTrending,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// Returns a copy of this Reel with the given fields replaced. Useful
  /// for admin edit operations and for toggling like state in the UI
  /// without mutating the model.
  Reel copyWith({
    String? id,
    String? title,
    String? titleLowercase,
    String? slug,
    String? description,
    String? posterUrl,
    String? videoUrl,
    List<ReelEpisode>? episodes,
    List<String>? downloadLinks,
    int? likeCount,
    bool? isTrending,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Reel(
      id: id ?? this.id,
      title: title ?? this.title,
      titleLowercase: titleLowercase ?? this.titleLowercase,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      posterUrl: posterUrl ?? this.posterUrl,
      videoUrl: videoUrl ?? this.videoUrl,
      episodes: episodes ?? this.episodes,
      downloadLinks: downloadLinks ?? this.downloadLinks,
      likeCount: likeCount ?? this.likeCount,
      isTrending: isTrending ?? this.isTrending,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Human-readable "time ago" string for the grid thumbnail overlay
  /// (e.g., "2 days ago"). Same format as Movie.timeAgo so the UI
  /// feels consistent across Movies and Reels.
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
}

// =============================================================================
// Defensive parsing helpers — mirror Movie.dart's helpers exactly.
// Duplicated here (rather than shared) so the Reel model is self-contained
// and has no implicit dependency on Movie.dart. See Task 27 ("All Posts
// disappeared" bug) for the rationale behind defensive parsing.
// =============================================================================

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

String _parseString(dynamic value, [String dflt = '']) {
  if (value is String) return value;
  return dflt;
}

String? _parseNullableString(dynamic value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

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

List<ReelEpisode> _parseEpisodeList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map((m) => ReelEpisode.fromMap(m))
      .where((e) => e.videoUrl.isNotEmpty)
      .toList();
}
