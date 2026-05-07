import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/models/movie_year.dart';
import 'package:cm_movies/app/core/services/api_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<MovieYear> _years = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadFilters();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getMovieGenres(),
        _apiService.getMovieTags(),
        _apiService.getMovieYears(),
      ]);
      if (mounted) {
        setState(() {
          _genres = results[0] as List<TagAndGenres>;
          _tags = results[1] as List<TagAndGenres>;
          _years = results[2] as List<MovieYear>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('movies')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: appConfig.translate('genre')),
            Tab(text: appConfig.translate('tag')),
            Tab(text: appConfig.translate('year')),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGenreList(appConfig, theme),
                _buildTagList(appConfig, theme),
                _buildYearList(appConfig, theme),
              ],
            ),
    );
  }

  Widget _buildGenreList(AppConfig appConfig, ThemeData theme) {
    if (_genres.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return ListView.builder(
      itemCount: _genres.length,
      itemBuilder: (context, index) {
        final genre = _genres[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(genre.name),
          subtitle: genre.moviesCount != null
              ? Text('${genre.moviesCount} ${appConfig.translate('movies')}')
              : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _FilterResultPage(
                  title: genre.name,
                  fetchFn: (page) => _apiService.getMoviesByGenre(genre.id, page: page),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTagList(AppConfig appConfig, ThemeData theme) {
    if (_tags.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return ListView.builder(
      itemCount: _tags.length,
      itemBuilder: (context, index) {
        final tag = _tags[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.secondaryContainer,
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(tag.name),
          subtitle: tag.moviesCount != null
              ? Text('${tag.moviesCount} ${appConfig.translate('movies')}')
              : null,
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => _FilterResultPage(
                  title: tag.name,
                  fetchFn: (page) => _apiService.getMoviesByTag(tag.id, page: page),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildYearList(AppConfig appConfig, ThemeData theme) {
    if (_years.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _years.length,
      itemBuilder: (context, index) {
        final year = _years[index];
        return InkWell(
          onTap: () {
            if (year.year != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _FilterResultPage(
                    title: year.year!,
                    fetchFn: (page) =>
                        _apiService.getMoviesByYear(year.year!, page: page),
                  ),
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  year.year ?? '',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (year.moviesCount != null)
                  Text(
                    '${year.moviesCount}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
          _movies = result['movies'] as List<Movie>;
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
          _movies.addAll(result['movies'] as List<Movie>);
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
      appBar: AppBar(
        title: Text(widget.title),
      ),
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
                          builder: (_) => MovieDetailScreen(slug: movie.slug),
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
