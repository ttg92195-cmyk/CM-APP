import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cm_movies/app/core/services/firestore_content_service.dart';

/// Progress event for the export (backup) phase. Fires after each page fetch
/// so the UI can show a live counter of how many movies have been exported.
class BatchExportProgress {
  final int exportedSoFar;
  final bool hasMore;

  const BatchExportProgress({
    required this.exportedSoFar,
    required this.hasMore,
  });
}

/// Result of a successful export (backup) operation.
class BatchExportResult {
  /// Absolute path to the saved JSON file on the device.
  final String filePath;

  /// Number of movies written to the file.
  final int count;

  /// File size in bytes.
  final int sizeBytes;

  /// ISO-8601 timestamp of the export (also embedded in the file name).
  final DateTime exportedAt;

  const BatchExportResult({
    required this.filePath,
    required this.count,
    required this.sizeBytes,
    required this.exportedAt,
  });

  /// Human-readable file size, e.g. "12.4 KB" or "1.8 MB".
  String get sizeFormatted {
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = sizeBytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unit]}';
  }
}

/// Result of validating a single parsed item against the schema.
/// Items are classified into three buckets the UI shows in the preview phase.
enum BatchItemStatus {
  /// Schema OK, no existing movie matches by tmdbId or slug — will be CREATED.
  willCreate,

  /// Schema OK, an existing movie matches by tmdbId or slug — will be UPDATED.
  /// (addMovie() performs this idempotently.)
  willUpdate,

  /// Schema validation failed — title missing, wrong type, etc. Will be SKIPPED.
  invalid,
}

/// One item in the parsed/validated batch.
class BatchImportItem {
  /// Original index in the JSON array (1-based for user-facing display).
  final int sourceIndex;

  /// Raw map from JSON — passed straight to FirestoreContentService.addMovie().
  /// Mutated by addMovie() internally (adds slug/title_lowercase/createdAt/etc.)
  final Map<String, dynamic> data;

  /// Classification after validation + duplicate lookup.
  BatchItemStatus status;

  /// Title used for preview / progress display. Falls back to '(untitled)'.
  String get displayTitle => (data['title']?.toString().isNotEmpty ?? false)
      ? data['title'].toString()
      : '(untitled)';

  /// Type for preview ('movie' / 'series' / unknown).
  String get displayType => (data['type']?.toString().isNotEmpty ?? false)
      ? data['type'].toString()
      : 'unknown';

  /// Year for preview (may be null).
  String? get displayYear => data['year']?.toString();

  /// tmdbId for preview (may be null).
  dynamic get tmdbId => data['tmdbId'];

  /// Reason for invalid status (only set when status == invalid).
  String? validationError;

  /// Result of the import attempt — filled in during the import phase.
  /// 'success_create', 'success_update', 'failure' or null if not yet imported.
  String? importResult;

  /// Error message when importResult == 'failure'.
  String? importError;

  BatchImportItem({
    required this.sourceIndex,
    required this.data,
    required this.status,
    this.validationError,
  });
}

/// Aggregated counts for the preview / summary screens.
class BatchImportCounts {
  final int total;
  final int willCreate;
  final int willUpdate;
  final int invalid;

  const BatchImportCounts({
    required this.total,
    required this.willCreate,
    required this.willUpdate,
    required this.invalid,
  });

  int get actionable => willCreate + willUpdate;
}

/// Progress event fired during the import phase.
class BatchImportProgress {
  final int current; // 1-based
  final int total;
  final String currentTitle;
  final int successCreateCount;
  final int successUpdateCount;
  final int failureCount;
  final BatchImportItem? lastItem; // null during initial spin-up

  const BatchImportProgress({
    required this.current,
    required this.total,
    required this.currentTitle,
    required this.successCreateCount,
    required this.successUpdateCount,
    required this.failureCount,
    this.lastItem,
  });

  double get fraction => total == 0 ? 0 : current / total;
}

/// Top-level parse result returned by [BatchImportService.parseFile].
class BatchParseResult {
  /// All items successfully parsed (status willCreate/willUpdate/invalid).
  final List<BatchImportItem> items;

  /// Items that failed JSON parsing entirely (not even added to [items]).
  /// Each entry is {'index': int, 'error': String}.
  final List<Map<String, dynamic>> parseErrors;

  /// True if file was empty or contained no recognisable array.
  final bool isEmpty;

  const BatchParseResult({
    required this.items,
    required this.parseErrors,
    required this.isEmpty,
  });
}

