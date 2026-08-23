// =============================================================================
// Phase 4 Step B — Reel Form Page (Add / Edit)
// =============================================================================
// A single form screen used for both creating a new Reel and editing an
// existing one. Reuses the layout patterns from add_movie_page.dart but
// adapted for the simpler Reel schema (no genres, tags, casts, directors,
// seasons — just title, description, poster, video, episodes, downloads).
//
// Usage:
//   // Add new Reel:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => const ReelFormPage(),
//   ));
//
//   // Edit existing Reel:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => ReelFormPage(reel: existingReel),
//   ));
//
// Form fields:
//   - Title (required, non-empty)
//   - Description (optional, multiline)
//   - Poster URL (optional, with live preview)
//   - Video URL (required, non-empty) — main video
//   - Episodes (dynamic list of {title, videoUrl, thumbnailUrl?}) — optional.
//     When episodes are added, the Reel becomes multi-episode and the
//     Reels Video Player (Step E) shows an Episodes icon.
//   - Download Links (dynamic list of strings) — optional.
//   - Trending toggle (default off).
//
// The form auto-generates `title_lowercase` and `slug` on the service side
// (ReelsService.addReel/updateReel) so the form does NOT need to send them.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/app/core/models/reel.dart';
import 'package:cm_movies/app/core/services/reels_service.dart';

class ReelFormPage extends StatefulWidget {
  /// When non-null, the form operates in EDIT mode and pre-populates
  /// all fields from this Reel. When null, the form is in ADD mode.
  final Reel? reel;

  const ReelFormPage({super.key, this.reel});

  @override
  State<ReelFormPage> createState() => _ReelFormPageState();
}

