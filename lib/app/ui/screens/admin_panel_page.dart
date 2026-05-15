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
  int _genresTagsSubTabIndex = 0;

  // Bulk delete
  Set<String> _selectedPostIds = {};
  bool get _isSelecting => _selectedPostIds.isNotEmpty;

  // Advanced filtering
  String? _filterGenre;
  String? _filterYear;

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
      _applyFilters();
    });
  }

  void _applyFilters() {
    _filteredPosts = _allPosts.where((post) {
      // Search query filter
      if (_searchQuery.isNotEmpty &&
          !post.title.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      // Genre filter
      if (_filterGenre != null && _filterGenre!.isNotEmpty) {
        if (!post.categories.any((c) =>
            c.toLowerCase() == _filterGenre!.toLowerCase())) {
          return false;
        }
      }
      // Year filter
      if (_filterYear != null && _filterYear!.isNotEmpty) {
        if (post.year != _filterYear) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<String> get _availableYears {
    final years = _allPosts
        .where((p) => p.year != null && p.year!.isNotEmpty)
        .map((p) => p.year!)
        .toSet()
        .toList();
    years.sort((a, b) => b.compareTo(a));
    return years;
  }

  Future<void> _bulkDeleteSelected() async {
    if (_selectedPostIds.isEmpty) return;
    final count = _selectedPostIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Bulk Delete Confirmation', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete $count post${count > 1 ? 's' : ''}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFE50914)),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      int deleted = 0;
      for (final id in _selectedPostIds.toList()) {
        try {
          await _contentService.deleteMovie(id);
          deleted++;
        } catch (_) {}
      }
      _selectedPostIds.clear();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $deleted post${deleted > 1 ? 's' : ''} successfully')),
        );
      }
    }
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
        // Bulk delete bar
        if (_isSelecting)
          Container(
            color: const Color(0xFFE50914).withOpacity(0.15),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${_selectedPostIds.length} selected',
                  style: const TextStyle(
                    color: Color(0xFFE50914),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedPostIds.clear());
                  },
                  child: const Text('Clear', style: TextStyle(color: Colors.white54)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _bulkDeleteSelected,
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Delete Selected'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
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
        // Filter bar
        _buildFilterBar(isDark),
        Expanded(
          child: posts.isEmpty
              ? const Center(child: Text('No posts found.'))
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

  Widget _buildFilterBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          // Genre dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: DropdownButton<String>(
                value: _filterGenre ?? '',
                hint: const Text('Genre', style: TextStyle(fontSize: 13)),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: const Icon(Icons.filter_list, size: 18),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('All Genres', style: TextStyle(fontSize: 13)),
                  ),
                  ..._genres.map((g) => DropdownMenuItem<String>(
                    value: g.name,
                    child: Text(g.name, style: const TextStyle(fontSize: 13)),
                  )),
                ],
                onChanged: (value) {
                  setState(() {
                    _filterGenre = (value == null || value.isEmpty) ? null : value;
                    _applyFilters();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Year dropdown
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey.shade300,
                ),
              ),
              child: DropdownButton<String>(
                value: _filterYear ?? '',
                hint: const Text('Year', style: TextStyle(fontSize: 13)),
                isExpanded: true,
                underline: const SizedBox.shrink(),
                icon: const Icon(Icons.calendar_today, size: 16),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('All Years', style: TextStyle(fontSize: 13)),
                  ),
                  ..._availableYears.map((y) => DropdownMenuItem<String>(
                    value: y,
                    child: Text(y, style: const TextStyle(fontSize: 13)),
                  )),
                ],
                onChanged: (value) {
                  setState(() {
                    _filterYear = (value == null || value.isEmpty) ? null : value;
                    _applyFilters();
                  });
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Clear filters button
          if (_filterGenre != null || _filterYear != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 20, color: Color(0xFFE50914)),
              onPressed: () {
                setState(() {
                  _filterGenre = null;
                  _filterYear = null;
                  _applyFilters();
                });
              },
              tooltip: 'Clear filters',
            ),
        ],
      ),
    );
  }

  Widget _buildPostListItem(Movie post, bool isDark) {
    final theme = Theme.of(context);
    final isSelected = _selectedPostIds.contains(post.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isSelected
          ? const Color(0xFFE50914).withOpacity(0.1)
          : null,
      shape: isSelected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: const BorderSide(color: Color(0xFFE50914), width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox for bulk selection
            GestureDetector(
              onTap: () {
                setState(() {
                  if (_selectedPostIds.contains(post.id)) {
                    _selectedPostIds.remove(post.id);
                  } else {
                    _selectedPostIds.add(post.id);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 4),
                child: Checkbox(
                  value: isSelected,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedPostIds.add(post.id);
                      } else {
                        _selectedPostIds.remove(post.id);
                      }
                    });
                  },
                  activeColor: const Color(0xFFE50914),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
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
                        const Icon(Icons.star, size: 12, color: Color(0xFFFF0000)),
                        Text(post.rating!, style: const TextStyle(fontSize: 12, color: Color(0xFFFF0000))),
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
          TabBar(
            onTap: (index) {
              setState(() => _genresTagsSubTabIndex = index);
            },
            tabs: const [
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
        // Add based on current sub-tab in Genres/Tags tab
        final genresTagsSubTab = _genresTagsSubTabIndex;
        if (genresTagsSubTab == 0) {
          await _contentService.addGenre(controller.text.trim());
        } else if (genresTagsSubTab == 1) {
          await _contentService.addTag(controller.text.trim());
        } else if (genresTagsSubTab == 2) {
          await _contentService.addCollection(controller.text.trim());
        }
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
