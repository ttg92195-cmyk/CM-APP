import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';

class EditMoviePage extends StatefulWidget {
  final String movieId;

  const EditMoviePage({super.key, required this.movieId});

  @override
  State<EditMoviePage> createState() => _EditMoviePageState();
}

class _EpisodeControllers {
  final TextEditingController title;
  final TextEditingController videoUrl;
  final TextEditingController downloadUrl;

  _EpisodeControllers({
    required this.title,
    required this.videoUrl,
    required this.downloadUrl,
  });

  void dispose() {
    title.dispose();
    videoUrl.dispose();
    downloadUrl.dispose();
  }
}

class _EditMoviePageState extends State<EditMoviePage> {
  final FirestoreContentService _contentService = FirestoreContentService();
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();

  final _titleController = TextEditingController();
  final _yearController = TextEditingController();
  final _posterController = TextEditingController();
  final _overviewController = TextEditingController();
  final _ratingController = TextEditingController();
  final _resolutionController = TextEditingController();
  final _durationController = TextEditingController();
  final _fileSizeController = TextEditingController();
  final _countryController = TextEditingController();
  String _format = 'MP4'; // Default format for movies

  String _type = 'movie';
  bool _isAdult = false;
  bool _isTrending = false;
  bool _isSaving = false;
  bool _isLoading = true;

  List<String> _allGenres = [];
  List<String> _allTags = [];
  List<String> _selectedGenres = [];
  List<String> _selectedTags = [];

  List<String> _directors = [];
  List<CastMember> _casts = [];
  List<MovieDownloadLink> _downloadLinks = [];
  List<Season> _seasons = [];

