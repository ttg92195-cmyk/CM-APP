import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/download_manager_service.dart';
import 'package:cm_movies/app/ui/screens/download_page.dart';
import 'package:cm_movies/app/ui/screens/vip_page.dart';

class MovieDownloadScreen extends StatefulWidget {
  final MovieDetail movieDetail;

  const MovieDownloadScreen({super.key, required this.movieDetail});

  @override
  State<MovieDownloadScreen> createState() => _MovieDownloadScreenState();
}

class _MovieDownloadScreenState extends State<MovieDownloadScreen> {
  final DownloadManagerService _downloadManager = DownloadManagerService.instance;

  @override
  void initState() {
    super.initState();
    _downloadManager.init();
  }

  Future<void> _startInAppDownload(MovieDownloadLink link) async {
    if (link.url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download link is not available'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // VIP Gate: Only VIP or Admin can download
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    if (!appConfig.isCurrentUserVip && !appConfig.isCurrentUserAdmin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('VIP membership required to download. Please upgrade to VIP.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const VipPage()),
        );
      }
      return;
    }

    if (Platform.isAndroid) {
      final hasPermission = await _downloadManager.checkStoragePermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to download files'),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }
    }

    final appConfig = Provider.of<AppConfig>(context, listen: false);
    if (!appConfig.downloadEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('download_disabled_msg')),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final result = await _downloadManager.addTaskWithResult(
      movieId: widget.movieDetail.id,
      movieTitle: widget.movieDetail.title,
      moviePoster: widget.movieDetail.fullPosterUrl.isNotEmpty ? widget.movieDetail.fullPosterUrl : widget.movieDetail.poster,
      url: link.url,
      quality: link.quality ?? 'Standard',
      size: link.size,
      serverName: link.serverName,
      customFileName: link.fileName,
    );

    if (mounted) {
      String message;
      Color bgColor;
      switch (result) {
        case AddTaskResult.success:
          message = '${appConfig.translate('downloading')} — ${link.quality ?? 'Standard'}';
          bgColor = const Color(0xFF4CAF50);
          break;
        case AddTaskResult.blockedDomain:
          message = 'Download blocked: domain not allowed';
          bgColor = Colors.redAccent;
          break;
        case AddTaskResult.emptyUrl:
          message = 'Download URL is empty';
          bgColor = Colors.redAccent;
          break;
        case AddTaskResult.alreadyExists:
          message = 'Already downloading ${link.quality ?? 'Standard'}';
          bgColor = Colors.orange;
          break;
        case AddTaskResult.permissionDenied:
          message = 'Storage permission required.';
          bgColor = Colors.redAccent;
          break;
        case AddTaskResult.maxTotalReached:
          message = 'Maximum 10 downloads reached. Please wait for a download to finish.';
          bgColor = Colors.orange;
          break;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: bgColor,
          duration: const Duration(seconds: 3),
          action: result == AddTaskResult.success
              ? SnackBarAction(
                  label: 'View',
                  textColor: Colors.white,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DownloadPage()),
                    );
                  },
                )
              : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final bodyTextColor = isDark ? Colors.white70 : Colors.black87;

    // Group download links by server name
    final Map<String, List<MovieDownloadLink>> serverGroups = {};
    for (final link in widget.movieDetail.downloadLinks) {
      final server = link.serverName.isEmpty ? 'Server 1' : link.serverName;
      serverGroups.putIfAbsent(server, () => []).add(link);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Download - ${widget.movieDetail.title}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: widget.movieDetail.downloadLinks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off,
                      size: 48, color: isDark ? Colors.white24 : Colors.black12),
                  const SizedBox(height: 12),
                  Text('No download links available',
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 14)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...serverGroups.entries.map((entry) {
                  final serverName = entry.key;
                  final links = entry.value;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          splashFactory: NoSplash.splashFactory,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        collapsedIconColor: metaTextColor,
                        iconColor: accentColor,
                        collapsedBackgroundColor: Colors.transparent,
                        backgroundColor: Colors.transparent,
                        shape: const RoundedRectangleBorder(side: BorderSide.none),
                        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.download, color: accentColor, size: 22),
                        ),
                        title: Text(
                          serverName,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          '${links.length} qualit${links.length == 1 ? 'y' : 'ies'} available',
                          style: TextStyle(color: metaTextColor, fontSize: 12),
                        ),
                        children: [
                          _buildTableHeader(metaTextColor),
                          const SizedBox(height: 6),
                          ...links.map((link) => _buildDownloadRow(
                                link: link,
                                accentColor: accentColor,
                                bodyTextColor: bodyTextColor,
                                cardBgColor: cardBgColor,
                              )),
                        ],
                      ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildTableHeader(Color metaTextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('Quality', style: TextStyle(
              color: metaTextColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text('Size', style: TextStyle(
              color: metaTextColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            flex: 2,
            child: Text('Server', style: TextStyle(
              color: metaTextColor, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadRow({
    required MovieDownloadLink link,
    required Color accentColor,
    required Color bodyTextColor,
    required Color cardBgColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Text(
                link.quality ?? 'Standard',
                style: TextStyle(color: bodyTextColor, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                link.size ?? '-',
                style: TextStyle(color: bodyTextColor, fontSize: 13),
              ),
            ),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: link.url.isNotEmpty
                      ? () => _startInAppDownload(link)
                      : null,
                  icon: const Icon(Icons.download, size: 14),
                  label: const Text('Download', style: TextStyle(fontSize: 10)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
