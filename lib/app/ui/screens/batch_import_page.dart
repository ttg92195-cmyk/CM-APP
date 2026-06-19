import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cm_movies/app/core/services/batch_import_service.dart';

/// Full-screen page that walks the admin through a Batch Import flow:
///
///   Phase 1 — Pick:    choose a local JSON file (file_picker)
///   Phase 2 — Parse:   read file, validate schema, show parse errors if any
///   Phase 3 — Preview: classify each item (willCreate / willUpdate / invalid)
///                      by checking Firestore for tmdbId/slug duplicates
///   Phase 4 — Import:  sequentially call addMovie() with progress bar + Cancel
///   Phase 5 — Summary: success / failure counts + retry-failed button
///
/// The page is intentionally a state machine — each phase has its own UI.
/// This keeps the code linear and easy to reason about, and avoids the
/// "everything-on-one-screen" anti-pattern that bit the Settings page.
class BatchImportPage extends StatefulWidget {
  const BatchImportPage({super.key});

  @override
  State<BatchImportPage> createState() => _BatchImportPageState();
}

class _BatchImportPageState extends State<BatchImportPage> {
  final BatchImportService _service = BatchImportService();

  // State machine
  _Phase _phase = _Phase.idle;

  // File pick
  String? _filePath;
  String? _fileName;

  // Parse
  BatchParseResult? _parseResult;
  String? _parseError;

  // Classify (preview)
  bool _isClassifying = false;
  String? _classifyError;
  BatchImportCounts? _counts;
  List<BatchImportItem>? _items;

  // Import
  bool _isImporting = false;
  bool _cancelRequested = false;
  BatchImportProgress? _progress;
  BatchImportResult? _result;

