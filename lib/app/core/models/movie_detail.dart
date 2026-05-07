import 'package:cm_movies/app/constants.dart';
import 'package:cm_movies/app/core/models/movie.dart';

class MovieDetail {
  final int id;
  final String title;
  final String slug;
  final String? year;
  final String? poster;
  final String? overview;
  final List<String> directors;
  final List<CastMember> casts;
  final List<MovieCategory> categories;
  final List<TagItem> tags;
  final List<MovieDownloadLink> downloadLinks;

  MovieDetail({
    required this.id,
    required this.title,
    required this.slug,
    this.year,
    this.poster,
    this.overview,
    this.directors = const [],
    this.casts = const [],
    this.categories = const [],
    this.tags = const [],
    this.downloadLinks = const [],
  });

  factory MovieDetail.fromMap(Map<String, dynamic> map) {
    return MovieDetail(
      id: map['id'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      year: map['year']?.toString(),
      poster: map['poster'] as String?,
      overview: map['overview'] as String?,
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
          ? List<MovieCategory>.from(
              (map['categories'] as List).map(
                (x) => MovieCategory.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
      tags: map['tags'] != null
          ? List<TagItem>.from(
              (map['tags'] as List).map(
                (x) => TagItem.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
      downloadLinks: map['movie_download_links'] != null
          ? List<MovieDownloadLink>.from(
              (map['movie_download_links'] as List).map(
                (x) => MovieDownloadLink.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
    );
  }

  String get fullPosterUrl {
    if (poster == null || poster!.isEmpty) return '';
    if (poster!.startsWith('http')) return poster!;
    return '$hostUrl$poster';
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
      profilePath: map['profile_path'] as String?,
    );
  }

  String get fullProfileUrl {
    if (profilePath == null || profilePath!.isEmpty) return '';
    if (profilePath!.startsWith('http')) return profilePath!;
    return '$hostUrl$profilePath';
  }
}

class TagItem {
  final int id;
  final String name;

  TagItem({
    required this.id,
    required this.name,
  });

  factory TagItem.fromMap(Map<String, dynamic> map) {
    return TagItem(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
    );
  }
}

class MovieDownloadLink {
  final int id;
  final String serverName;
  final String url;
  final String? size;
  final String? quality;
  final String? resolution;
  final int? viewable;

  MovieDownloadLink({
    required this.id,
    required this.serverName,
    required this.url,
    this.size,
    this.quality,
    this.resolution,
    this.viewable,
  });

  factory MovieDownloadLink.fromMap(Map<String, dynamic> map) {
    return MovieDownloadLink(
      id: map['id'] as int? ?? 0,
      serverName: map['server_name'] as String? ?? '',
      url: map['url'] as String? ?? '',
      size: map['size']?.toString(),
      quality: map['quality']?.toString(),
      resolution: map['resolution']?.toString(),
      viewable: map['viewable'] as int?,
    );
  }
}
