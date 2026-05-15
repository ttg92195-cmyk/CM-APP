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
    return MovieDetail(
      id: docId ?? map['id']?.toString() ?? '',
      title: map['title'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      year: map['year']?.toString(),
      poster: map['poster'] as String?,
      backdrop: map['backdrop'] as String?,
      overview: map['overview'] as String?,
      rating: map['rating']?.toString(),
      resolution: map['resolution'] as String?,
      duration: map['duration']?.toString(),
      format: map['format'] as String?,
      fileSize: map['fileSize']?.toString(),
      isAdult: map['isAdult'] as int?,
      type: map['type'] as String?,
      isTrending: map['isTrending'] as bool? ?? false,
      views: map['views'] as int?,
      country: map['country'] as String?,
      directors: map['directors'] != null
          ? List<String>.from(
              (map['directors'] as List).map((x) => x.toString()),
            )
          : [],
      casts: map['casts'] != null
          ? List<CastMember>.from(
              (map['casts'] as List).map(
                (x) => CastMember.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
      categories: map['categories'] != null
          ? List<String>.from(map['categories'] as List)
          : [],
      tags: map['tags'] != null
          ? List<String>.from(map['tags'] as List)
          : [],
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
      seasons: map['seasons'] != null
          ? List<Season>.from(
              (map['seasons'] as List).map(
                (x) => Season.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
      tmdbId: map['tmdbId'] as int?,
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

  String get fullBackdropUrl {
    if (backdrop == null || backdrop!.isEmpty) return '';
    if (backdrop!.startsWith('http')) return backdrop!;
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
