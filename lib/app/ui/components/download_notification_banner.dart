import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';

/// A floating notification banner that shows active download progress.
///
/// Displays at the top of the screen when downloads are in progress.
/// - Shows file name, progress percentage, speed, and ETA for a single download
/// - Shows "X downloads in progress" summary when multiple are active
/// - Animated progress bar with the app's red accent color (#E50914)
/// - Dismissible by swiping right
/// - Only visible when there are active (downloading) tasks
class DownloadNotificationBanner extends StatefulWidget {
  final DownloadManagerService downloadManager;

  const DownloadNotificationBanner({
    super.key,
    required this.downloadManager,
  });

  @override
  State<DownloadNotificationBanner> createState() => _DownloadNotificationBannerState();
}

class _DownloadNotificationBannerState extends State<DownloadNotificationBanner>
    with SingleTickerProviderStateMixin {
  bool _dismissed = false;
  late AnimationController _progressAnimController;
  double _previousProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    // Listen to download manager to reset dismissed state when new downloads start
    widget.downloadManager.addListener(_onDownloadManagerUpdate);
  }

  @override
  void dispose() {
    widget.downloadManager.removeListener(_onDownloadManagerUpdate);
    _progressAnimController.dispose();
    super.dispose();
  }

  void _onDownloadManagerUpdate() {
    final downloadingTasks = widget.downloadManager.tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .toList();

    // If there are active downloads and banner was dismissed, show it again
    if (downloadingTasks.isNotEmpty && _dismissed) {
      setState(() => _dismissed = false);
    }

    // Animate progress changes
    if (downloadingTasks.isNotEmpty) {
      final task = downloadingTasks.first;
      if (task.progress != _previousProgress) {
        _previousProgress = task.progress;
        _progressAnimController.forward(from: 0.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.downloadManager,
      builder: (context, _) {
        final downloadingTasks = widget.downloadManager.tasks
            .where((t) => t.status == DownloadStatus.downloading)
            .toList();

        // Don't show if no active downloads or user dismissed
        if (downloadingTasks.isEmpty || _dismissed) {
          return const SizedBox.shrink();
        }

        return _buildBanner(context, downloadingTasks);
      },
    );
  }

  Widget _buildBanner(BuildContext context, List<DownloadTask> downloadingTasks) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const accentColor = Color(0xFFE50914);

    final isSingle = downloadingTasks.length == 1;
    final task = downloadingTasks.first;

    // Calculate aggregate progress for multiple downloads
    double aggregateProgress = 0.0;
    String aggregateSpeed = '';
    String aggregateEta = '';

    if (isSingle) {
      aggregateProgress = task.progress;
      aggregateSpeed = task.speedText;
      aggregateEta = task.etaText;
    } else {
      double totalProgress = 0.0;
      double totalSpeed = 0.0;
      int? minEta;

      for (final t in downloadingTasks) {
        totalProgress += t.progress;
        totalSpeed += t.speedBytesPerSec;
        if (t.etaSeconds != null && t.etaSeconds! > 0) {
          if (minEta == null || t.etaSeconds! > minEta) {
            minEta = t.etaSeconds;
          }
        }
      }

      aggregateProgress = totalProgress / downloadingTasks.length;
      aggregateSpeed = _formatSpeed(totalSpeed);
      if (minEta != null) {
        aggregateEta = _formatEta(minEta);
      }
    }

    return Dismissible(
      key: ValueKey('download_banner_${downloadingTasks.map((t) => t.id).join('_')}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() => _dismissed = true);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [
                    const Color(0xFFE50914).withOpacity(0.25),
                    const Color(0xFF2A1015),
                  ]
                : [
                    const Color(0xFFE50914).withOpacity(0.08),
                    const Color(0xFFFFF0F1),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withOpacity(isDark ? 0.4 : 0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.15),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Row(
                  children: [
                    // Animated download icon
                    _buildDownloadIcon(accentColor, isDark),
                    const SizedBox(width: 12),

                    // Download info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Title row
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  isSingle
                                      ? task.movieTitle
                                      : '${downloadingTasks.length} downloads in progress',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              // Progress percentage
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${(aggregateProgress * 100).toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: accentColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),

                          // Quality + server for single, or summary for multiple
                          if (isSingle) ...[
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getQualityBadgeColor(task.quality),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    task.quality,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    task.downloadedSizeText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ] else ...[
                            Text(
                              _buildMultiSummary(downloadingTasks),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 3),

                          // Speed and ETA row — wrap each Text in Flexible so long
                          // speed/ETA combos (e.g. "1.5 MB/s · 2h 15m left") don't overflow
                          Row(
                            children: [
                              if (aggregateSpeed.isNotEmpty) ...[
                                Icon(
                                  Icons.speed,
                                  size: 12,
                                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    aggregateSpeed,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                              if (aggregateSpeed.isNotEmpty && aggregateEta.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '·',
                                    style: TextStyle(
                                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              if (aggregateEta.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    aggregateEta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
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
                  ],
                ),
              ),

              // Animated progress bar
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                child: LinearProgressIndicator(
                  value: aggregateProgress.clamp(0.0, 1.0),
                  minHeight: 3,
                  backgroundColor: accentColor.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadIcon(Color accentColor, bool isDark) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: accentColor.withOpacity(isDark ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.download_rounded,
            color: accentColor,
            size: 22,
          ),
          // Small pulsing indicator
          Positioned(
            right: 4,
            top: 4,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 1200),
              builder: (context, value, child) {
                return Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withOpacity(0.5 * (1 - value)),
                        blurRadius: 4 * value,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                );
              },
              onEnd: () {
                // Restart the pulse animation by rebuilding
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  String _buildMultiSummary(List<DownloadTask> tasks) {
    final titles = tasks.take(2).map((t) => t.movieTitle).toList();
    if (tasks.length <= 2) {
      return titles.join(', ');
    }
    return '${titles.first}, ${titles[1]} +${tasks.length - 2} more';
  }

  Color _getQualityBadgeColor(String quality) {
    final q = quality.toLowerCase();
    if (q.contains('4k') || q.contains('uhd')) return const Color(0xFFE50914);
    if (q.contains('1080')) return const Color(0xFFFF6D00);
    if (q.contains('720')) return const Color(0xFFFFAB00);
    return const Color(0xFF4CAF50);
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024) return '${bytesPerSec.round()} B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatEta(int etaSeconds) {
    if (etaSeconds <= 0) return '';
    if (etaSeconds < 60) return '${etaSeconds}s left';
    if (etaSeconds < 3600) return '${etaSeconds ~/ 60}m ${etaSeconds % 60}s left';
    final hours = etaSeconds ~/ 3600;
    final mins = (etaSeconds % 3600) ~/ 60;
    return '${hours}h ${mins}m left';
  }
}

/// A compact floating mini-banner for the home page that shows a
/// small download progress indicator. Less intrusive than the full banner.
class DownloadMiniIndicator extends StatelessWidget {
  final DownloadManagerService downloadManager;
  final VoidCallback? onTap;

  const DownloadMiniIndicator({
    super.key,
    required this.downloadManager,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: downloadManager,
      builder: (context, _) {
        final downloadingTasks = downloadManager.tasks
            .where((t) => t.status == DownloadStatus.downloading)
            .toList();

        if (downloadingTasks.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        const accentColor = Color(0xFFE50914);

        // Calculate aggregate progress
        double totalProgress = 0.0;
        for (final t in downloadingTasks) {
          totalProgress += t.progress;
        }
        final avgProgress = totalProgress / downloadingTasks.length;

        // Get top task speed
        double topSpeed = 0.0;
        for (final t in downloadingTasks) {
          if (t.speedBytesPerSec > topSpeed) {
            topSpeed = t.speedBytesPerSec;
          }
        }

        final speedText = _formatSpeed(topSpeed);

        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [
                        accentColor.withOpacity(0.2),
                        const Color(0xFF2A1015),
                      ]
                    : [
                        accentColor.withOpacity(0.06),
                        const Color(0xFFFFF0F1),
                      ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withOpacity(isDark ? 0.35 : 0.2),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Download icon with progress ring
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: avgProgress.clamp(0.0, 1.0),
                        strokeWidth: 2.5,
                        backgroundColor: accentColor.withOpacity(0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                      Icon(
                        Icons.download_rounded,
                        size: 13,
                        color: accentColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Info text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        downloadingTasks.length == 1
                            ? downloadingTasks.first.movieTitle
                            : '${downloadingTasks.length} downloads in progress',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (speedText.isNotEmpty)
                        Text(
                          '${(avgProgress * 100).toStringAsFixed(0)}% · $speedText',
                          style: TextStyle(
                            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                // Tap to view arrow
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    if (bytesPerSec < 1024) return '${bytesPerSec.round()} B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