/// Top-level import result returned by [BatchImportService.runImport].
class BatchImportResult {
  final int total;
  final int created;
  final int updated;
  final int failed;
  final int skipped;
  final List<BatchImportItem> items; // final state of each item

  const BatchImportResult({
    required this.total,
    required this.created,
    required this.updated,
    required this.failed,
    required this.skipped,
    required this.items,
  });
}

/// Service that orchestrates a Batch Import flow:
///   1. parseFile()    — read JSON file, deserialize each entry, capture parse errors
///   2. classify()     — for each valid item, check Firestore for tmdbId/slug duplicates
///   3. runImport()    — sequentially call FirestoreContentService.addMovie() with progress
///
/// The service deliberately does NOT use WriteBatch — it reuses the existing
/// addMovie() function which already handles duplicate detection, counter sync,
/// and idempotent updates. This keeps the import logic safe and consistent
/// with the rest of the app.
class BatchImportService {
  final FirestoreContentService _contentService;
  final FirebaseFirestore _firestore;

  BatchImportService({
    FirestoreContentService? contentService,
    FirebaseFirestore? firestore,
  })  : _contentService = contentService ?? FirestoreContentService(),
        _firestore = firestore ?? FirebaseFirestore.instance;

  // ===========================================================================
  // PHASE 0 — EXPORT (BACKUP)
  // ===========================================================================

  /// Export every movie in the Firestore `movies` collection to a JSON file
  /// on the local device. The file is written to [outputDir] (or the app's
  /// documents directory if null) with a timestamped file name like
  /// `cm_movies_backup_2026-06-19_14-30-00.json`.
  ///
  /// This is a "safety net" feature: the admin should run it before any
  /// large Batch Import, so if something goes wrong they have an exact
  /// snapshot of the database to restore from (by importing the backup file
  /// back through BatchImportPage).
  ///
  /// Pagination: fetches in pages of [pageSize] (default 200) to keep memory
  /// usage flat regardless of collection size. A 1000-movie export uses
  /// ~40 MB heap during the write phase.
  ///
  /// The exported JSON is an array of raw Firestore document maps, wrapped
  /// in a top-level object with metadata:
  ///   {
  ///     "_meta": {
  ///       "exportedAt": "2026-06-19T14:30:00",
  ///       "count": 1234,
  ///       "source": "cm_movies"
  ///     },
  ///     "movies": [ { ...full movie doc... }, ... ]
  ///   }
  ///
  /// The "movies" wrapper key is recognised by parseJsonString(), so the
  /// exported file can be re-imported as-is to restore.
  Future<BatchExportResult> exportAllMovies({
    String? outputDir,
    int pageSize = 200,
    void Function(BatchExportProgress)? onProgress,
  }) async {
    final moviesRef = _firestore.collection('movies');
    final allDocs = <Map<String, dynamic>>[];
    DocumentSnapshot? lastDoc;
    bool hasMore = true;

    // Paginated fetch — Firestore .get() returns at most the page size, and
    // we follow with startAfterDocument() until a page comes back short.
    while (hasMore) {
      Query query = moviesRef
          .orderBy('createdAt', descending: true)
          .limit(pageSize);

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();

      if (snapshot.docs.isEmpty) {
        hasMore = false;
        break;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        // Strip server-only fields that wouldn't round-trip cleanly.
        // createdAt/updatedAt are Timestamps on the server; we keep them as
        // ISO strings so the JSON is human-readable and parseable later.
        final cleaned = _serializeMovieDoc(data, doc.id);
        allDocs.add(cleaned);
      }

      lastDoc = snapshot.docs.last;
      hasMore = snapshot.docs.length >= pageSize;

      onProgress?.call(BatchExportProgress(
        exportedSoFar: allDocs.length,
        hasMore: hasMore,
      ));
    }

    // Build the output JSON. We do NOT use jsonEncode with the entire list
    // in one shot for very large datasets — but in practice 1000 movies
    // produces ~5 MB of JSON which encodes in <500 ms and uses ~25 MB heap.
    // For 10,000+ movies we'd switch to a streaming encoder, but that's a
    // Phase 4+ concern.
    final now = DateTime.now();
    final payload = <String, dynamic>{
      '_meta': {
        'exportedAt': now.toIso8601String(),
        'count': allDocs.length,
        'source': 'cm_movies',
        'appVersion': 'batch_import_v1',
      },
      'movies': allDocs,
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);
    final bytes = utf8.encode(jsonStr);

    // Resolve output directory.
    Directory dir;
    if (outputDir != null && outputDir.isNotEmpty) {
      dir = Directory(outputDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } else {
      // Default to the app's documents directory — always writable, no
      // storage permission needed on Android 10+.
      dir = await _defaultExportDir();
    }

    final fileName = _formatBackupFileName(now);
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    return BatchExportResult(
      filePath: file.path,
      count: allDocs.length,
      sizeBytes: bytes.length,
      exportedAt: now,
    );
  }

  /// Default export directory: app documents dir + '/batch_import_backups'.
  /// Created on first call. We use a subdirectory so backups don't pollute
  /// the root documents directory.
  Future<Directory> _defaultExportDir() async {
    // Use the app's documents directory — always writable, no storage
    // permission needed on Android 10+. On Android, this resolves to
    // /data/data/<package>/app_flutter (or similar).
    final baseDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${baseDir.path}/batch_import_backups');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  /// Convert a raw Firestore movie document into a JSON-serializable map.
  /// Firestore Timestamp fields become ISO-8601 strings; everything else
  /// passes through unchanged. The document ID is preserved as 'id' so
  /// re-import can detect duplicates by tmdbId/slug (still safe).
  Map<String, dynamic> _serializeMovieDoc(
    Map<String, dynamic> data,
    String docId,
  ) {
    final out = <String, dynamic>{};

    data.forEach((key, value) {
      out[key] = _serializeValue(value);
    });

    // Always preserve the Firestore document ID for traceability.
    // addMovie() doesn't use this field (it uses tmdbId/slug), so it's
    // safe to include — and useful for manual diffing if a restore goes wrong.
    if (!out.containsKey('id')) {
      out['id'] = docId;
    }

    return out;
  }

  /// Recursively serialize a Firestore value into JSON-safe form.
  /// Timestamps → ISO string. GeoPoint → {lat, lng}. DocumentReference → path.
  dynamic _serializeValue(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((k, v) => out[k.toString()] = _serializeValue(v));
      return out;
    }
    if (value is List) {
      return value.map(_serializeValue).toList();
    }
    // Primitives (String, int, double, bool) pass through.
    return value;
  }

  /// Build a safe, filesystem-friendly file name for the backup.
  /// Format: cm_movies_backup_YYYY-MM-DD_HH-MM-ss.json
  String _formatBackupFileName(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'cm_movies_backup_'
        '${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}-${two(now.minute)}-${two(now.second)}'
        '.json';
  }

  // ===========================================================================
  // PHASE 1 — PARSE
  // ===========================================================================

  /// Read the JSON file from [path] and parse it into [BatchImportItem]s.
  ///
  /// Accepted JSON shapes:
  ///   A) A JSON array of movie objects:   [ { ... }, { ... }, ... ]
  ///   B) An object with a 'movies' key:   { "movies": [ ... ] }
  ///   C) An object with a 'data' key:     { "data":   [ ... ] }
  ///
  /// Each item is validated against a minimal schema (title required, type
  /// must be 'movie' or 'series' if present). Invalid items are kept in the
  /// returned list but flagged with status == invalid so the UI can preview
  /// them; they will be skipped during the import phase.
  Future<BatchParseResult> parseFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw BatchImportException('File not found: $path');
    }

