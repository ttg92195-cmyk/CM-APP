import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/series_detail_screen.dart';

class GenresTagsCollectionsPage extends StatefulWidget {
  const GenresTagsCollectionsPage({super.key});

  @override
  State<GenresTagsCollectionsPage> createState() =>
      _GenresTagsCollectionsPageState();
}

class _GenresTagsCollectionsPageState extends State<GenresTagsCollectionsPage>
    with SingleTickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  late TabController _tabController;

  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<TagAndGenres> _collections = [];
  bool _isLoading = true;

  // Sub-tab controllers for Genres and Tags
  late TabController _genresSubTabController;
  late TabController _tagsSubTabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _genresSubTabController = TabController(length: 2, vsync: this);
    _tagsSubTabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _genresSubTabController.dispose();
    _tagsSubTabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      List<TagAndGenres> genres = [];
      List<TagAndGenres> tags = [];
      List<TagAndGenres> collections = [];

      try {
        genres = await _contentService.getGenres();
      } catch (e) {
        debugPrint('Error loading genres: $e');
      }

      try {
        tags = await _contentService.getTags();
      } catch (e) {
        debugPrint('Error loading tags: $e');
      }

      try {
        collections = await _contentService.getCollections();
      } catch (e) {
        debugPrint('Error loading collections: $e');
      }

      if (mounted) {
        setState(() {
          _genres = genres;
          _tags = tags;
          _collections = collections;
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
          ? _buildSkeletonGrid()
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

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(10),
          ),
        );
      },
    );
  }

  // ==================== GENRES TAB (with Movies/Series sub-tabs) ====================
  Widget _buildGenresTab(AppConfig appConfig, ThemeData theme) {
    if (_genres.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFE50914).withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _genresSubTabController,
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
            indicatorColor: const Color(0xFFE50914),
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Movies'),
              Tab(text: 'Series'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _genresSubTabController,
            children: [
              // Movies Genres
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Movies',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _genres.map((g) => g.name).toList(),
                        filterType: 'genre', typeFilter: 'movie'),
                  ],
                ),
              ),
              // Series Genres
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Series',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _genres.map((g) => g.name).toList(),
                        filterType: 'genre', typeFilter: 'series'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== TAGS TAB (with Movies/Series sub-tabs) ====================
  Widget _buildTagsTab(AppConfig appConfig, ThemeData theme) {
    if (_tags.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              bottom: BorderSide(
                color: const Color(0xFFE50914).withOpacity(0.2),
                width: 1,
              ),
            ),
          ),
          child: TabBar(
            controller: _tagsSubTabController,
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
            indicatorColor: const Color(0xFFE50914),
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Movies'),
              Tab(text: 'Series'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tagsSubTabController,
            children: [
              // Movies Tags
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Movies',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _tags.map((t) => t.name).toList(),
                        filterType: 'tag', typeFilter: 'movie'),
                  ],
                ),
              ),
              // Series Tags
              SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Series',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFE50914),
                        ),
                      ),
                    ),
                    _buildNeonGrid(theme, _tags.map((t) => t.name).toList(),
                        filterType: 'tag', typeFilter: 'series'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== COLLECTIONS TAB ====================
  Widget _buildCollectionsTab(AppConfig appConfig, ThemeData theme) {
    if (_collections.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildNeonGrid(theme, _collections.map((c) => c.name).toList(),
          filterType: 'collection'),
    );
  }

  // ==================== SHARED WIDGETS ====================

  Widget _buildNeonGrid(ThemeData theme, List<String> items,
      {required String filterType, String? typeFilter}) {
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
          isSolid: filterType == 'collection',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FilterResultPage(
                  title: item,
                  genreName: filterType == 'genre' ? item : null,
                  tagName: filterType == 'tag' ? item : null,
                  collectionName: filterType == 'collection' ? item : null,
                  typeFilter: typeFilter,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ==================== NEON GLOW BUTTON (Netflix Red) ====================
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isHovering = true),
      onTapUp: (_) => setState(() => _isHovering = false),
      onTapCancel: () => setState(() => _isHovering = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: widget.isSolid
              ? const Color(0xFFE50914)
              : isDark
                  ? const Color(0xFF1A1A1A)
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: widget.isSolid
              ? null
              : Border.all(
                  color: _isHovering
                      ? const Color(0xFFE50914)
                      : isDark
                          ? const Color(0xFFB81D24)
                          : Colors.grey.shade400,
                  width: 1.5,
                ),
          boxShadow: _isHovering
              ? [
                  BoxShadow(
                    color: const Color(0xFFE50914).withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : widget.isSolid
                  ? [
                      BoxShadow(
                        color: const Color(0xFFE50914).withOpacity(0.3),
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
                color: widget.isSolid
                    ? Colors.white
                    : isDark
                        ? Colors.white
                        : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: _isHovering
                    ? [
                        Shadow(
                          color: const Color(0xFFE50914).withOpacity(0.8),
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

// ==================== FILTER RESULT PAGE (public) ====================
class FilterResultPage extends StatefulWidget {
  final String title;
  final String? genreName;
  final String? tagName;
  final String? collectionName;
  final String? typeFilter; // 'movie' or 'series'

  const FilterResultPage({
    super.key,
    required this.title,
    this.genreName,
    this.tagName,
    this.collectionName,
    this.typeFilter,
  });

  @override
  State<FilterResultPage> createState() => _FilterResultPageState();
}

class _FilterResultPageState extends State<FilterResultPage> {
  final FirestoreContentService _contentService = FirestoreContentService();

  List<Movie> _movies = [];
  List<Movie> _filteredMovies = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
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
      Map<String, dynamic> result;
      if (widget.genreName != null) {
        result = await _contentService.getMoviesByGenre(widget.genreName!, limit: 50);
      } else if (widget.tagName != null) {
        result = await _contentService.getMoviesByTag(widget.tagName!, limit: 50);
      } else if (widget.collectionName != null) {
        result = await _contentService.getMoviesByCollection(widget.collectionName!, limit: 50);
      } else {
        result = await _contentService.getMovies(limit: 50);
      }

      if (mounted) {
        final allMovies = result['movies'] as List<Movie>;

        // Apply type filter if specified (Movies or Series sub-tab)
        List<Movie> filtered;
        if (widget.typeFilter != null) {
          filtered = allMovies
              .where((m) => m.type == widget.typeFilter)
              .toList();
        } else {
          filtered = allMovies;
        }

        setState(() {
          _movies = allMovies;
          _filteredMovies = filtered;
          _hasMore = result['hasMore'] as bool;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('FilterResultPage load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      Map<String, dynamic> result;
      if (widget.genreName != null) {
        result = await _contentService.getMoviesByGenre(
          widget.genreName!, limit: 20, startAfter: _lastDoc,
        );
      } else if (widget.tagName != null) {
        result = await _contentService.getMoviesByTag(
          widget.tagName!, limit: 20, startAfter: _lastDoc,
        );
      } else if (widget.collectionName != null) {
        result = await _contentService.getMoviesByCollection(
          widget.collectionName!, limit: 20, startAfter: _lastDoc,
        );
      } else {
        result = await _contentService.getMovies(limit: 20, startAfter: _lastDoc);
      }

      if (mounted) {
        final newMovies = result['movies'] as List<Movie>;
        List<Movie> filtered;
        if (widget.typeFilter != null) {
          filtered = newMovies
              .where((m) => m.type == widget.typeFilter)
              .toList();
        } else {
          filtered = newMovies;
        }

        setState(() {
          _movies.addAll(newMovies);
          _filteredMovies.addAll(filtered);
          _hasMore = result['hasMore'] as bool;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? _buildSkeletonGrid()
          : RefreshIndicator(
              onRefresh: _loadMovies,
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  if (scrollInfo.metrics.pixels ==
                          scrollInfo.metrics.maxScrollExtent &&
                      !_isLoadingMore &&
                      _hasMore) {
                    _loadMore();
                  }
                  return false;
                },
                child: _filteredMovies.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.movie_filter_outlined,
                              size: 64,
                              color: theme.colorScheme.onSurface.withOpacity(0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No ${widget.title} yet',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.55,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _filteredMovies.length + (_isLoadingMore ? 6 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _filteredMovies.length) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final movie = _filteredMovies[index];
                          return MovieCard(
                            movie: movie,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => movie.type == 'series'
                                      ? SeriesDetailScreen(slug: movie.slug)
                                      : MovieDetailScreen(slug: movie.slug),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
    );
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2A2A2A)
                : const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(8),
          ),
        );
      },
    );
  }
}
