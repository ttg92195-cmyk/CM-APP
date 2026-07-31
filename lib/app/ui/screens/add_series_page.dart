import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';

class AddSeriesPage extends StatefulWidget {
  const AddSeriesPage({super.key});

  @override
  State<AddSeriesPage> createState() => _AddSeriesPageState();
}

class _AddSeriesPageState extends State<AddSeriesPage> {
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
  List<Season> _seasons = [];

  // Server options (1-10)
  static const List<String> _serverOptions = [
    'Server 1', 'Server 2', 'Server 3', 'Server 4', 'Server 5',
    'Server 6', 'Server 7', 'Server 8', 'Server 9', 'Server 10',
  ];

  @override
  void initState() {
    super.initState();
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

  Future<void> _saveSeries() async {
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
        'duration': null, // Series doesn't have duration
        'fileSize': null, // Series doesn't have file size
        'format': null, // Series doesn't have format
        'isAdult': _isAdult ? 1 : 0,
        'type': 'series',
        'isTrending': _isTrending,
        'categories': _selectedGenres,
        'tags': _selectedTags,
        'directors': _directors,
        'casts': _casts.map((c) => {'name': c.name, 'profilePath': c.profilePath}).toList(),
        'downloadLinks': <Map<String, dynamic>>[],
        'watchLinks': <Map<String, dynamic>>[],
        'seasons': _seasons.map((s) => s.toMap()).toList(),
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
        title: const Text('Add Series'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveSeries,
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
                      decoration: const InputDecoration(labelText: 'Title *', hintText: 'Enter series title'),
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

                    // Resolution only (no Duration for series)
                    TextFormField(
                      controller: _resolutionController,
                      decoration: const InputDecoration(labelText: 'Resolution', hintText: 'e.g. 4K / 1080p / 720p'),
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

                    // Series Details header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE50914).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE50914).withOpacity(0.3)),
                      ),
                      child: const Text('Series Details', style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.bold, fontSize: 16)),
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
                        // AUDIT C5 — dispose the controller after the dialog
                        // closes. Director name is captured via the dialog's
                        // return value, so we can dispose before using it.
                        final controller = TextEditingController();
                        String? result;
                        try {
                          result = await showDialog<String>(
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
                        } finally {
                          controller.dispose();
                        }
                        if (result != null && result.isNotEmpty) {
                          final directorName = result.trim();
                          setState(() => _directors.add(directorName));
                        }
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
                        // AUDIT C5 — dispose both controllers in finally.
                        // Capture text values BEFORE disposal.
                        final nameController = TextEditingController();
                        final profileController = TextEditingController();
                        String? name;
                        String? profile;
                        try {
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
                          if (result == true) {
                            name = nameController.text.trim();
                            profile = profileController.text.trim();
                          }
                        } finally {
                          nameController.dispose();
                          profileController.dispose();
                        }
                        if (name != null && name.isNotEmpty) {
                          final castName = name;
                          final castProfile = (profile == null || profile.isEmpty) ? null : profile;
                          setState(() {
                            _casts.add(CastMember(
                              name: castName,
                              profilePath: castProfile,
                            ));
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Add Cast Member'),
                    ),
                    const SizedBox(height: 24),

                    // ===== SEASONS & EPISODES =====
                    _buildSectionTitle('Seasons & Episodes'),
                    const SizedBox(height: 12),

                    // Add Season button
                    OutlinedButton.icon(
                      onPressed: () => _showAddSeasonDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Season'),
                    ),
                    const SizedBox(height: 12),

                    // Seasons list with ExpansionTile
                    ..._seasons.asMap().entries.map((entry) {
                      final seasonIndex = entry.key;
                      final season = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.all(12),
                          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          // Phase 4.44 — remove the colored border line that
                          // Material 3 draws around the tile when expanded.
                          // Bro reported "Season 1 နိုပ်ရင် အနီရောင် မျဉ်းကြောင်း
                          // ပေါ်လာတာ" (a red/colored line appears when
                          // expanding Season 1). The default Material 3
                          // ExpansionTile uses `shape: RoundedRectangleBorder`
                          // with a BorderSide based on the theme's divider
                          // color, which shows up as a visible border around
                          // the tile only when expanded. Setting both `shape`
                          // and `collapsedShape` to `Border()` (empty border)
                          // removes this line on both states.
                          shape: const Border(),
                          collapsedShape: const Border(),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.video_library, color: Color(0xFFE50914), size: 22),
                          ),
                          title: Text(season.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          subtitle: Text('${season.episodes.length} episode${season.episodes.length == 1 ? '' : 's'}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                onPressed: () => setState(() => _seasons.removeAt(seasonIndex)),
                              ),
                            ],
                          ),
                          children: [
                            // Episodes
                            ...season.episodes.asMap().entries.map((epEntry) {
                              final epIndex = epEntry.key;
                              final episode = epEntry.value;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.play_circle_outline, size: 20, color: Color(0xFFE50914)),
                                title: Text(episode.name, style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                  '${episode.downloadLinks.length} download · ${episode.watchLinks.length} watch',
                                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white38 : Colors.black38)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 18),
                                      onPressed: () => _showEditEpisodeDialog(seasonIndex, epIndex),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                                      onPressed: () => setState(() => _seasons[seasonIndex].episodes.removeAt(epIndex)),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            // Add Episode buttons
                            // Phase 4.44 — stack vertically instead of in a Row.
                            // Bro reported "Add Episode (Download) Add Episode
                            // (Watch) ဆိုတယ်ဟာကနေရာမဆံဘူထင်ရပါတယ်"
                            // (the two buttons appear on the same line, looks
                            // like they're not separated). Changed from Row to
                            // Column with crossAxisAlignment.startAlign so
                            // each button gets its own line — Bro's exact
                            // requested layout:
                            //   Add Episode (Download)
                            //   Add Episode (Watch)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showAddEpisodeDownloadDialog(seasonIndex),
                                  icon: const Icon(Icons.download, size: 18),
                                  label: const Text('Add Episode (Download)'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _showAddEpisodeWatchDialog(seasonIndex),
                                  icon: const Icon(Icons.play_arrow, size: 18),
                                  label: const Text('Add Episode (Watch)'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }

  void _showAddSeasonDialog() {
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
        // Capture value BEFORE disposing controller.
        final seasonName = controller.text.trim();
        setState(() {
          _seasons.add(Season(name: seasonName));
        });
      }
    }).whenComplete(() {
      // AUDIT C5 — dispose controller.
      controller.dispose();
    });
  }

  void _showAddEpisodeDownloadDialog(int seasonIndex) {
    final episodeNameController = TextEditingController(text: 'Episode ${_seasons[seasonIndex].episodes.length + 1}');
    String? selectedServer = _serverOptions.first;
    final qualityController = TextEditingController();
    final sizeController = TextEditingController();
    final urlController = TextEditingController();
    final fileNameController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Add Episode - ${_seasons[seasonIndex].name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: episodeNameController, decoration: const InputDecoration(labelText: 'Episode Title *'), autofocus: true),
                const SizedBox(height: 8),
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
                TextField(controller: urlController, decoration: const InputDecoration(labelText: 'Download URL *', hintText: 'Direct download link'), keyboardType: TextInputType.url),
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
      if (result == true && episodeNameController.text.trim().isNotEmpty) {
        // Capture all values BEFORE disposing controllers below.
        final epName = episodeNameController.text.trim();
        final url = urlController.text.trim();
        final quality = qualityController.text.trim();
        final size = sizeController.text.trim();
        final fileName = fileNameController.text.trim();
        setState(() {
          // Find existing episode or create new one
          final existingIndex = _seasons[seasonIndex].episodes.indexWhere((e) => e.name == epName);
          if (existingIndex >= 0) {
            // Add download link to existing episode
            _seasons[seasonIndex].episodes[existingIndex].downloadLinks.add(MovieDownloadLink(
              serverName: selectedServer ?? 'Server 1',
              url: url,
              quality: quality.isEmpty ? null : quality,
              size: size.isEmpty ? null : size,
              fileName: fileName.isEmpty ? null : fileName,
            ));
          } else {
            // Create new episode with this download link
            _seasons[seasonIndex].episodes.add(Episode(
              name: epName,
              downloadLinks: [
                MovieDownloadLink(
                  serverName: selectedServer ?? 'Server 1',
                  url: url,
                  quality: quality.isEmpty ? null : quality,
                  size: size.isEmpty ? null : size,
                  fileName: fileName.isEmpty ? null : fileName,
                ),
              ],
              watchLinks: [],
            ));
          }
        });
      }
    }).whenComplete(() {
      // AUDIT C5 — dispose all five controllers.
      episodeNameController.dispose();
      qualityController.dispose();
      sizeController.dispose();
      urlController.dispose();
      fileNameController.dispose();
    });
  }

  void _showAddEpisodeWatchDialog(int seasonIndex) {
    final episodeNameController = TextEditingController(text: 'Episode ${_seasons[seasonIndex].episodes.length + 1}');
    String? selectedServer = _serverOptions.first;
    final qualityController = TextEditingController();
    final sizeController = TextEditingController();
    final urlController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Add Episode - ${_seasons[seasonIndex].name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: episodeNameController, decoration: const InputDecoration(labelText: 'Episode Title *'), autofocus: true),
                const SizedBox(height: 8),
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
                TextField(controller: urlController, decoration: const InputDecoration(labelText: 'Watch URL *', hintText: 'Player link for watching'), keyboardType: TextInputType.url),
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
      if (result == true && episodeNameController.text.trim().isNotEmpty) {
        // Capture all values BEFORE disposing controllers below.
        final epName = episodeNameController.text.trim();
        final url = urlController.text.trim();
        final quality = qualityController.text.trim();
        final size = sizeController.text.trim();
        setState(() {
          final existingIndex = _seasons[seasonIndex].episodes.indexWhere((e) => e.name == epName);
          if (existingIndex >= 0) {
            // Add watch link to existing episode
            _seasons[seasonIndex].episodes[existingIndex].watchLinks.add(MovieWatchLink(
              serverName: selectedServer ?? 'Server 1',
              url: url,
              quality: quality.isEmpty ? null : quality,
              size: size.isEmpty ? null : size,
            ));
          } else {
            // Create new episode with this watch link
            _seasons[seasonIndex].episodes.add(Episode(
              name: epName,
              downloadLinks: [],
              watchLinks: [
                MovieWatchLink(
                  serverName: selectedServer ?? 'Server 1',
                  url: url,
                  quality: quality.isEmpty ? null : quality,
                  size: size.isEmpty ? null : size,
                ),
              ],
            ));
          }
        });
      }
    }).whenComplete(() {
      // AUDIT C5 — dispose all four controllers.
      episodeNameController.dispose();
      qualityController.dispose();
      sizeController.dispose();
      urlController.dispose();
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
                  '${_seasons[seasonIndex].name} - ${episode.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // Download Links section
                    if (episode.downloadLinks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('Download Links', style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                      ),
                      ...episode.downloadLinks.asMap().entries.map((entry) {
                        final link = entry.value;
                        return ListTile(
                          dense: true,
                          title: Text(link.serverName),
                          subtitle: Text('${link.quality ?? ''} ${link.size ?? ''}'.trim()),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                            onPressed: () {
                              setState(() => episode.downloadLinks.removeAt(entry.key));
                              setModalState(() {});
                            },
                          ),
                        );
                      }),
                    ],
                    // Watch Links section
                    if (episode.watchLinks.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('Watch Links', style: TextStyle(fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
                      ),
                      ...episode.watchLinks.asMap().entries.map((entry) {
                        final link = entry.value;
                        return ListTile(
                          dense: true,
                          title: Text(link.serverName),
                          subtitle: Text('${link.quality ?? ''} ${link.size ?? ''}'.trim()),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                            onPressed: () {
                              setState(() => episode.watchLinks.removeAt(entry.key));
                              setModalState(() {});
                            },
                          ),
                        );
                      }),
                    ],
                    if (episode.downloadLinks.isEmpty && episode.watchLinks.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('No links yet'),
                      )),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAddDownloadLinkToEpisode(seasonIndex, episodeIndex);
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Add Download'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAddWatchLinkToEpisode(seasonIndex, episodeIndex);
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Add Watch'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914), foregroundColor: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDownloadLinkToEpisode(int seasonIndex, int episodeIndex) {
    String? selectedServer = _serverOptions.first;
    final qualityController = TextEditingController();
    final sizeController = TextEditingController();
    final urlController = TextEditingController();
    final fileNameController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${_seasons[seasonIndex].name} - ${_seasons[seasonIndex].episodes[episodeIndex].name} - Download Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedServer,
                  decoration: const InputDecoration(labelText: 'Select Server'),
                  items: _serverOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDialogState(() => selectedServer = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: fileNameController, decoration: const InputDecoration(labelText: 'File Name', hintText: 'e.g. Movie_Name_1080p.mkv')),
                const SizedBox(height: 8),
                TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. 720p, 1080p')),
                const SizedBox(height: 8),
                TextField(controller: sizeController, decoration: const InputDecoration(labelText: 'Size', hintText: 'e.g. 1.5 GB')),
                const SizedBox(height: 8),
                TextField(controller: urlController, decoration: const InputDecoration(labelText: 'Download URL *', hintText: 'Direct download link'), keyboardType: TextInputType.url),
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
        // Capture all values BEFORE disposing controllers below.
        final url = urlController.text.trim();
        final quality = qualityController.text.trim();
        final size = sizeController.text.trim();
        final fileName = fileNameController.text.trim();
        setState(() {
          _seasons[seasonIndex].episodes[episodeIndex].downloadLinks.add(MovieDownloadLink(
            serverName: selectedServer ?? 'Server 1',
            url: url,
            quality: quality.isEmpty ? null : quality,
            size: size.isEmpty ? null : size,
            fileName: fileName.isEmpty ? null : fileName,
          ));
        });
      }
    }).whenComplete(() {
      // AUDIT C5 — dispose all four controllers.
      qualityController.dispose();
      sizeController.dispose();
      urlController.dispose();
      fileNameController.dispose();
    });
  }

  void _showAddWatchLinkToEpisode(int seasonIndex, int episodeIndex) {
    String? selectedServer = _serverOptions.first;
    final qualityController = TextEditingController();
    final sizeController = TextEditingController();
    final urlController = TextEditingController();

    showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${_seasons[seasonIndex].name} - ${_seasons[seasonIndex].episodes[episodeIndex].name} - Watch Link'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedServer,
                  decoration: const InputDecoration(labelText: 'Select Server'),
                  items: _serverOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDialogState(() => selectedServer = v),
                ),
                const SizedBox(height: 8),
                TextField(controller: qualityController, decoration: const InputDecoration(labelText: 'Quality', hintText: 'e.g. 720p, 1080p')),
                const SizedBox(height: 8),
                TextField(controller: sizeController, decoration: const InputDecoration(labelText: 'Size', hintText: 'e.g. 1.5 GB')),
                const SizedBox(height: 8),
                TextField(controller: urlController, decoration: const InputDecoration(labelText: 'Watch URL *', hintText: 'Player link for watching'), keyboardType: TextInputType.url),
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
        // Capture all values BEFORE disposing controllers below.
        final url = urlController.text.trim();
        final quality = qualityController.text.trim();
        final size = sizeController.text.trim();
        setState(() {
          _seasons[seasonIndex].episodes[episodeIndex].watchLinks.add(MovieWatchLink(
            serverName: selectedServer ?? 'Server 1',
            url: url,
            quality: quality.isEmpty ? null : quality,
            size: size.isEmpty ? null : size,
          ));
        });
      }
    }).whenComplete(() {
      // AUDIT C5 — dispose all three controllers.
      qualityController.dispose();
      sizeController.dispose();
      urlController.dispose();
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
