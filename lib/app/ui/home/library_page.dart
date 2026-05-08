import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/models/movie.dart';
import 'package:cm_movies/app/core/models/tag_and_genres.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/ui/components/movie_card.dart';
import 'package:cm_movies/app/ui/screens/movie_detail_screen.dart';
import 'package:cm_movies/app/ui/screens/genres_tags_collections_page.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage>
    with SingleTickerProviderStateMixin {
  final FirestoreContentService _contentService = FirestoreContentService();
  late TabController _tabController;

  List<TagAndGenres> _genres = [];
  List<TagAndGenres> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        _contentService.getGenres(),
        _contentService.getTags(),
      ]);
      if (mounted) {
        setState(() {
          _genres = results[0] as List<TagAndGenres>;
          _tags = results[1] as List<TagAndGenres>;
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
                builder: (_) => FilterResultPage(
                  title: genre.name,
                  genreName: genre.name,
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
                builder: (_) => FilterResultPage(
                  title: tag.name,
                  tagName: tag.name,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
