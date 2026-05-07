import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cm_movies/app/constants.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/models/movie_year.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 15);

  Future<Map<String, dynamic>> _getRequest(String url) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(_timeout);
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load data: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Trending Movies
  Future<List<Movie>> getTrendingMovies() async {
    final data = await _getRequest(apiMovieTrendingUrl);
    if (data['success'] == true && data['data'] != null) {
      return (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // Trending TV Shows
  Future<List<Movie>> getTrendingTvShows() async {
    final data = await _getRequest(apiTvShowTrendingUrl);
    if (data['success'] == true && data['data'] != null) {
      return (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // Movie Detail
  Future<MovieDetail?> getMovieDetail(String slug) async {
    final data = await _getRequest('$apiMovieUrl/$slug');
    if (data['success'] == true && data['data'] != null) {
      return MovieDetail.fromMap(data['data'] as Map<String, dynamic>);
    }
    return null;
  }

  // Movie Genres
  Future<List<TagAndGenres>> getMovieGenres() async {
    final data = await _getRequest(apiMovieGenresUrl);
    if (data['success'] == true && data['data'] != null) {
      return (data['data'] as List)
          .map((x) => TagAndGenres.fromMap(x as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // Movie Tags
  Future<List<TagAndGenres>> getMovieTags() async {
    final data = await _getRequest(apiMovieTagsUrl);
    if (data['success'] == true && data['data'] != null) {
      return (data['data'] as List)
          .map((x) => TagAndGenres.fromMap(x as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // Movie Years
  Future<List<MovieYear>> getMovieYears() async {
    final data = await _getRequest(apiMovieYearsUrl);
    if (data['success'] == true && data['data'] != null) {
      return (data['data'] as List)
          .map((x) => MovieYear.fromMap(x as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // Movies by Genre
  Future<Map<String, dynamic>> getMoviesByGenre(int genreId, {int page = 1}) async {
    final data = await _getRequest('$apiMovieGenresUrl/$genreId?page=$page');
    if (data['success'] == true) {
      final movies = (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
      final meta = data['meta'] as Map<String, dynamic>?;
      return {
        'movies': movies,
        'current_page': meta?['current_page'] ?? 1,
        'last_page': meta?['last_page'] ?? 1,
        'total': meta?['total'] ?? 0,
      };
    }
    return {'movies': <Movie>[], 'current_page': 1, 'last_page': 1, 'total': 0};
  }

  // Movies by Tag
  Future<Map<String, dynamic>> getMoviesByTag(int tagId, {int page = 1}) async {
    final data = await _getRequest('$apiMovieTagsUrl/$tagId?page=$page');
    if (data['success'] == true) {
      final movies = (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
      final meta = data['meta'] as Map<String, dynamic>?;
      return {
        'movies': movies,
        'current_page': meta?['current_page'] ?? 1,
        'last_page': meta?['last_page'] ?? 1,
        'total': meta?['total'] ?? 0,
      };
    }
    return {'movies': <Movie>[], 'current_page': 1, 'last_page': 1, 'total': 0};
  }

  // Movies by Year
  Future<Map<String, dynamic>> getMoviesByYear(String year, {int page = 1}) async {
    final data = await _getRequest('$apiMovieByYearUrl/$year?page=$page');
    if (data['success'] == true) {
      final movies = (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
      final meta = data['meta'] as Map<String, dynamic>?;
      return {
        'movies': movies,
        'current_page': meta?['current_page'] ?? 1,
        'last_page': meta?['last_page'] ?? 1,
        'total': meta?['total'] ?? 0,
      };
    }
    return {'movies': <Movie>[], 'current_page': 1, 'last_page': 1, 'total': 0};
  }

  // Search
  Future<Map<String, dynamic>> searchMovies(String keyword, {int page = 1}) async {
    final data = await _getRequest('$apiSearchUrl=$keyword&page=$page');
    if (data['success'] == true) {
      final movies = (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
      final meta = data['meta'] as Map<String, dynamic>?;
      return {
        'movies': movies,
        'current_page': meta?['current_page'] ?? 1,
        'last_page': meta?['last_page'] ?? 1,
        'total': meta?['total'] ?? 0,
      };
    }
    return {'movies': <Movie>[], 'current_page': 1, 'last_page': 1, 'total': 0};
  }

  // All Movies (paginated)
  Future<Map<String, dynamic>> getMovies({int page = 1}) async {
    final data = await _getRequest('$apiMovieUrl?page=$page');
    if (data['success'] == true) {
      final movies = (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
      final meta = data['meta'] as Map<String, dynamic>?;
      return {
        'movies': movies,
        'current_page': meta?['current_page'] ?? 1,
        'last_page': meta?['last_page'] ?? 1,
        'total': meta?['total'] ?? 0,
      };
    }
    return {'movies': <Movie>[], 'current_page': 1, 'last_page': 1, 'total': 0};
  }

  // TV Shows (paginated)
  Future<Map<String, dynamic>> getTvShows({int page = 1}) async {
    final data = await _getRequest('$apiTvShowUrl?page=$page');
    if (data['success'] == true) {
      final movies = (data['data'] as List)
          .map((x) => Movie.fromMap(x as Map<String, dynamic>))
          .toList();
      final meta = data['meta'] as Map<String, dynamic>?;
      return {
        'movies': movies,
        'current_page': meta?['current_page'] ?? 1,
        'last_page': meta?['last_page'] ?? 1,
        'total': meta?['total'] ?? 0,
      };
    }
    return {'movies': <Movie>[], 'current_page': 1, 'last_page': 1, 'total': 0};
  }
}
