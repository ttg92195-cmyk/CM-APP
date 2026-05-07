import 'package:cm_movies/app/constants.dart';

class Movie {
  final int id;
  final String title;
  final String slug;
  final String? year;
  final String? poster;
  final String? rating;
  final String? resolution;
  final int? isAdult;
  final List<MovieCategory> categories;
  final String? type;

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
  });

  factory Movie.fromMap(Map<String, dynamic> map) {
    return Movie(
      id: map['id'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      slug: map['slug'] as String? ?? '',
      year: map['year']?.toString(),
      poster: map['poster'] as String?,
      rating: map['rating']?.toString(),
      resolution: map['resolution'] as String?,
      isAdult: map['is_adult'] as int?,
      categories: map['categories'] != null
          ? List<MovieCategory>.from(
              (map['categories'] as List).map(
                (x) => MovieCategory.fromMap(x as Map<String, dynamic>),
              ),
            )
          : [],
      type: map['type'] as String?,
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
      'is_adult': isAdult,
      'categories': categories.map((x) => x.toMap()).toList(),
      'type': type,
    };
  }

  String get fullPosterUrl {
    if (poster == null || poster!.isEmpty) return '';
    if (poster!.startsWith('http')) return poster!;
    return '$hostUrl$poster';
  }
}

class MovieCategory {
  final int id;
  final String name;

  MovieCategory({
    required this.id,
    required this.name,
  });

  factory MovieCategory.fromMap(Map<String, dynamic> map) {
    return MovieCategory(
      id: map['id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }
}
