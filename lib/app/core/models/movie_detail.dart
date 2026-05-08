class MovieDetail {
  final String id;
  final String title;
  final String slug;
  final String? year;
  final String? poster;
  final String? overview;
  final String? rating;
  final String? resolution;
  final int? isAdult;
  final String? type;
  final bool isTrending;
  final List<String> directors;
  final List<CastMember> casts;
  final List<String> categories;
  final List<String> tags;
  final List<MovieDownloadLink> downloadLinks;

  MovieDetail({
    required this.id,
    required this.title,
    required this.slug,
    this.year,
    this.poster,
    this.overview,
    this.rating,
    this.resolution,
    this.isAdult,
    this.type,
    this.isTrending = false,
    this.directors = const [],
    this.casts = const [],
    this.categories = const [],
    this.tags = const [],
    this.downloadLinks = const [],
  });

  factory MovieDetail.fromMap(Map<String, dynamic> map, {String? docId}) {
    return MovieDetail(
      id: docId ?? map['id']?.toString() ?? '',
      title: map['title'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      year: map['year']?.toString(),
      poster: map['poster'] as String?,
      overview: map['overview'] as String?,
      rating: map['rating']?.toString(),
      resolution: map['resolution'] as String?,
      isAdult: map['isAdult'] as int?,
      type: map['type'] as String?,
      isTrending: map['isTrending'] as bool? ?? false,
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'slug': slug,
      'year': year,
      'poster': poster,
      'overview': overview,
      'rating': rating,
      'resolution': resolution,
      'isAdult': isAdult,
      'type': type,
      'isTrending': isTrending,
      'directors': directors,
      'casts': casts.map((x) => x.toMap()).toList(),
      'categories': categories,
      'tags': tags,
      'downloadLinks': downloadLinks.map((x) => x.toMap()).toList(),
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

class MovieDownloadLink {
  final String serverName;
  final String url;
  final String? size;
  final String? quality;
  final String? resolution;

  MovieDownloadLink({
    required this.serverName,
    required this.url,
    this.size,
    this.quality,
    this.resolution,
  });

  factory MovieDownloadLink.fromMap(Map<String, dynamic> map) {
    return MovieDownloadLink(
      serverName: map['serverName'] as String? ?? '',
      url: map['url'] as String? ?? '',
      size: map['size']?.toString(),
      quality: map['quality']?.toString(),
      resolution: map['resolution']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'serverName': serverName,
      'url': url,
      'size': size,
      'quality': quality,
      'resolution': resolution,
    };
  }
}
