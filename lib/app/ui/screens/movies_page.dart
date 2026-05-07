import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/api_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';

class MoviesPage extends StatefulWidget {
  const MoviesPage({super.key});

  @override
  State<MoviesPage> createState() => _MoviesPageState();
}

class _MoviesPageState extends State<MoviesPage> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<Movie> _movies = [];
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadMovies();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoadingMore &&
        _currentPage < _lastPage) {
      _loadMore();
    }
  }

  Future<void> _loadMovies() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getMovies(page: 1);
      if (mounted) {
        setState(() {
          _movies = result['movies'] as List<Movie>;
          _currentPage = result['current_page'] as int;
          _lastPage = result['last_page'] as int;
          _total = result['total'] as int;
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
      final result = await _apiService.getMovies(page: _currentPage + 1);
      if (mounted) {
        setState(() {
          _movies.addAll(result['movies'] as List<Movie>);
          _currentPage = result['current_page'] as int;
          _lastPage = result['last_page'] as int;
          _total = result['total'] as int;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('movies')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadMovies,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Total count
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '$_total ${appConfig.translate("movies")}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),

                  // Movie grid
                  SliverPadding(
                    padding: const EdgeInsets.all(8),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.55,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
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
                        childCount: _movies.length,
                      ),
                    ),
                  ),

                  // Loading more indicator
                  if (_isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),

                  // Bottom spacing
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 16),
                  ),
                ],
              ),
            ),
    );
  }
}
