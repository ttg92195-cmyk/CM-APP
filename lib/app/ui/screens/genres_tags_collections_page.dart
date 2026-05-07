import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/api_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';

class GenresTagsCollectionsPage extends StatefulWidget {
  const GenresTagsCollectionsPage({super.key});

  @override
  State<GenresTagsCollectionsPage> createState() =>
      _GenresTagsCollectionsPageState();
}

class _GenresTagsCollectionsPageState extends State<GenresTagsCollectionsPage>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<String> _collections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getMovieGenres(),
        _apiService.getMovieTags(),
      ]);
      if (mounted) {
        setState(() {
          _genres = results[0] as List<TagAndGenres>;
          _tags = results[1] as List<TagAndGenres>;
          _collections = [
            'Marvel Cinematic Universe',
            'DC Extended Universe',
            'Harry Potter',
            'Fast and Furious',
            'James Bond 007',
            'Star Wars',
            'Lord of the Rings',
            'Mission Impossible',
            'Jurassic Park',
            'Toy Story',
            'Studio Ghibli',
            'A24 Movies',
          ];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('genres_tags_collections')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: appConfig.translate('genres')),
            Tab(text: appConfig.translate('tags')),
            Tab(text: appConfig.translate('collections')),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGenreGrid(appConfig, theme),
                _buildTagGrid(appConfig, theme),
                _buildCollectionGrid(appConfig, theme),
              ],
            ),
    );
  }

  Widget _buildGenreGrid(AppConfig appConfig, ThemeData theme) {
    if (_genres.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _genres.length,
      itemBuilder: (context, index) {
        final genre = _genres[index];
        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _FilterResultPage(
                  title: genre.name,
                  fetchFn: (page) =>
                      _apiService.getMoviesByGenre(genre.id, page: page),
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: const Color(0xFF00897B), width: 1.5),
              borderRadius: BorderRadius.circular(8),
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1A1A1A)
                  : const Color(0xFFF5F5F5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  genre.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (genre.moviesCount != null)
                  Text(
                    '${genre.moviesCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTagGrid(AppConfig appConfig, ThemeData theme) {
    if (_tags.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _tags.length,
      itemBuilder: (context, index) {
        final tag = _tags[index];
        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _FilterResultPage(
                  title: tag.name,
                  fetchFn: (page) =>
                      _apiService.getMoviesByTag(tag.id, page: page),
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: const Color(0xFF00897B), width: 1.5),
              borderRadius: BorderRadius.circular(8),
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1A1A1A)
                  : const Color(0xFFF5F5F5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  tag.name,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (tag.moviesCount != null)
                  Text(
                    '${tag.moviesCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollectionGrid(AppConfig appConfig, ThemeData theme) {
    if (_collections.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _collections.length,
      itemBuilder: (context, index) {
        final collection = _collections[index];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF00897B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  collection,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Reuse _FilterResultPage from library_page.dart
class _FilterResultPage extends StatefulWidget {
  final String title;
  final Future<Map<String, dynamic>> Function(int page) fetchFn;

  const _FilterResultPage({
    required this.title,
    required this.fetchFn,
  });

  @override
  State<_FilterResultPage> createState() => _FilterResultPageState();
}

class _FilterResultPageState extends State<_FilterResultPage> {
  List<Movie> _movies = [];
  int _currentPage = 1;
  int _lastPage = 1;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  Future<void> _loadMovies() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.fetchFn(1);
      if (mounted) {
        setState(() {
          _movies = (result['movies'] as List).cast<Movie>();
          _currentPage = result['current_page'] as int;
          _lastPage = result['last_page'] as int;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _lastPage) return;
    setState(() => _isLoadingMore = true);
    try {
      final result = await widget.fetchFn(_currentPage + 1);
      if (mounted) {
        setState(() {
          _movies.addAll((result['movies'] as List).cast<Movie>());
          _currentPage = result['current_page'] as int;
          _lastPage = result['last_page'] as int;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo.metrics.pixels ==
                        scrollInfo.metrics.maxScrollExtent &&
                    !_isLoadingMore &&
                    _currentPage < _lastPage) {
                  _loadMore();
                }
                return false;
              },
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _movies.length + (_isLoadingMore ? 6 : 0),
                itemBuilder: (context, index) {
                  if (index >= _movies.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final movie = _movies[index];
                  return MovieCard(
                    movie: movie,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MovieDetailScreen(slug: movie.slug),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
