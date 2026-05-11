import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';
import 'package:cm_movies/app/core/services/saf_storage_service.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final DownloadManagerService _downloadManager = DownloadManagerService.instance;
  bool _hasStoragePermission = false;

  @override
  void initState() {
    super.initState();
    _downloadManager.init();
    _checkPermission();
    // Verify completed files still exist after loading
    _downloadManager.verifyCompletedFiles();
  }

  Future<void> _checkPermission() async {
    final granted = await _downloadManager.checkStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = granted);
    }
  }

  Future<void> _requestPermission() async {
    final granted = await _downloadManager.requestStoragePermission();
    if (mounted) {
      setState(() => _hasStoragePermission = granted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('download_manager')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: () => _showDownloadSettings(appConfig, theme),
            tooltip: 'Download Settings',
          ),
          ListenableBuilder(
            listenable: _downloadManager,
            builder: (context, _) {
              if (_downloadManager.completedTasks.isNotEmpty) {
                return IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                  onPressed: () => _showClearCompletedConfirm(appConfig, theme),
                  tooltip: appConfig.translate('clear_completed'),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Storage Permission Banner (show if not granted)
          if (!_hasStoragePermission && Platform.isAndroid)
            _buildPermissionBanner(appConfig, theme),

          // Download Toggle
          _buildDownloadToggle(appConfig, theme),

          const SizedBox(height: 8),

          // Stats Summary
          ListenableBuilder(
            listenable: _downloadManager,
            builder: (context, _) {
              if (_downloadManager.totalTasks == 0) return const SizedBox.shrink();
              return _buildStatsSummary(theme);
            },
          ),

          // Download Tasks
          Expanded(
            child: ListenableBuilder(
              listenable: _downloadManager,
              builder: (context, _) {
                final tasks = _downloadManager.tasks;
                final activeTasks = _downloadManager.activeTasks;
                final completedTasks = _downloadManager.completedTasks;
                final failedTasks = _downloadManager.failedTasks;

                if (tasks.isEmpty) {
                  return _buildEmptyState(appConfig, theme);
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    // Active Downloads
                    if (activeTasks.isNotEmpty) ...[
                      _buildSectionHeader(
                        '${appConfig.translate('active_downloads')} (${activeTasks.length})',
                        theme,
                        icon: Icons.downloading_rounded,
                        iconColor: const Color(0xFFE50914),
                      ),
                      const SizedBox(height: 8),
                      ...activeTasks.map((task) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildActiveTaskCard(task, appConfig, theme),
                          )),
                    ],

                    // Completed Downloads
                    if (completedTasks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSectionHeader(
                        '${appConfig.translate('completed_downloads')} (${completedTasks.length})',
                        theme,
                        icon: Icons.check_circle_outline,
                        iconColor: Colors.green,
                      ),
                      const SizedBox(height: 8),
                      ...completedTasks.map((task) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildCompletedTaskCard(task, appConfig, theme),
                          )),
                    ],

                    // Failed Downloads
                    if (failedTasks.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSectionHeader(
                        '${appConfig.translate('failed')} (${failedTasks.length})',
                        theme,
                        icon: Icons.error_outline,
                        iconColor: Colors.redAccent,
                      ),
                      const SizedBox(height: 8),
                      ...failedTasks.map((task) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildFailedTaskCard(task, appConfig, theme),
                          )),
                    ],

                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.orange.shade900.withOpacity(0.3) : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.orange.shade400.withOpacity(0.5),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_off_outlined, color: Colors.orange.shade400, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage Permission Required',
                  style: TextStyle(
                    color: isDark ? Colors.orange.shade200 : Colors.orange.shade800,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Allow storage access so downloads are visible in your file manager',
                  style: TextStyle(
                    color: isDark ? Colors.orange.shade300.withOpacity(0.7) : Colors.orange.shade700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _requestPermission,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            child: const Text('Allow', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadToggle(AppConfig appConfig, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.download_rounded,
                color: appConfig.downloadEnabled ? Colors.green : Colors.grey,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appConfig.translate('download_toggle'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      appConfig.translate('download_toggle_desc'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: appConfig.downloadEnabled,
                onChanged: (val) => appConfig.setDownloadEnabled(val),
                activeColor: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsSummary(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final active = _downloadManager.activeCount;
    final completed = _downloadManager.completedCount;
    final failed = _downloadManager.failedCount;
    final totalSize = _downloadManager.completedTotalSize;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.grey.shade200,
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatChip(
              icon: Icons.downloading_rounded,
              label: '$active Active',
              color: const Color(0xFFE50914),
              isDark: isDark,
            ),
            Container(
              width: 1,
              height: 20,
              color: isDark ? Colors.white12 : Colors.grey.shade300,
            ),
            _buildStatChip(
              icon: Icons.check_circle_outline,
              label: '$completed Done',
              color: Colors.green,
              isDark: isDark,
            ),
            if (failed > 0) ...[
              Container(
                width: 1,
                height: 20,
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
              _buildStatChip(
                icon: Icons.error_outline,
                label: '$failed Failed',
                color: Colors.redAccent,
                isDark: isDark,
              ),
            ],
            if (totalSize.isNotEmpty) ...[
              Container(
                width: 1,
                height: 20,
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
              _buildStatChip(
                icon: Icons.storage_outlined,
                label: totalSize,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                isDark: isDark,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(AppConfig appConfig, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.download_outlined,
            size: 72,
            color: theme.colorScheme.onSurface.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            appConfig.translate('no_downloads_yet'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap "Save" on any movie or series to start downloading',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme,
      {IconData? icon, Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? theme.colorScheme.onSurface.withOpacity(0.7)),
            const SizedBox(width: 6),
          ],
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTaskCard(DownloadTask task, AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = const Color(0xFFE50914);
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final isDownloading = task.status == DownloadStatus.downloading;
    final isPaused = task.status == DownloadStatus.paused;

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: poster + info
            Row(
              children: [
                // Poster
                Container(
                  width: 45,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    color: isDark ? const Color(0xFF121212) : Colors.grey.shade200,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: task.moviePoster != null && task.moviePoster!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: task.moviePoster!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Icon(Icons.movie,
                                size: 20, color: isDark ? Colors.white24 : Colors.black12),
                          )
                        : Icon(Icons.movie,
                            size: 20, color: isDark ? Colors.white24 : Colors.black12),
                  ),
                ),
                const SizedBox(width: 10),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.movieTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: _getQualityBadgeColor(task.quality),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              task.quality,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            task.serverName,
                            style: TextStyle(color: metaTextColor, fontSize: 10),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Status text with speed and ETA
                      Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: isDownloading
                                ? CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: task.progress,
                                    color: accentColor,
                                  )
                                : Icon(
                                    Icons.pause_circle_filled,
                                    size: 12,
                                    color: Colors.orange.shade400,
                                  ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              isDownloading
                                  ? _buildActiveStatusText(task)
                                  : appConfig.translate('paused'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDownloading ? accentColor : Colors.orange.shade400,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Action buttons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isDownloading)
                      IconButton(
                        icon: Icon(Icons.pause_circle_outline,
                            size: 28, color: Colors.orange.shade400),
                        onPressed: () => _downloadManager.pauseDownload(task.id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        tooltip: 'Pause',
                      )
                    else if (isPaused)
                      IconButton(
                        icon: Icon(Icons.play_circle_filled,
                            size: 28, color: Colors.green.shade400),
                        onPressed: () => _downloadManager.resumeDownload(task.id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        tooltip: 'Resume',
                      ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: metaTextColor),
                      onPressed: () => _showCancelConfirm(task, appConfig, theme),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      tooltip: 'Cancel',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: task.progress,
                      minHeight: 6,
                      backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDownloading ? accentColor : Colors.orange.shade400,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  task.progressText,
                  style: TextStyle(
                    color: isDownloading ? accentColor : Colors.orange.shade400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            // Speed and ETA row
            if (isDownloading && (task.speedText.isNotEmpty || task.etaText.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (task.speedText.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.speed, size: 11, color: metaTextColor),
                          const SizedBox(width: 3),
                          Text(
                            task.speedText,
                            style: TextStyle(
                              color: metaTextColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                    if (task.etaText.isNotEmpty)
                      Text(
                        task.etaText,
                        style: TextStyle(
                          color: metaTextColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _buildActiveStatusText(DownloadTask task) {
    final parts = <String>[];
    parts.add('${task.downloadedSizeText} / ${task.totalSizeText}');
    return parts.join(' · ');
  }

  Widget _buildCompletedTaskCard(DownloadTask task, AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade200,
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Poster
            Container(
              width: 45,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: isDark ? const Color(0xFF121212) : Colors.grey.shade200,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: task.moviePoster != null && task.moviePoster!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: task.moviePoster!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(Icons.movie,
                            size: 20, color: isDark ? Colors.white24 : Colors.black12),
                      )
                    : Icon(Icons.movie,
                        size: 20, color: isDark ? Colors.white24 : Colors.black12),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.movieTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _getQualityBadgeColor(task.quality),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          task.quality,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle, size: 12, color: Colors.green.shade400),
                      const SizedBox(width: 3),
                      Text(
                        appConfig.translate('completed'),
                        style: TextStyle(
                          color: Colors.green.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    task.totalSizeText,
                    style: TextStyle(color: metaTextColor, fontSize: 10),
                  ),
                ],
              ),
            ),
            // Action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Open file button
                IconButton(
                  icon: Icon(Icons.play_circle_outline, size: 22, color: const Color(0xFFE50914)),
                  onPressed: () async {
                    final success = await _downloadManager.openFile(task.id);
                    if (!success && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cannot open file. It may have been moved or deleted.'),
                          backgroundColor: Colors.redAccent,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Open file',
                ),
                // Delete file button
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: metaTextColor),
                  onPressed: () => _showDeleteConfirm(task, appConfig, theme),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedTaskCard(DownloadTask task, AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Poster for failed items too
            Container(
              width: 45,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: isDark ? const Color(0xFF121212) : Colors.grey.shade200,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: task.moviePoster != null && task.moviePoster!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: task.moviePoster!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(Icons.movie,
                            size: 20, color: isDark ? Colors.white24 : Colors.black12),
                      )
                    : Icon(Icons.movie,
                        size: 20, color: isDark ? Colors.white24 : Colors.black12),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.movieTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _getQualityBadgeColor(task.quality),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          task.quality,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        task.serverName,
                        style: TextStyle(color: metaTextColor, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.error_outline, size: 12, color: Colors.redAccent.shade200),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          task.errorMessage ?? appConfig.translate('failed'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.redAccent.shade200,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Retry button
                IconButton(
                  icon: Icon(Icons.refresh, size: 22, color: const Color(0xFFE50914)),
                  onPressed: () => _downloadManager.retryDownload(task.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: appConfig.translate('retry'),
                ),
                // Remove button
                IconButton(
                  icon: Icon(Icons.close, size: 18, color: metaTextColor),
                  onPressed: () => _downloadManager.removeTask(task.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Remove',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getQualityBadgeColor(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd')) return const Color(0xFFE50914);
    if (q.contains('1080')) return const Color(0xFFFF6D00);
    if (q.contains('720')) return const Color(0xFFFFAB00);
    return const Color(0xFF4CAF50);
  }

  // ===== Confirmation Dialogs =====

  void _showCancelConfirm(DownloadTask task, AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text('Cancel Download?'),
        content: Text('Remove "${task.movieTitle}" and delete partial file?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Keep', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadManager.removeTask(task.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Download'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(DownloadTask task, AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: const Text('Delete Download?'),
        content: Text('Delete the downloaded file for "${task.movieTitle}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadManager.deleteFile(task.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Delete File Only'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadManager.removeTask(task.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  void _showClearCompletedConfirm(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(appConfig.translate('clear_completed')),
        content: Text('Remove all completed downloads from the list? Files will be kept on disk.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadManager.clearCompleted();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  // ===== Download Settings =====

  void _showDownloadSettings(AppConfig appConfig, ThemeData theme) async {
    final isDark = theme.brightness == Brightness.dark;
    String currentPath = await _downloadManager.getDownloadDisplayPath();
    bool hasPermission = await _downloadManager.checkStoragePermission();
    // Check if SAF permission is still valid (can be revoked by user/system)
    bool safPermissionValid = true;
    if (Platform.isAndroid) {
      safPermissionValid = await SafStorageService.instance.isSafPermissionValid();
      if (!safPermissionValid) {
        // SAF permission was revoked - clear the stored folder
        await SafStorageService.instance.clearStoredFolder();
        currentPath = await _downloadManager.getDownloadDisplayPath();
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Download Settings',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Storage Permission (Status Checker)
                  if (Platform.isAndroid) ...[
                    Text(
                      'Storage Permission',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Status Checker - tappable to grant permission if not granted
                    InkWell(
                      onTap: hasPermission
                          ? null
                          : () => _showPermissionModal(appConfig, theme, (granted) {
                                setModalState(() => hasPermission = granted);
                                if (mounted) {
                                  setState(() => _hasStoragePermission = granted);
                                }
                              }),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: hasPermission
                              ? (isDark ? Colors.green.shade900.withOpacity(0.2) : Colors.green.shade50)
                              : (isDark ? Colors.red.shade900.withOpacity(0.2) : Colors.red.shade50),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: hasPermission
                                ? Colors.green.shade400.withOpacity(0.4)
                                : Colors.red.shade400.withOpacity(0.4),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              hasPermission ? Icons.verified_user_rounded : Icons.shield_outlined,
                              color: hasPermission ? Colors.green.shade400 : Colors.red.shade400,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              hasPermission ? 'Granted' : 'Not Granted — Tap to Allow',
                              style: TextStyle(
                                color: hasPermission
                                    ? Colors.green.shade400
                                    : Colors.red.shade400,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!hasPermission) ...[
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.red.shade400),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Download Location (SAF Folder Picker)
                  Text(
                    'Download Location',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // SAF Folder Picker Button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Current path display
                        Row(
                          children: [
                            Icon(Icons.folder_outlined, size: 18, color: theme.colorScheme.onSurface.withOpacity(0.6)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                currentPath,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Choose Folder Button (SAF)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              // Open SAF folder picker
                              final result = await _downloadManager.openSafFolderPicker();
                              if (result != null) {
                                // SAF folder selected successfully
                                setModalState(() => currentPath = result.treePath);
                                // Also fix any existing failed tasks that have wrong save paths
                                await _downloadManager.fixExistingTaskPaths();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text('Download location setup complete!'),
                                      backgroundColor: Colors.green.shade600,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.folder_open, size: 18),
                            label: const Text('Choose Folder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFE50914),
                              side: const BorderSide(color: Color(0xFFE50914)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap "Choose Folder" to select a download location. The system file picker will open — select any folder and tap "Use this folder" to grant access.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Max concurrent downloads info
                  Text(
                    'Simultaneous Downloads',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Up to 3 downloads can run at the same time. Additional downloads will start automatically when a slot opens.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Show modal dialog to grant storage permission
  void _showPermissionModal(AppConfig appConfig, ThemeData theme, Function(bool) onResult) {
    final isDark = theme.brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.red.shade400, size: 24),
            const SizedBox(width: 8),
            const Text('Storage Permission', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage permission is required to download and save files to your device.',
              style: TextStyle(
                color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Without this permission, downloads will fail. Grant access to continue.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(ctx);
              final granted = await _downloadManager.requestStoragePermission();
              onResult(granted);
            },
            icon: const Icon(Icons.verified_user_rounded, size: 18),
            label: const Text('Grant Permission'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }
}
