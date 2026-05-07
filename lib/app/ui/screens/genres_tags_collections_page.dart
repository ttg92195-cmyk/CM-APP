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

  List<TagAndGenres> _apiGenres = [];
  List<TagAndGenres> _apiTags = [];
  bool _isLoading = true;

  // Hardcoded data matching screenshots
  final List<String> _movieGenres = [
    'Action', 'Adventure', 'Animation', 'Comedy', 'Crime',
    'Documentary', 'Drama', 'Family', 'Fantasy', 'History',
    'Horror', 'Music', 'Mystery', 'Revenge', 'Romance',
    'Science Fiction', 'Thriller', 'TV Movie', 'War', 'Western',
  ];

  final List<String> _seriesGenres = [
    'Action & Adventure', 'Animation', 'Comedy',
  ];

  final List<String> _movieTags = [
    '4K', 'Animation', 'Anime', 'Bollywood', 'C Drama',
    'Donghua', 'Featured Movies', 'K Drama', 'Reality Show',
    'Thai Drama', 'Trending',
  ];

  final List<String> _seriesTags = [
    '4K', 'Animation', 'Anime', 'Bollywood', 'C Drama',
    'Donghua', 'Featured Movies', 'K Drama', 'Reality Show',
    'Thai Drama', 'Trending',
  ];

  final List<String> _movieCollections = [
    '007', 'A24 Movies', 'American Pie', 'Batman',
    'CHRISTMAS MOVIES', 'DCEU', 'Detective Chinatown',
    'Dragon Gate Posthouse', 'Fast and Furious',
    'Final Destination', 'Harry Potter',
    'Marvel Cinematic Universe - MCU', "Ocean's Collection",
    'Queen Of Kung Fu', 'Quentin Tarantino', 'Saw Collection',
    'Scooby-Doo', 'Studio Ghibli',
  ];

  final List<String> _seriesCollections = [
    'Sit-com', 'Sports Documentaries',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadApiData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadApiData() async {
    try {
      final results = await Future.wait([
        _apiService.getMovieGenres(),
        _apiService.getMovieTags(),
      ]);
      if (mounted) {
        setState(() {
          _apiGenres = results[0] as List<TagAndGenres>;
          _apiTags = results[1] as List<TagAndGenres>;
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
                _buildGenresTab(appConfig, theme),
                _buildTagsTab(appConfig, theme),
                _buildCollectionsTab(appConfig, theme),
              ],
            ),
    );
  }

  // ==================== GENRES TAB ====================
  Widget _buildGenresTab(AppConfig appConfig, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Movies Section
          _buildSectionTitle(theme, 'Movies'),
          const SizedBox(height: 8),
          _buildNeonGrid(theme, _movieGenres, isGenre: true, isTag: false),

          const SizedBox(height: 24),

          // Series Section
          _buildSectionTitle(theme, 'Series'),
          const SizedBox(height: 8),
          _buildNeonGrid(theme, _seriesGenres, isGenre: true, isTag: false),
        ],
      ),
    );
  }

  // ==================== TAGS TAB ====================
  Widget _buildTagsTab(AppConfig appConfig, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Movies Section
          _buildSectionTitle(theme, 'Movies'),
          const SizedBox(height: 8),
          _buildNeonGrid(theme, _movieTags, isGenre: false, isTag: true),

          const SizedBox(height: 24),

          // Series Section
          _buildSectionTitle(theme, 'Series'),
          const SizedBox(height: 8),
          _buildNeonGrid(theme, _seriesTags, isGenre: false, isTag: true),
        ],
      ),
    );
  }

  // ==================== COLLECTIONS TAB ====================
  Widget _buildCollectionsTab(AppConfig appConfig, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Movies Section
          _buildSectionTitle(theme, 'Movies'),
          const SizedBox(height: 8),
          _buildNeonGrid(theme, _movieCollections, isGenre: false, isTag: false),

          const SizedBox(height: 24),

          // Series Section
          _buildSectionTitle(theme, 'Series'),
          const SizedBox(height: 8),
          _buildNeonGrid(theme, _seriesCollections, isGenre: false, isTag: false),
        ],
      ),
    );
  }

  // ==================== SHARED WIDGETS ====================

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildNeonGrid(ThemeData theme, List<String> items,
      {required bool isGenre, required bool isTag}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _NeonGlowButton(
          title: item,
          isSolid: !isGenre && !isTag, // Collections = solid teal
          onTap: () {
            // Try to find matching API item for navigation
            if (isGenre) {
              final match = _apiGenres.where((g) => g.name.toLowerCase() == item.toLowerCase()).toList();
              if (match.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FilterResultPage(
                      title: item,
                      fetchFn: (page) =>
                          _apiService.getMoviesByGenre(match.first.id, page: page),
                    ),
                  ),
                );
              }
            } else if (isTag) {
              final match = _apiTags.where((t) => t.name.toLowerCase() == item.toLowerCase()).toList();
              if (match.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _FilterResultPage(
                      title: item,
                      fetchFn: (page) =>
                          _apiService.getMoviesByTag(match.first.id, page: page),
                    ),
                  ),
                );
              }
            }
          },
        );
      },
    );
  }
}

// ==================== NEON GLOW BUTTON ====================
class _NeonGlowButton extends StatefulWidget {
  final String title;
  final bool isSolid;
  final VoidCallback? onTap;

  const _NeonGlowButton({
    required this.title,
    this.isSolid = false,
    this.onTap,
  });

  @override
  State<_NeonGlowButton> createState() => _NeonGlowButtonState();
}

class _NeonGlowButtonState extends State<_NeonGlowButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isHovering = true),
      onTapUp: (_) => setState(() => _isHovering = false),
      onTapCancel: () => setState(() => _isHovering = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.isSolid
              ? const Color(0xFF00897B)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: widget.isSolid
              ? null
              : Border.all(
                  color: _isHovering
                      ? const Color(0xFF00E5FF)
                      : const Color(0xFF00897B),
                  width: 1.5,
                ),
          boxShadow: _isHovering
              ? [
                  BoxShadow(
                    color: const Color(0xFF00E5FF).withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : widget.isSolid
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00897B).withOpacity(0.3),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: _isHovering
                    ? [
                        Shadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.8),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== FILTER RESULT PAGE ====================
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
