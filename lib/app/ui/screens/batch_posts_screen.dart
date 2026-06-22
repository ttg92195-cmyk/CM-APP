import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';

/// Full-screen grid view of the movies created (or updated) by a single
/// Batch Import run.
///
/// Task 25 (Number 1): Bro reported that when a Batch Import uploaded
/// movies with wrong IDs (e.g. a tmdbId that wasn't actually a TMDB id),
/// the resulting "wrong" movies were very hard to find and delete from
/// the Admin Panel — you'd have to scroll through thousands of posts to
/// locate them. This screen fixes that by showing ONLY the movies from
/// a specific batch (typically 50-200 items), with a search box and a
/// per-card delete button.
///
/// Source of [movieIds]: the `createdMovieIds` / `updatedMovieIds` field
/// on the batch_imports audit document. Populated by `_recordAudit()` in
/// batch_import_service.dart since Task 25. Old batches imported before
/// this field was added will pass an empty list — caller should check
/// and not navigate to this screen in that case.
///
/// This is an admin-only screen (no _requireAdmin() check here because
/// the parent screens already enforce admin). Deletes go through
/// FirestoreContentService.deleteMovie(), which itself enforces admin.
class BatchPostsScreen extends StatefulWidget {
  /// Firestore document IDs of the movies to display.
  final List<String> movieIds;

  /// Display label for the AppBar title — e.g. "Created Posts" or
  /// "Updated Posts".
  final String titleLabel;

  /// Optional subtitle shown under the title — e.g. the batch's source
  /// file name + date.
  final String? subtitle;

  const BatchPostsScreen({
    super.key,
    required this.movieIds,
    required this.titleLabel,
    this.subtitle,
  });

  @override
  State<BatchPostsScreen> createState() => _BatchPostsScreenState();
}

class _BatchPostsScreenState extends State<BatchPostsScreen> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  /// All movies fetched from Firestore (the "source of truth" before any
  /// search filter is applied).
  List<Movie> _allMovies = [];

  /// Subset of [_allMovies] that matches the current search query. Equal
  /// to [_allMovies] when the search box is empty.
  List<Movie> _filteredMovies = [];

  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadMovies();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// Fetch all movies in [widget.movieIds] from Firestore using the
  /// batched `getMoviesByIds()` helper (30 IDs per query, run in
  /// parallel via Future.wait). Movies that no longer exist are
  /// silently skipped — this happens when an admin deletes a movie
  /// directly from the Admin Panel between the batch import and this
  /// screen being opened.
  Future<void> _loadMovies() async {
    if (widget.movieIds.isEmpty) {
      setState(() {
        _allMovies = [];
        _filteredMovies = [];
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final map = await _contentService.getMoviesByIds(widget.movieIds);
      // Preserve the original order from movieIds — this matches the
      // order movies were created in the batch, which is useful for
      // the admin to spot "I imported X then Y then Z, where's Y?"
      final ordered = <Movie>[];
      for (final id in widget.movieIds) {
        final m = map[id];
        if (m != null) ordered.add(m);
      }
      if (mounted) {
        setState(() {
          _allMovies = ordered;
          _filteredMovies = ordered;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('BatchPostsScreen _loadMovies failed: $e');
      if (mounted) {
        setState(() {
          _loadError = 'Failed to load movies: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), _applyFilter);
  }

  /// Client-side case-insensitive substring filter on title. Search is
  /// client-side because we already have all movies in memory (typical
  /// batch is 50-200 docs). No need to round-trip to Firestore.
  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _filteredMovies = _allMovies);
      return;
    }
    setState(() {
      _filteredMovies = _allMovies
          .where((m) => m.titleLowercase.contains(q))
          .toList();
    });
  }

  /// Delete a single movie from Firestore, then remove it from both
  /// [_allMovies] and [_filteredMovies]. Shows a confirmation dialog
  /// before deleting.
  Future<void> _deleteMovie(Movie movie) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Post'),
        content: Text(
          'Delete "${movie.title}"?\n\n'
          'This permanently removes the movie from Firestore. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _contentService.deleteMovie(movie.id);
      if (mounted) {
        setState(() {
          _allMovies.removeWhere((m) => m.id == movie.id);
          _filteredMovies.removeWhere((m) => m.id == movie.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${movie.title}"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('BatchPostsScreen _deleteMovie failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete "${movie.title}": $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _navigateToDetail(Movie movie) {
    final isSeries = movie.type == 'series';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => isSeries
            ? SeriesDetailScreen(slug: movie.slug)
            : MovieDetailScreen(slug: movie.slug),
      ),
    ).then((_) {
      // Refresh on return — the user might have edited/deleted the
      // movie from inside the detail screen.
      if (mounted) _loadMovies();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.titleLabel),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          if (_allMovies.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  '${_filteredMovies.length}/${_allMovies.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadMovies,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(theme, isDark),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 56, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _loadMovies,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_allMovies.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No posts in this batch.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Either this batch imported 0 movies, or all imported movies\n'
              'have since been deleted from Firestore.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Search bar — client-side filter on title.
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by title...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilter();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE50914)),
              ),
            ),
          ),
        ),

        // "Delete in trash" hint row.
        if (_filteredMovies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.4)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tap the trash icon on a card to delete that post.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Grid of movie cards with delete overlay.
        Expanded(
          child: _filteredMovies.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 56,
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No posts match your search.',
                        style: TextStyle(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.53,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: _filteredMovies.length,
                  itemBuilder: (context, index) {
                    final movie = _filteredMovies[index];
                    return Stack(
                      children: [
                        MovieCard(
                          movie: movie,
                          onTap: () => _navigateToDetail(movie),
                        ),
                        // Delete button — top-right corner, semi-opaque
                        // red circle with a trash icon. Positioned just
                        // inside the card's top-right corner so it
                        // doesn't get clipped by the grid's spacing.
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _deleteMovie(movie),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.red.shade300,
                                  width: 1.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(6),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
