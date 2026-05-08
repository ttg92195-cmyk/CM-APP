import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
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
  final FirestoreContentService _contentService = FirestoreContentService();
  late TabController _tabController;

  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<TagAndGenres> _collections = [];
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
    try {
      final results = await Future.wait([
        _contentService.getGenres(),
        _contentService.getTags(),
        _contentService.getCollections(),
      ]);
      if (mounted) {
        setState(() {
          _genres = results[0] as List<TagAndGenres>;
          _tags = results[1] as List<TagAndGenres>;
          _collections = results[2] as List<TagAndGenres>;
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
    if (_genres.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildNeonGrid(theme, _genres.map((g) => g.name).toList(), isGenre: true, isTag: false),
    );
  }

  // ==================== TAGS TAB ====================
  Widget _buildTagsTab(AppConfig appConfig, ThemeData theme) {
    if (_tags.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildNeonGrid(theme, _tags.map((t) => t.name).toList(), isGenre: false, isTag: true),
    );
  }

  // ==================== COLLECTIONS TAB ====================
  Widget _buildCollectionsTab(AppConfig appConfig, ThemeData theme) {
    if (_collections.isEmpty) {
      return Center(child: Text(appConfig.translate('no_results')));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: _buildNeonGrid(theme, _collections.map((c) => c.name).toList(), isGenre: false, isTag: false),
    );
  }

  // ==================== SHARED WIDGETS ====================

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
          isSolid: !isGenre && !isTag, // Collections = solid red
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FilterResultPage(
                  title: item,
                  genreName: isGenre ? item : null,
                  tagName: isTag ? item : null,
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

// ==================== FILTER RESULT PAGE (public for home_screen) ====================
class FilterResultPage extends StatefulWidget {
  final String title;
  final String? genreName;
  final String? tagName;

  const FilterResultPage({
    super.key,
    required this.title,
    this.genreName,
    this.tagName,
  });

  @override
  State<FilterResultPage> createState() => _FilterResultPageState();
}

class _FilterResultPageState extends State<FilterResultPage> {
  final FirestoreContentService _contentService = FirestoreContentService();

  List<Movie> _movies = [];
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
        result = await _contentService.getMoviesByGenre(widget.genreName!, limit: 20);
      } else if (widget.tagName != null) {
        result = await _contentService.getMoviesByTag(widget.tagName!, limit: 20);
      } else {
        result = await _contentService.getMovies(limit: 20);
      }

      if (mounted) {
        setState(() {
          _movies = result['movies'] as List<Movie>;
          _hasMore = result['hasMore'] as bool;
          _lastDoc = result['lastDoc'] as DocumentSnapshot?;
          _isLoading = false;
        });
      }
    } catch (e) {
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
      } else {
        result = await _contentService.getMovies(limit: 20, startAfter: _lastDoc);
      }

      if (mounted) {
        setState(() {
          _movies.addAll(result['movies'] as List<Movie>);
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : NotificationListener<ScrollNotification>(
              onNotification: (scrollInfo) {
                if (scrollInfo.metrics.pixels ==
                        scrollInfo.metrics.maxScrollExtent &&
                    !_isLoadingMore &&
                    _hasMore) {
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
