import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cm_movies/app/core/services/saf_storage_service.dart';
import 'package:open_filex/open_filex.dart';

/// Enum for download status
enum DownloadStatus {
  idle, // Not started
  downloading, // Actively downloading
  paused, // Paused by user
  completed, // Finished
  failed, // Error occurred
}

/// Model for a single download task
class DownloadTask {
  final String id; // Unique ID (movieId_quality)
  final String movieId;
  final String movieTitle;
  final String? moviePoster;
  final String url;
  final String quality;
  final String? size;
  final String serverName;
  final String savePath;
  final DateTime addedAt;
  final DateTime? completedAt;

  // Download state
  final DownloadStatus status;
  final double progress; // 0.0 to 1.0
  final int downloadedBytes;
  final int? totalBytes;
  final String? errorMessage;

  // Speed tracking
  final double speedBytesPerSec; // Current download speed
  final int? etaSeconds; // Estimated time remaining

  DownloadTask({
    required this.id,
    required this.movieId,
    required this.movieTitle,
    this.moviePoster,
    required this.url,
    required this.quality,
    this.size,
    required this.serverName,
    required this.savePath,
    required this.addedAt,
    this.completedAt,
    this.status = DownloadStatus.idle,
    this.progress = 0.0,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.errorMessage,
    this.speedBytesPerSec = 0.0,
    this.etaSeconds,
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
    DateTime? completedAt,
    double? speedBytesPerSec,
    int? etaSeconds,
    String? savePath,
  }) {
    return DownloadTask(
      id: id,
      movieId: movieId,
      movieTitle: movieTitle,
      moviePoster: moviePoster,
      url: url,
      quality: quality,
      size: size,
      serverName: serverName,
      savePath: savePath ?? this.savePath,
      addedAt: addedAt,
      completedAt: completedAt ?? this.completedAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      etaSeconds: etaSeconds ?? this.etaSeconds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'movieId': movieId,
      'movieTitle': movieTitle,
      'moviePoster': moviePoster,
      'url': url,
      'quality': quality,
      'size': size,
      'serverName': serverName,
      'savePath': savePath,
      'addedAt': addedAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'status': status.index,
      'progress': progress,
      'downloadedBytes': downloadedBytes,
      'totalBytes': totalBytes,
      'errorMessage': errorMessage,
      'speedBytesPerSec': speedBytesPerSec,
      'etaSeconds': etaSeconds,
    };
  }

  factory DownloadTask.fromMap(Map<String, dynamic> map) {
    return DownloadTask(
      id: map['id'] as String? ?? '',
      movieId: map['movieId'] as String? ?? '',
      movieTitle: map['movieTitle'] as String? ?? '',
      moviePoster: map['moviePoster'] as String?,
      url: map['url'] as String? ?? '',
      quality: map['quality'] as String? ?? '',
      size: map['size']?.toString(),
      serverName: map['serverName'] as String? ?? '',
      savePath: map['savePath'] as String? ?? '',
      addedAt: DateTime.tryParse(map['addedAt'] as String? ?? '') ?? DateTime.now(),
      completedAt: map['completedAt'] != null
          ? DateTime.tryParse(map['completedAt'] as String)
          : null,
      status: DownloadStatus.values[map['status'] as int? ?? 0],
      progress: (map['progress'] as num?)?.toDouble() ?? 0.0,
      downloadedBytes: map['downloadedBytes'] as int? ?? 0,
      totalBytes: map['totalBytes'] as int?,
      errorMessage: map['errorMessage'] as String?,
      speedBytesPerSec: (map['speedBytesPerSec'] as num?)?.toDouble() ?? 0.0,
      etaSeconds: map['etaSeconds'] as int?,
    );
  }

  String get progressText => '${(progress * 100).toStringAsFixed(1)}%';

  String get downloadedSizeText => _formatBytes(downloadedBytes);

  String get totalSizeText => totalBytes != null ? _formatBytes(totalBytes!) : (size ?? 'Unknown');

  String get speedText {
    if (speedBytesPerSec <= 0) return '';
    return '${_formatBytes(speedBytesPerSec.round())}/s';
  }

  String get etaText {
    if (etaSeconds == null || etaSeconds! <= 0) return '';
    final eta = etaSeconds!;
    if (eta < 60) return '${eta}s left';
    if (eta < 3600) return '${eta ~/ 60}m ${eta % 60}s left';
    final hours = eta ~/ 3600;
    final mins = (eta % 3600) ~/ 60;
    return '${hours}h ${mins}m left';
  }

  /// Check if the downloaded file exists on disk
  Future<bool> fileExists() async {
    try {
      return await File(savePath).exists();
    } catch (_) {
      return false;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Result of adding a download task
enum AddTaskResult {
  success,
  blockedDomain,
  emptyUrl,
  alreadyExists,
  permissionDenied,
}

/// Download Manager Service - handles all download operations
/// Uses singleton pattern so all screens share the same download state
class DownloadManagerService extends ChangeNotifier {
  static DownloadManagerService? _instance;
  static const String _tasksKey = 'download_tasks';
  static const int _maxConcurrentDownloads = 3;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 180),
    sendTimeout: const Duration(minutes: 10),
    // Follow redirects for file hosting services (MediaFire, etc.)
    followRedirects: true,
    maxRedirects: 10,
    // Better buffer size for large file downloads
    receiveDataWhenStatusError: true,
  ));

  /// Download performance tuning constants
  static const int _maxAutoRetries = 5; // Auto-retry on network errors
  static const Duration _stallTimeout = Duration(seconds: 30); // Reconnect if stalled this long
  static const int _stallSpeedThreshold = 2 * 1024; // 2 KB/s = stalled (mobile data can be slow)

  static String? _customDownloadDir;
  static String? get customDownloadDir => _customDownloadDir;

  /// Check if SAF folder is being used for downloads
  Future<bool> get isUsingSafFolder async {
    return await SafStorageService.instance.hasStoredFolder();
  }
  static Future<void> setCustomDownloadDir(String path) async {
    _customDownloadDir = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_download_dir', path);
  }

  /// Open SAF folder picker to let user select download folder
  /// Returns the result with treeUri and treePath, or null if cancelled
  Future<SafFolderResult?> openSafFolderPicker() async {
    final result = await SafStorageService.instance.openFolderPicker();
    if (result != null) {
      // Clear custom download dir since we're using SAF now
      _customDownloadDir = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('custom_download_dir');
      notifyListeners();
    }
    return result;
  }

