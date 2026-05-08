import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/ui/screens/add_movie_page.dart';
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

  List<Movie> _movies = [];
  List<Movie> _series = [];
  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  List<TagAndGenres> _collections = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
        _contentService.getMovies(limit: 100),
        _contentService.getSeries(limit: 100),
        _contentService.getGenres(),
        _contentService.getTags(),
        _contentService.getCollections(),
      ]);

      if (mounted) {
        setState(() {
          _movies = (results[0] as Map<String, dynamic>)['movies'] as List<Movie>;
          _series = (results[1] as Map<String, dynamic>)['movies'] as List<Movie>;
          _genres = results[2] as List<TagAndGenres>;
          _tags = results[3] as List<TagAndGenres>;
          _collections = results[4] as List<TagAndGenres>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMovie(String id, String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Confirmation'),
        content: Text('Are you sure you want to delete this ${type == 'movie' ? 'movie' : 'series'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted successfully')),
        );
      }
    }
  }

  Future<void> _deleteGenre(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Genre'),
        content: const Text('Are you sure you want to delete this genre?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _contentService.deleteGenre(id);
      _loadData();
    }
  }

  Future<void> _deleteTag(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Tag'),
        content: const Text('Are you sure you want to delete this tag?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _contentService.deleteTag(id);
      _loadData();
    }
  }

  Future<void> _deleteCollection(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Collection'),
        content: const Text('Are you sure you want to delete this collection?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _contentService.deleteCollection(id);
      _loadData();
    }
  }

  Future<void> _addGenreDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Genre'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Genre Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _contentService.addGenre(result);
      _loadData();
    }
  }

  Future<void> _addTagDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Tag'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tag Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _contentService.addTag(result);
      _loadData();
    }
  }

  Future<void> _addCollectionDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Collection'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Collection Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _contentService.addCollection(result);
      _loadData();
    }
  }

  Future<void> _editGenreDialog(TagAndGenres genre) async {
    final controller = TextEditingController(text: genre.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Genre'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Genre Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _contentService.updateGenre(genre.id, result);
      _loadData();
    }
  }

  Future<void> _editTagDialog(TagAndGenres tag) async {
    final controller = TextEditingController(text: tag.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Tag'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tag Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _contentService.updateTag(tag.id, result);
      _loadData();
    }
  }

  Future<void> _editCollectionDialog(TagAndGenres collection) async {
    final controller = TextEditingController(text: collection.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Collection'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Collection Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _contentService.updateCollection(collection.id, result);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'Movies (${_movies.length})'),
            Tab(text: 'Series (${_series.length})'),
            Tab(text: 'Genres (${_genres.length})'),
            Tab(text: 'Tags (${_tags.length})'),
            Tab(text: 'Collections (${_collections.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildMoviesTab(isDark),
                _buildSeriesTab(isDark),
                _buildGenresTab(isDark),
                _buildTagsTab(isDark),
                _buildCollectionsTab(isDark),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final index = _tabController.index;
          if (index <= 1) {
            // Movies or Series tab
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddMoviePage(
                  initialType: index == 0 ? 'movie' : 'series',
                ),
              ),
            ).then((_) => _loadData());
          } else if (index == 2) {
            _addGenreDialog();
          } else if (index == 3) {
            _addTagDialog();
          } else if (index == 4) {
            _addCollectionDialog();
          }
        },
        backgroundColor: const Color(0xFFE50914),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildMoviesTab(bool isDark) {
    if (_movies.isEmpty) {
      return const Center(child: Text('No movies yet. Tap + to add one.'));
    }
    return ListView.builder(
      itemCount: _movies.length,
      itemBuilder: (context, index) {
        final movie = _movies[index];
        return _buildMovieListItem(movie, isDark);
      },
    );
  }

  Widget _buildSeriesTab(bool isDark) {
    if (_series.isEmpty) {
      return const Center(child: Text('No series yet. Tap + to add one.'));
    }
    return ListView.builder(
      itemCount: _series.length,
      itemBuilder: (context, index) {
        final series = _series[index];
        return _buildMovieListItem(series, isDark);
      },
    );
  }

  Widget _buildMovieListItem(Movie movie, bool isDark) {
    return ListTile(
      leading: Container(
        width: 50,
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(6),
        ),
        child: movie.fullPosterUrl.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  movie.fullPosterUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 24),
                ),
              )
            : const Icon(Icons.movie, size: 24),
      ),
      title: Text(
        movie.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${movie.year ?? 'N/A'} • ${movie.categories.join(', ')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isDark ? Colors.white54 : Colors.black54,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (movie.isTrending)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'TRENDING',
                style: TextStyle(
                  color: Color(0xFFE50914),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditMoviePage(movieId: movie.id),
                ),
              ).then((_) => _loadData());
            },
          ),
          IconButton(
            icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400),
            onPressed: () => _deleteMovie(movie.id, movie.type ?? 'movie'),
          ),
        ],
      ),
    );
  }

  Widget _buildGenresTab(bool isDark) {
    if (_genres.isEmpty) {
      return const Center(child: Text('No genres yet. Tap + to add one.'));
    }
    return ListView.builder(
      itemCount: _genres.length,
      itemBuilder: (context, index) {
        final genre = _genres[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE50914).withOpacity(0.15),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFFE50914),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(genre.name),
          subtitle: Text('${genre.moviesCount ?? 0} movies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _editGenreDialog(genre),
              ),
              IconButton(
                icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400),
                onPressed: () => _deleteGenre(genre.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTagsTab(bool isDark) {
    if (_tags.isEmpty) {
      return const Center(child: Text('No tags yet. Tap + to add one.'));
    }
    return ListView.builder(
      itemCount: _tags.length,
      itemBuilder: (context, index) {
        final tag = _tags[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE50914).withOpacity(0.15),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFFE50914),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(tag.name),
          subtitle: Text('${tag.moviesCount ?? 0} movies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _editTagDialog(tag),
              ),
              IconButton(
                icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400),
                onPressed: () => _deleteTag(tag.id),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollectionsTab(bool isDark) {
    if (_collections.isEmpty) {
      return const Center(child: Text('No collections yet. Tap + to add one.'));
    }
    return ListView.builder(
      itemCount: _collections.length,
      itemBuilder: (context, index) {
        final collection = _collections[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE50914).withOpacity(0.15),
            child: Text(
              '${index + 1}',
              style: const TextStyle(
                color: Color(0xFFE50914),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(collection.name),
          subtitle: Text('${collection.moviesCount ?? 0} movies'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _editCollectionDialog(collection),
              ),
              IconButton(
                icon: Icon(Icons.delete, size: 20, color: Colors.red.shade400),
                onPressed: () => _deleteCollection(collection.id),
              ),
            ],
          ),
        );
      },
    );
  }
}