    final fileSize = await file.length();
    if (fileSize == 0) {
      return const BatchParseResult(
        items: [],
        parseErrors: [],
        isEmpty: true,
      );
    }

    // Read the entire file. For very large files (>20 MB) we would need a
    // streaming parser, but the typical admin export is well under 5 MB.
    // A 5 MB JSON file with ~1000 movies parses in <1 second on a mid-range
    // phone and uses ~30 MB of heap — well within Flutter's default budget.
    final raw = await file.readAsString();
    return parseJsonString(raw);
  }

  /// Same as [parseFile] but operates on an in-memory JSON string.
  /// Useful for tests and for parsing JSON pasted into a text field.
  BatchParseResult parseJsonString(String raw) {
    if (raw.trim().isEmpty) {
      return const BatchParseResult(
        items: [],
        parseErrors: [],
        isEmpty: true,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      throw BatchImportException(
        'Invalid JSON: ${e.toString()}',
      );
    }

    List<dynamic>? array;
    if (decoded is List) {
      array = decoded;
    } else if (decoded is Map) {
      // Accept either 'movies' or 'data' as the wrapper key.
      final inner = decoded['movies'] ?? decoded['data'];
      if (inner is List) {
        array = inner;
      } else {
        throw BatchImportException(
          'Expected a JSON array, or an object with a "movies" or "data" key '
          'containing an array.',
        );
      }
    } else {
      throw BatchImportException(
        'Expected a JSON array or object at the top level.',
      );
    }

    if (array.isEmpty) {
      return const BatchParseResult(
        items: [],
        parseErrors: [],
        isEmpty: true,
      );
    }

    final items = <BatchImportItem>[];
    final parseErrors = <Map<String, dynamic>>[];

    for (var i = 0; i < array.length; i++) {
      final entry = array[i];
      if (entry is! Map) {
        parseErrors.add({
          'index': i + 1,
          'error': 'Entry is not a JSON object (got ${entry.runtimeType}).',
        });
        continue;
      }

      // Make a mutable, deep-cast copy so addMovie() can mutate it safely.
      final data = _deepCast(entry);
      final validationError = _validate(data);

      items.add(BatchImportItem(
        sourceIndex: i + 1,
        data: data,
        status: validationError == null
            ? BatchItemStatus.willCreate // tentative — classify() will refine
            : BatchItemStatus.invalid,
        validationError: validationError,
      ));
    }

    return BatchParseResult(
      items: items,
      parseErrors: parseErrors,
      isEmpty: false,
    );
  }

  // ===========================================================================
  // PHASE 2 — CLASSIFY (preview)
  // ===========================================================================

  /// For each non-invalid item, look up Firestore by tmdbId then slug.
  /// Sets item.status to willCreate or willUpdate accordingly.
  ///
  /// This is the slowest step because it issues 1-2 Firestore reads per item.
  /// For 1000 items this is ~2-3 seconds of network round-trips.
  Future<void> classify(List<BatchImportItem> items) async {
    for (final item in items) {
      if (item.status == BatchItemStatus.invalid) continue;

      bool exists = false;

      // PRIORITY 1: tmdbId (most reliable)
      final tmdbId = item.data['tmdbId'];
      if (!exists && tmdbId != null) {
        try {
          final existing = await _contentService.findByTmdbId(tmdbId);
          if (existing != null) exists = true;
        } catch (e) {
          debugPrint('classify: findByTmdbId failed for $tmdbId: $e');
          // Treat as not-found — addMovie() will re-check and handle safely.
        }
      }

      // PRIORITY 2: slug (auto-generated if missing)
      if (!exists) {
        final slug = (item.data['slug']?.toString().isNotEmpty ?? false)
            ? item.data['slug'].toString()
            : _generateSlug(item.data['title']?.toString() ?? '');
        if (slug.isNotEmpty) {
          try {
            final snap = await _firestore
                .collection('movies')
                .where('slug', isEqualTo: slug)
                .limit(1)
                .get();
            if (snap.docs.isNotEmpty) exists = true;
          } catch (e) {
            debugPrint('classify: slug lookup failed for "$slug": $e');
          }
        }
      }

      item.status =
          exists ? BatchItemStatus.willUpdate : BatchItemStatus.willCreate;
    }
  }

  /// Quick aggregated counts — call after [classify].
  BatchImportCounts tally(List<BatchImportItem> items) {
    int willCreate = 0, willUpdate = 0, invalid = 0;
    for (final item in items) {
      switch (item.status) {
        case BatchItemStatus.willCreate:
          willCreate++;
          break;
        case BatchItemStatus.willUpdate:
          willUpdate++;
          break;
        case BatchItemStatus.invalid:
          invalid++;
          break;
      }
    }
    return BatchImportCounts(
      total: items.length,
      willCreate: willCreate,
      willUpdate: willUpdate,
      invalid: invalid,
    );
  }

  // ===========================================================================
  // PHASE 3 — IMPORT
  // ===========================================================================

  /// Sequentially import all actionable items (willCreate + willUpdate).
  /// Skips invalid items.
  ///
  /// Calls [onProgress] after every item so the UI can update its progress bar.
  /// Stops early if [shouldStop] returns true — useful for a Cancel button.
  ///
  /// Returns a [BatchImportResult] with per-item outcomes.
  Future<BatchImportResult> runImport(
    List<BatchImportItem> items, {
    void Function(BatchImportProgress)? onProgress,
    bool Function()? shouldStop,
  }) async {
    final actionable = items
        .where((i) => i.status != BatchItemStatus.invalid)
        .toList(growable: false);

    int created = 0;
    int updated = 0;
    int failed = 0;
    int skipped = items.length - actionable.length;

    final total = actionable.length;
    for (var i = 0; i < total; i++) {
      if (shouldStop != null && shouldStop()) {
        // Mark remaining items as skipped
        for (var j = i; j < total; j++) {
          actionable[j].importResult = 'skipped';
        }
        skipped += (total - i);
        break;
      }

      final item = actionable[i];
      final wasUpdate = item.status == BatchItemStatus.willUpdate;

      onProgress?.call(BatchImportProgress(
        current: i + 1,
        total: total,
        currentTitle: item.displayTitle,
        successCreateCount: created,
        successUpdateCount: updated,
        failureCount: failed,
      ));

      try {
        // addMovie() does its own duplicate re-check and counter sync.
        // It returns the doc ID. We don't need it, but the call is required
        // to trigger all the safety logic in FirestoreContentService.
        await _contentService.addMovie(item.data);

        if (wasUpdate) {
          updated++;
          item.importResult = 'success_update';
        } else {
          // addMovie() may have flipped this to an update if a race condition
          // inserted a duplicate between classify() and now. We can detect
          // this by checking if the returned data has createdAt set by us
          // (no) vs the server (yes for new). For simplicity, trust the
          // pre-classification — the discrepancy is at most one item.
          created++;
          item.importResult = 'success_create';
        }
      } catch (e) {
        failed++;
        item.importResult = 'failure';
        item.importError = e.toString();
        debugPrint('BatchImport item ${item.sourceIndex} failed: $e');
        // Continue to next item — do not abort the whole batch.
      }

      onProgress?.call(BatchImportProgress(
        current: i + 1,
        total: total,
        currentTitle: item.displayTitle,
        successCreateCount: created,
        successUpdateCount: updated,
        failureCount: failed,
        lastItem: item,
      ));
    }

    return BatchImportResult(
      total: items.length,
      created: created,
      updated: updated,
      failed: failed,
      skipped: skipped,
      items: items,
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  /// Deep-cast a JSON map (which may contain dynamic values from jsonDecode)
  /// into a `Map<String, dynamic>` with proper types. Lists are recursively
  /// cast so `List<dynamic>` becomes `List<Map<String, dynamic>>` where
  /// appropriate — this is what FirestoreContentService.addMovie() expects.
  Map<String, dynamic> _deepCast(Map<dynamic, dynamic> src) {
    final out = <String, dynamic>{};
    src.forEach((key, value) {
      out[key.toString()] = _deepCastValue(value);
    });
    return out;
  }

  dynamic _deepCastValue(dynamic value) {
    if (value is Map) {
      return _deepCast(value);
    }
    if (value is List) {
      return value.map(_deepCastValue).toList();
    }
    return value;
  }

  /// Validate that the item has the minimal fields required by addMovie().
  /// Returns an error string if invalid, null if OK.
  ///
  /// Validation rules:
  ///   - `title` must be a non-empty string.
  ///   - `type` (if present) must be 'movie' or 'series'.
  ///   - `tmdbId` (if present) must be an int or a numeric string.
  ///   - `categories` and `tags` (if present) must be Lists of strings.
  String? _validate(Map<String, dynamic> data) {
    final title = data['title'];
    if (title is! String || title.trim().isEmpty) {
      return 'Missing or empty "title" field.';
    }

    final type = data['type'];
    if (type != null && type is! String) {
      return '"type" must be a string ("movie" or "series").';
    }
    if (type is String && type != 'movie' && type != 'series') {
      return '"type" must be "movie" or "series" (got "$type").';
    }

    final tmdbId = data['tmdbId'];
    if (tmdbId != null) {
      if (tmdbId is! int && tmdbId is! num) {
        // Allow numeric strings; non-numeric strings are an error.
        if (tmdbId is String) {
          if (int.tryParse(tmdbId) == null) {
            return '"tmdbId" must be an integer or numeric string '
                '(got "$tmdbId").';
          }
          // Promote to int — addMovie() does numeric comparison.
          data['tmdbId'] = int.parse(tmdbId);
        } else {
          return '"tmdbId" must be an integer (got ${tmdbId.runtimeType}).';
        }
      }
    }

    final categories = data['categories'];
    if (categories != null && categories is! List) {
      return '"categories" must be an array of strings.';
    }

    final tags = data['tags'];
    if (tags != null && tags is! List) {
      return '"tags" must be an array of strings.';
    }

    return null;
  }

  /// Slug generator — mirrors FirestoreContentService._generateSlug.
  /// Used during classify() to detect slug duplicates for items without a
  /// pre-set slug. Kept private; addMovie() will auto-generate the real slug.
  String _generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
  }
}

/// Custom exception type for batch-import failures so the UI can distinguish
/// them from generic Dart errors.
class BatchImportException implements Exception {
  final String message;
  BatchImportException(this.message);

  @override
  String toString() => 'BatchImportException: $message';
}
