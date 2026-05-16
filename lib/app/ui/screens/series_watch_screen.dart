import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/models/movie_detail.dart';
import 'package:cm_movies/app/ui/screens/video_player_screen.dart';

class SeriesWatchScreen extends StatefulWidget {
  final MovieDetail seriesDetail;

  const SeriesWatchScreen({super.key, required this.seriesDetail});

  @override
  State<SeriesWatchScreen> createState() => _SeriesWatchScreenState();
}

class _SeriesWatchScreenState extends State<SeriesWatchScreen> {
  // Track expanded season and selected episode
  int? _expandedSeason;
  int? _selectedEpisodeSeason;
  int? _selectedEpisodeIndex;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = Theme.of(context).colorScheme.primary;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final cardBgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final metaTextColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final bodyTextColor = isDark ? Colors.white70 : Colors.black87;

    final hasWatchLinks = widget.seriesDetail.seasons
        .any((s) => s.episodes.any((e) => e.watchLinks.isNotEmpty));

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text('Watch - ${widget.seriesDetail.title}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: !hasWatchLinks
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline, size: 48, color: isDark ? Colors.white24 : Colors.black12),
                  const SizedBox(height: 12),
                  Text('No watch links available',
                      style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 14)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Season-based structure
                ...widget.seriesDetail.seasons.asMap().entries.map((seasonEntry) {
                  final seasonIndex = seasonEntry.key;
                  final season = seasonEntry.value;

                  // Check if this season has any watch links
                  final seasonHasLinks = season.episodes.any((e) => e.watchLinks.isNotEmpty);
                  if (!seasonHasLinks) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(12),
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
                        initiallyExpanded: _expandedSeason == seasonIndex,
                        onExpansionChanged: (expanded) {
                          setState(() {
                            _expandedSeason = expanded ? seasonIndex : null;
                          });
                        },
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.video_library, color: accentColor, size: 22),
                        ),
                        title: Text(
                          season.name,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          '${season.episodes.length} episode${season.episodes.length == 1 ? '' : 's'}',
                          style: TextStyle(color: metaTextColor, fontSize: 12),
                        ),
                        children: [
                          // Episode list
                          ...season.episodes.asMap().entries.map((epEntry) {
                            final epIndex = epEntry.key;
                            final episode = epEntry.value;
                            final isSelected = _selectedEpisodeSeason == seasonIndex && _selectedEpisodeIndex == epIndex;

                            return Column(
                              children: [
                                // Episode button
                                InkWell(
                                  splashColor: Colors.transparent,
                                  highlightColor: Colors.transparent,
                                  onTap: episode.watchLinks.isNotEmpty
                                      ? () {
                                          setState(() {
                                            if (isSelected) {
                                              _selectedEpisodeSeason = null;
                                              _selectedEpisodeIndex = null;
                                            } else {
                                              _selectedEpisodeSeason = seasonIndex;
                                              _selectedEpisodeIndex = epIndex;
                                            }
                                          });
                                        }
                                      : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected ? accentColor.withOpacity(0.1) : Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected ? Icons.play_circle_filled : Icons.play_circle_outline,
                                          color: episode.watchLinks.isNotEmpty ? accentColor : metaTextColor,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            episode.name,
                                            style: TextStyle(
                                              color: episode.watchLinks.isNotEmpty ? bodyTextColor : metaTextColor,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (episode.watchLinks.isNotEmpty)
                                          Icon(
                                            isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                            color: metaTextColor,
                                            size: 18,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                // Show quality/size/watch rows if selected
                                if (isSelected && episode.watchLinks.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  _buildTableHeader(metaTextColor),
                                  const SizedBox(height: 4),
                                  ...episode.watchLinks.map((link) => _buildWatchRow(
                                        link: link,
                                        accentColor: accentColor,
                                        bodyTextColor: bodyTextColor,
                                        cardBgColor: cardBgColor,
                                      )),
                                ],
                                const SizedBox.shrink(),
                              ],
                            );
                          }),
                        ],
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
          Expanded(flex: 2, child: Text('Quality', style: TextStyle(color: metaTextColor, fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Size', style: TextStyle(color: metaTextColor, fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Server', style: TextStyle(color: metaTextColor, fontSize: 11, fontWeight: FontWeight.w600))),
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
            Expanded(
              flex: 2,
              child: Text(link.quality ?? 'Standard',
                  style: TextStyle(color: bodyTextColor, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
            Expanded(
              flex: 2,
              child: Text(link.size ?? '-',
                  style: TextStyle(color: bodyTextColor, fontSize: 13)),
            ),
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
                                title: widget.seriesDetail.title,
                                videoId: widget.seriesDetail.id,
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
