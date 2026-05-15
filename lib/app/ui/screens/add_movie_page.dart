import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';

class AddMoviePage extends StatefulWidget {
  final String initialType;

  const AddMoviePage({super.key, this.initialType = 'movie'});

  @override
  State<AddMoviePage> createState() => _AddMoviePageState();
}

class _AddMoviePageState extends State<AddMoviePage> {
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
  final _durationController = TextEditingController();
  final _fileSizeController = TextEditingController();
  final _formatController = TextEditingController();

  String _type = 'movie';
  bool _isAdult = false;
  bool _isTrending = false;
  bool _isSaving = false;

  // Multi-select data
  List<String> _allGenres = [];
  List<String> _allTags = [];
  List<String> _selectedGenres = [];
  List<String> _selectedTags = [];

  // Dynamic lists
  List<String> _directors = [];
  List<CastMember> _casts = [];
  List<MovieDownloadLink> _downloadLinks = [];
  List<MovieWatchLink> _watchLinks = [];

  // Server options (1-10)
  static const List<String> _serverOptions = [
    'Server 1', 'Server 2', 'Server 3', 'Server 4', 'Server 5',
    'Server 6', 'Server 7', 'Server 8', 'Server 9', 'Server 10',
  ];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _loadGenresAndTags();
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
    _formatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadGenresAndTags() async {
    final genres = await _contentService.getGenres();
    final tags = await _contentService.getTags();
    if (mounted) {
      setState(() {
        _allGenres = genres.map((g) => g.name).toList();
        _allTags = tags.map((t) => t.name).toList();
      });
    }
  }

  Future<void> _saveMovie() async {
    if (!_formKey.currentState!.validate()) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title is required')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        'year': _yearController.text.trim().isEmpty ? null : _yearController.text.trim(),
        'poster': _posterController.text.trim().isEmpty ? null : _posterController.text.trim(),
        'overview': _overviewController.text.trim().isEmpty ? null : _overviewController.text.trim(),
        'rating': _ratingController.text.trim().isEmpty ? null : _ratingController.text.trim(),
        'resolution': _resolutionController.text.trim().isEmpty ? null : _resolutionController.text.trim(),
        'duration': _durationController.text.trim().isEmpty ? null : _durationController.text.trim(),
        'fileSize': _fileSizeController.text.trim().isEmpty ? null : _fileSizeController.text.trim(),
        'format': _formatController.text.trim().isEmpty ? null : _formatController.text.trim(),
        'isAdult': _isAdult ? 1 : 0,
        'type': _type,
        'isTrending': _isTrending,
        'categories': _selectedGenres,
        'tags': _selectedTags,
        'directors': _directors,
        'casts': _casts.map((c) => {'name': c.name, 'profilePath': c.profilePath}).toList(),
        'downloadLinks': _downloadLinks.map((l) => l.toMap()).toList(),
        'watchLinks': _watchLinks.map((l) => l.toMap()).toList(),
        'seasons': <Map<String, dynamic>>[],
      };

