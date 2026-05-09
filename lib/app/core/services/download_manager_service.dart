import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

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
  });

  DownloadTask copyWith({
    DownloadStatus? status,
    double? progress,
    int? downloadedBytes,
    int? totalBytes,
    String? errorMessage,
    DateTime? completedAt,
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
    );
  }

  String get progressText => '${(progress * 100).toStringAsFixed(1)}%';

  String get downloadedSizeText => _formatBytes(downloadedBytes);

  String get totalSizeText => totalBytes != null ? _formatBytes(totalBytes!) : (size ?? 'Unknown');

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Download Manager Service - handles all download operations
class DownloadManagerService extends ChangeNotifier {
  static const String _tasksKey = 'download_tasks';
  final Dio _dio = Dio();

  final Map<String, CancelToken> _cancelTokens = {};
  List<DownloadTask> _tasks = [];

  List<DownloadTask> get tasks => _tasks;
  List<DownloadTask> get activeTasks => _tasks.where((t) =>
      t.status == DownloadStatus.downloading || t.status == DownloadStatus.paused).toList();
  List<DownloadTask> get completedTasks => _tasks.where((t) =>
      t.status == DownloadStatus.completed).toList();

  /// Initialize - load saved tasks
  Future<void> init() async {
    await _loadTasks();
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
        _tasks.remove(existing);
      } else {
        return; // Already downloading/paused
      }
    }

    final fileName = '${movieTitle.replaceAll(RegExp(r'[^\w\s-]'), '')}_$quality.mkv'
        .replaceAll(' ', '_');
    final savePath = '/storage/emulated/0/Download/CM_Movies/$fileName';

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

    // Auto-start download
    startDownload(taskId);
  }

  /// Start or resume a download
  Future<void> startDownload(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.status == DownloadStatus.downloading) return;

    // Update status to downloading
    _tasks[index] = task.copyWith(status: DownloadStatus.downloading);
    notifyListeners();

    final cancelToken = CancelToken();
    _cancelTokens[taskId] = cancelToken;

    try {
      // Ensure directory exists
      final dir = Directory('/storage/emulated/0/Download/CM_Movies');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      await _dio.download(
        task.url,
        task.savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          final idx = _tasks.indexWhere((t) => t.id == taskId);
          if (idx == -1) return;

          final progress = total > 0 ? received / total : 0.0;
          _tasks[idx] = _tasks[idx].copyWith(
            progress: progress,
            downloadedBytes: received,
            totalBytes: total,
          );
          notifyListeners();
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 30),
          sendTimeout: const Duration(minutes: 5),
        ),
        deleteOnError: true,
      );

      // Download completed
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        _tasks[idx] = _tasks[idx].copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          completedAt: DateTime.now(),
        );
        await _saveTasks();
        notifyListeners();
      }
    } catch (e) {
      final idx = _tasks.indexWhere((t) => t.id == taskId);
      if (idx != -1) {
        if (CancelToken.isCancel(e)) {
          // Was paused, not an error
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.paused,
          );
        } else {
          _tasks[idx] = _tasks[idx].copyWith(
            status: DownloadStatus.failed,
            errorMessage: e.toString(),
          );
        }
        await _saveTasks();
        notifyListeners();
      }
    } finally {
      _cancelTokens.remove(taskId);
    }
  }

  /// Pause a download
  void pauseDownload(String taskId) {
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Paused by user');
    }
  }

  /// Resume a paused download
  Future<void> resumeDownload(String taskId) async {
    await startDownload(taskId);
  }

  /// Retry a failed download
  Future<void> retryDownload(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.idle,
      progress: 0.0,
      downloadedBytes: 0,
      errorMessage: null,
    );
    notifyListeners();
    await startDownload(taskId);
  }

  /// Remove a download task
  Future<void> removeTask(String taskId) async {
    // Cancel if active
    final cancelToken = _cancelTokens[taskId];
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel('Removed by user');
    }

    // Delete file if downloaded
    final task = _tasks.firstWhere((t) => t.id == taskId);
    if (task.status == DownloadStatus.completed) {
      try {
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

  /// Clear all completed downloads
  Future<void> clearCompleted() async {
    _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
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
      if (data != null && data.isNotEmpty) {
        final List<dynamic> decoded = json.decode(data) as List<dynamic>;
        _tasks = decoded
            .map((x) => DownloadTask.fromMap(x as Map<String, dynamic>))
            .toList();

        // Reset downloading tasks to paused on restart
        for (int i = 0; i < _tasks.length; i++) {
          if (_tasks[i].status == DownloadStatus.downloading) {
            _tasks[i] = _tasks[i].copyWith(status: DownloadStatus.paused);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading download tasks: $e');
    }
  }
}
