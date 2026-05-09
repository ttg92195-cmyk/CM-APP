import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';

class EditMoviePage extends StatefulWidget {
  final String movieId;

  const EditMoviePage({super.key, required this.movieId});

  @override
  State<EditMoviePage> createState() => _EditMoviePageState();
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
    _scrollController.dispose();
    super.dispose();
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

    setState(() => _isSaving = true);

    try {
      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        'year': _yearController.text.trim().isEmpty ? null : _yearController.text.trim(),
        'poster': _posterController.text.trim().isEmpty ? null : _posterController.text.trim(),
        'backdrop': null,
        'overview': _overviewController.text.trim().isEmpty ? null : _overviewController.text.trim(),
        'rating': _ratingController.text.trim().isEmpty ? null : _ratingController.text.trim(),
        'resolution': _resolutionController.text.trim().isEmpty ? null : _resolutionController.text.trim(),
        'duration': _durationController.text.trim().isEmpty ? null : _durationController.text.trim(),
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

                    // Duration + Resolution
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _durationController,
                            decoration: const InputDecoration(labelText: 'Duration (min)', hintText: 'e.g. 120'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _resolutionController,
                            decoration: const InputDecoration(labelText: 'Resolution', hintText: 'e.g. 4K, HD'),
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
                      OutlinedButton.icon(
                        onPressed: () {
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
                              setState(() => _seasons.add(Season(name: controller.text.trim())));
                            }
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Season'),
                      ),
                      const SizedBox(height: 12),
                      ..._seasons.asMap().entries.map((entry) {
                        final seasonIndex = entry.key;
                        final season = entry.value;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(season.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                    IconButton(icon: const Icon(Icons.delete, size: 20, color: Colors.red), onPressed: () => setState(() => _seasons.removeAt(seasonIndex))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...season.episodes.asMap().entries.map((epEntry) {
                                  final epIndex = epEntry.key;
                                  final episode = epEntry.value;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(Icons.play_circle_outline, size: 20, color: Color(0xFFE50914)),
                                    title: Text(episode.name, style: const TextStyle(fontSize: 13)),
                                    subtitle: Text('${episode.downloadLinks.length} link(s)',
                                      style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _showEditEpisodeDialog(seasonIndex, epIndex)),
                                        IconButton(icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                          onPressed: () => setState(() => _seasons[seasonIndex].episodes.removeAt(epIndex))),
                                      ],
                                    ),
                                  );
                                }),
                                TextButton.icon(
                                  onPressed: () {
                                    final controller = TextEditingController(text: 'Episode ${season.episodes.length + 1}');
                                    showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: Text('Add Episode - ${season.name}'),
                                        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Episode Name'), autofocus: true),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
                                        ],
                                      ),
                                    ).then((result) {
                                      if (result == true && controller.text.trim().isNotEmpty) {
                                        setState(() => _seasons[seasonIndex].episodes.add(Episode(name: controller.text.trim())));
                                      }
                                    });
                                  },
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Episode'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
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
              TextField(controller: serverController, decoration: const InputDecoration(labelText: 'Server Name *'), autofocus: true),
              const SizedBox(height: 8),
              TextField(controller: urlController, decoration: const InputDecoration(labelText: 'URL *'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. FHD, HD')),
              const SizedBox(height: 8),
              TextField(controller: resController, decoration: const InputDecoration(labelText: 'Resolution', hintText: 'e.g. 1080p')),
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
            quality: qualityController.text.trim().isEmpty ? null : qualityController.text.trim(),
            resolution: resController.text.trim().isEmpty ? null : resController.text.trim(),
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
                            subtitle: Text('${link.quality ?? ''} ${link.size ?? ''}'.trim()),
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
              TextField(controller: serverController, decoration: const InputDecoration(labelText: 'Server Name *'), autofocus: true),
              const SizedBox(height: 8),
              TextField(controller: urlController, decoration: const InputDecoration(labelText: 'URL *'), keyboardType: TextInputType.url),
              const SizedBox(height: 8),
              TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. FHD')),
              const SizedBox(height: 8),
              TextField(controller: resController, decoration: const InputDecoration(labelText: 'Resolution', hintText: 'e.g. 1080p')),
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
            quality: qualityController.text.trim().isEmpty ? null : qualityController.text.trim(),
            resolution: resController.text.trim().isEmpty ? null : resController.text.trim(),
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