  // Episode controllers: seasonIndex -> (episodeIndex -> controllers)
  Map<int, Map<int, _EpisodeControllers>> _episodeControllers = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _yearController.dispose();
    _posterController.dispose();
    _overviewController.dispose();
    _ratingController.dispose();
    _resolutionController.dispose();
    _durationController.dispose();
    _fileSizeController.dispose();
    _countryController.dispose();
    _scrollController.dispose();
    _disposeAllEpisodeControllers();
    super.dispose();
  }

  void _disposeAllEpisodeControllers() {
    for (final seasonMap in _episodeControllers.values) {
      for (final controllers in seasonMap.values) {
        controllers.dispose();
      }
    }
    _episodeControllers.clear();
  }

  void _initEpisodeControllers() {
    _disposeAllEpisodeControllers();
    for (int si = 0; si < _seasons.length; si++) {
      _episodeControllers[si] = {};
      for (int ei = 0; ei < _seasons[si].episodes.length; ei++) {
        final ep = _seasons[si].episodes[ei];
        _episodeControllers[si]![ei] = _EpisodeControllers(
          title: TextEditingController(text: ep.name),
          videoUrl: TextEditingController(text: ep.videoUrl ?? ''),
          downloadUrl: TextEditingController(text: ep.downloadUrl ?? ''),
        );
      }
    }
  }

  _EpisodeControllers _getOrCreateControllers(int seasonIndex, int episodeIndex) {
    _episodeControllers[seasonIndex] ??= {};
    if (_episodeControllers[seasonIndex]![episodeIndex] == null) {
      final ep = _seasons[seasonIndex].episodes[episodeIndex];
      _episodeControllers[seasonIndex]![episodeIndex] = _EpisodeControllers(
        title: TextEditingController(text: ep.name),
        videoUrl: TextEditingController(text: ep.videoUrl ?? ''),
        downloadUrl: TextEditingController(text: ep.downloadUrl ?? ''),
      );
    }
    return _episodeControllers[seasonIndex]![episodeIndex]!;
  }

  void _addSeason() {
    final controller = TextEditingController(text: 'Season ${_seasons.length + 1}');
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Season'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Season Name'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    ).then((result) {
      if (result == true && controller.text.trim().isNotEmpty) {
        setState(() {
          final seasonIndex = _seasons.length;
          _seasons.add(Season(name: controller.text.trim()));
          _episodeControllers[seasonIndex] = {};
        });
      }
    });
  }

  void _removeSeason(int seasonIndex) {
    _episodeControllers[seasonIndex]?.values.forEach((c) => c.dispose());
    _episodeControllers.remove(seasonIndex);
    final newControllers = <int, Map<int, _EpisodeControllers>>{};
    _episodeControllers.forEach((key, value) {
      final newKey = key > seasonIndex ? key - 1 : key;
      newControllers[newKey] = value;
    });
    _episodeControllers = newControllers;
    setState(() {
      _seasons.removeAt(seasonIndex);
    });
  }

  void _addEpisode(int seasonIndex) {
    setState(() {
      final epIndex = _seasons[seasonIndex].episodes.length;
      final newEpisode = Episode(name: 'Episode ${epIndex + 1}');
      _seasons[seasonIndex].episodes.add(newEpisode);
      _episodeControllers[seasonIndex] ??= {};
      _episodeControllers[seasonIndex]![epIndex] = _EpisodeControllers(
        title: TextEditingController(text: newEpisode.name),
        videoUrl: TextEditingController(text: ''),
        downloadUrl: TextEditingController(text: ''),
      );
    });
  }

  void _removeEpisode(int seasonIndex, int episodeIndex) {
    _episodeControllers[seasonIndex]?[episodeIndex]?.dispose();
    _episodeControllers[seasonIndex]?.remove(episodeIndex);
    final newMap = <int, _EpisodeControllers>{};
    _episodeControllers[seasonIndex]?.forEach((key, value) {
      final newKey = key > episodeIndex ? key - 1 : key;
      newMap[newKey] = value;
    });
    _episodeControllers[seasonIndex] = newMap;
    setState(() {
      _seasons[seasonIndex].episodes.removeAt(episodeIndex);
    });
  }

  void _syncControllersToModel() {
    for (int si = 0; si < _seasons.length; si++) {
      for (int ei = 0; ei < _seasons[si].episodes.length; ei++) {
        final controllers = _episodeControllers[si]?[ei];
        if (controllers != null) {
          final old = _seasons[si].episodes[ei];
          _seasons[si].episodes[ei] = Episode(
            name: controllers.title.text.trim().isEmpty ? old.name : controllers.title.text.trim(),
            videoUrl: controllers.videoUrl.text.trim().isEmpty ? null : controllers.videoUrl.text.trim(),
            downloadUrl: controllers.downloadUrl.text.trim().isEmpty ? null : controllers.downloadUrl.text.trim(),
            downloadLinks: old.downloadLinks,
          );
        }
      }
    }
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _contentService.getMovieById(widget.movieId),
        _contentService.getGenres(),
        _contentService.getTags(),
      ]);

      final detail = results[0] as MovieDetail?;
      final genres = results[1] as List;
      final tags = results[2] as List;

      if (detail != null && mounted) {
        setState(() {
          _titleController.text = detail.title;
          _yearController.text = detail.year ?? '';
          _posterController.text = detail.poster ?? '';
          _overviewController.text = detail.overview ?? '';
          _ratingController.text = detail.rating ?? '';
          _resolutionController.text = detail.resolution ?? '';
          _durationController.text = detail.duration ?? '';
          _fileSizeController.text = detail.fileSize ?? '';
          _countryController.text = detail.country ?? '';
          _format = ['MP4', 'MKV', 'MKV / MP4'].contains(detail.format) ? detail.format! : 'MP4';
          _type = detail.type ?? 'movie';
          _isAdult = detail.isAdult != null && detail.isAdult! > 0;
          _isTrending = detail.isTrending;
          _selectedGenres = List<String>.from(detail.categories);
          _selectedTags = List<String>.from(detail.tags);
          _directors = List<String>.from(detail.directors);
          _casts = List<CastMember>.from(detail.casts);
          _downloadLinks = List<MovieDownloadLink>.from(detail.downloadLinks);
          _seasons = List<Season>.from(detail.seasons);
          _allGenres = genres.map((g) => g.name as String).toList();
          _allTags = tags.map((t) => t.name as String).toList();
          _initEpisodeControllers();
          _isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not found')));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading: $e')));
      }
    }
  }

  Future<void> _saveMovie() async {
    if (!_formKey.currentState!.validate()) return;

    // Sync episode controllers data to model before saving
    _syncControllersToModel();

    setState(() => _isSaving = true);

    try {
      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        'year': _yearController.text.trim().isEmpty ? null : _yearController.text.trim(),
        'poster': _posterController.text.trim().isEmpty ? null : _posterController.text.trim(),
        'overview': _overviewController.text.trim().isEmpty ? null : _overviewController.text.trim(),
        'rating': _ratingController.text.trim().isEmpty ? null : _ratingController.text.trim(),
        'resolution': _resolutionController.text.trim().isEmpty ? null : _resolutionController.text.trim(),
        'duration': _type != 'series' ? (_durationController.text.trim().isEmpty ? null : _durationController.text.trim()) : null,
        'fileSize': _fileSizeController.text.trim().isEmpty ? null : _fileSizeController.text.trim(),
        'country': _countryController.text.trim().isEmpty ? null : _countryController.text.trim(),
        'format': _type != 'series' ? _format : null,
        'isAdult': _isAdult ? 1 : 0,
        'type': _type,
        'isTrending': _isTrending,
        'categories': _selectedGenres,
        'tags': _selectedTags,
        'directors': _directors,
        'casts': _casts.map((c) => {'name': c.name, 'profilePath': c.profilePath}).toList(),
        'downloadLinks': _downloadLinks.map((l) => {
          'serverName': l.serverName,
          'url': l.url,
          'watchName': l.watchName,
          'watchUrl': l.watchUrl,
          'size': l.size,
          'quality': l.quality,
          'resolution': l.resolution,
        }).toList(),
        'seasons': _seasons.map((s) => s.toMap()).toList(),
      };

      await _contentService.updateMovie(widget.movieId, data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated successfully!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${_type == 'movie' ? 'Movie' : 'Series'}'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveMovie,
            icon: const Icon(Icons.save, color: Color(0xFFE50914)),
            label: const Text('Update', style: TextStyle(color: Color(0xFFE50914))),
          ),
        ],
      ),
      body: _isLoading || _isSaving
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: 'Title *', hintText: 'Enter title'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Year + Rating
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _yearController,
                            decoration: const InputDecoration(labelText: 'Year', hintText: 'e.g. 2024'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _ratingController,
                            decoration: const InputDecoration(labelText: 'Rating', hintText: 'e.g. 8.5'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Format + Resolution (for Movies)
                    if (_type != 'series') ...[
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _format,
                              decoration: const InputDecoration(labelText: 'Format'),
                              items: const [
                                DropdownMenuItem(value: 'MP4', child: Text('MP4')),
                                DropdownMenuItem(value: 'MKV', child: Text('MKV')),
                                DropdownMenuItem(value: 'MKV / MP4', child: Text('MKV / MP4')),
                              ],
                              onChanged: (v) => setState(() => _format = v ?? 'MP4'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _durationController,
                              decoration: const InputDecoration(labelText: 'Duration (min)', hintText: 'e.g. 120'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _resolutionController,
                        decoration: const InputDecoration(labelText: 'Resolution', hintText: 'e.g. 4K, HD'),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Seasons info (for Series)
                    if (_type == 'series') ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: TextEditingController(text: '${_seasons.length}'),
                              decoration: const InputDecoration(labelText: 'Seasons', hintText: 'Number of seasons'),
                              readOnly: true,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: TextEditingController(text: '${_seasons.fold<int>(0, (sum, s) => sum + s.episodes.length)}'),
                              decoration: const InputDecoration(labelText: 'Episodes', hintText: 'Total episodes'),
                              readOnly: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _resolutionController,
                        decoration: const InputDecoration(labelText: 'Resolution', hintText: 'e.g. 4K, HD'),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // File Size + Country
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fileSizeController,
                            decoration: const InputDecoration(labelText: 'File Size', hintText: 'e.g. 7 GB / 2.2 GB / 1.1 GB'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _countryController,
                            decoration: const InputDecoration(labelText: 'Country', hintText: 'e.g. US, KR, JP'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Toggles
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Is Adult'),
                            value: _isAdult,
                            onChanged: (v) => setState(() => _isAdult = v),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Is Trending'),
                            value: _isTrending,
                            onChanged: (v) => setState(() => _isTrending = v),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Details header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE50914).withOpacity(0.3)),
                      ),
                      child: Text(
                        '${_type == 'movie' ? 'Movie' : 'Series'} Details',
                        style: const TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Poster
                    TextFormField(
                      controller: _posterController,
                      decoration: const InputDecoration(labelText: 'Poster URL', hintText: 'https://...'),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 16),

                    // Overview
                    TextFormField(
                      controller: _overviewController,
                      decoration: const InputDecoration(labelText: 'Overview', alignLabelWithHint: true),
                      maxLines: 4,
                      textAlignVertical: TextAlignVertical.top,
                    ),
                    const SizedBox(height: 16),

                    // Tags
                    _buildSectionTitle('Tags'),
                    const SizedBox(height: 8),
                    _buildMultiSelectChips(_allTags, _selectedTags, (tag, selected) {
                      setState(() {
                        if (selected) { _selectedTags.add(tag); } else { _selectedTags.remove(tag); }
                      });
                    }),
                    const SizedBox(height: 16),

                    // Genres
                    _buildSectionTitle('Genres'),
                    const SizedBox(height: 8),
                    _buildMultiSelectChips(_allGenres, _selectedGenres, (genre, selected) {
                      setState(() {
                        if (selected) { _selectedGenres.add(genre); } else { _selectedGenres.remove(genre); }
                      });
                    }),
                    const SizedBox(height: 16),

                    // Director
                    _buildSectionTitle('Director'),
                    const SizedBox(height: 8),
                    ..._directors.asMap().entries.map((entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text(entry.value)),
                          IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () async {
                            final controller = TextEditingController(text: entry.value);
                            final result = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Edit Director'),
                                content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Director Name'), autofocus: true),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                  ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
                                ],
                              ),
                            );
                            if (result != null && result.isNotEmpty) setState(() => _directors[entry.key] = result);
                          }),
                          IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => setState(() => _directors.removeAt(entry.key))),
                        ],
                      ),
                    )),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final controller = TextEditingController();
                        final result = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Add Director'),
                            content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Director Name'), autofocus: true),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Add')),
                            ],
                          ),
                        );
                        if (result != null && result.isNotEmpty) setState(() => _directors.add(result));
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Director'),
                    ),
                    const SizedBox(height: 16),

                    // Cast
                    _buildSectionTitle('Cast'),
                    const SizedBox(height: 8),
                    ..._casts.asMap().entries.map((entry) {
                      final cast = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: const Color(0xFFE50914).withOpacity(0.15),
                              child: Text(cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?', style: const TextStyle(color: Color(0xFFE50914))),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cast.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                  if (cast.profilePath != null && cast.profilePath!.isNotEmpty)
                                    Text(cast.profilePath!, maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                                ],
                              ),
                            ),
                            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () async {
                              final nameController = TextEditingController(text: cast.name);
                              final profileController = TextEditingController(text: cast.profilePath ?? '');
                              final result = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Edit Cast Member'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name *'), autofocus: true),
                                      const SizedBox(height: 8),
                                      TextField(controller: profileController, decoration: const InputDecoration(labelText: 'Profile Photo URL')),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                                  ],
                                ),
                              );
                              if (result == true && nameController.text.trim().isNotEmpty) {
                                setState(() {
                                  _casts[entry.key] = CastMember(
                                    name: nameController.text.trim(),
                                    profilePath: profileController.text.trim().isEmpty ? null : profileController.text.trim(),
                                  );
                                });
                              }
                            }),
                            IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => setState(() => _casts.removeAt(entry.key))),
                          ],
                        ),
                      );
                    }),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final nameController = TextEditingController();
                        final profileController = TextEditingController();
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Add Cast Member'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name *'), autofocus: true),
                                const SizedBox(height: 8),
                                TextField(controller: profileController, decoration: const InputDecoration(labelText: 'Profile Photo URL')),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
                            ],
                          ),
                        );
                        if (result == true && nameController.text.trim().isNotEmpty) {
                          setState(() {
                            _casts.add(CastMember(
                              name: nameController.text.trim(),
                              profilePath: profileController.text.trim().isEmpty ? null : profileController.text.trim(),
                            ));
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Cast Member'),
                    ),
                    const SizedBox(height: 24),

                    // Download Links (for movies)
                    if (_type != 'series') ...[
                      _buildSectionTitle('Download Links'),
                      const SizedBox(height: 8),
                      ..._downloadLinks.asMap().entries.map((entry) {
                        final link = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(link.serverName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                      Text('${link.quality ?? ''} ${link.resolution ?? ''} ${link.size ?? ''}'.trim(),
                                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                                    ],
                                  ),
                                ),
                                IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => setState(() => _downloadLinks.removeAt(entry.key))),
                              ],
                            ),
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: () => _showAddDownloadLinkModal(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Download Link'),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Seasons & Episodes (for series)
                    if (_type == 'series') ...[
                      _buildSectionTitle('Seasons & Episodes'),
                      const SizedBox(height: 12),
                      ..._seasons.asMap().entries.map((entry) {
                        final seasonIndex = entry.key;
                        final season = entry.value;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            childrenPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            leading: const Icon(Icons.video_library, color: Color(0xFFE50914)),
                            title: Text(season.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: Text('${season.episodes.length} episode${season.episodes.length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                  onPressed: () => _removeSeason(seasonIndex),
                                  tooltip: 'Delete Season',
                                ),
                              ],
                            ),
                            initiallyExpanded: false,
                            children: [
                              if (season.episodes.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Text('No episodes yet. Add one below.',
                                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38)),
                                )
                              else
                                ...season.episodes.asMap().entries.map((epEntry) {
                                  final epIndex = epEntry.key;
                                  final controllers = _getOrCreateControllers(seasonIndex, epIndex);
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.play_circle_outline, size: 16, color: isDark ? Colors.white54 : Colors.black54),
                                            const SizedBox(width: 6),
                                            Text('Episode ${epIndex + 1}',
                                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: isDark ? Colors.white70 : Colors.black87)),
                                            const Spacer(),
                                            IconButton(
                                              icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                                              onPressed: () => _removeEpisode(seasonIndex, epIndex),
                                              tooltip: 'Delete Episode',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        TextFormField(
                                          controller: controllers.title,
                                          decoration: const InputDecoration(
                                            labelText: 'Episode Title',
                                            hintText: 'e.g. Episode 1 - Pilot',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                          ),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: controllers.videoUrl,
                                                decoration: const InputDecoration(
                                                  labelText: 'Video URL',
                                                  hintText: 'Watch/stream URL',
                                                  isDense: true,
                                                  border: OutlineInputBorder(),
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                ),
                                                style: const TextStyle(fontSize: 13),
                                                keyboardType: TextInputType.url,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextFormField(
                                                controller: controllers.downloadUrl,
                                                decoration: const InputDecoration(
                                                  labelText: 'Download URL',
                                                  hintText: 'Direct download link',
                                                  isDense: true,
                                                  border: OutlineInputBorder(),
                                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                                ),
                                                style: const TextStyle(fontSize: 13),
                                                keyboardType: TextInputType.url,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Show existing download links count
                                        if (epEntry.value.downloadLinks.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text('${epEntry.value.downloadLinks.length} additional download link(s)',
                                            style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                              // Add Episode button
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: TextButton.icon(
                                  onPressed: () => _addEpisode(seasonIndex),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Episode'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      // Add Season button
                      OutlinedButton.icon(
                        onPressed: _addSeason,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Season'),
                      ),
                      const SizedBox(height: 12),
                    ],

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  void _showAddDownloadLinkModal() {
    final serverController = TextEditingController();
    final urlController = TextEditingController();
    final watchNameController = TextEditingController();
    final watchUrlController = TextEditingController();
    final qualityController = TextEditingController();
    final resController = TextEditingController();
    final sizeController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Download Link'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: serverController, decoration: const InputDecoration(labelText: 'Server Name *', hintText: 'e.g. Direct-1'), autofocus: true),
              const SizedBox(height: 8),
              TextField(controller: urlController, decoration: const InputDecoration(labelText: 'Download URL *', hintText: 'Direct download link'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              TextField(controller: watchNameController, decoration: const InputDecoration(labelText: 'Watch Name', hintText: 'e.g. Server-1')),
              const SizedBox(height: 8),
              TextField(controller: watchUrlController, decoration: const InputDecoration(labelText: 'Watch URL', hintText: 'Player link for watching'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. 720p, 1080p')),
              const SizedBox(height: 8),
              TextField(controller: sizeController, decoration: const InputDecoration(labelText: 'Size', hintText: 'e.g. 1.5 GB')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    ).then((result) {
      if (result == true && serverController.text.trim().isNotEmpty) {
        setState(() {
          _downloadLinks.add(MovieDownloadLink(
            serverName: serverController.text.trim(),
            url: urlController.text.trim(),
            watchName: watchNameController.text.trim().isEmpty ? null : watchNameController.text.trim(),
            watchUrl: watchUrlController.text.trim().isEmpty ? null : watchUrlController.text.trim(),
            quality: qualityController.text.trim().isEmpty ? null : qualityController.text.trim(),
            resolution: null,
            size: sizeController.text.trim().isEmpty ? null : sizeController.text.trim(),
          ));
        });
      }
    });
  }

  void _showEditEpisodeDialog(int seasonIndex, int episodeIndex) {
    final episode = _seasons[seasonIndex].episodes[episodeIndex];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) => Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${_seasons[seasonIndex].name} - ${episode.name} - Download Links',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(),
              Expanded(
                child: episode.downloadLinks.isEmpty
                    ? Center(child: Text('No download links yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))))
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: episode.downloadLinks.length,
                        itemBuilder: (_, index) {
                          final link = episode.downloadLinks[index];
                          return ListTile(
                            dense: true,
                            title: Text(link.serverName),
                            subtitle: Text('${link.quality ?? ''} ${link.size ?? ''}${link.watchUrl != null && link.watchUrl!.isNotEmpty ? ' · Watch: ${link.watchName ?? 'Available'}' : ''}'.trim()),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                              onPressed: () {
                                setState(() => episode.downloadLinks.removeAt(index));
                                setModalState(() {});
                              },
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showAddEpisodeDownloadLinkDialog(seasonIndex, episodeIndex);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Download Link'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddEpisodeDownloadLinkDialog(int seasonIndex, int episodeIndex) {
    final serverController = TextEditingController();
    final urlController = TextEditingController();
    final watchNameController = TextEditingController();
    final watchUrlController = TextEditingController();
    final qualityController = TextEditingController();
    final resController = TextEditingController();
    final sizeController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${_seasons[seasonIndex].name} - ${_seasons[seasonIndex].episodes[episodeIndex].name} - Download Link'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: serverController, decoration: const InputDecoration(labelText: 'Server Name *', hintText: 'e.g. Direct-1'), autofocus: true),
              const SizedBox(height: 8),
              TextField(controller: urlController, decoration: const InputDecoration(labelText: 'Download URL *', hintText: 'Direct download link'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              TextField(controller: watchNameController, decoration: const InputDecoration(labelText: 'Watch Name', hintText: 'e.g. Server-1')),
              const SizedBox(height: 8),
              TextField(controller: watchUrlController, decoration: const InputDecoration(labelText: 'Watch URL', hintText: 'Player link for watching'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. 720p, 1080p')),
              const SizedBox(height: 8),
              TextField(controller: sizeController, decoration: const InputDecoration(labelText: 'Size', hintText: 'e.g. 1.5 GB')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    ).then((result) {
      if (result == true && serverController.text.trim().isNotEmpty) {
        setState(() {
          _seasons[seasonIndex].episodes[episodeIndex].downloadLinks.add(MovieDownloadLink(
            serverName: serverController.text.trim(),
            url: urlController.text.trim(),
            watchName: watchNameController.text.trim().isEmpty ? null : watchNameController.text.trim(),
            watchUrl: watchUrlController.text.trim().isEmpty ? null : watchUrlController.text.trim(),
            quality: qualityController.text.trim().isEmpty ? null : qualityController.text.trim(),
            resolution: null,
            size: sizeController.text.trim().isEmpty ? null : sizeController.text.trim(),
          ));
        });
      }
    });
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold));
  }

  Widget _buildMultiSelectChips(List<String> allItems, List<String> selectedItems, Function(String, bool) onToggle) {
    if (allItems.isEmpty) return const Text('No items available. Add genres/tags first.');
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: allItems.map((item) {
        final isSelected = selectedItems.contains(item);
        return FilterChip(
          label: Text(item),
          selected: isSelected,
          onSelected: (selected) => onToggle(item, selected),
          selectedColor: const Color(0xFFE50914).withOpacity(0.3),
          checkmarkColor: const Color(0xFFE50914),
          side: BorderSide(color: isSelected ? const Color(0xFFE50914) : Colors.grey.withOpacity(0.5)),
        );
      }).toList(),
    );
  }
}