  // Export (backup)
  bool _isExporting = false;
  int _exportedSoFar = 0;
  bool _exportHasMore = true;
  BatchExportResult? _lastExport;
  String? _exportError;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Batch Import (JSON)'),
        actions: [
          if (_phase == _Phase.preview || _phase == _Phase.parseError)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Start over',
              onPressed: _reset,
            ),
        ],
      ),
      body: SafeArea(
        child: _buildBodyForPhase(isDark),
      ),
    );
  }

  // ===========================================================================
  // PHASE ROUTER
  // ===========================================================================

  Widget _buildBodyForPhase(bool isDark) {
    switch (_phase) {
      case _Phase.idle:
        return _buildPickPhase(isDark);
      case _Phase.parsing:
        return _buildLoadingPhase('Parsing JSON file…', isDark);
      case _Phase.parseError:
        return _buildParseErrorPhase(isDark);
      case _Phase.preview:
        if (_isClassifying) {
          return _buildLoadingPhase('Checking Firestore for duplicates…', isDark);
        }
        return _buildPreviewPhase(isDark);
      case _Phase.importing:
        return _buildImportingPhase(isDark);
      case _Phase.summary:
        return _buildSummaryPhase(isDark);
    }
  }

  // ===========================================================================
  // PHASE 1 — PICK
  // ===========================================================================

  Widget _buildPickPhase(bool isDark) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero illustration
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: const Color(0xFFE50914).withOpacity(0.1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.upload_file,
                  size: 64,
                  color: const Color(0xFFE50914).withOpacity(0.85),
                ),
                const SizedBox(height: 12),
                Text(
                  'Batch Import Movies & Series',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Import multiple movies or series into Firestore from a single JSON file. The import is safe to re-run — duplicates are updated, not created twice.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? Colors.white70 : Colors.black54,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Selected file chip (if any)
          if (_fileName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFFE50914).withOpacity(0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Color(0xFFE50914), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fileName!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _filePath = null;
                      _fileName = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Pick button
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            label: Text(_filePath == null ? 'Choose JSON File' : 'Choose Different File'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: const Color(0xFFE50914),
              side: const BorderSide(color: Color(0xFFE50914)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Parse button (enabled once a file is chosen)
          FilledButton.icon(
            onPressed: _filePath == null ? null : _parseFile,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Parse & Validate'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDark
                  ? Colors.white12
                  : Colors.black12,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Backup section — recommended before any large import.
          _buildBackupCard(isDark),

          const SizedBox(height: 28),

          // Help / expected schema
          _buildSchemaHelpCard(isDark),
        ],
      ),
    );
  }

  // ===========================================================================
  // BACKUP / EXPORT CARD
  // ===========================================================================

  Widget _buildBackupCard(bool isDark) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue.withOpacity(0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.backup_outlined,
                  size: 20,
                  color: Colors.blue.shade400,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup Before Import',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Export all current movies & series to a JSON file. '
                      'Recommended before any large import — if something '
                      'goes wrong, you can re-import this file to restore.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Last export info (if any)
          if (_lastExport != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.green.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last backup: ${_lastExport!.count} movies • '
                          '${_lastExport!.sizeFormatted}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade300,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lastExport!.filePath,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontFamily: 'monospace',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Export error (if any)
          if (_exportError != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.red.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _exportError!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade300,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Export progress (while running)
          if (_isExporting) ...[
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _exportHasMore
                        ? 'Exporting… $_exportedSoFar movies fetched so far'
                        : 'Writing JSON file… $_exportedSoFar movies total',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Action row
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isExporting ? null : _runExport,
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: Text(
                    _isExporting ? 'Exporting…' : 'Export Database',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark
                        ? Colors.white12
                        : Colors.black12,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runExport() async {
    setState(() {
      _isExporting = true;
      _exportedSoFar = 0;
      _exportHasMore = true;
      _lastExport = null;
      _exportError = null;
    });

    try {
      final result = await _service.exportAllMovies(
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _exportedSoFar = p.exportedSoFar;
              _exportHasMore = p.hasMore;
            });
          }
        },
      );

      if (!mounted) return;
      setState(() {
        _lastExport = result;
        _isExporting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backup complete: ${result.count} movies (${result.sizeFormatted})',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _exportError = 'Export failed: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildSchemaHelpCard(bool isDark) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.blue.shade400),
              const SizedBox(width: 8),
              Text(
                'Expected JSON Schema',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'A JSON array of objects, or an object with a "movies" key. Each object must have at least:',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 8),
          _codeBlock(
            '''[
  {
    "title": "Inception",        // required
    "type": "movie",             // "movie" or "series"
    "year": "2010",
    "tmdbId": 27205,             // optional but recommended
    "poster": "https://...",
    "overview": "...",
    "categories": ["Action"],
    "tags": ["Mind-Bending"],
    "downloadLinks": [
      { "serverName": "Server 1", "url": "..." }
    ]
  }
]''',
            isDark,
          ),
          const SizedBox(height: 8),
          Text(
            'Required fields: title. Optional: type, year, tmdbId, slug, poster, '
            'backdrop, overview, rating, duration, categories, tags, '
            'downloadLinks, watchLinks, seasons (for series), isTrending, isAdult.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(String text, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D0D) : const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.4,
          color: isDark ? Colors.green.shade200 : Colors.black87,
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
      );
      if (result == null) return;
      final path = result.files.single.path;
      if (path == null) return;
      setState(() {
        _filePath = path;
        _fileName = result.files.single.name;
        _parseResult = null;
        _parseError = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File pick failed: $e')),
        );
      }
    }
  }

  // ===========================================================================
  // PHASE 2 — PARSE
  // ===========================================================================

  Future<void> _parseFile() async {
    if (_filePath == null) return;
    setState(() {
      _phase = _Phase.parsing;
      _parseError = null;
    });

    try {
      final result = await _service.parseFile(_filePath!);
      if (!mounted) return;

      if (result.isEmpty) {
        setState(() {
          _parseError = 'The file is empty or contains no items.';
          _phase = _Phase.parseError;
        });
        return;
      }

      setState(() {
        _parseResult = result;
        _phase = _Phase.preview;
      });

      // Kick off classification (Phase 3) automatically.
      _classify();
    } on BatchImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _parseError = e.message;
        _phase = _Phase.parseError;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _parseError = 'Unexpected error while parsing: $e';
        _phase = _Phase.parseError;
      });
    }
  }

  // ===========================================================================
  // PHASE 3 — CLASSIFY (preview)
  // ===========================================================================

  Future<void> _classify() async {
    if (_parseResult == null) return;
    setState(() {
      _isClassifying = true;
      _classifyError = null;
    });

    try {
      // Build a fresh list — classify() mutates item.status in place.
      final items = _parseResult!.items;
      await _service.classify(items);
      if (!mounted) return;
      setState(() {
        _items = items;
        _counts = _service.tally(items);
        _isClassifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isClassifying = false;
        _classifyError = 'Failed to check duplicates: $e';
      });
    }
  }

  Widget _buildPreviewPhase(bool isDark) {
    final theme = Theme.of(context);
    final counts = _counts;
    final items = _items;
    if (counts == null || items == null) {
      // Classify hasn't finished yet — _buildBodyForPhase shows the loading
      // variant when _isClassifying is true, so this branch shouldn't fire.
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Summary header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preview',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _fileName ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),
              // Counters
              Row(
                children: [
                  _countChip('Total', counts.total, Colors.blueGrey, isDark),
                  const SizedBox(width: 8),
                  _countChip('New', counts.willCreate, Colors.green, isDark),
                  const SizedBox(width: 8),
                  _countChip('Update', counts.willUpdate, Colors.orange, isDark),
                  const SizedBox(width: 8),
                  _countChip('Invalid', counts.invalid, Colors.red, isDark),
                ],
              ),
              if (_classifyError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _classifyError!,
                  style: TextStyle(color: Colors.red.shade400, fontSize: 12),
                ),
              ],
            ],
          ),
        ),

        // Items list
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'No items to display.',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final item = items[i];
                    return _previewItemTile(item, isDark);
                  },
                ),
        ),

        // Action bar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  counts.actionable == 0
                      ? 'Nothing to import.'
                      : '${counts.actionable} item${counts.actionable > 1 ? 's' : ''} will be imported.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: counts.actionable == 0 ? null : _startImport,
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Start Import'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE50914),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: isDark
                      ? Colors.white12
                      : Colors.black12,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _countChip(
    String label,
    int value,
    MaterialColor color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(isDark ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color.shade300,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color.shade300,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewItemTile(BatchImportItem item, bool isDark) {
    final (color, label) = switch (item.status) {
      BatchItemStatus.willCreate => (Colors.green, 'NEW'),
      BatchItemStatus.willUpdate => (Colors.orange, 'UPDATE'),
      BatchItemStatus.invalid => (Colors.red, 'INVALID'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Index
          SizedBox(
            width: 28,
            child: Text(
              '${item.sourceIndex}',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 10),
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Title + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.displayTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  children: [
                    if (item.displayType != 'unknown')
                      _metaText(item.displayType, isDark),
                    if (item.displayYear != null)
                      _metaText(item.displayYear!, isDark),
                    if (item.tmdbId != null)
                      _metaText('TMDB:${item.tmdbId}', isDark),
                  ],
                ),
                if (item.validationError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.validationError!,
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaText(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        color: isDark ? Colors.white54 : Colors.black54,
      ),
    );
  }

  // ===========================================================================
  // PHASE 4 — IMPORT
  // ===========================================================================

  Future<void> _startImport() async {
    if (_items == null) return;
    setState(() {
      _isImporting = true;
      _cancelRequested = false;
      _phase = _Phase.importing;
      _progress = null;
      _result = null;
    });

    try {
      final result = await _service.runImport(
        _items!,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        shouldStop: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _isImporting = false;
        _phase = _Phase.summary;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _phase = _Phase.summary;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Import aborted: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildImportingPhase(bool isDark) {
    final p = _progress;
    final double fraction = p?.fraction ?? 0;
    final int current = p?.current ?? 0;
    final int total = p?.total ?? (_items?.where((i) => i.status != BatchItemStatus.invalid).length ?? 0);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Circular progress
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: fraction > 0 ? fraction : null,
                    strokeWidth: 8,
                    backgroundColor:
                        const Color(0xFFE50914).withOpacity(0.15),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                  ),
                ),
                Text(
                  total == 0 ? '…' : '$current/$total',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Current item
          Text(
            p?.currentTitle ?? 'Starting…',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Linear progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction > 0 ? fraction : null,
              minHeight: 8,
              backgroundColor: const Color(0xFFE50914).withOpacity(0.15),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
            ),
          ),
          const SizedBox(height: 20),
          // Live counters
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _liveCounter('Created', p?.successCreateCount ?? 0, Colors.green),
              _liveCounter('Updated', p?.successUpdateCount ?? 0, Colors.orange),
              _liveCounter('Failed', p?.failureCount ?? 0, Colors.red),
            ],
          ),
          const SizedBox(height: 28),
          // Cancel button
          OutlinedButton.icon(
            onPressed: _cancelRequested
                ? null
                : () {
                    setState(() => _cancelRequested = true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Cancelling after the current item finishes…',
                        ),
                      ),
                    );
                  },
            icon: const Icon(Icons.cancel_outlined, color: Colors.red),
            label: Text(
              _cancelRequested ? 'Cancelling…' : 'Cancel',
              style: const TextStyle(color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveCounter(String label, int value, MaterialColor color) {
    return Column(
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // PHASE 5 — SUMMARY
  // ===========================================================================

  Widget _buildSummaryPhase(bool isDark) {
    final result = _result;
    if (result == null) {
      return const Center(child: Text('No import result.'));
    }

    final theme = Theme.of(context);
    final failedItems = result.items
        .where((i) => i.importResult == 'failure')
        .toList(growable: false);
    final hasFailures = failedItems.isNotEmpty;

    return Column(
      children: [
        // Header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          child: Column(
            children: [
              Icon(
                hasFailures ? Icons.warning_amber_rounded : Icons.check_circle,
                size: 56,
                color: hasFailures ? Colors.orange : Colors.green,
              ),
              const SizedBox(height: 8),
              Text(
                hasFailures ? 'Import Completed (with failures)' : 'Import Complete!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              // Big counters
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _liveCounter('Created', result.created, Colors.green),
                  _liveCounter('Updated', result.updated, Colors.orange),
                  _liveCounter('Failed', result.failed, Colors.red),
                  _liveCounter('Skipped', result.skipped, Colors.blueGrey),
                ],
              ),
            ],
          ),
        ),

        // Failed items list (if any)
        if (hasFailures)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Text(
                    'Failed Items (${failedItems.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
                ...failedItems.map(
                  (item) => Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E1E)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${item.sourceIndex}',
                          style: TextStyle(
                            color: Colors.red.shade400,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayTitle,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.importError != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.importError!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'All actionable items imported successfully.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),

        // Action bar
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.black12,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Import Another'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(result),
                  icon: const Icon(Icons.check),
                  label: const Text('Done'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SHARED / ERROR PHASES
  // ===========================================================================

  Widget _buildLoadingPhase(String message, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParseErrorPhase(bool isDark) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.error_outline,
            size: 56,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 12),
          Text(
            'Parse Error',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: SelectableText(
              _parseError ?? 'Unknown error.',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.red.shade200 : Colors.red.shade700,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Show parse errors per entry (if any)
          if (_parseResult?.parseErrors.isNotEmpty == true) ...[
            Text(
              '${_parseResult!.parseErrors.length} entries could not be parsed:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            ..._parseResult!.parseErrors.take(20).map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• #${e['index']}: ${e['error']}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ),
            if (_parseResult!.parseErrors.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '… and ${_parseResult!.parseErrors.length - 20} more.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
          ],

          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // STATE HELPERS
  // ===========================================================================

  void _reset() {
    setState(() {
      _phase = _Phase.idle;
      _filePath = null;
      _fileName = null;
      _parseResult = null;
      _parseError = null;
      _isClassifying = false;
      _classifyError = null;
      _counts = null;
      _items = null;
      _isImporting = false;
      _cancelRequested = false;
      _progress = null;
      _result = null;
      // NOTE: We intentionally do NOT reset _lastExport here — the backup
      // info card should persist across imports so the user can see which
      // backup file is the most recent one. Resetting _isExporting / error
      // is fine in case the user navigated away mid-export.
      _isExporting = false;
      _exportError = null;
    });
  }
}

/// Internal phase enum — kept private so callers can't accidentally drive
/// the page into an inconsistent state.
enum _Phase {
  idle,        // pick file
  parsing,     // reading + parsing JSON
  parseError,  // JSON invalid — show error
  preview,     // parse OK — show classified counts + items
  importing,   // sequential addMovie() loop running
  summary,     // import finished — show counts + failed items
}
