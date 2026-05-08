import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/ui/screens/add_movie_page.dart';
import 'package:cm_movies/app/ui/screens/add_series_page.dart';
import 'package:cm_movies/app/ui/screens/edit_movie_page.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage>
    with SingleTickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  late TabController _tabController;

  List<Movie> _allPosts = [];
  List<Movie> _filteredPosts = [];
  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<TagAndGenres> _collections = [];

  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
        _contentService.getAllPosts(limit: 100),
        _contentService.getGenres(),
        _contentService.getTags(),
        _contentService.getCollections(),
      ]);

      if (mounted) {
        final posts = (results[0] as Map<String, dynamic>)['movies'] as List<Movie>;
        setState(() {
          _allPosts = posts;
          _filteredPosts = posts;
          _genres = results[1] as List<TagAndGenres>;
          _tags = results[2] as List<TagAndGenres>;
          _collections = results[3] as List<TagAndGenres>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filterPosts(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredPosts = _allPosts;
      } else {
        _filteredPosts = _allPosts.where((post) =>
          post.title.toLowerCase().contains(query.toLowerCase())).toList();
      }
    });
  }

  Future<void> _deletePost(String id, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Confirmation'),
        content: Text('Are you sure you want to delete this ${type == 'series' ? 'series' : 'movie'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _contentService.deleteMovie(id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted successfully')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final movies = _filteredPosts.where((p) => p.type != 'series').toList();
    final series = _filteredPosts.where((p) => p.type == 'series').toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'All (${_filteredPosts.length})'),
            Tab(text: 'Movies (${movies.length})'),
            Tab(text: 'Series (${series.length})'),
            Tab(text: 'Genres/Tags'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPostsTab(_filteredPosts, isDark),
                _buildPostsTab(movies, isDark),
                _buildPostsTab(series, isDark),
                _buildGenresTagsTab(isDark),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final index = _tabController.index;
          if (index <= 2) {
            _showAddOptions();
          } else {
            _addGenreTagDialog();
          }
        },
        backgroundColor: const Color(0xFFE50914),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.movie, color: Color(0xFFE50914)),
              title: const Text('Add Movie'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddMoviePage(initialType: 'movie')),
                ).then((_) => _loadData());
              },
            ),
            ListTile(
              leading: const Icon(Icons.tv, color: Color(0xFFE50914)),
              title: const Text('Add Series'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddSeriesPage()),
                ).then((_) => _loadData());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsTab(List<Movie> posts, bool isDark) {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            onChanged: _filterPosts,
            decoration: InputDecoration(
              hintText: 'Search posts...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: posts.isEmpty
              ? const Center(child: Text('No posts yet. Tap + to add one.'))
              : ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return _buildPostListItem(post, isDark);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPostListItem(Movie post, bool isDark) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 55,
                height: 78,
                child: post.fullPosterUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: post.fullPosterUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                          child: const Icon(Icons.movie, size: 24),
                        ),
                      )
                    : Container(
                        color: isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade300,
                        child: const Icon(Icons.movie, size: 24),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (post.year != null && post.year!.isNotEmpty)
                        Text(post.year!, style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                      if (post.year != null && post.year!.isNotEmpty)
                        const Text(' • ', style: TextStyle(fontSize: 12)),
                      if (post.rating != null && post.rating!.isNotEmpty) ...[
                        const Icon(Icons.star, size: 12, color: Colors.amber),
                        Text(post.rating!, style: const TextStyle(fontSize: 12, color: Colors.amber)),
                        const Text(' • ', style: TextStyle(fontSize: 12)),
                      ],
                      Text(
                        post.timeAgo.isNotEmpty ? post.timeAgo : 'Unknown',
                        style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.black38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (post.isTrending)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('TRENDING', style: TextStyle(color: Color(0xFFE50914), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (post.type == 'series' ? Colors.blue : Colors.green).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          post.type == 'series' ? 'SERIES' : 'MOVIE',
                          style: TextStyle(
                            color: post.type == 'series' ? Colors.blue : Colors.green,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Edit & Delete buttons
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => EditMoviePage(movieId: post.id)),
                    ).then((_) => _loadData());
                  },
                ),
                IconButton(
                  icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400),
                  onPressed: () => _deletePost(post.id, post.type ?? 'movie'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenresTagsTab(bool isDark) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Genres'),
              Tab(text: 'Tags'),
              Tab(text: 'Collections'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSimpleList(_genres, isDark, 'genre'),
                _buildSimpleList(_tags, isDark, 'tag'),
                _buildSimpleList(_collections, isDark, 'collection'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimpleList(List<TagAndGenres> items, bool isDark, String type) {
    if (items.isEmpty) return Center(child: Text('No ${type}s yet. Tap + to add one.'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE50914).withOpacity(0.15),
            child: Text('${index + 1}', style: const TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold)),
          ),
          title: Text(item.name),
          subtitle: Text('${item.moviesCount ?? 0} movies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _editItemDialog(item, type)),
              IconButton(icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400), onPressed: () => _deleteItemDialog(item, type)),
            ],
          ),
        );
      },
    );
  }

  void _addGenreTagDialog() {
    final controller = TextEditingController();
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: controller, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
            const SizedBox(height: 12),
            const Text('This will be added as a Genre, Tag, or Collection based on the current tab.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    ).then((result) async {
      if (result == true && controller.text.trim().isNotEmpty) {
        // Add to all three for simplicity
        await _contentService.addGenre(controller.text.trim());
        await _contentService.addTag(controller.text.trim());
        _loadData();
      }
    });
  }

  Future<void> _editItemDialog(TagAndGenres item, String type) async {
    final controller = TextEditingController(text: item.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${type[0].toUpperCase()}${type.substring(1)}'),
        content: TextField(controller: controller, decoration: InputDecoration(labelText: 'Name'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      if (type == 'genre') await _contentService.updateGenre(item.id, result);
      else if (type == 'tag') await _contentService.updateTag(item.id, result);
      else await _contentService.updateCollection(item.id, result);
      _loadData();
    }
  }

  Future<void> _deleteItemDialog(TagAndGenres item, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${type[0].toUpperCase()}${type.substring(1)}'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      if (type == 'genre') await _contentService.deleteGenre(item.id);
      else if (type == 'tag') await _contentService.deleteTag(item.id);
      else await _contentService.deleteCollection(item.id);
      _loadData();
    }
  }
}
