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
import 'package:cm_movies/app/ui/home/trending_movie_component.dart';

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

      // PARALLEL FETCH — previously sequential (genres → tags → collections),
      // adding 3 × query latency on slow networks. Now all three fire in
      // parallel; total wait ≈ slowest query instead of sum of all three.
      // (Task 36 #2 — see movies_page.dart for the artificial-skeleton-floor
      // removal rationale; that pattern was also removed here.)
      final results = await Future.wait([
        _contentService.getGenres().catchError((e) {
          debugPrint('Error loading genres: $e');
          return <TagAndGenres>[];
        }),
        _contentService.getTags().catchError((e) {
          debugPrint('Error loading tags: $e');
          return <TagAndGenres>[];
        }),
        _contentService.getCollections().catchError((e) {
          debugPrint('Error loading collections: $e');
          return <TagAndGenres>[];
        }),
      ]);

      genres = results[0] as List<TagAndGenres>;
      tags = results[1] as List<TagAndGenres>;
      collections = results[2] as List<TagAndGenres>;

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
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
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

  // ==================== GENRES TAB (with Movies/Series sub-tabs) ====================
  Widget _buildGenresTab(AppConfig appConfig, ThemeData theme) {
    if (_genres.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _genresSubTabController,
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
            indicatorColor: const Color(0xFFE50914),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
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
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tagsSubTabController,
            labelColor: const Color(0xFFE50914),
            unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.5),
            indicatorColor: const Color(0xFFE50914),
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: Colors.transparent,
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
                          ? Colors.white24
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
  // Track seen IDs to prevent duplicates
  final Set<String> _seenIds = {};

  @override
  void initState() {
    super.initState();
    _loadMovies();
  }

  Future<void> _loadMovies() async {
    setState(() {
      _isLoading = true;
      _seenIds.clear();
    });
    try {
      Map<String, dynamic> result;
      if (widget.genreName != null) {
        result = await _contentService.getMoviesByGenre(
          widget.genreName!, limit: 20, typeFilter: widget.typeFilter, // PAGINATION: 20/page (Task 38 Req 5)
        );
      } else if (widget.tagName != null) {
        result = await _contentService.getMoviesByTag(
          widget.tagName!, limit: 20, typeFilter: widget.typeFilter, // PAGINATION: 20/page (Task 38 Req 5)
        );
      } else if (widget.collectionName != null) {
        result = await _contentService.getMoviesByCollection(
          widget.collectionName!, limit: 20, typeFilter: widget.typeFilter, // PAGINATION: 20/page (Task 38 Req 5)
        );
      } else {
        result = await _contentService.getMovies(limit: 20); // PAGINATION: 20/page
      }

      if (mounted) {
        final allMovies = result['movies'] as List<Movie>;

        // Track IDs to prevent future duplicates
        for (final m in allMovies) {
          _seenIds.add(m.id);
        }

        // Apply type filter if specified (Movies or Series sub-tab)
        List<Movie> filtered;
        if (widget.typeFilter != null) {
          filtered = allMovies
              .where((m) => m.type == widget.typeFilter)
              .toList();
        } else {
          filtered = allMovies;
        }

        // NOTE: previously had an artificial 600ms skeleton floor here.
        // Removed in Task 36 #2 — see movies_page.dart for the rationale.
        setState(() {
          _movies = allMovies;
          _filteredMovies = filtered;
          _hasMore = result['hasMore'] as bool;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoading = false;
        });

        // Task 38 Req 5 — post-frame auto-load safety net.
        // If the first page returned fewer items than would fill the
        // viewport (e.g., on a large tablet showing 30+ items per screen,
        // or a genre with exactly 20 docs that doesn't fill the screen),
        // the scroll listener never fires — and infinite scroll silently
        // dies. Schedule a `_loadMore()` on the next frame; `_loadMore`
        // will no-op if `_hasMore` is already false (e.g., the genre only
        // had 20 docs total).
        if (_hasMore && _filteredMovies.length < 30) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _hasMore && !_isLoadingMore) {
              _loadMore();
            }
          });
        }
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
          typeFilter: widget.typeFilter, // Task 38 Req 5
        );
      } else if (widget.tagName != null) {
        result = await _contentService.getMoviesByTag(
          widget.tagName!, limit: 20, startAfter: _lastDoc,
          typeFilter: widget.typeFilter, // Task 38 Req 5
        );
      } else if (widget.collectionName != null) {
        result = await _contentService.getMoviesByCollection(
          widget.collectionName!, limit: 20, startAfter: _lastDoc,
          typeFilter: widget.typeFilter, // Task 38 Req 5
        );
      } else {
        result = await _contentService.getMovies(limit: 20, startAfter: _lastDoc);
      }

      if (mounted) {
        final newMovies = result['movies'] as List<Movie>;

        // Deduplicate by ID to prevent duplicates
        final dedupedMovies = <Movie>[];
        for (final m in newMovies) {
          if (!_seenIds.contains(m.id)) {
            _seenIds.add(m.id);
            dedupedMovies.add(m);
          }
        }

        List<Movie> filtered;
        if (widget.typeFilter != null) {
          filtered = dedupedMovies
              .where((m) => m.type == widget.typeFilter)
              .toList();
        } else {
          filtered = dedupedMovies;
        }

        setState(() {
          _movies.addAll(dedupedMovies);
          _filteredMovies.addAll(filtered);
          // Task 39 — stop paginating when dedup returns 0 items, which
          // happens when Firestore returned a page of docs we've already
          // seen (e.g., the fallback path returned page 1 again before
          // the startAfterDocument fix was deployed, or the genre has
          // fewer than `limit` total docs and Firestore returned the
          // same set with a slightly different doc-ID order). Without
          // this guard, the auto-load safety net would spin forever
          // calling _loadMore → 0 new docs → _hasMore stays true →
          // another _loadMore → ad infinitum (and burn Firestore reads).
          _hasMore = (result['hasMore'] as bool) && dedupedMovies.isNotEmpty;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoadingMore = false;
        });

        // Task 38 Req 5 — chained auto-load safety net (mirror of the one
        // in _loadMovies). If after a `_loadMore` we still have fewer
        // than 30 visible items AND `_hasMore` is still true, the grid
        // likely still doesn't fill the viewport — schedule another
        // `_loadMore` on the next frame. Caps infinite recursion because
        // `_loadMore` no-ops once `_hasMore` flips false (Firestore
        // returned fewer than `limit` docs).
        if (_hasMore && _filteredMovies.length < 30) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _hasMore && !_isLoadingMore) {
              _loadMore();
            }
          });
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: _isLoading
          ? _buildSkeletonGrid()
          : RefreshIndicator(
              onRefresh: _loadMovies,
              child: NotificationListener<ScrollNotification>(
                onNotification: (scrollInfo) {
                  // Task 38 Req 5 — trigger at 80% scroll instead of 100%
                  // so the next page kicks in BEFORE the user hits the
                  // bottom (smoother infinite scroll). Combined with the
                  // post-frame auto-load below, this also handles the case
                  // where the first page didn't even fill the viewport
                  // (e.g., on a large tablet).
                  final trigger = scrollInfo.metrics.pixels >=
                      scrollInfo.metrics.maxScrollExtent * 0.8;
                  if (trigger && !_isLoadingMore && _hasMore) {
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.53,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.53,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
      ),
      itemCount: 9,
      itemBuilder: (context, index) {
        return const MovieCardSkeleton();
      },
    );
  }
}
