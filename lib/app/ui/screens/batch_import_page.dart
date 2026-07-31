import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cm_movies/app/core/services/batch_import_service.dart';
import 'package:cm_movies/app/core/services/saf_storage_service.dart';
import 'package:cm_movies/app/ui/screens/batch_import_history_page.dart';

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

  // File pick — Phase 4.45: support multiple files.
  // Bro reported "Choose JSON File နိုပ်ရင် JSON File တခုဘဲတင်ရတာကြောင့်
  // တပြိုင်နက်ရွေးချယ်ရအောင်လုပ်ပေးနိုင်မလာ" (currently only one file at a
  // time, please allow selecting multiple files at once).
  //
  // We keep the single-valued `_filePath` / `_fileName` / `_fileSizeBytes`
  // fields for backward-compat with code paths that haven't been migrated
  // yet (they always reflect the FIRST file in `_pickedFiles`), but the
  // source of truth is now `_pickedFiles`.
  final List<_PickedFile> _pickedFiles = [];

  /// Convenience: the first picked file, or null if none. Used by code paths
  /// that haven't been migrated to multi-file yet.
  String? get _filePath =>
      _pickedFiles.isEmpty ? null : _pickedFiles.first.path;
  String? get _fileName =>
      _pickedFiles.isEmpty ? null : _pickedFiles.first.name;

  /// Total size across all picked files (sum). null if no files picked OR
  /// if any file has size 0 (file_picker sometimes returns 0 on web flows).
  int? get _fileSizeBytes {
    if (_pickedFiles.isEmpty) return null;
    var total = 0;
    var anyZero = false;
    for (final f in _pickedFiles) {
      if (f.sizeBytes == 0) {
        anyZero = true;
      }
      total += f.sizeBytes;
    }
    return anyZero ? null : total;
  }

  /// True when ANY picked file is above the service's soft warning threshold
  /// (5 MB). Drives the orange "large file" chip styling and forces a
  /// confirmation dialog before parsing.
  bool get _isLargeFile =>
      _pickedFiles.any((f) =>
          f.sizeBytes > BatchImportService.largeFileWarningBytes);

  /// Phase 4.45 — human-readable label for the picked file(s), used in the
  /// importing phase header and the audit log.
  /// Returns null if no files are picked.
  /// Examples:
  ///   "backup.json"
  ///   "backup.json +2 more"
  String? get _sourceFileLabel {
    if (_pickedFiles.isEmpty) return null;
    if (_pickedFiles.length == 1) return _pickedFiles.first.name;
    final firstName = _pickedFiles.first.name;
    final extra = _pickedFiles.length - 1;
    return '$firstName +$extra more';
  }

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
  /// True when [_result] came from a retry run — used by the summary header
  /// to say "Retry Complete!" instead of "Import Complete!".
  bool _isRetryResult = false;

  // Export (backup)
  bool _isExporting = false;
  int _exportedSoFar = 0;
  bool _exportHasMore = true;
  BatchExportResult? _lastExport;
  String? _exportError;
  // Phase 4.45 — when set, the export was also copied to the user's SAF
  // folder (Downloads, etc.) so they can access it from outside the app.
  // This is the human-readable path shown in the success card.
  String? _exportSafPath;

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
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Import History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BatchImportHistoryPage(),
                ),
              );
            },
          ),
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

          // Selected file(s) chip — Phase 4.45: show a column of chips
          // (one per picked file) when multiple files are selected.
          if (_pickedFiles.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _isLargeFile
                      ? Colors.orange.withOpacity(0.6)
                      : const Color(0xFFE50914).withOpacity(0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row: "N file(s) selected" + total size + clear-all
                  Row(
                    children: [
                      Icon(
                        _isLargeFile ? Icons.warning_amber_rounded : Icons.insert_drive_file,
                        color: _isLargeFile ? Colors.orange : const Color(0xFFE50914),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pickedFiles.length == 1
                                  ? _pickedFiles.first.name
                                  : '${_pickedFiles.length} files selected',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_fileSizeBytes != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                _isLargeFile
                                    ? '${BatchImportService.formatFileSize(_fileSizeBytes!)} total • large file — confirm before parsing'
                                    : BatchImportService.formatFileSize(_fileSizeBytes!),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _isLargeFile
                                      ? Colors.orange.shade300
                                      : (isDark ? Colors.white54 : Colors.black54),
                                  fontWeight: _isLargeFile ? FontWeight.w600 : FontWeight.w400,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear all',
                        onPressed: () => setState(() {
                          _pickedFiles.clear();
                          _parseResult = null;
                          _parseError = null;
                        }),
                      ),
                    ],
                  ),
                  // Per-file list (only when more than one file is picked).
                  if (_pickedFiles.length > 1) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    ..._pickedFiles.asMap().entries.map((entry) {
                      final index = entry.key;
                      final f = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              f.sizeBytes > BatchImportService.largeFileWarningBytes
                                  ? Icons.warning_amber_rounded
                                  : Icons.description,
                              size: 16,
                              color: f.sizeBytes > BatchImportService.largeFileWarningBytes
                                  ? Colors.orange
                                  : (isDark ? Colors.white54 : Colors.black54),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                f.name,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (f.sizeBytes > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  BatchImportService.formatFileSize(f.sizeBytes),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              tooltip: 'Remove this file',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                              onPressed: () => _removePickedFile(index),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Pick button
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            // Phase 4.45 — button label now reflects multi-file support.
            label: Text(_pickedFiles.isEmpty
                ? 'Choose JSON File(s)'
                : 'Choose Different Files'),
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

          // Parse button (enabled once at least one file is chosen)
          FilledButton.icon(
            onPressed: _pickedFiles.isEmpty ? null : _parseFile,
            icon: const Icon(Icons.play_arrow),
            label: Text(_pickedFiles.length > 1
                ? 'Parse & Validate ${_pickedFiles.length} Files'
                : 'Parse & Validate'),
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
                          // Phase 4.45 — if the file was also copied to the
                          // SAF folder, show the user-accessible path
                          // (much more useful than the private internal path).
                          // Otherwise show the private internal path.
                          _exportSafPath != null
                              ? 'Saved to: $_exportSafPath'
                              : _lastExport!.filePath,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: _exportSafPath != null
                                ? Colors.green.shade300
                                : (isDark ? Colors.white54 : Colors.black54),
                            fontFamily: 'monospace',
                          ),
                          maxLines: 2,
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
      _exportSafPath = null;
    });

    try {
      // Step 1: Run the export — saves to the app's private documents dir
      // (always writable, no permission needed).
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

      // Step 2 — Phase 4.45: ALSO copy the file to the user's SAF folder
      // (Downloads, etc.) so they can access it from outside the app.
      //
      // Before this fix, the export saved to /data/data/<package>/app_flutter/
      // batch_import_backups/... which is the app's PRIVATE internal storage.
      // Bro couldn't find the file in any file manager — from their
      // perspective the export "didn't work". Now we copy it to the
      // user-selected SAF folder (which they picked during onboarding or
      // via Settings → Download Location). If no SAF folder is set, we
      // prompt them to pick one.
      String? safPath;
      try {
        final saf = SafStorageService.instance;
        var hasFolder = await saf.hasStoredFolder();

        // If no SAF folder is set OR the stored permission is no longer
        // valid (user revoked it), prompt the user to pick one. We don't
        // force this — if they cancel, the export still saved to the
        // private dir and they get the private path in the success card.
        if (!hasFolder || !(await saf.isSafPermissionValid())) {
          if (!mounted) return;
          final confirmed = await _showPickSafFolderDialog();
          if (confirmed) {
            final folderResult = await saf.openFolderPicker();
            hasFolder = folderResult != null;
          }
          // If user declined, hasFolder stays false — we skip the SAF
          // copy and just show the private path. The export itself still
          // succeeded.
        }

        if (hasFolder) {
          final fileName = _basename(result.filePath);
          final copied = await saf.saveFileToSafFolder(
            sourceFilePath: result.filePath,
            fileName: fileName,
          );
          if (copied) {
            safPath = await saf.getStoredTreePath();
          }
        }
      } catch (e) {
        // Don't fail the whole export if the SAF copy fails — the file
        // is still saved in the app's private dir.
        debugPrint('Phase 4.45 SAF copy failed (non-fatal): $e');
      }

      if (!mounted) return;
      setState(() {
        _lastExport = result;
        _exportSafPath = safPath;
        _isExporting = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safPath != null
                ? 'Backup complete: ${result.count} movies saved to your folder'
                : 'Backup complete: ${result.count} movies (${result.sizeFormatted})',
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

  /// Phase 4.45 — prompt the user to pick a SAF folder for the export.
  /// Returns true if they tapped "Pick Folder", false if they cancelled.
  Future<bool> _showPickSafFolderDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Backup Where?'),
        content: const Text(
          'To access the backup file from outside the app (e.g. from your '
          'file manager or Downloads folder), pick a folder on your device.\n\n'
          'The backup will also be saved inside the app\'s private storage '
          'regardless of your choice.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
            ),
            child: const Text('Pick Folder'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Phase 4.45 — extract the file name from a full path.
  /// Used to pass the backup file name to SafStorageService.saveFileToSafFolder.
  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final lastSlash = normalized.lastIndexOf('/');
    return lastSlash >= 0 ? normalized.substring(lastSlash + 1) : normalized;
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
      // Phase 4.45 — allowMultiple: true. Bro requested "တပြိုင်နက်ရွေးချယ်ရ
      // အောင်လုပ်ပေးနိုင်မလာ" (be able to select multiple files at once).
      // FilePicker returns a list of PlatformFile when allowMultiple is true.
      // We replace _pickedFiles with the new selection (additive selection
      // across multiple picker invocations would be confusing UX).
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: false,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      setState(() {
        _pickedFiles
          ..clear()
          ..addAll(result.files.map((picked) {
            final path = picked.path;
            return _PickedFile(
              path: path ?? '',
              name: picked.name,
              sizeBytes: picked.size,
            );
          }).where((f) => f.path.isNotEmpty));
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

  /// Phase 4.45 — remove a single file from the picked list by index.
  void _removePickedFile(int index) {
    setState(() {
      _pickedFiles.removeAt(index);
      _parseResult = null;
      _parseError = null;
    });
  }

  // ===========================================================================
  // PHASE 2 — PARSE
  // ===========================================================================

  Future<void> _parseFile() async {
    // Phase 4.45 — parse ALL picked files and merge items into one batch.
    // Each file is parsed individually (so per-file errors are clear), then
    // items are concatenated and parse errors are merged.
    if (_pickedFiles.isEmpty) return;

    // Large-file confirmation gate. Triggered if ANY file is above the soft
    // warning threshold. The service has a hard 50 MB cap per file that
    // throws after picking — but for files between 5 MB and 50 MB we want
    // to give the admin a chance to back out BEFORE we kick off the parse,
    // since parsing a 30 MB JSON file can take 5+ seconds on a low-end
    // phone and uses ~200 MB of heap.
    if (_isLargeFile) {
      final confirmed = await _showLargeFileConfirmDialog();
      if (!confirmed) return;
    }

    setState(() {
      _phase = _Phase.parsing;
      _parseError = null;
    });

    try {
      final mergedItems = <BatchImportItem>[];
      final mergedParseErrors = <String>[];
      var anyEmpty = false;

      for (var i = 0; i < _pickedFiles.length; i++) {
        final picked = _pickedFiles[i];
        final result = await _service.parseFile(picked.path);

        // Track if EVERY file was empty (so we can show the empty message).
        if (result.isEmpty) {
          anyEmpty = true;
        }

        // Prefix per-file errors with the file name so the admin can see
        // WHICH file had the problem.
        if (result.parseErrors.isNotEmpty) {
          for (final err in result.parseErrors) {
            mergedParseErrors.add('[${picked.name}] $err');
          }
        }

        // Append items. We DO NOT de-duplicate across files here — the
        // classify phase (next) detects duplicates against the EXISTING
        // Firestore database, not against other items in this batch.
        // If two JSON files contain the same movie (same tmdbId/slug),
        // addMovie() handles it idempotently (creates once, updates after).
        mergedItems.addAll(result.items);
      }

      if (!mounted) return;

      if (mergedItems.isEmpty) {
        setState(() {
          _parseError = anyEmpty
              ? 'All ${_pickedFiles.length} file(s) are empty or contain no items.'
              : 'No valid items found in ${_pickedFiles.length} file(s). '
                  'Check the parse errors below.';
          _phase = _Phase.parseError;
        });
        return;
      }

      setState(() {
        _parseResult = BatchParseResult(
          items: mergedItems,
          parseErrors: mergedParseErrors,
          isEmpty: false,
        );
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

  /// Confirmation dialog shown before parsing a file above
  /// [BatchImportService.largeFileWarningBytes]. Returns true if the admin
  /// tapped "Parse Anyway", false if they cancelled.
  ///
  /// This is a UX nudge only — the service's [BatchImportService.parseFile]
  /// has its own hard cap that throws a [BatchImportException] for files
  /// above [BatchImportService.maxFileSizeBytes].
  Future<bool> _showLargeFileConfirmDialog() async {
    if (!mounted) return false;
    // Phase 4.45 — support multi-file: total size is the sum across all
    // picked files. The dialog now also mentions the file count when more
    // than one file is selected.
    final sizeStr = _fileSizeBytes != null
        ? BatchImportService.formatFileSize(_fileSizeBytes!)
        : 'unknown';
    final fileCountStr = _pickedFiles.length == 1
        ? 'the selected file'
        : 'all ${_pickedFiles.length} selected files (combined)';
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          title: const Text('Large File Warning'),
          content: Text(
            'Total size of $fileCountStr is $sizeStr.\n\n'
            'Parsing a large JSON file can take several seconds and uses '
            'a lot of memory on low-end devices. If the app feels sluggish '
            'or crashes, consider splitting the file into smaller batches '
            'of ~1000 movies each.\n\n'
            'Files larger than ${BatchImportService.formatFileSize(
              BatchImportService.maxFileSizeBytes,
            )} (each) will be refused outright.\n\n'
            'Do you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Parse Anyway'),
            ),
          ],
        );
      },
    );
    return result ?? false;
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
                // Phase 4.45 — show "file1.json +2 more" when multiple
                // files were merged into this import.
                _sourceFileLabel ?? '',
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
      _isRetryResult = false;
    });

    // Build audit context (best-effort: if the user is somehow not signed
    // in, runImport() will still work — it just won't write an audit row).
    String? appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Non-fatal: audit log will simply have a null appVersion.
    }

    final auditContext = BatchImportService.currentAdminContext(
      sourceFileName: _sourceFileLabel,
      sourceFileSizeBytes: _fileSizeBytes,
      appVersion: appVersion,
    );

    try {
      final result = await _service.runImport(
        _items!,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        shouldStop: () => _cancelRequested,
        auditContext: auditContext,
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

  /// Re-import only the items that failed in the previous run.
  ///
  /// This is invoked from the summary phase's "Retry Failed" button. It
  /// re-uses the in-memory `_result.items` list (so we still have the full
  /// movie data for each failed item) and delegates to
  /// `BatchImportService.retryFailed()`.
  ///
  /// On completion, the summary screen shows the retry's outcomes (created /
  /// updated / failed / skipped) — NOT the original batch's. The previous
  /// failed-items list is replaced with whatever failed AGAIN in this retry.
  /// A fresh audit log row is written with `isRetry: true`.
  Future<void> _retryFailed() async {
    final previousResult = _result;
    if (previousResult == null) return;
    if (previousResult.failed == 0) {
      // Nothing to retry — defensive; the button should be hidden in this case.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No failed items to retry.'),
          backgroundColor: Colors.blueGrey,
        ),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _cancelRequested = false;
      _phase = _Phase.importing;
      _progress = null;
      // Keep _result around so _buildImportingPhase can show the total
      // count of actionable items from the retry's perspective. We replace
      // it with the retry result on completion.
    });

    // Build audit context with isRetry: true so the new audit row is marked.
    String? appVersion;
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Non-fatal.
    }

    final auditContext = BatchImportService.currentAdminContext(
      sourceFileName: _sourceFileLabel != null ? '(retry) $_sourceFileLabel' : '(retry)',
      sourceFileSizeBytes: _fileSizeBytes,
      appVersion: appVersion,
    )?.copyWith(isRetry: true);

    try {
      final retryResult = await _service.retryFailed(
        previousResult.items,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        shouldStop: () => _cancelRequested,
        auditContext: auditContext,
      );
      if (!mounted) return;
      setState(() {
        _result = retryResult;
        _isRetryResult = true;
        _isImporting = false;
        _phase = _Phase.summary;
      });

      // Brief SnackBar to confirm what just happened.
      final msg = retryResult.failed == 0
          ? 'Retry complete: all ${retryResult.created + retryResult.updated} '
              'previously-failed items now succeeded.'
          : 'Retry partial: ${retryResult.created + retryResult.updated} '
              'succeeded, ${retryResult.failed} still failing.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor:
                retryResult.failed == 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _phase = _Phase.summary;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry aborted: $e'),
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
                _isRetryResult
                    ? (hasFailures
                        ? 'Retry Completed (with failures)'
                        : 'Retry Complete!')
                    : (hasFailures
                        ? 'Import Completed (with failures)'
                        : 'Import Complete!'),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Retry button — full-width, only shown when there are failures.
              // Suppressed after a retry run to avoid an infinite retry loop
              // in the UI (admin can hit "Import Another" to start fresh).
              if (hasFailures && !_isRetryResult) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _retryFailed,
                    icon: const Icon(Icons.replay),
                    label: Text(
                      'Retry ${failedItems.length} Failed Item'
                      '${failedItems.length == 1 ? '' : 's'}',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isDark
                          ? Colors.white12
                          : Colors.black12,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              // Bottom row: Import Another (outlined) + Done (filled red)
              Row(
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
      _pickedFiles.clear();
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
      _isRetryResult = false;
      // NOTE: We intentionally do NOT reset _lastExport here — the backup
      // info card should persist across imports so the user can see which
      // backup file is the most recent one. Resetting _isExporting / error
      // is fine in case the user navigated away mid-export.
      _isExporting = false;
      _exportError = null;
    });
  }
}

/// Phase 4.45 — simple holder for one picked JSON file.
class _PickedFile {
  final String path;
  final String name;
  final int sizeBytes;

  const _PickedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });
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
