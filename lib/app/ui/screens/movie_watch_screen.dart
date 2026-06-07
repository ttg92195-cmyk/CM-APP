import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/ui/screens/video_player_screen.dart';

class MovieWatchScreen extends StatefulWidget {
  final MovieDetail movieDetail;

  const MovieWatchScreen({super.key, required this.movieDetail});

  @override
  State<MovieWatchScreen> createState() => _MovieWatchScreenState();
}

class _MovieWatchScreenState extends State<MovieWatchScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final bodyTextColor = isDark ? Colors.white70 : Colors.black87;

    // Group watch links by server name
    final Map<String, List<MovieWatchLink>> serverGroups = {};
    for (final link in widget.movieDetail.watchLinks) {
      final server = link.serverName.isEmpty ? 'Server 1' : link.serverName;
      serverGroups.putIfAbsent(server, () => []).add(link);
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Watch - ${widget.movieDetail.title}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: widget.movieDetail.watchLinks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline,
                      size: 48, color: isDark ? Colors.white24 : Colors.black12),
                  const SizedBox(height: 12),
                  Text('No watch links available',
                      style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                          fontSize: 14)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Server groups as expandable tiles
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
                          child: Icon(Icons.play_circle, color: accentColor, size: 22),
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
                          // Header row
                          _buildTableHeader(metaTextColor),
                          const SizedBox(height: 6),
                          // Quality/Size/Watch rows
                          ...links.map((link) => _buildWatchRow(
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

  Widget _buildWatchRow({
    required MovieWatchLink link,
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
            // Quality
            Expanded(
              flex: 2,
              child: Text(
                link.quality ?? 'Standard',
                style: TextStyle(color: bodyTextColor, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            // Size
            Expanded(
              flex: 2,
              child: Text(
                link.size ?? '-',
                style: TextStyle(color: bodyTextColor, fontSize: 13),
              ),
            ),
            // Watch button
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 32,
                child: ElevatedButton.icon(
                  onPressed: link.url.isNotEmpty
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VideoPlayerScreen(
                                videoUrl: link.url,
                                title: widget.movieDetail.title,
                                videoId: widget.movieDetail.id,
                              ),
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.play_arrow, size: 14),
                  label: const Text('Watch', style: TextStyle(fontSize: 11)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
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
