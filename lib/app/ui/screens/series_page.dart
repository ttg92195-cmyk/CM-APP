import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/services/api_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';

class SeriesPage extends StatefulWidget {
  const SeriesPage({super.key});

  @override
  State<SeriesPage> createState() => _SeriesPageState();
}

class _SeriesPageState extends State<SeriesPage> {
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();

  List<Movie> _series = [];
  int _currentPage = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadSeries();
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

  Future<void> _loadSeries() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getTvShows(page: 1);
      if (mounted) {
        setState(() {
          _series = result['movies'] as List<Movie>;
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
      final result = await _apiService.getTvShows(page: _currentPage + 1);
      if (mounted) {
        setState(() {
          _series.addAll(result['movies'] as List<Movie>);
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
        title: Text(appConfig.translate('series')),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSeries,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Total count
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        '$_total ${appConfig.translate("series")}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                  ),

                  // Series grid
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
                          final series = _series[index];
                          return MovieCard(
                            movie: series,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MovieDetailScreen(slug: series.slug),
                                ),
                              );
                            },
                          );
                        },
                        childCount: _series.length,
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

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 16),
                  ),
                ],
              ),
            ),
    );
  }
}