  /// Get the SAF folder display path for UI
  Future<String?> getSafFolderPath() async {
    return await SafStorageService.instance.getStoredTreePath();
  }

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, _SpeedTracker> _speedTrackers = {};
  List<DownloadTask> _tasks = [];
  bool _isInitialized = false;
  int _activeDownloadCount = 0;

  /// Queue for pending downloads when max concurrent is reached
  final List<String> _pendingQueue = [];

  /// Tracks tasks explicitly paused by the user (prevents auto-reconnect from overriding pause)
  final Set<String> _pausedByUser = {};

  /// Singleton factory constructor - always returns the same instance
  factory DownloadManagerService() {
    _instance ??= DownloadManagerService._internal();
    return _instance!;
  }

  /// Private internal constructor
  DownloadManagerService._internal();

  /// Convenience getter for the singleton instance
  static DownloadManagerService get instance => DownloadManagerService();

  List<DownloadTask> get tasks => _tasks;
  List<DownloadTask> get activeTasks => _tasks.where((t) =>
      t.status == DownloadStatus.downloading || t.status == DownloadStatus.paused).toList();
  List<DownloadTask> get completedTasks => _tasks.where((t) =>
      t.status == DownloadStatus.completed).toList();
  List<DownloadTask> get failedTasks => _tasks.where((t) =>
      t.status == DownloadStatus.failed).toList();

  /// Summary stats
  int get activeCount => activeTasks.length;
  int get completedCount => completedTasks.length;
  int get failedCount => failedTasks.length;
  int get totalTasks => _tasks.length;

  /// Total size of completed downloads
  String get completedTotalSize {
    int total = 0;
    for (final t in completedTasks) {
      total += t.downloadedBytes;
    }
    if (total == 0) return '';
    return DownloadTask(
      id: '', movieId: '', movieTitle: '', url: '', quality: '',
      serverName: '', savePath: '', addedAt: DateTime.now(),
      downloadedBytes: total,
    ).downloadedSizeText;
  }