class _ReelFormPageState extends State<ReelFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _posterController = TextEditingController();
  final _videoUrlController = TextEditingController();

  // Episodes state — each entry is {title, videoUrl, thumbnailUrl?}.
  // The controller list mirrors `_episodes` so we can dispose them.
  List<Map<String, TextEditingController>> _episodeControllers = [];
  List<ReelEpisode> _episodes = [];

  // Download links — list of plain-string controllers.
  List<TextEditingController> _downloadLinkControllers = [];

  bool _isTrending = false;
  bool _isSaving = false;

  // ReelsService is a singleton; just call ReelsService.instance.
  // We don't need to inject it for the form's simple CRUD use case.

  @override
  void initState() {
    super.initState();
    // Pre-populate fields in edit mode.
    if (widget.reel != null) {
      final r = widget.reel!;
      _titleController.text = r.title;
      _descriptionController.text = r.description ?? '';
      _posterController.text = r.posterUrl ?? '';
      _videoUrlController.text = r.videoUrl;
      _episodes = List<ReelEpisode>.from(r.episodes);
      _downloadLinkControllers = r.downloadLinks
          .map((url) => TextEditingController(text: url))
          .toList();
      _isTrending = r.isTrending;
    }
    // Rebuild episode controllers from _episodes list.
    for (final ep in _episodes) {
      _episodeControllers.add({
        'title': TextEditingController(text: ep.title),
        'videoUrl': TextEditingController(text: ep.videoUrl),
        'thumbnailUrl': TextEditingController(text: ep.thumbnailUrl ?? ''),
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _posterController.dispose();
    _videoUrlController.dispose();
    for (final m in _episodeControllers) {
      m['title']?.dispose();
      m['videoUrl']?.dispose();
      m['thumbnailUrl']?.dispose();
    }
    for (final c in _downloadLinkControllers) {
      c.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================================
  // SAVE
  // ============================================================
  Future<void> _saveReel() async {
    if (!_formKey.currentState!.validate()) return;
    final title = _titleController.text.trim();
    final videoUrl = _videoUrlController.text.trim();
    if (title.isEmpty) {
      _showSnack('Title is required');
      return;
    }
    if (videoUrl.isEmpty) {
      _showSnack('Video URL is required');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Build episodes list from controllers.
      final episodes = <ReelEpisode>[];
      for (final m in _episodeControllers) {
        final epTitle = (m['title']?.text.trim()) ?? '';
        final epUrl = (m['videoUrl']?.text.trim()) ?? '';
        // Skip episode rows where BOTH title and url are empty — admin
        // may have added a placeholder row by mistake.
        if (epTitle.isEmpty && epUrl.isEmpty) continue;
        if (epUrl.isEmpty) {
          _showSnack('Episode "$epTitle" is missing a video URL');
          setState(() => _isSaving = false);
          return;
        }
        episodes.add(ReelEpisode(
          title: epTitle.isEmpty ? 'Episode ${episodes.length + 1}' : epTitle,
          videoUrl: epUrl,
          thumbnailUrl: (m['thumbnailUrl']?.text.trim() ?? '').isNotEmpty
              ? m['thumbnailUrl']!.text.trim()
              : null,
        ));
      }

      // Build download links list from controllers.
      final downloadLinks = _downloadLinkControllers
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // Build the Reel object.
      final reel = Reel(
        id: widget.reel?.id ?? '',
        title: title,
        titleLowercase: title.toLowerCase(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        posterUrl: _posterController.text.trim().isEmpty
            ? null
            : _posterController.text.trim(),
        videoUrl: videoUrl,
        episodes: episodes,
        downloadLinks: downloadLinks,
        // addReel always overwrites likeCount=0; updateReel preserves it
        // by NOT including it in the update payload (we exclude it below).
        likeCount: widget.reel?.likeCount ?? 0,
        isTrending: _isTrending,
        createdAt: widget.reel?.createdAt,
        updatedAt: widget.reel?.updatedAt,
      );

      if (widget.reel == null) {
        // ADD mode.
        await ReelsService.instance.addReel(reel);
      } else {
        // EDIT mode — send only changed fields + the admin-managed
        // updatedAt timestamp. Send the full field set so the service's
        // auto-derived title_lowercase + slug are recomputed.
        await ReelsService.instance.updateReel(reel.id, {
          'title': reel.title,
          'description': reel.description,
          'posterUrl': reel.posterUrl,
          'videoUrl': reel.videoUrl,
          'episodes': episodes.map((e) => e.toMap()).toList(),
          'downloadLinks': downloadLinks,
          'isTrending': _isTrending,
          // NOTE: likeCount is INTENTIONALLY NOT sent — admin must not
          // be able to spoof like counts. The service's updateReel()
          // leaves the field untouched when not present in the payload.
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.reel == null
              ? 'Reel added successfully!'
              : 'Reel updated successfully!')),
        );
        Navigator.pop(context, true); // pass `true` so caller knows to refresh
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ============================================================
  // EPISODE & DOWNLOAD LINK CRUD
  // ============================================================
  void _addEpisode() {
    setState(() {
      final titleCtrl = TextEditingController();
      final videoCtrl = TextEditingController();
      final thumbCtrl = TextEditingController();
      _episodeControllers.add({
        'title': titleCtrl,
        'videoUrl': videoCtrl,
        'thumbnailUrl': thumbCtrl,
      });
    });
  }

  void _removeEpisode(int index) {
    setState(() {
      final m = _episodeControllers.removeAt(index);
      m['title']?.dispose();
      m['videoUrl']?.dispose();
      m['thumbnailUrl']?.dispose();
    });
  }

  void _addDownloadLink() {
    setState(() {
      _downloadLinkControllers.add(TextEditingController());
    });
  }

  void _removeDownloadLink(int index) {
    setState(() {
      _downloadLinkControllers.removeAt(index).dispose();
    });
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditMode = widget.reel != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? 'Edit Reel' : 'Add Reel'),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveReel,
            icon: const Icon(Icons.save, color: Color(0xFFE50914)),
            label:
                const Text('Save', style: TextStyle(color: Color(0xFFE50914))),
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
                    // ====================== TITLE ======================
                    _buildSectionLabel('Title *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Reel title',
                        hintText: 'e.g. Behind the scenes — Tom Holland',
                        border: OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // ====================== DESCRIPTION ======================
                    _buildSectionLabel('Description'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'A short caption shown under the title',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      textInputAction: TextInputAction.newline,
                    ),
                    const SizedBox(height: 16),

                    // ====================== POSTER URL ======================
                    _buildSectionLabel('Poster URL'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _posterController,
                      decoration: const InputDecoration(
                        labelText: 'Poster image URL (optional)',
                        hintText: 'https://example.com/poster.jpg',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_posterController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 9 / 16,
                          child: CachedNetworkImage(
                            imageUrl: _posterController.text.trim(),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: isDark ? Colors.white10 : Colors.black12,
                              child: const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.red.withOpacity(0.1),
                              child: const Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.red, size: 32),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ====================== VIDEO URL ======================
                    _buildSectionLabel('Video URL *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _videoUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Main video URL',
                        hintText: 'https://example.com/reel.mp4',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Video URL is required' : null,
                    ),
                    const SizedBox(height: 16),

                    // ====================== EPISODES ======================
                    _buildSectionHeader(
                      'Episodes',
                      'Optional. Add multiple episodes to make this Reel multi-episode.',
                      onAdd: _addEpisode,
                      addLabel: 'Add Episode',
                    ),
                    ..._episodeControllers.asMap().entries.map((entry) {
                      final i = entry.key;
                      final m = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor:
                                        const Color(0xFFE50914).withOpacity(0.15),
                                    child: Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        color: Color(0xFFE50914),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text('Episode ${i + 1}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, size: 20),
                                    color: Colors.red.shade400,
                                    onPressed: () => _removeEpisode(i),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: m['title'],
                                decoration: const InputDecoration(
                                  labelText: 'Episode title',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: m['videoUrl'],
                                decoration: const InputDecoration(
                                  labelText: 'Episode video URL',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: m['thumbnailUrl'],
                                decoration: const InputDecoration(
                                  labelText: 'Episode thumbnail URL (optional)',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),

                    // ====================== DOWNLOAD LINKS ======================
                    _buildSectionHeader(
                      'Download Links',
                      'Optional. Direct download URLs.',
                      onAdd: _addDownloadLink,
                      addLabel: 'Add Link',
                    ),
                    ..._downloadLinkControllers.asMap().entries.map((entry) {
                      final i = entry.key;
                      final c = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor:
                                  const Color(0xFFE50914).withOpacity(0.15),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Color(0xFFE50914),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: c,
                                decoration: const InputDecoration(
                                  hintText: 'https://example.com/download.mp4',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.url,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, size: 20),
                              color: Colors.red.shade400,
                              onPressed: () => _removeDownloadLink(i),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),

                    // ====================== TRENDING TOGGLE ======================
                    SwitchListTile(
                      value: _isTrending,
                      onChanged: (v) => setState(() => _isTrending = v),
                      title: const Text('Mark as Trending'),
                      subtitle: const Text(
                        'Trending Reels appear in the Trending row (Phase 4 Step D).',
                        style: TextStyle(fontSize: 12),
                      ),
                      activeColor: const Color(0xFFE50914),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }

  // ============================================================
  // BUILD HELPERS
  // ============================================================
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle, {
    required VoidCallback onAdd,
    required String addLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(addLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
