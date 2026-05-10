import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  final DownloadManagerService _downloadManager = DownloadManagerService.instance;

  @override
  void initState() {
    super.initState();
    _downloadManager.init();
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
                  onPressed: () => _downloadManager.clearCompleted(),
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
          // Download Toggle
          _buildDownloadToggle(appConfig, theme),

          const SizedBox(height: 8),

          // Download Tasks
          Expanded(
            child: ListenableBuilder(
              listenable: _downloadManager,
              builder: (context, _) {
                final tasks = _downloadManager.tasks;
                final activeTasks = _downloadManager.activeTasks;
                final completedTasks = _downloadManager.completedTasks;

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
                      ),
                      const SizedBox(height: 8),
                      ...completedTasks.map((task) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildCompletedTaskCard(task, appConfig, theme),
                          )),
                    ],

                    // Failed Downloads
                    ..._buildFailedSection(tasks, appConfig, theme),

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
            'Download movies from the detail page',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurface.withOpacity(0.7),
        ),
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
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
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
                      // Status text
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
                          Text(
                            isDownloading
                                ? '${task.progressText} · ${task.downloadedSizeText}'
                                : appConfig.translate('paused'),
                            style: TextStyle(
                              color: isDownloading ? accentColor : Colors.orange.shade400,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
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
                      )
                    else if (isPaused)
                      IconButton(
                        icon: Icon(Icons.play_circle_filled,
                            size: 28, color: Colors.green.shade400),
                        onPressed: () => _downloadManager.resumeDownload(task.id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    IconButton(
                      icon: Icon(Icons.close, size: 20, color: metaTextColor),
                      onPressed: () => _downloadManager.removeTask(task.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.progress,
                minHeight: 6,
                backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDownloading
                      ? accentColor
                      : Colors.orange.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
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
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: metaTextColor),
              onPressed: () => _downloadManager.removeTask(task.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFailedSection(List<DownloadTask> tasks, AppConfig appConfig, ThemeData theme) {
    final failedTasks = tasks.where((t) => t.status == DownloadStatus.failed).toList();
    if (failedTasks.isEmpty) return [];

    final isDark = theme.brightness == Brightness.dark;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return [
      const SizedBox(height: 12),
      _buildSectionHeader(
        '${appConfig.translate('failed')} (${failedTasks.length})',
        theme,
      ),
      const SizedBox(height: 8),
      ...failedTasks.map((task) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
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
                              Icon(Icons.error_outline, size: 12, color: Colors.redAccent.shade200),
                              const SizedBox(width: 3),
                              Text(
                                appConfig.translate('failed'),
                                style: TextStyle(
                                  color: Colors.redAccent.shade200,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _downloadManager.retryDownload(task.id),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(appConfig.translate('retry')),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFE50914),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )),
    ];
  }

  Color _getQualityBadgeColor(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd')) return const Color(0xFFE50914);
    if (q.contains('1080')) return const Color(0xFFFF6D00);
    if (q.contains('720')) return const Color(0xFFFFAB00);
    return const Color(0xFF4CAF50);
  }

  void _showDownloadSettings(AppConfig appConfig, ThemeData theme) async {
    final isDark = theme.brightness == Brightness.dark;
    String currentPath = await _downloadManager.getCurrentDownloadPath();

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

                  // Download Location
                  Text(
                    'Download Location',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
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
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.folder_open, size: 20),
                          onPressed: () async {
                            final controller = TextEditingController();
                            final result = await showDialog<String>(
                              context: context,
                              builder: (dialogCtx) => AlertDialog(
                                title: const Text('Change Download Location'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Enter the full path for downloads:',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: controller,
                                      decoration: const InputDecoration(
                                        labelText: 'Folder Path',
                                        hintText: '/storage/emulated/0/Download/CM_Movies',
                                        border: OutlineInputBorder(),
                                      ),
                                      autofocus: true,
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dialogCtx),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFE50914),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );
                            if (result != null && result.isNotEmpty) {
                              await DownloadManagerService.setCustomDownloadDir(result);
                              final newPath = await _downloadManager.getCurrentDownloadPath();
                              setModalState(() => currentPath = newPath);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the folder icon to change the download location.',
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
}