  /// Initialize - load saved tasks and migrate old downloads (only runs once)
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadTasks();
    await _migrateOldDownloads();
    await fixExistingTaskPaths();
  }

  /// Auto-migrate download files from old public directory to new scoped storage.
  /// Old path: /storage/emulated/0/Download/CM_Movies/
  /// New path: Android/data/than.pre.cm/files/Download/CM_Movies/
  /// This runs once and silently moves any files found in the old location.
  Future<void> _migrateOldDownloads() async {
    if (!Platform.isAndroid) return;

    // Check if migration was already done
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool('downloads_migrated_v2') ?? false;
    if (migrated) return;

    try {
      final oldDir = Directory('/storage/emulated/0/Download/CM_Movies');
      if (!await oldDir.exists()) {
        // No old directory, mark as migrated and return
        await prefs.setBool('downloads_migrated_v2', true);
        return;
      }

      final newDir = await _getDownloadDir();
      final newDirectory = Directory(newDir);

      // Ensure new directory exists
      if (!await newDirectory.exists()) {
        await newDirectory.create(recursive: true);
      }

      // Move each file from old to new directory
      int movedCount = 0;
      await for (final entity in oldDir.list()) {
        if (entity is File) {
          final fileName = entity.path.split('/').last;
          final newPath = '$newDir/$fileName';

          // Skip if file already exists in new location
          if (await File(newPath).exists()) {
            try {
              await entity.delete();
            } catch (_) {}
            continue;
          }

          try {
            await entity.rename(newPath);
            movedCount++;
          } catch (e) {
            // rename might fail across mount points, try copy + delete
            try {
              await entity.copy(newPath);
              await entity.delete();
              movedCount++;
            } catch (e2) {
              debugPrint('Failed to migrate file $fileName: $e2');
            }
          }
        }
      }

      // Update task save paths to point to new directory
      bool tasksUpdated = false;
      for (int i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        if (task.savePath.contains('/storage/emulated/0/Download/CM_Movies/')) {
          final fileName = task.savePath.split('/').last;
          final newPath = '$newDir/$fileName';

          // Update task with new path
          _tasks[i] = DownloadTask(
            id: task.id,
            movieId: task.movieId,
            movieTitle: task.movieTitle,
            moviePoster: task.moviePoster,
            url: task.url,
            quality: task.quality,
            size: task.size,
            serverName: task.serverName,
            savePath: newPath,
            addedAt: task.addedAt,
            completedAt: task.completedAt,
            status: task.status,
            progress: task.progress,
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes,
            errorMessage: task.errorMessage,
            speedBytesPerSec: task.speedBytesPerSec,
            etaSeconds: task.etaSeconds,
          );
          tasksUpdated = true;
        }
      }

      if (tasksUpdated) {
        await _saveTasks();
        notifyListeners();
      }

      // Try to remove the old directory if empty
      try {
        final remaining = await oldDir.list().length;
        if (remaining == 0) {
          await oldDir.delete();
        }
      } catch (_) {}

      if (movedCount > 0) {
        debugPrint('Migrated $movedCount download files to scoped storage');
      }

      // Mark migration as complete
      await prefs.setBool('downloads_migrated_v2', true);
    } catch (e) {
      debugPrint('Download migration failed (non-critical): $e');
      // Still mark as migrated to avoid retrying on every app start
      await prefs.setBool('downloads_migrated_v2', true);
    }
  }

  // ===== PERMISSION HANDLING =====

  /// Check if storage permission is granted.
  /// On Android 11+ (scoped storage), also checks if SAF folder permission
  /// is still valid. This is important for the Status Checker UI to show
  /// the correct permission state.
  Future<bool> checkStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await _getAndroidSdkVersion();
    if (sdkInt >= 30) {
      // Android 11+: Scoped storage for app directory works without permission,
      // BUT if a SAF folder has been previously selected, we must verify
      // the SAF permission is still valid (user may have revoked it).
      final hasSaf = await SafStorageService.instance.hasStoredFolder();
      if (hasSaf) {
        final safValid = await SafStorageService.instance.isSafPermissionValid();
        if (!safValid) {
          // SAF permission revoked — clear stored folder so we fall back to app storage
          await SafStorageService.instance.clearStoredFolder();
          return false; // Permission no longer valid
        }
      }
      return true; // Either no SAF (app storage works) or SAF is valid
    } else {
      return await Permission.storage.isGranted;
    }
  }

  /// Request storage permission.
  /// On Android 11+, this opens the SAF folder picker so the user can
  /// grant access to a visible folder (like Downloads).
  /// On Android 10 and below, requests the legacy storage permission.
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await _getAndroidSdkVersion();

    if (sdkInt >= 30) {
      // Android 11+: Open SAF folder picker to let user grant access
      // to a visible folder. This is the recommended way on Android 11+.
      final result = await SafStorageService.instance.openFolderPicker();
      if (result != null) {
        // User selected a folder — permission granted
        // Clear custom download dir since we're using SAF now
        _customDownloadDir = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('custom_download_dir');
        notifyListeners();
        return true;
      }
      return false; // User cancelled the picker
    } else {
      // Android 10 and below: request legacy storage permission
      final status = await Permission.storage.request();
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    }
  }

  /// Get Android SDK version — reads the actual device SDK version
  Future<int> _getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 30;
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.version.sdkInt;
    } catch (_) {
      return 30; // Safe fallback: assume Android 11+ (scoped storage)
    }
  }

  /// Request runtime storage permission using the native Android system dialog.
  /// This shows the standard "Allow KMM to access videos on this device?" dialog.
  /// - Android 13+ (SDK 33+): Uses Permission.videos (READ_MEDIA_VIDEO)
  /// - Android 10-12 (SDK 29-32): Uses Permission.storage (READ_EXTERNAL_STORAGE)
  /// - Android 9 and below (SDK ≤28): Uses Permission.storage (WRITE_EXTERNAL_STORAGE)
  /// Returns true if permission is granted.
  Future<bool> requestRuntimePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await _getAndroidSdkVersion();

    if (sdkInt >= 33) {
      // Android 13+: Use granular media permission for videos
      // This shows the system dialog: "Allow KMM to access videos on this device?"
      var status = await Permission.videos.status;
      if (status.isGranted) return true;

      status = await Permission.videos.request();
      if (status.isGranted) return true;

      // If permanently denied, guide user to app settings
      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    } else if (sdkInt >= 29) {
      // Android 10-12: Use READ_EXTERNAL_STORAGE
      // This shows the system dialog: "Allow KMM to access photos and media?"
      var status = await Permission.storage.status;
      if (status.isGranted) return true;

      status = await Permission.storage.request();
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    } else {
      // Android 9 and below: Request legacy storage permission
      var status = await Permission.storage.status;
      if (status.isGranted) return true;

      status = await Permission.storage.request();
      if (status.isGranted) return true;

      if (status.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }
      return false;
    }
  }

  /// Check if runtime storage permission has been granted.
  /// - Android 13+: Checks Permission.videos
  /// - Android 10-12: Checks Permission.storage
  /// - Android 9 and below: Checks Permission.storage
  /// Returns true if the appropriate permission is granted.
  Future<bool> hasRuntimePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await _getAndroidSdkVersion();

    if (sdkInt >= 33) {
      // Android 13+: Check granular video permission
      return await Permission.videos.isGranted;
    } else {
      // Android 12 and below: Check legacy storage permission
      return await Permission.storage.isGranted;
    }
  }

  /// Get cross-platform download directory for ACTUAL file writing.
  /// IMPORTANT: This always returns the app's private storage directory on Android,
  /// NOT the SAF folder path. On Android 11+ with scoped storage, we cannot write
  /// to arbitrary directories (like SAF-selected folders) using standard File I/O.
  /// Instead, we download to app private storage first, then copy to the SAF folder
  /// after completion using ContentResolver.
  Future<String> _getDownloadDir() async {
    // Check custom download directory first (only if it's within app storage)
    if (_customDownloadDir != null && _customDownloadDir!.isNotEmpty) {
      // Only use custom dir if it's within app's external storage
      // (custom dirs outside app storage won't be writable on Android 11+)
      if (Platform.isAndroid) {
        final appDir = await getExternalStorageDirectory();
        if (appDir != null && _customDownloadDir!.startsWith(appDir.path)) {
          final dir = Directory(_customDownloadDir!);
          if (await dir.exists()) return dir.path;
          try {
            await dir.create(recursive: true);
            return dir.path;
          } catch (_) {
            // Fall through to default
          }
        }
        // Custom dir is outside app storage - skip it on Android 11+
      } else {
        final dir = Directory(_customDownloadDir!);
        if (await dir.exists()) return dir.path;
        try {
          await dir.create(recursive: true);
          return dir.path;
        } catch (_) {
          // Fall through to default
        }
      }
    }

    // NOTE: SAF folder path is NOT used for actual download path because
    // on Android 11+ with scoped storage, we cannot write to arbitrary
    // directories (like /storage/emulated/0/Download) using standard File I/O.
    // Files are downloaded to app private storage first, then copied to
    // the SAF folder after completion using ContentResolver.
    // See startDownload() -> completion handler -> saveFileToSafFolder()

    // On Android, use app-specific external storage (scoped storage)
    // This avoids needing MANAGE_EXTERNAL_STORAGE and Play Store rejection.
    // The directory is accessible via file managers under:
    //   Android/data/than.pre.cm/files/Download/CM_Movies
    if (Platform.isAndroid) {
      final appDir = await getExternalStorageDirectory();
      if (appDir != null) {
        // Use a user-friendly path under the app's external storage
        final dir = Directory('${appDir.path}/Download/CM_Movies');
        try {
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          return dir.path;
        } catch (_) {
          // Fall back to the app external storage root
          return appDir.path;
        }
      }

      // Fallback to internal app directory
      final appDocDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${appDocDir.path}/CM_Movies');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir.path;
    }

    // On iOS and other platforms, use app documents directory
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/CM_Movies');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Get the display path for the download location (shown in UI).
  /// If a SAF folder has been selected, returns the human-readable SAF path.
  /// Otherwise returns the actual download directory.
  Future<String> getDownloadDisplayPath() async {
    // If SAF folder is configured, show that path (where files end up visible)
    if (Platform.isAndroid) {
      final safPath = await SafStorageService.instance.getStoredTreePath();
      if (safPath != null && safPath.isNotEmpty) {
        return safPath;
      }
    }
    if (_customDownloadDir != null && _customDownloadDir!.isNotEmpty) {
      return _customDownloadDir!;
    }
    return await _getDownloadDir();
  }

  /// Get current download path for display
  Future<String> getCurrentDownloadPath() async {
    if (_customDownloadDir != null) return _customDownloadDir!;
    return await _getDownloadDir();
  }

  /// Add a new download task with result feedback
  Future<AddTaskResult> addTaskWithResult({
    required String movieId,
    required String movieTitle,
    String? moviePoster,
    required String url,
    required String quality,
    String? size,
    required String serverName,
  }) async {
    // Check for empty or invalid URL first (before domain check)
    if (url.trim().isEmpty) {
      debugPrint('Download URL is empty');
      return AddTaskResult.emptyUrl;
    }

    // PERMISSION GATE: Check storage permission before allowing download
    if (Platform.isAndroid) {
      final hasPermission = await checkStoragePermission();
      if (!hasPermission) {
        debugPrint('Download blocked: Storage permission not granted');
        return AddTaskResult.permissionDenied;
      }
    }

    // Normalize the URL (convert share URLs to direct download URLs)
    final normalizedUrl = _normalizeDownloadUrl(url.trim());
    debugPrint('Download URL: $url -> normalized: $normalizedUrl');

    // M2: Validate download URL against allowlist or media extension
    if (!_isValidDownloadUrl(normalizedUrl)) {
      debugPrint('Blocked download from untrusted domain: $normalizedUrl');
      return AddTaskResult.blockedDomain;
    }

    final taskId = '${movieId}_${quality.replaceAll(' ', '_')}';

    // Check if already exists
    if (_tasks.any((t) => t.id == taskId)) {
      final existing = _tasks.firstWhere((t) => t.id == taskId);
      if (existing.status == DownloadStatus.completed) {
        // Delete old file before re-downloading
        try {
          final file = File(existing.savePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
        _tasks.remove(existing);
      } else if (existing.status == DownloadStatus.failed) {
        // Retry the failed task
        await retryDownload(taskId);
        return AddTaskResult.success;
      } else {
        return AddTaskResult.alreadyExists; // Already downloading/paused
      }
    }

    // Detect correct file extension from URL
    final fileExt = _detectFileExtension(normalizedUrl);
    final fileName = '${movieTitle.replaceAll(RegExp(r'[^\w\s-]'), '')}_$quality$fileExt'
        .replaceAll(' ', '_');
    final downloadDir = await _getDownloadDir();
    final savePath = '$downloadDir/$fileName';

    final task = DownloadTask(
      id: taskId,
      movieId: movieId,
      movieTitle: movieTitle,
      moviePoster: moviePoster,
      url: normalizedUrl,
      quality: quality,
      size: size,
      serverName: serverName,
      savePath: savePath,
      addedAt: DateTime.now(),
    );

    _tasks.insert(0, task);
    await _saveTasks();
    notifyListeners();

    // Start download (or queue it)
    _startOrQueueDownload(taskId);
    return AddTaskResult.success;
  }

  /// Add a new download task
  Future<void> addTask({
    required String movieId,
    required String movieTitle,
    String? moviePoster,
    required String url,
    required String quality,
    String? size,
    required String serverName,
  }) async {
    // Delegate to addTaskWithResult for consistent behavior
    await addTaskWithResult(
      movieId: movieId,
      movieTitle: movieTitle,
      moviePoster: moviePoster,
      url: url,
      quality: quality,
      size: size,
      serverName: serverName,
    );
  }

  /// Start download or queue it if max concurrent reached
  void _startOrQueueDownload(String taskId) {
    if (_activeDownloadCount < _maxConcurrentDownloads) {
      startDownload(taskId);
    } else {
      _pendingQueue.add(taskId);
      // Update task status to show it's queued
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        _tasks[idx] = _tasks[idx].copyWith(
          status: DownloadStatus.idle,
          errorMessage: 'Queued (max $_maxConcurrentDownloads simultaneous)',
        );
        notifyListeners();
      }
    }
  }

  /// Process the next queued download
  void _processQueue() {
    while (_pendingQueue.isNotEmpty && _activeDownloadCount < _maxConcurrentDownloads) {
      final taskId = _pendingQueue.removeAt(0);
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1 && _tasks[idx].status == DownloadStatus.idle) {
        startDownload(taskId);
      }
    }
  }

  /// Start or resume a download with byte-range support
  /// Includes stall detection (auto-reconnect if speed drops) and auto-retry on network errors
  Future<void> startDownload(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    var task = _tasks[index];
    if (task.status == DownloadStatus.downloading) return;

    // Recalculate save path if the current path is invalid (e.g., outside app storage)
    // This fixes tasks that were created with SAF paths that aren't directly writable
    if (Platform.isAndroid) {
      final downloadDir = await _getDownloadDir();
      final fileName = task.savePath.split('/').last;
      final correctPath = '$downloadDir/$fileName';
      if (task.savePath != correctPath) {
        debugPrint('Fixing download path: ${task.savePath} -> $correctPath');
        task = task.copyWith(savePath: correctPath);
        _tasks[index] = task;
        await _saveTasks();
      }
    }

    // Ensure save directory exists
    try {
      final saveDir = Directory(task.savePath).parent;
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }
    } catch (e) {
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        _tasks[idx] = _tasks[idx].copyWith(
          status: DownloadStatus.failed,
          errorMessage: 'Cannot create download directory: $e',
        );
        await _saveTasks();
        notifyListeners();
      }
      return;
    }

    // Request storage permission before downloading on Android
    if (Platform.isAndroid) {
      final hasPermission = await checkStoragePermission();
      if (!hasPermission) {
        final idx = _tasks.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.failed,
            errorMessage: 'Storage permission denied. Grant permission and retry.',
          );
          await _saveTasks();
          notifyListeners();
        }
        return;
      }
    }

    // Increment active count
    _activeDownloadCount++;

    // Initialize speed tracker
    _speedTrackers[taskId] = _SpeedTracker();

    // Update status to downloading
    _tasks[index] = task.copyWith(
      status: DownloadStatus.downloading,
      errorMessage: null,
    );
    notifyListeners();

    // Stall detection state
    DateTime? _stallDetectedAt;
    int _lastStallCheckBytes = 0;
    int _autoRetryCount = 0;

    // Throttle UI notifications to avoid jank on mobile data
    int _lastNotifyTime = 0;
    const _notifyIntervalMs = 250; // Update UI max 4 times per second

    Future<void> doDownload() async {
      final cancelToken = CancelToken();
      _cancelTokens[taskId] = cancelToken;

      try {
        // Check if partial file exists for resume support
        int startByte = 0;
        final currentTaskIdx = _tasks.indexWhere((t) => t.id == taskId);
        if (currentTaskIdx == -1) return;
        final currentTask = _tasks[currentTaskIdx];

        final file = File(currentTask.savePath);
        if (currentTask.downloadedBytes > 0 && await file.exists()) {
          final fileSize = await file.length();
          if (fileSize < currentTask.downloadedBytes) {
            // File is smaller than recorded bytes - something went wrong, restart
            startByte = 0;
          } else {
            startByte = fileSize; // Use actual file size for more reliable resume
          }
        } else {
          // No partial file, start from beginning
          startByte = 0;
        }

        // Reset stall detection for new connection
        _stallDetectedAt = null;
        _lastStallCheckBytes = startByte;

        // Build headers - add Range header for resume
        final headers = <String, dynamic>{};
        if (startByte > 0) {
          headers['Range'] = 'bytes=$startByte-';
          debugPrint('Resuming download from byte $startByte for $taskId');
        }

        // Use stream-based download for proper resume support.
        // Dio's download() overwrites the file from position 0 even with Range header,
        // which breaks resume. Instead, we use a streaming GET request and write
        // chunks to the file in APPEND mode when resuming.
        final response = await _dio.get<ResponseBody>(
          currentTask.url,
          cancelToken: cancelToken,
          options: Options(
            headers: headers,
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(minutes: 60),
            sendTimeout: const Duration(minutes: 10),
            validateStatus: (status) => status != null && (status == 200 || status == 206),
          ),
        );

        // If server returned 200 (full content) when we requested a range,
        // the server doesn't support resume — need to start from scratch
        if (response.statusCode == 200 && startByte > 0) {
          debugPrint('Server does not support Range requests for $taskId — restarting from scratch');
          startByte = 0;
          _stallDetectedAt = null;
          _lastStallCheckBytes = 0;
        }

        // Determine total file size from Content-Range or Content-Length
        final contentRange = response.headers.value('content-range');
        int serverTotalBytes = -1;
        if (contentRange != null) {
          // Content-Range: bytes 1000-9999/10000
          final parts = contentRange.split('/');
          if (parts.length == 2) {
            serverTotalBytes = int.tryParse(parts[1]) ?? -1;
          }
        }
        if (serverTotalBytes <= 0) {
          final contentLength = response.headers.value('content-length');
          if (contentLength != null) {
            final cl = int.tryParse(contentLength) ?? -1;
            if (cl > 0) {
              // Content-Length for a 206 response is just the remaining bytes
              serverTotalBytes = (response.statusCode == 206) ? startByte + cl : cl;
            }
          }
        }
        final actualTotal = serverTotalBytes > 0 ? serverTotalBytes : -1;

        // Open file in append mode if resuming, write mode if starting fresh
        final fileSink = file.openWrite(mode: startByte > 0 ? FileMode.append : FileMode.write);

        try {
          int receivedSinceStart = 0;
          final stream = response.data?.stream;
          if (stream == null) {
            throw DioException(requestOptions: RequestOptions(), error: 'Empty response stream', type: DioExceptionType.connectionError);
          }

          await for (final chunk in stream) {
            if (cancelToken.isCancelled) break;

            // Write chunk to file
            fileSink.add(chunk);
            receivedSinceStart += chunk.length;

            // Flush periodically (every 256KB) for crash safety
            if (receivedSinceStart % (256 * 1024) < chunk.length) {
              await fileSink.flush();
            }

            final actualReceived = startByte + receivedSinceStart;
            final progress = actualTotal > 0 ? actualReceived / actualTotal : 0.0;

            // Calculate speed and ETA
            final tracker = _speedTrackers[taskId];
            double speed = 0.0;
            int? eta;
            if (tracker != null) {
              tracker.addSample(actualReceived);
              speed = tracker.speedBytesPerSec;
              if (speed > 0 && actualTotal > 0) {
                final remaining = actualTotal - actualReceived;
                eta = (remaining / speed).round();
              }
            }

            // === STALL DETECTION ===
            if (actualReceived > _lastStallCheckBytes + 50 * 1024) {
              _lastStallCheckBytes = actualReceived;
              if (speed > 0 && speed < _stallSpeedThreshold) {
                _stallDetectedAt ??= DateTime.now();
                final stalledDuration = DateTime.now().difference(_stallDetectedAt!);
                if (stalledDuration >= _stallTimeout) {
                  // Don't auto-reconnect if user has paused
                  if (_pausedByUser.contains(taskId)) {
                    debugPrint('Stall detected but user paused $taskId — not reconnecting');
                    break;
                  }
                  debugPrint('Download stall detected for $taskId: speed=${_formatSpeed(speed)}, reconnecting...');
                  if (!cancelToken.isCancelled) {
                    cancelToken.cancel('Stall detected - reconnecting');
                  }
                  break;
                }
              } else {
                _stallDetectedAt = null;
              }
            }

            // Update task data
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx != -1) {
              // Throttle UI updates
              final now = DateTime.now().millisecondsSinceEpoch;
              final shouldNotify = (now - _lastNotifyTime >= _notifyIntervalMs) ||
                  progress >= 1.0 ||
                  actualTotal <= 0;

              _tasks[idx] = _tasks[idx].copyWith(
                progress: progress.clamp(0.0, 1.0),
                downloadedBytes: actualReceived,
                totalBytes: actualTotal > 0 ? actualTotal : null,
                speedBytesPerSec: speed,
                etaSeconds: eta,
              );
              if (shouldNotify) {
                _lastNotifyTime = now;
                notifyListeners();
              }
            }
          }
        } finally {
          await fileSink.close();
        }

        // If the stream was cancelled (pause/stall), throw to reach the error handler
        if (cancelToken.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(),
            error: cancelToken.cancelError?.message ?? 'Cancelled',
            type: DioExceptionType.cancel,
          );
        }

        // Download completed
        final idx = _tasks.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.completed,
            progress: 1.0,
            downloadedBytes: _tasks[idx].totalBytes ?? _tasks[idx].downloadedBytes,
            completedAt: DateTime.now(),
            speedBytesPerSec: 0.0,
            etaSeconds: null,
          );

          // If using SAF folder, copy file to SAF folder for visibility in file managers
          if (Platform.isAndroid) {
            final safService = SafStorageService.instance;
            final hasSaf = await safService.hasStoredFolder();
            if (hasSaf) {
              final fileName = _tasks[idx].savePath.split('/').last;
              if (fileName.isNotEmpty) {
                final saved = await safService.saveFileToSafFolder(
                  sourceFilePath: _tasks[idx].savePath,
                  fileName: fileName,
                );
                if (saved) {
                  debugPrint('Copied download to SAF folder: $fileName');
                }
              }
            }
          }

          await _saveTasks();
          notifyListeners();
        }
      } on DioException catch (e) {
        final idx = _tasks.indexWhere((t) => t.id == taskId);
        if (idx == -1) return;

        if (CancelToken.isCancel(e)) {
          // Check if user explicitly paused (via _pausedByUser flag or cancel reason)
          final reason = e.message ?? (e.error?.toString() ?? '');
          final wasPausedByUser = _pausedByUser.contains(taskId) || reason.contains('Paused by user');
          if (wasPausedByUser) {
            // User paused - save current progress for resume
            _tasks[idx] = _tasks[idx].copyWith(
              status: DownloadStatus.paused,
              speedBytesPerSec: 0.0,
              etaSeconds: null,
            );
            await _saveTasks();
            notifyListeners();
            return;
          }
          // Stall or other auto-cancel - attempt auto-reconnect
          // But NOT if the user has paused the download during the delay
          if (_autoRetryCount < _maxAutoRetries) {
            _autoRetryCount++;
            debugPrint('Auto-reconnect attempt $_autoRetryCount/$_maxAutoRetries for $taskId');
            // Brief pause before reconnecting
            await Future.delayed(const Duration(seconds: 2));
            // Re-check if user paused during the delay
            if (_pausedByUser.contains(taskId)) {
              debugPrint('User paused during auto-reconnect delay for $taskId — aborting reconnect');
              _tasks[idx] = _tasks[idx].copyWith(
                status: DownloadStatus.paused,
                speedBytesPerSec: 0.0,
                etaSeconds: null,
              );
              await _saveTasks();
              notifyListeners();
              return;
            }
            // Save current progress before retrying
            await _saveTasks();
            return doDownload(); // Reconnect with fresh connection
          }
          // Exhausted retries
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.failed,
            errorMessage: 'Download stalled repeatedly. Tap retry to continue.',
            speedBytesPerSec: 0.0,
            etaSeconds: null,
          );
          await _saveTasks();
          notifyListeners();
          return;
        }

        // Network error - attempt auto-retry with resume
        // But NOT if the user paused the download
        if (_pausedByUser.contains(taskId)) {
          debugPrint('User paused during network error for $taskId — aborting auto-retry');
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.paused,
            speedBytesPerSec: 0.0,
            etaSeconds: null,
          );
          await _saveTasks();
          notifyListeners();
          return;
        }
        final isRetryable = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.sendTimeout;
        if (isRetryable && _autoRetryCount < _maxAutoRetries) {
          _autoRetryCount++;
          debugPrint('Auto-retry attempt $_autoRetryCount/$_maxAutoRetries for $taskId after ${e.type}');
          await Future.delayed(Duration(seconds: 2 * _autoRetryCount)); // Exponential backoff
          // Re-check if user paused during the backoff delay
          if (_pausedByUser.contains(taskId)) {
            debugPrint('User paused during auto-retry delay for $taskId — aborting retry');
            _tasks[idx] = _tasks[idx].copyWith(
              status: DownloadStatus.paused,
              speedBytesPerSec: 0.0,
              etaSeconds: null,
            );
            await _saveTasks();
            notifyListeners();
            return;
          }
          await _saveTasks();
          return doDownload();
        }

        String errorMsg = _getDioErrorMessage(e);
        _tasks[idx] = _tasks[idx].copyWith(
          status: DownloadStatus.failed,
          errorMessage: errorMsg,
          speedBytesPerSec: 0.0,
          etaSeconds: null,
        );
        await _saveTasks();
        notifyListeners();
      } catch (e) {
        final idx = _tasks.indexWhere((t) => t.id == taskId);
        if (idx != -1) {
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.failed,
            errorMessage: e.toString(),
            speedBytesPerSec: 0.0,
            etaSeconds: null,
          );
          await _saveTasks();
          notifyListeners();
        }
      }
    }

    try {
      await doDownload();
    } finally {
      _cancelTokens.remove(taskId);
      _speedTrackers.remove(taskId);
      _pausedByUser.remove(taskId); // Clean up pause flag when download ends
      _activeDownloadCount--;
      _processQueue();
    }
  }

  /// Format speed for debug logging
  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.round()} B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  /// Get a human-readable error message from DioException
  String _getDioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Connection timed out. Check your internet and retry.';
      case DioExceptionType.sendTimeout:
        return 'Upload timed out. Please retry.';
      case DioExceptionType.receiveTimeout:
        return 'Download timed out. Please retry.';
      case DioExceptionType.connectionError:
        return 'No internet connection. Check your network and retry.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) return 'File not found on server (404).';
        if (code == 403) return 'Access denied by server (403).';
        if (code == 416) return 'Resume not supported. Will restart download.';
        return 'Server error ($code). Please retry.';
      case DioExceptionType.cancel:
        return 'Download cancelled.';
      case DioExceptionType.unknown:
        return e.message ?? 'Unknown error occurred.';
      default:
        return e.message ?? 'Download failed.';
    }
  }

  /// Pause a download
  void pauseDownload(String taskId) {
    // Mark as user-paused FIRST so auto-reconnect can check it
    _pausedByUser.add(taskId);

    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Paused by user');
    }
    // Ensure task state is saved immediately for reliable resume
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1 && _tasks[idx].status == DownloadStatus.downloading) {
      _tasks[idx] = _tasks[idx].copyWith(
        status: DownloadStatus.paused,
        speedBytesPerSec: 0.0,
        etaSeconds: null,
      );
      _saveTasks(); // Don't await - fire and forget for quick UI response
      notifyListeners();
    }
  }

  /// Resume a paused download (actually resumes from where it left off)
  Future<void> resumeDownload(String taskId) async {
    // Clear the user-paused flag so auto-reconnect can work again
    _pausedByUser.remove(taskId);
    await startDownload(taskId);
  }

  /// Retry a failed download (resumes from partial if possible)
  Future<void> retryDownload(String taskId) async {
    // Clear the user-paused flag since user explicitly wants to retry
    _pausedByUser.remove(taskId);

    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    // Reset error state but keep downloadedBytes for resume
    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.idle,
      errorMessage: null,
      speedBytesPerSec: 0.0,
      etaSeconds: null,
    );
    notifyListeners();
    await startDownload(taskId);
  }

  /// Remove a download task (optionally keep the downloaded file)
  Future<void> removeTask(String taskId, {bool keepFile = false}) async {
    // Cancel if active
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Removed by user');
    }

    // Remove from queue if pending
    _pendingQueue.remove(taskId);
    _pausedByUser.remove(taskId);

    // Delete file if not keeping it
    if (!keepFile) {
      try {
        final task = _tasks.firstWhere((t) => t.id == taskId);
        final file = File(task.savePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    _tasks.removeWhere((t) => t.id == taskId);
    await _saveTasks();
    notifyListeners();
  }

  /// Delete the downloaded file for a completed task (keeps task in list)
  Future<bool> deleteFile(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;

    final task = _tasks[index];
    try {
      final file = File(task.savePath);
      if (await file.exists()) {
        await file.delete();
      }
      _tasks[index] = task.copyWith(
        status: DownloadStatus.failed,
        errorMessage: 'File deleted. Tap retry to download again.',
        progress: 0.0,
        downloadedBytes: 0,
        totalBytes: null,
        completedAt: null,
      );
      await _saveTasks();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Open a downloaded file using the system's default app
  /// Tries the local file first, then falls back to SAF folder if configured
  Future<bool> openFile(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;

    final task = _tasks[index];
    final file = File(task.savePath);

    // Try opening the local file first
    if (await file.exists()) {
      try {
        final result = await OpenFilex.open(task.savePath);
        return result.type == ResultType.done;
      } catch (e) {
        debugPrint('Error opening local file: $e');
        // Fall through to SAF
      }
    }

    // If local file doesn't exist and SAF is configured, try opening from SAF
    if (Platform.isAndroid) {
      final safService = SafStorageService.instance;
      final hasSaf = await safService.hasStoredFolder();
      if (hasSaf) {
        final fileName = task.savePath.split('/').last;
        final opened = await safService.openFileFromSafFolder(fileName);
        if (opened) return true;
      }
    }

    return false;
  }

  /// Clear all completed downloads (removes from list, keeps files)
  Future<void> clearCompleted() async {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
    await _saveTasks();
    notifyListeners();
  }

  /// Clear all failed downloads
  Future<void> clearFailed() async {
    _tasks.removeWhere((t) => t.status == DownloadStatus.failed);
    await _saveTasks();
    notifyListeners();
  }

  /// Check if a download exists for a movie quality
  bool hasDownload(String movieId, String quality) {
    final taskId = '${movieId}_${quality.replaceAll(' ', '_')}';
    return _tasks.any((t) => t.id == taskId);
  }

  DownloadTask? getTask(String movieId, String quality) {
    final taskId = '${movieId}_${quality.replaceAll(' ', '_')}';
    try {
      return _tasks.firstWhere((t) => t.id == taskId);
    } catch (_) {
      return null;
    }
  }

  /// Verify completed files still exist on disk, mark as failed if missing
  Future<void> verifyCompletedFiles() async {
    bool changed = false;
    for (int i = 0; i < _tasks.length; i++) {
      if (_tasks[i].status == DownloadStatus.completed) {
        final exists = await _tasks[i].fileExists();
        if (!exists) {
          _tasks[i] = _tasks[i].copyWith(
            status: DownloadStatus.failed,
            errorMessage: 'File not found. It may have been moved or deleted.',
            progress: 0.0,
            downloadedBytes: 0,
            completedAt: null,
          );
          changed = true;
        }
      }
    }
    if (changed) {
      await _saveTasks();
      notifyListeners();
    }
  }

  /// Fix existing task save paths that point to non-app-storage directories.
  /// On Android 11+, tasks with paths like /storage/emulated/0/Alarms/ or
  /// /storage/emulated/0/Download/ won't be writable. This recalculates
  /// their savePath to point to the app's private storage directory.
  Future<void> fixExistingTaskPaths() async {
    if (!Platform.isAndroid) return;

    final downloadDir = await _getDownloadDir();
    bool changed = false;

    for (int i = 0; i < _tasks.length; i++) {
      final task = _tasks[i];
      // Only fix tasks whose savePath is outside app storage
      if (!task.savePath.startsWith(downloadDir) &&
          (task.status == DownloadStatus.failed ||
           task.status == DownloadStatus.idle ||
           task.status == DownloadStatus.paused)) {
        final fileName = task.savePath.split('/').last;
        final correctPath = '$downloadDir/$fileName';
        debugPrint('Fixing task path: ${task.savePath} -> $correctPath');
        _tasks[i] = task.copyWith(
          savePath: correctPath,
          // Reset download progress since we're changing the path
          downloadedBytes: 0,
          progress: 0.0,
        );
        changed = true;
      }
    }

    if (changed) {
      await _saveTasks();
      notifyListeners();
    }
  }

  // ===== PERSISTENCE =====

  // M2: Domain allowlist for download URLs — prevents malicious URL injection
  static const Set<String> _allowedDomains = {
    // Google/Firebase
    'googleapis.com', 'firebasestorage.app', 'firebaseio.com', 'google.com',
    'drive.google.com', 'docs.google.com',
    // Mega
    'mega.nz', 'mega.co.nz',
    // MediaFire
    'mediafire.com',
    // Dropbox
    'dropbox.com', 'dl.dropboxusercontent.com',
    // MP4Upload / Streamable
    'mp4upload.com', 'streamable.com',
    // GDrive proxies
    'gdrive.io',
    'gdtot.dad', 'appdrive.in', 'driveapp.in', 'driveeee.net', 'hubdrive.in',
    // Common video CDNs and hosting
    'cloudfront.net', 'amazonaws.com', 'akamaized.net', 'cloudflare.com',
    'videopress.com', 'vimeo.com', 'dailymotion.com',
    // Additional file hosts
    '1fichier.com', 'userscloud.com', 'zippyshare.com', 'upload.ee',
    'anonfiles.com', 'pixeldrain.com', 'gofile.io', 'catbox.moe',
    'send.cm', 'uploadhaven.com', 'bowfile.com', 'nitroflare.com',
    'rapidgator.net', 'alfafile.net', 'depositfiles.com',
  };

  // Media file extensions — direct media URLs are always allowed regardless of domain
  static const Set<String> _mediaExtensions = {
    '.mp4', '.mkv', '.avi', '.webm', '.mov', '.wmv', '.flv', '.m4v',
    '.ts', '.mpg', '.mpeg', '.3gp', '.ogv', '.divx', '.rmvb',
    '.zip', '.rar', '.7z', '.tar', '.gz',
  };

  /// Validate that a download URL is from a trusted domain OR is a direct media file.
  /// Direct media URLs (ending in .mp4, .mkv, etc.) are always allowed — they are
  /// clearly media files, not malicious redirects.
  /// Domain allowlist provides security at the domain level for non-media URLs.
  /// TODO (L7): Enforce HTTPS-only when all download sources support it.
  ///     Signed/time-limited URLs require Firebase Blaze plan (not yet available).
  ///     When Blaze plan is enabled, replace direct URLs with Firebase Storage
  ///     signed URLs via Cloud Functions for time-limited download access.
  static bool _isValidDownloadUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      // Allow HTTPS and HTTP — many file hosting services use HTTP
      if (uri.scheme != 'https' && uri.scheme != 'http') return false;
      final host = uri.host.toLowerCase();
      if (host.isEmpty) return false;

      // Allow direct media file URLs regardless of domain
      // This covers CDN-hosted MP4/MKV files on any domain
      final pathLower = uri.path.toLowerCase();
      for (final ext in _mediaExtensions) {
        if (pathLower.endsWith(ext)) return true;
        // Handle URLs with query params after extension, e.g. file.mp4?token=xxx
        final pathSegments = uri.pathSegments;
        if (pathSegments.isNotEmpty) {
          final lastSegment = pathSegments.last.toLowerCase();
          if (lastSegment.contains(ext)) return true;
        }
      }

      // Check domain allowlist for non-media URLs
      for (final allowed in _allowedDomains) {
        if (host == allowed || host.endsWith('.$allowed')) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Normalize download URLs to direct download format where possible.
  /// Converts share/preview URLs to direct download URLs for supported services.
  static String _normalizeDownloadUrl(String url) {
    if (url.isEmpty) return url;
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      final path = uri.path;

      // Google Drive: Convert share URL to direct download URL
      // Input:  https://drive.google.com/file/d/FILE_ID/view?usp=sharing
      // Output: https://drive.google.com/uc?export=download&id=FILE_ID
      if ((host == 'drive.google.com' || host.endsWith('.drive.google.com')) &&
          path.contains('/file/d/')) {
        final match = RegExp(r'/file/d/([^/]+)').firstMatch(path);
        if (match != null) {
          final fileId = match.group(1)!;
          return 'https://drive.google.com/uc?export=download&id=$fileId';
        }
      }

      // Google Drive: Convert open URL to direct download URL
      // Input:  https://drive.google.com/open?id=FILE_ID
      // Output: https://drive.google.com/uc?export=download&id=FILE_ID
      if ((host == 'drive.google.com' || host.endsWith('.drive.google.com')) &&
          path == '/open') {
        final id = uri.queryParameters['id'];
        if (id != null && id.isNotEmpty) {
          return 'https://drive.google.com/uc?export=download&id=$id';
        }
      }

      // Dropbox: Convert share URL to direct download URL
      // Input:  https://www.dropbox.com/s/xxxxx/file.mp4?dl=0
      // Output: https://www.dropbox.com/s/xxxxx/file.mp4?dl=1
      if ((host == 'dropbox.com' || host == 'www.dropbox.com') &&
          path.startsWith('/s/')) {
        final newParams = Map<String, String>.from(uri.queryParameters);
        newParams['dl'] = '1';
        return uri.replace(queryParameters: newParams).toString();
      }

      // Dropbox: Convert /scl/ links
      // Input:  https://www.dropbox.com/scl/fi/xxxxx/file.mp4?dl=0&rlkey=xxx
      // Output: https://www.dropbox.com/scl/fi/xxxxx/file.mp4?dl=1&rlkey=xxx
      if ((host == 'dropbox.com' || host == 'www.dropbox.com') &&
          path.startsWith('/scl/')) {
        final newParams = Map<String, String>.from(uri.queryParameters);
        newParams['dl'] = '1';
        return uri.replace(queryParameters: newParams).toString();
      }

      return url;
    } catch (_) {
      return url;
    }
  }

  /// Detect the file extension from a URL for proper file naming
  static String _detectFileExtension(String url, {String fallback = '.mkv'}) {
    if (url.isEmpty) return fallback;
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      // Check path for known media extensions
      for (final ext in _mediaExtensions) {
        if (path.toLowerCase().endsWith(ext)) return ext;
      }
      // Check last path segment (handles query params)
      final segments = uri.pathSegments;
      if (segments.isNotEmpty) {
        final last = segments.last.toLowerCase();
        for (final ext in _mediaExtensions) {
          if (last.contains(ext)) return ext;
        }
      }
      return fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = json.encode(_tasks.map((t) => t.toMap()).toList());
      await prefs.setString(_tasksKey, encoded);
    } catch (e) {
      debugPrint('Error saving download tasks: $e');
    }
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_tasksKey);
      _customDownloadDir = prefs.getString('custom_download_dir');
      if (data != null && data.isNotEmpty) {
        final List<dynamic> decoded = json.decode(data) as List<dynamic>;
        _tasks = decoded
            .map((x) => DownloadTask.fromMap(x as Map<String, dynamic>))
            .toList();

        // Reset downloading tasks to paused on restart (so they can be resumed)
        // Also reset speed/ETA since they're not meaningful after restart
        for (int i = 0; i < _tasks.length; i++) {
          if (_tasks[i].status == DownloadStatus.downloading) {
            _tasks[i] = _tasks[i].copyWith(
              status: DownloadStatus.paused,
              speedBytesPerSec: 0.0,
              etaSeconds: null,
            );
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading download tasks: $e');
    }
  }
}

/// Speed tracker that calculates download speed using a sliding window.
/// Uses a larger window for stable readings on variable-speed networks (mobile data).
class _SpeedTracker {
  final List<_SpeedSample> _samples = [];
  static const int _maxSamples = 20;
  static const Duration _sampleWindow = Duration(seconds: 10);

  void addSample(int totalBytes) {
    final now = DateTime.now();
    _samples.add(_SpeedSample(timestamp: now, totalBytes: totalBytes));

    // Remove old samples outside the window
    _samples.removeWhere((s) => now.difference(s.timestamp) > _sampleWindow);

    // Keep only max samples
    while (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
  }

  double get speedBytesPerSec {
    if (_samples.length < 2) return 0.0;

    final first = _samples.first;
    final last = _samples.last;
    final timeDiff = last.timestamp.difference(first.timestamp).inMilliseconds;

    if (timeDiff <= 0) return 0.0;

    final bytesDiff = last.totalBytes - first.totalBytes;
    return (bytesDiff / timeDiff) * 1000; // Convert ms to seconds
  }
}

class _SpeedSample {
  final DateTime timestamp;
  final int totalBytes;

  _SpeedSample({required this.timestamp, required this.totalBytes});
}
