import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/bookmark_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';

class MovieBookmarkScreen extends StatefulWidget {
  const MovieBookmarkScreen({super.key});

  @override
  State<MovieBookmarkScreen> createState() => _MovieBookmarkScreenState();
}

class _MovieBookmarkScreenState extends State<MovieBookmarkScreen> {
  final BookmarkService _bookmarkService = BookmarkService();
  List<Movie> _bookmarks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await _bookmarkService.getBookmarks();
    if (mounted) {
      setState(() {
        _bookmarks = bookmarks;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeBookmark(int index) async {
    final movie = _bookmarks[index];
    await _bookmarkService.removeBookmark(movie.id);
    if (mounted) {
      setState(() {
        _bookmarks.removeAt(index);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Provider.of<AppConfig>(context, listen: false)
                .translate('bookmark_removed'),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('bookmarks')),
        actions: [
          if (_bookmarks.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(appConfig.translate('clear_history')),
                    content: Text(appConfig.translate('no_bookmarks')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(appConfig.translate('retry')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await _bookmarkService.clearBookmarks();
                  _loadBookmarks();
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bookmarks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bookmark_outline,
                        size: 64,
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        appConfig.translate('no_bookmarks'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadBookmarks,
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.53,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: _bookmarks.length,
                    itemBuilder: (context, index) {
                      final movie = _bookmarks[index];
                      return GestureDetector(
                        onLongPress: () => _removeBookmark(index),
                        child: MovieCard(
                          movie: movie,
                          onTap: () {
                            final isSeries = movie.type == 'series';
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => isSeries
                                    ? SeriesDetailScreen(slug: movie.slug)
                                    : MovieDetailScreen(slug: movie.slug),
                              ),
                            ).then((_) => _loadBookmarks());
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
