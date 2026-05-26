import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TmdbService {
  // API key loaded from .env file for security (not hardcoded in source code)
  static String get _apiKey => dotenv.env['TMDB_API_KEY'] ?? '2e928cd76f7f5ae46f6e022f5dcc2612';
  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
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
      final params = {'api_key': _apiKey, ...?queryParams};
      final response = await _dio.get(path, queryParameters: params);
      return response;
    } on DioException catch (e) {
      debugPrint('TMDB API Error: ${e.message} - Path: $path');
      rethrow;
    }
  }

  // ==================== DISCOVER ====================

  /// Discover movies with optional filters
  /// [language] is always 'en-US' for display (titles, overviews in English)
  /// [originalLanguage] is used as `with_original_language` filter (e.g. 'ja' for Japanese movies)
  Future<Map<String, dynamic>> discoverMovies({
    int? genre,
    String? year,
    String language = 'en-US',
    String? originalLanguage,
    String sortBy = 'popularity.desc',
    int page = 1,
  }) async {
    final params = <String, dynamic>{
      'language': language, // Always en-US for display text
      'sort_by': sortBy,
      'page': page,
      'vote_count.gte': 50, // filter out movies with too few votes
    };
    if (genre != null) params['with_genres'] = genre.toString();
    if (year != null) params['primary_release_year'] = year;
    if (originalLanguage != null && originalLanguage.isNotEmpty) {
      params['with_original_language'] = originalLanguage;
    }

    final response = await _get('/discover/movie', queryParams: params);
    return response.data as Map<String, dynamic>;
  }

  /// Discover TV series with optional filters
  /// [language] is always 'en-US' for display (titles, overviews in English)
  /// [originalLanguage] is used as `with_original_language` filter (e.g. 'ja' for Japanese series)
  Future<Map<String, dynamic>> discoverTV({
    int? genre,
    String? year,
    String language = 'en-US',
    String? originalLanguage,
    String sortBy = 'popularity.desc',
    int page = 1,
  }) async {
    final params = <String, dynamic>{
      'language': language, // Always en-US for display text
      'sort_by': sortBy,
      'page': page,
      'vote_count.gte': 50,
    };
    if (genre != null) params['with_genres'] = genre.toString();
    if (year != null) params['first_air_date_year'] = year;
    if (originalLanguage != null && originalLanguage.isNotEmpty) {
      params['with_original_language'] = originalLanguage;
    }

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
  /// [language] is always 'en-US' for display
  Future<Map<String, dynamic>> searchMovies(String query, {int page = 1, String language = 'en-US'}) async {
    final response = await _get(
      '/search/movie',
      queryParams: {'query': query, 'page': page, 'language': language},
    );
    return response.data as Map<String, dynamic>;
  }

  /// Search TV series by title
  /// [language] is always 'en-US' for display
  Future<Map<String, dynamic>> searchTV(String query, {int page = 1, String language = 'en-US'}) async {
    final response = await _get(
      '/search/tv',
      queryParams: {'query': query, 'page': page, 'language': language},
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

  /// Extract all cast members from credits (no limit)
  /// Use [count] to optionally cap the list; defaults to 0 meaning unlimited.
  static List<Map<String, String>> extractTopCast(Map<String, dynamic>? credits, {int count = 0}) {
    if (credits == null) return [];
    final cast = credits['cast'] as List?;
    if (cast == null) return [];
    var filtered = cast
        .whereType<Map<String, dynamic>>()
        .where((person) => (person['name']?.toString() ?? '').isNotEmpty);
    if (count > 0) filtered = filtered.take(count);
    return filtered
        .map((person) => {
              'name': person['name']?.toString() ?? '',
              'profilePath': person['profile_path'] != null
                  ? getPosterUrl(person['profile_path'].toString())
                  : '',
            })
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

    // Extract duration from runtime (available in movie details API)
    // Store as integer (minutes) — UI will format as "95 min"
    final runtime = tmdbMovie['runtime'] as int?;
    final duration = (runtime != null && runtime > 0) ? runtime : null;

    return {
      'title': tmdbMovie['title'] ?? tmdbMovie['name'] ?? '',
      'slug': '', // Will be auto-generated by FirestoreContentService
      'year': year,
      'poster': getPosterUrl(tmdbMovie['poster_path']?.toString()),
      'backdrop': getBackdropUrl(tmdbMovie['backdrop_path']?.toString()),
      'overview': tmdbMovie['overview']?.toString() ?? '',
      'rating': (tmdbMovie['vote_average'] ?? 0).toDouble().toStringAsFixed(1),
      'type': 'movie',
      'duration': duration,
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

    // Extract duration from episode_run_time (available in TV details API)
    // Store as integer (minutes) — UI will format as "45 min"
    final episodeRunTime = tmdbTV['episode_run_time'] as List<dynamic>?;
    int? duration;
    if (episodeRunTime != null && episodeRunTime.isNotEmpty) {
      final first = episodeRunTime.first;
      duration = first is int ? first : int.tryParse(first.toString());
    }

    // Extract series status from TMDB (e.g. "Returning Series", "Ended", "Canceled")
    final status = tmdbTV['status']?.toString() ?? '';

    return {
      'title': tmdbTV['name'] ?? tmdbTV['title'] ?? '',
      'slug': '', // Will be auto-generated by FirestoreContentService
      'year': year,
      'poster': getPosterUrl(tmdbTV['poster_path']?.toString()),
      'backdrop': getBackdropUrl(tmdbTV['backdrop_path']?.toString()),
      'overview': tmdbTV['overview']?.toString() ?? '',
      'rating': (tmdbTV['vote_average'] ?? 0).toDouble().toStringAsFixed(1),
      'type': 'series',
      'duration': duration,
      'isAdult': 0,
      'categories': genreNames,
      'directors': directors,
      'casts': casts,
      'tags': <String>[],
      'downloadLinks': <Map<String, dynamic>>[],
      'seasons': seasons,
      'tmdbId': tmdbTV['id'],
      'country': country,
      'status': status,
    };
  }
}
