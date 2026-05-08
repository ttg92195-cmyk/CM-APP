class Movie {
  final String id;
  final String title;
  final String slug;
  final String? year;
  final String? poster;
  final String? rating;
  final String? resolution;
  final int? isAdult;
  final List<String> categories;
  final String? type;
  final bool isTrending;

  Movie({
    required this.id,
    required this.title,
    required this.slug,
    this.year,
    this.poster,
    this.rating,
    this.resolution,
    this.isAdult,
    this.categories = const [],
    this.type,
    this.isTrending = false,
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
      isAdult: map['isAdult'] as int?,
      categories: map['categories'] != null
          ? List<String>.from(map['categories'] as List)
          : [],
      type: map['type'] as String?,
      isTrending: map['isTrending'] as bool? ?? false,
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
      'isAdult': isAdult,
      'categories': categories,
      'type': type,
      'isTrending': isTrending,
    };
  }

  String get fullPosterUrl {
    if (poster == null || poster!.isEmpty) return '';
    if (poster!.startsWith('http')) return poster!;
    return '';
  }
}
