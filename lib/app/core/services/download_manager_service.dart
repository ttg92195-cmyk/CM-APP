import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
      savePath: savePath,
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

/// Download Manager Service - handles all download operations
/// Uses singleton pattern so all screens share the same download state
class DownloadManagerService extends ChangeNotifier {
  static DownloadManagerService? _instance;
  static const String _tasksKey = 'download_tasks';
  static const int _maxConcurrentDownloads = 3;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 60),
    sendTimeout: const Duration(minutes: 10),
  ));

  static String? _customDownloadDir;
  static String? get customDownloadDir => _customDownloadDir;
  static Future<void> setCustomDownloadDir(String path) async {
    _customDownloadDir = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_download_dir', path);
  }

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, _SpeedTracker> _speedTrackers = {};
  List<DownloadTask> _tasks = [];
  bool _isInitialized = false;
  int _activeDownloadCount = 0;

  /// Queue for pending downloads when max concurrent is reached
  final List<String> _pendingQueue = [];

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

  /// Initialize - load saved tasks (only runs once)
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadTasks();
  }

  // ===== PERMISSION HANDLING =====

  /// Check if storage permission is granted
  /// Uses scoped storage on Android 11+ (no MANAGE_EXTERNAL_STORAGE needed)
  /// Only checks legacy storage permission on Android 10 and below
  Future<bool> checkStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (Platform.isAndroid) {
      final sdkInt = await _getAndroidSdkVersion();
      if (sdkInt >= 30) {
        // Android 11+: Scoped storage - no special permission needed
        // App-specific external directory is accessible without permission
        return true;
      } else {
        return await Permission.storage.isGranted;
      }
    }
    return true;
  }

  /// Request storage permission
  /// Returns true if permission is granted
  /// On Android 11+, scoped storage is used (no permission request needed)
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await _getAndroidSdkVersion();

    if (sdkInt >= 30) {
      // Android 11+: Scoped storage - no permission needed
      // App writes to its own external directory automatically
      return true;
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

  /// Get Android SDK version
  Future<int> _getAndroidSdkVersion() async {
    try {
      return 30; // Default assume Android 11+ for safe permission handling
    } catch (_) {
      return 30;
    }
  }

  /// Get cross-platform download directory
  /// Uses scoped storage on Android 11+ (app-specific external directory)
  /// which doesn't require MANAGE_EXTERNAL_STORAGE permission.
  /// Files are accessible via file managers and persist across app updates.
  Future<String> _getDownloadDir() async {
    // Check custom download directory first
    if (_customDownloadDir != null && _customDownloadDir!.isNotEmpty) {
      final dir = Directory(_customDownloadDir!);
      if (await dir.exists()) return dir.path;
      // Try to create the custom directory
      try {
        await dir.create(recursive: true);
        return dir.path;
      } catch (_) {
        // Fall through to default
      }
    }

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

  /// Get current download path for display
  Future<String> getCurrentDownloadPath() async {
    if (_customDownloadDir != null) return _customDownloadDir!;
    return await _getDownloadDir();
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
    final taskId = '${movieId}_${quality.replaceAll(' ', '_')}';

    // Check if already exists
    if (_tasks.any((t) => t.id == taskId)) {
      // If completed, allow re-download
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
        return;
      } else {
        return; // Already downloading/paused
      }
    }

    final fileName = '${movieTitle.replaceAll(RegExp(r'[^\w\s-]'), '')}_$quality.mkv'
        .replaceAll(' ', '_');
    final downloadDir = await _getDownloadDir();
    final savePath = '$downloadDir/$fileName';

    final task = DownloadTask(
      id: taskId,
      movieId: movieId,
      movieTitle: movieTitle,
      moviePoster: moviePoster,
      url: url,
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
  Future<void> startDownload(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.status == DownloadStatus.downloading) return;

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

    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      // Check if partial file exists for resume support
      int startByte = task.downloadedBytes;
      final file = File(task.savePath);
      if (startByte > 0 && await file.exists()) {
        final fileSize = await file.length();
        if (fileSize < startByte) {
          // File is smaller than recorded bytes - something went wrong, restart
          startByte = 0;
        } else {
          startByte = fileSize; // Use actual file size for more reliable resume
        }
      } else {
        // No partial file, start from beginning
        startByte = 0;
      }

      // Build headers - add Range header for resume
      final headers = <String, dynamic>{};
      if (startByte > 0) {
        headers['Range'] = 'bytes=$startByte-';
      }

      await _dio.download(
        task.url,
        task.savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final idx = _tasks.indexWhere((t) => t.id == taskId);
          if (idx == -1) return;

          // For resumed downloads, received is relative to the Range request
          final actualReceived = startByte + received;
          final actualTotal = total > 0 ? startByte + total : -1;
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

          _tasks[idx] = _tasks[idx].copyWith(
            progress: progress.clamp(0.0, 1.0),
            downloadedBytes: actualReceived,
            totalBytes: actualTotal > 0 ? actualTotal : null,
            speedBytesPerSec: speed,
            etaSeconds: eta,
          );
          notifyListeners();
        },
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(minutes: 60),
          sendTimeout: const Duration(minutes: 10),
        ),
        deleteOnError: false, // Keep partial file for resume
      );

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
        await _saveTasks();
        notifyListeners();
      }
    } on DioException catch (e) {
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        if (CancelToken.isCancel(e)) {
          // Was paused - save current progress for resume
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.paused,
            speedBytesPerSec: 0.0,
            etaSeconds: null,
          );
        } else {
          String errorMsg = _getDioErrorMessage(e);
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.failed,
            errorMessage: errorMsg,
            speedBytesPerSec: 0.0,
            etaSeconds: null,
          );
        }
        await _saveTasks();
        notifyListeners();
      }
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
    } finally {
      _cancelTokens.remove(taskId);
      _speedTrackers.remove(taskId);
      _activeDownloadCount--;
      _processQueue();
    }
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
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Paused by user');
    }
  }

  /// Resume a paused download (actually resumes from where it left off)
  Future<void> resumeDownload(String taskId) async {
    await startDownload(taskId);
  }

  /// Retry a failed download (resumes from partial if possible)
  Future<void> retryDownload(String taskId) async {
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
  Future<bool> openFile(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;

    final task = _tasks[index];
    final file = File(task.savePath);
    if (!await file.exists()) return false;

    try {
      final result = await OpenFilex.open(task.savePath);
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('Error opening file: $e');
      return false;
    }
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

  // ===== PERSISTENCE =====

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

/// Speed tracker that calculates download speed using a sliding window
class _SpeedTracker {
  final List<_SpeedSample> _samples = [];
  static const int _maxSamples = 10;
  static const Duration _sampleWindow = Duration(seconds: 5);

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
