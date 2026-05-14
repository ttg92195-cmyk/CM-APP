import 'package:cloud_firestore/cloud_firestore.dart';

class Movie {
  final String id;
  final String title;
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
  final DateTime? createdAt;

  Movie({
    required this.id,
    required this.title,
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
    this.createdAt,
  });

  factory Movie.fromMap(Map<String, dynamic> map, {String? docId}) {
    return Movie(
      id: docId ?? map['id']?.toString() ?? '',
      title: map['title'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      year: map['year']?.toString(),
      poster: map['poster'] as String?,
      rating: map['rating']?.toString(),
      resolution: map['resolution'] as String?,
      duration: map['duration']?.toString(),
      seasons: map['seasons'] is List ? (map['seasons'] as List).length.toString() : map['seasons']?.toString(),
      isAdult: map['isAdult'] as int?,
      categories: map['categories'] != null
          ? List<String>.from(map['categories'] as List)
          : [],
      type: map['type'] as String?,
      isTrending: map['isTrending'] as bool? ?? false,
      createdAt: _parseDateTime(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
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
      'createdAt': createdAt?.toIso8601String(),
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