      await _contentService.addMovie(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved successfully!')));
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
        title: Text('Add ${_type == 'movie' ? 'Movie' : 'Series'}'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveMovie,
            icon: const Icon(Icons.save, color: Color(0xFFE50914)),
            label: const Text('Save', style: TextStyle(color: Color(0xFFE50914))),
          ),
        ],
      ),
      body: _isSaving
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
                      decoration: const InputDecoration(labelText: 'Title *', hintText: 'Enter movie title'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Year + Rating row
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

                    // Duration + Resolution row
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
                            decoration: const InputDecoration(labelText: 'Resolution', hintText: 'e.g. 4K / 1080p / 720p'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // File Size + Format row
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _fileSizeController,
                            decoration: const InputDecoration(labelText: 'File Size', hintText: 'e.g. 4.8 GB / 1.9 GB / 976 MB'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _formatController,
                            decoration: const InputDecoration(labelText: 'Format', hintText: 'e.g. MKV / MP4'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Is Adult + Is Trending
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

                    // Movie Details section header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE50914).withOpacity(0.3)),
                      ),
                      child: Text(
                        'Movie Details',
                        style: const TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Poster URL
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
                            Expanded(child: Text(cast.name, style: const TextStyle(fontWeight: FontWeight.w500))),
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

                    // ===== DOWNLOAD LINKS =====
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
                                    if (link.fileName != null && link.fileName!.isNotEmpty)
                                      Text(link.fileName!, style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54)),
                                    Text('${link.quality ?? ''} ${link.size ?? ''}'.trim(),
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

                    // ===== WATCH LINKS =====
                    _buildSectionTitle('Watch Links'),
                    const SizedBox(height: 8),
                    ..._watchLinks.asMap().entries.map((entry) {
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
                                    Text('${link.quality ?? ''} ${link.size ?? ''}'.trim(),
                                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                                  ],
                                ),
                              ),
                              IconButton(icon: const Icon(Icons.delete, size: 20), onPressed: () => setState(() => _watchLinks.removeAt(entry.key))),
                            ],
                          ),
                        ),
                      );
                    }),
                    OutlinedButton.icon(
                      onPressed: () => _showAddWatchLinkModal(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Watch Link'),
                    ),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  void _showAddDownloadLinkModal() {
    String? selectedServer = _serverOptions.first;
    final urlController = TextEditingController();
    final qualityController = TextEditingController();
    final sizeController = TextEditingController();
    final fileNameController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Download Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Select Server
                DropdownButtonFormField<String>(
                  value: selectedServer,
                  decoration: const InputDecoration(labelText: 'Select Server'),
                  items: _serverOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDialogState(() => selectedServer = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: fileNameController, decoration: const InputDecoration(labelText: 'File Name', hintText: 'e.g. Movie_Name_1080p.mkv')),
                const SizedBox(height: 8),
                TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. 4K, 1080p, 720p')),
                const SizedBox(height: 8),
                TextField(controller: sizeController, decoration: const InputDecoration(labelText: 'Size', hintText: 'e.g. 4.5 GB')),
                const SizedBox(height: 8),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(labelText: 'Download URL *', hintText: 'Direct download link'),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    ).then((result) {
      if (result == true && urlController.text.trim().isNotEmpty) {
        setState(() {
          _downloadLinks.add(MovieDownloadLink(
            serverName: selectedServer ?? 'Server 1',
            url: urlController.text.trim(),
            quality: qualityController.text.trim().isEmpty ? null : qualityController.text.trim(),
            size: sizeController.text.trim().isEmpty ? null : sizeController.text.trim(),
            fileName: fileNameController.text.trim().isEmpty ? null : fileNameController.text.trim(),
          ));
        });
      }
    });
  }

  void _showAddWatchLinkModal() {
    String? selectedServer = _serverOptions.first;
    final urlController = TextEditingController();
    final qualityController = TextEditingController();
    final sizeController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Watch Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Select Server
                DropdownButtonFormField<String>(
                  value: selectedServer,
                  decoration: const InputDecoration(labelText: 'Select Server'),
                  items: _serverOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDialogState(() => selectedServer = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. 4K, 1080p, 720p')),
                const SizedBox(height: 8),
                TextField(controller: sizeController, decoration: const InputDecoration(labelText: 'Size', hintText: 'e.g. 4.5 GB')),
                const SizedBox(height: 8),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(labelText: 'Watch URL *', hintText: 'Player link for watching'),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    ).then((result) {
      if (result == true && urlController.text.trim().isNotEmpty) {
        setState(() {
          _watchLinks.add(MovieWatchLink(
            serverName: selectedServer ?? 'Server 1',
            url: urlController.text.trim(),
            quality: qualityController.text.trim().isEmpty ? null : qualityController.text.trim(),
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
