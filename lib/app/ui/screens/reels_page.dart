// =============================================================================
// Phase 4 Step C — Reels Page (bottom nav 5th tab)
// =============================================================================
// The Reels tab page shown when the user taps the 5th item in the bottom
// navigation. Phase 4 Step C provides only the SKELETON — an empty state
// with a friendly "Reels coming soon" message — because the 3-column
// grid UI is Step D.
//
// Why split Step C and Step D:
//   - Bro asked for "တစ်ခုချင်စီလုပ်ပါ" (do one thing at a time).
//   - Step C wires the tab into the bottom nav + IndexedStack.
//   - Step D fills the page body with the actual grid UI.
//   - Keeping them separate means Bro can build & test the bottom-nav
//     tab navigation works BEFORE I touch the page body — if there's a
//     tab index bug, it shows up cleanly without the grid UI confusing
//     the test.
//
// The page is a StatefulWidget because Step D will need state for:
//   - loading reels from ReelsService
//   - pagination cursor
//   - error state
//   - pull-to-refresh
//
// For Step C, we keep the state minimal — just a `RefreshIndicator`
// wrapping a friendly empty state so the tab doesn't look broken.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

class ReelsPage extends StatefulWidget {
  const ReelsPage({super.key});

  @override
  State<ReelsPage> createState() => _ReelsPageState();
}

class _ReelsPageState extends State<ReelsPage> {
  // Phase 4 Step C: empty placeholder state.
  // Step D will replace this with: ReelsService.getReels() + grid UI.

  Future<void> _onRefresh() async {
    // No-op for Step C — just simulate a delay so the
    // RefreshIndicator spinner shows. Step D will do a real reload.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white54 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      // No AppBar — Reels tab is a full-bleed visual tab like TikTok/IG.
      // Step D will overlay a custom header with the "Reels" title.
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: const Color(0xFFE50914),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_collection_outlined,
                    size: 80,
                    color: const Color(0xFFE50914).withOpacity(0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appConfig.translate('reels'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appConfig.translate('reels_empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: subTextColor,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Helpful hint pointing to the next step's UI.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: const Color(0xFFE50914)),
                        const SizedBox(width: 8),
                        Text(
                          'Grid UI coming in Step D',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFFE50914),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
