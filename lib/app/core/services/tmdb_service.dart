import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class TmdbService {
  static const String _apiKey = '2e928cd76f7f5ae46f6e022f5dcc2612';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    queryParameters: {'api_key': _apiKey},
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  // Rate limiter: max 8 requests per second
  final List<DateTime> _requestTimestamps = [];
  static const int _maxRequestsPerSecond = 7; // keep slightly under 8 for safety
  static const Duration _rateLimitWindow = Duration(seconds: 1);

  Future<void> _rateLimit() async {
    final now = DateTime.now();
    // Remove timestamps older than 1 second
    _requestTimestamps.removeWhere(
      (ts) => now.difference(ts) > _rateLimitWindow,
    );

    if (_requestTimestamps.length >= _maxRequestsPerSecond) {
      // Wait until the oldest request in the window expires
      final oldest = _requestTimestamps.first;
      final waitDuration = _rateLimitWindow - now.difference(oldest);
      if (waitDuration.isNegative) return;
      await Future.delayed(waitDuration + const Duration(milliseconds: 50));
    }

    _requestTimestamps.add(DateTime.now());
  }

  Future<Response> _get(String path, {Map<String, dynamic>? queryParams}) async {
    await _rateLimit();
    try {
      final response = await _dio.get(path, queryParameters: queryParams);
      return response;
    } on DioException catch (e) {
      debugPrint('TMDB API Error: ${e.message} - Path: $path');
      rethrow;
    }
  }

  // ==================== DISCOVER ====================

  /// Discover movies with optional filters
  Future<Map<String, dynamic>> discoverMovies({
    int? genre,
    String? year,
    String language = 'en-US',
    String sortBy = 'popularity.desc',
    int page = 1,
  }) async {
    final params = <String, dynamic>{
      'language': language,
      'sort_by': sortBy,
      'page': page,
      'vote_count.gte': 50, // filter out movies with too few votes
    };
    if (genre != null) params['with_genres'] = genre.toString();
    if (year != null) params['primary_release_year'] = year;

    final response = await _get('/discover/movie', queryParams: params);
    return response.data as Map<String, dynamic>;
  }

  /// Discover TV series with optional filters
  Future<Map<String, dynamic>> discoverTV({
    int? genre,
    String? year,
    String language = 'en-US',
    String sortBy = 'popularity.desc',
    int page = 1,
  }) async {
    final params = <String, dynamic>{
      'language': language,
      'sort_by': sortBy,
      'page': page,
      'vote_count.gte': 50,
    };
    if (genre != null) params['with_genres'] = genre.toString();
    if (year != null) params['first_air_date_year'] = year;

    final response = await _get('/discover/tv', queryParams: params);
    return response.data as Map<String, dynamic>;
  }

  // ==================== DETAILS ====================

  /// Get full movie details with credits
  Future<Map<String, dynamic>> getMovieDetails(int tmdbId) async {
    final response = await _get(
      '/movie/$tmdbId',
      queryParams: {'append_to_response': 'credits'},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Get full TV details with credits
  Future<Map<String, dynamic>> getTVDetails(int tmdbId) async {
    final response = await _get(
      '/tv/$tmdbId',
      queryParams: {'append_to_response': 'credits'},
    );
    return response.data as Map<String, dynamic>;
  }

  // ==================== GENRES ====================

  /// Get movie genres from TMDB
  Future<List<Map<String, dynamic>>> getMovieGenres() async {
    final response = await _get('/genre/movie/list');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['genres'] ?? []);
  }

  /// Get TV genres from TMDB
  Future<List<Map<String, dynamic>>> getTVGenres() async {
    final response = await _get('/genre/tv/list');
    final data = response.data as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['genres'] ?? []);
  }

  // ==================== SEARCH ====================

  /// Search movies by title
  Future<Map<String, dynamic>> searchMovies(String query, {int page = 1}) async {
    final response = await _get(
      '/search/movie',
      queryParams: {'query': query, 'page': page},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Search TV series by title
  Future<Map<String, dynamic>> searchTV(String query, {int page = 1}) async {
    final response = await _get(
      '/search/tv',
      queryParams: {'query': query, 'page': page},
    );
    return response.data as Map<String, dynamic>;
  }

  // ==================== HELPER: IMAGE URL ====================

  /// Get full poster URL from a relative path
  static String getPosterUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase$path';
  }

  /// Get full backdrop URL from a relative path
  static String getBackdropUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase$path';
  }

  // ==================== DATA MAPPING ====================

  /// Map TMDB genre IDs to genre names using the provided genre map
  static List<String> mapGenreIdsToNames(List<dynamic>? genreIds, Map<int, String> genreMap) {
    if (genreIds == null) return [];
    return genreIds
        .whereType<int>()
        .map((id) => genreMap[id] ?? 'Unknown')
        .where((name) => name != 'Unknown')
        .toList();
  }

  /// Extract director names from movie credits
  static List<String> extractDirectors(Map<String, dynamic>? credits) {
    if (credits == null) return [];
    final crew = credits['crew'] as List?;
    if (crew == null) return [];
    return crew
        .whereType<Map<String, dynamic>>()
        .where((person) => person['job'] == 'Director')
        .map((person) => person['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  /// Extract creator names from TV series created_by field
  static List<String> extractCreators(List<dynamic>? createdBy) {
    if (createdBy == null) return [];
    return createdBy
        .whereType<Map<String, dynamic>>()
        .map((creator) => creator['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  /// Extract top N cast members from credits
  static List<Map<String, String>> extractTopCast(Map<String, dynamic>? credits, {int count = 10}) {
    if (credits == null) return [];
    final cast = credits['cast'] as List?;
    if (cast == null) return [];
    return cast
        .whereType<Map<String, dynamic>>()
        .take(count)
        .map((person) => {
              'name': person['name']?.toString() ?? '',
              'profilePath': person['profile_path'] != null
                  ? getPosterUrl(person['profile_path'].toString())
                  : '',
            })
        .where((cast) => cast['name']!.isNotEmpty)
        .toList();
  }

  /// Map TMDB movie data to Firestore schema
  static Map<String, dynamic> mapMovieToFirestore(
    Map<String, dynamic> tmdbMovie,
    Map<int, String> genreMap,
  ) {
    final genreIds = tmdbMovie['genre_ids'] as List<dynamic>? ?? [];
    final genreNames = mapGenreIdsToNames(genreIds, genreMap);

    final credits = tmdbMovie['credits'] as Map<String, dynamic>?;
    final directors = extractDirectors(credits);
    final casts = extractTopCast(credits);

    final releaseDate = tmdbMovie['release_date']?.toString() ?? '';
    final year = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null;

    final originCountry = tmdbMovie['origin_country'] as List<dynamic>?;
    final country = (originCountry != null && originCountry.isNotEmpty)
        ? originCountry.first.toString()
        : null;

    return {
      'title': tmdbMovie['title'] ?? tmdbMovie['name'] ?? '',
      'slug': '', // Will be auto-generated by FirestoreContentService
      'year': year,
      'poster': getPosterUrl(tmdbMovie['poster_path']?.toString()),
      'backdrop': getBackdropUrl(tmdbMovie['backdrop_path']?.toString()),
      'overview': tmdbMovie['overview']?.toString() ?? '',
      'rating': (tmdbMovie['vote_average'] ?? 0).toDouble().toStringAsFixed(1),
      'type': 'movie',
      'isAdult': tmdbMovie['adult'] == true ? 1 : 0,
      'categories': genreNames,
      'directors': directors,
      'casts': casts,
      'tags': <String>[],
      'downloadLinks': <Map<String, dynamic>>[],
      'seasons': <Map<String, dynamic>>[],
      'tmdbId': tmdbMovie['id'],
      'country': country,
    };
  }

  /// Map TMDB TV series data to Firestore schema
  static Map<String, dynamic> mapTVToFirestore(
    Map<String, dynamic> tmdbTV,
    Map<int, String> genreMap,
  ) {
    final genreIds = tmdbTV['genre_ids'] as List<dynamic>? ?? [];
    // For TV details, genres may be full objects with id and name
    List<String> genreNames;
    if (genreIds.isEmpty && tmdbTV['genres'] != null) {
      final genresList = tmdbTV['genres'] as List<dynamic>? ?? [];
      genreNames = genresList
          .whereType<Map<String, dynamic>>()
          .map((g) => g['name']?.toString() ?? '')
          .where((name) => name.isNotEmpty)
          .toList();
    } else {
      genreNames = mapGenreIdsToNames(genreIds, genreMap);
    }

    final credits = tmdbTV['credits'] as Map<String, dynamic>?;
    final createdBy = tmdbTV['created_by'] as List<dynamic>?;
    final directors = extractCreators(createdBy);
    final casts = extractTopCast(credits);

    final firstAirDate = tmdbTV['first_air_date']?.toString() ?? '';
    final year = firstAirDate.length >= 4 ? firstAirDate.substring(0, 4) : null;

    final originCountry = tmdbTV['origin_country'] as List<dynamic>?;
    final country = (originCountry != null && originCountry.isNotEmpty)
        ? originCountry.first.toString()
        : null;

    // Map seasons and episodes
    final seasons = <Map<String, dynamic>>[];
    final tmdbSeasons = tmdbTV['seasons'] as List<dynamic>? ?? [];
    for (final seasonData in tmdbSeasons) {
      final season = seasonData as Map<String, dynamic>;
      final seasonNumber = season['season_number'] as int? ?? 0;
      final episodeCount = season['episode_count'] as int? ?? 0;
      final seasonName = season['name']?.toString() ?? 'Season $seasonNumber';

      // Skip specials (season 0)
      if (seasonNumber == 0) continue;

      final episodes = <Map<String, dynamic>>[];
      for (int i = 1; i <= episodeCount; i++) {
        episodes.add({
          'name': 'Episode $i',
          'downloadLinks': <Map<String, dynamic>>[],
        });
      }

      seasons.add({
        'name': seasonName,
        'episodes': episodes,
      });
    }

    return {
      'title': tmdbTV['name'] ?? tmdbTV['title'] ?? '',
      'slug': '', // Will be auto-generated by FirestoreContentService
      'year': year,
      'poster': getPosterUrl(tmdbTV['poster_path']?.toString()),
      'backdrop': getBackdropUrl(tmdbTV['backdrop_path']?.toString()),
      'overview': tmdbTV['overview']?.toString() ?? '',
      'rating': (tmdbTV['vote_average'] ?? 0).toDouble().toStringAsFixed(1),
      'type': 'series',
      'isAdult': 0,
      'categories': genreNames,
      'directors': directors,
      'casts': casts,
      'tags': <String>[],
      'downloadLinks': <Map<String, dynamic>>[],
      'seasons': seasons,
      'tmdbId': tmdbTV['id'],
      'country': country,
    };
  }
}
