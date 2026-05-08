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

  // Form controllers
  final _titleController = TextEditingController();
  final _yearController = TextEditingController();
  final _posterController = TextEditingController();
  final _overviewController = TextEditingController();
  final _ratingController = TextEditingController();
  final _resolutionController = TextEditingController();

  String _type = 'movie';
  bool _isAdult = false;
  bool _isTrending = false;
  bool _isSaving = false;
  bool _isLoading = true;

  // Multi-select data
  List<String> _allGenres = [];
  List<String> _allTags = [];
  List<String> _selectedGenres = [];
  List<String> _selectedTags = [];

  // Dynamic lists
  List<String> _directors = [];
  List<CastMember> _casts = [];
  List<MovieDownloadLink> _downloadLinks = [];

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
          _type = detail.type ?? 'movie';
          _isAdult = detail.isAdult != null && detail.isAdult! > 0;
          _isTrending = detail.isTrending;
          _selectedGenres = List<String>.from(detail.categories);
          _selectedTags = List<String>.from(detail.tags);
          _directors = List<String>.from(detail.directors);
          _casts = List<CastMember>.from(detail.casts);
          _downloadLinks = List<MovieDownloadLink>.from(detail.downloadLinks);
          _allGenres = genres.map((g) => g.name as String).toList();
          _allTags = tags.map((t) => t.name as String).toList();
          _isLoading = false;
        });
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Movie not found')),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading: $e')),
        );
      }
    }
  }

  Future<void> _saveMovie() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final data = {
        'title': _titleController.text.trim(),
        'year': _yearController.text.trim().isEmpty ? null : _yearController.text.trim(),
        'poster': _posterController.text.trim().isEmpty ? null : _posterController.text.trim(),
        'overview': _overviewController.text.trim().isEmpty ? null : _overviewController.text.trim(),
        'rating': _ratingController.text.trim().isEmpty ? null : _ratingController.text.trim(),
        'resolution': _resolutionController.text.trim().isEmpty ? null : _resolutionController.text.trim(),
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
      };

      await _contentService.updateMovie(widget.movieId, data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Updated successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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
            label: const Text(
              'Update',
              style: TextStyle(color: Color(0xFFE50914)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isSaving
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
                          decoration: const InputDecoration(
                            labelText: 'Title *',
                            hintText: 'Enter movie/series title',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Type and Year row
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _type,
                                decoration: const InputDecoration(
                                  labelText: 'Type',
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'movie', child: Text('Movie')),
                                  DropdownMenuItem(value: 'series', child: Text('Series')),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _type = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _yearController,
                                decoration: const InputDecoration(
                                  labelText: 'Year',
                                  hintText: 'e.g. 2024',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Poster URL
                        TextFormField(
                          controller: _posterController,
                          decoration: const InputDecoration(
                            labelText: 'Poster URL',
                            hintText: 'https://...',
                          ),
                          keyboardType: TextInputType.url,
                        ),
                        const SizedBox(height: 16),

                        // Rating and Resolution row
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _ratingController,
                                decoration: const InputDecoration(
                                  labelText: 'Rating',
                                  hintText: 'e.g. 8.5',
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: _resolutionController,
                                decoration: const InputDecoration(
                                  labelText: 'Resolution',
                                  hintText: 'e.g. 4K, HD',
                                ),
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
                        const SizedBox(height: 16),

                        // Overview
                        TextFormField(
                          controller: _overviewController,
                          decoration: const InputDecoration(
                            labelText: 'Overview',
                            alignLabelWithHint: true,
                          ),
                          maxLines: 4,
                          textAlignVertical: TextAlignVertical.top,
                        ),
                        const SizedBox(height: 24),

                        // Categories (Genres) multi-select
                        _buildSectionTitle('Categories (Genres)'),
                        const SizedBox(height: 8),
                        _buildMultiSelectChips(
                          _allGenres,
                          _selectedGenres,
                          (genre, selected) {
                            setState(() {
                              if (selected) {
                                _selectedGenres.add(genre);
                              } else {
                                _selectedGenres.remove(genre);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 24),

                        // Tags multi-select
                        _buildSectionTitle('Tags'),
                        const SizedBox(height: 8),
                        _buildMultiSelectChips(
                          _allTags,
                          _selectedTags,
                          (tag, selected) {
                            setState(() {
                              if (selected) {
                                _selectedTags.add(tag);
                              } else {
                                _selectedTags.remove(tag);
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 24),

                        // Directors
                        _buildSectionTitle('Directors'),
                        const SizedBox(height: 8),
                        ..._directors.asMap().entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(entry.value),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () {
                                    setState(() => _directors.removeAt(entry.key));
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final controller = TextEditingController();
                            final result = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Add Director'),
                                content: TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(
                                    labelText: 'Director Name',
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
                              setState(() => _directors.add(result));
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Director'),
                        ),
                        const SizedBox(height: 24),

                        // Cast Members
                        _buildSectionTitle('Cast Members'),
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
                                  child: Text(
                                    cast.name.isNotEmpty ? cast.name[0].toUpperCase() : '?',
                                    style: const TextStyle(color: Color(0xFFE50914)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(cast.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                                      if (cast.profilePath != null && cast.profilePath!.isNotEmpty)
                                        Text(
                                          cast.profilePath!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 20),
                                  onPressed: () {
                                    setState(() => _casts.removeAt(entry.key));
                                  },
                                ),
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
                                    TextField(
                                      controller: nameController,
                                      decoration: const InputDecoration(labelText: 'Name *'),
                                      autofocus: true,
                                    ),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: profileController,
                                      decoration: const InputDecoration(labelText: 'Profile Photo URL'),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Add'),
                                  ),
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

                        // Download Links
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
                                        Text(
                                          '${link.quality ?? ''} ${link.resolution ?? ''} ${link.size ?? ''}'.trim(),
                                          style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20),
                                    onPressed: () {
                                      setState(() => _downloadLinks.removeAt(entry.key));
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final serverController = TextEditingController();
                            final urlController = TextEditingController();
                            final qualityController = TextEditingController();
                            final resController = TextEditingController();
                            final sizeController = TextEditingController();
                            final result = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Add Download Link'),
                                content: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(
                                        controller: serverController,
                                        decoration: const InputDecoration(labelText: 'Server Name *'),
                                        autofocus: true,
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: urlController,
                                        decoration: const InputDecoration(labelText: 'URL *'),
                                        keyboardType: TextInputType.url,
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: qualityController,
                                        decoration: const InputDecoration(
                                          labelText: 'Quality',
                                          hintText: 'e.g. BluRay, WEB-DL',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: resController,
                                        decoration: const InputDecoration(
                                          labelText: 'Resolution',
                                          hintText: 'e.g. 1080p, 4K',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: sizeController,
                                        decoration: const InputDecoration(
                                          labelText: 'Size',
                                          hintText: 'e.g. 1.5 GB',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Add'),
                                  ),
                                ],
                              ),
                            );
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
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Download Link'),
                        ),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildMultiSelectChips(
    List<String> allItems,
    List<String> selectedItems,
    Function(String, bool) onToggle,
  ) {
    if (allItems.isEmpty) {
      return const Text('No items available. Add genres/tags first.');
    }
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
          side: BorderSide(
            color: isSelected
                ? const Color(0xFFE50914)
                : Colors.grey.withOpacity(0.5),
          ),
        );
      }).toList(),
    );
  }
}
