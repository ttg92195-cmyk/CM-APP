import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/screens/help_support_page.dart';
import 'package:cm_movies/app/ui/screens/about_kmm_page.dart';
import 'package:cm_movies/app/ui/screens/privacy_policy_page.dart';
import 'package:cm_movies/app/ui/screens/vip_page.dart';
import 'package:cm_movies/app/core/services/poster_cache_manager.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // KMM brand accent color
  static const Color _kAccent = Color(0xFFE50914);

  // Per-section icon tint palette (premium, harmonized)
  static const Color _cVip = Color(0xFFFFB300);
  static const Color _cTheme = Color(0xFF7E57C2);
  static const Color _cPlayer = Color(0xFF1E88E5);
  static const Color _cStorage = Color(0xFF00897B);
  static const Color _cDownloadNotif = Color(0xFFE53935);
  static const Color _cPushNotif = Color(0xFFFF8F00);
  static const Color _cLanguage = Color(0xFF43A047);
  static const Color _cAbout = Color(0xFF607D8B);
  static const Color _cHelp = Color(0xFF8D6E63);
  static const Color _cPrivacy = Color(0xFF5C6BC0);

  // =========================================================================
  // Clear cache — DESIGN CHANGE (audit finding C7)
  // =========================================================================
  // BEFORE this fix, _clearCache() did 3 things:
  //   1. DefaultCacheManager().emptyCache()   ✓ OK — image cache
  //   2. Wipe temp directory                  ✓ OK — temp files
  //   3. WIPE SharedPreferences except 6 keys ✗ BUG — destroyed user data
  //
  // The 3rd step was a critical data-loss bug. The 6 "preserved" keys were
  // only the AppConfig settings (theme/language/player/etc.), but
  // SharedPreferences ALSO stores:
  //   - 'bookmarked_movies'      -> user's bookmarks (BookmarkService)
  //   - 'watchlist_movies'       -> user's watchlist (WatchlistService)
  //   - 'recent_movies'          -> recently-viewed movies (RecentService)
  //   - 'search_history_v1'      -> search history (SearchHistoryService)
  //   - 'download_tasks'         -> download task list (DownloadManagerService)
  //   - 'custom_download_dir'    -> user's chosen download folder
  //   - 'saf_tree_uri/path'      -> SAF folder selection for downloads
  //   - 'downloads_migrated_v2'  -> migration flag (wiping triggers re-migration)
  //   - 'watch_pos_<id>' x N     -> video resume positions (video_player_screen)
  //   - 'watch_dur_<id>' x N     -> video durations for resume
  //
  // Tapping "Clear Cache" silently destroyed ALL of the above. Bro would
  // have lost bookmarks, watch progress, search history, and downloads.
  //
  // FIX: Removed the SharedPreferences wipe entirely. SharedPreferences
  // doesn't actually store any "cache" — every key in there is either a
  // user setting or user data that the user expects to persist. Real
  // cache lives on disk in the cache directory, which is already cleared
  // by steps 1 + 2 (DefaultCacheManager + temp dir).
  //
  // ALSO ADDED: PosterCacheManager.emptyCache() — the custom long-lived
  // poster cache we added in commit 2c68b60. Without this, "Clear Cache"
  // would leave 365-day-old posters on disk indefinitely.
  // =========================================================================
  Future<void> _clearCache(BuildContext context) async {
    try {
      // 1. Clear the default CachedNetworkImage cache.
      await DefaultCacheManager().emptyCache();

      // 2. Clear our custom long-lived PosterCacheManager (posters +
      //    backdrops cached for 365 days). This is the bulk of "cache"
      //    on disk for CM Movies.
      try {
        await PosterCacheManager.instance.clearAllPosters();
      } catch (e) {
        // Best-effort — don't fail the whole clear if this one errors.
        debugPrint('PosterCacheManager.emptyCache failed: $e');
      }

      // 3. Clear the OS temporary directory (where CachedNetworkImage
      //    and other libs stash transient files).
      try {
        final tempDir = await getTemporaryDirectory();
        if (tempDir.existsSync()) {
          final tempFiles = tempDir.listSync(recursive: true);
          for (final file in tempFiles) {
            try {
              if (file is File) {
                await file.delete();
              } else if (file is Directory) {
                await file.delete(recursive: true);
              }
            } catch (_) {
              // Skip files that can't be deleted (in use, etc.)
            }
          }
        }
      } catch (_) {
        // Temp directory cleanup is best-effort
      }

      // 4. SharedPreferences is INTENTIONALLY NOT TOUCHED.
      // Every key in there is either a user setting (theme, language,
      // player mode, notification toggles) or user data (bookmarks,
      // watchlist, recents, search history, download tasks, SAF folder
      // selection, video resume positions, migration flags). Wiping
      // them = silent data loss for the user. See method doc above.

      if (mounted) {
        final appConfig = Provider.of<AppConfig>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('cache_cleared')),
            backgroundColor: _kAccent,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to clear cache. Please try again.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // ---- Bottom sheets for single-tile selectors ----

  void _showVideoPlayerSheet(BuildContext context, AppConfig appConfig) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor:
          isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grabber
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  appConfig.translate('select_video_player'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
            ),
            RadioListTile<String>(
              value: 'builtin',
              groupValue: appConfig.videoPlayerMode,
              activeColor: _kAccent,
              title: Text(appConfig.translate('built_in_player')),
              subtitle: Text(appConfig.translate('video_player_desc')),
              onChanged: (v) {
                if (v != null) appConfig.setVideoPlayerMode(v);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<String>(
              value: 'external',
              groupValue: appConfig.videoPlayerMode,
              activeColor: _kAccent,
              title: Text(appConfig.translate('external_player')),
              onChanged: (v) {
                // Phase 4.37: setVideoPlayerMode is now non-blocking on
                // the UI thread (deferred disk write), so the sheet can
                // dismiss immediately without waiting for the prefs write.
                if (v != null) appConfig.setVideoPlayerMode(v);
                Navigator.pop(ctx);
              },
            ),
            // ============================================================
            // Video Player 2 — DISABLED placeholder (v2.0.0, Task 38 #3)
            // ============================================================
            // Bro explicitly disabled this for the v2.0.0 release. The
            // option is shown so users know it's coming, but it cannot be
            // selected. The `onChanged: null` makes RadioListTile render
            // in its disabled state (grayed out, no ripple). Tapping the
            // title/subtitle area still does nothing because the radio is
            // disabled.
            //
            // To re-enable in a future version (v2.1.0+): wire `onChanged`
            // to a real handler that calls `appConfig.setVideoPlayerMode(
            // 'builtin_v2')` (or whatever the new mode key is), and
            // remove the trailing "Under construction" chip.
            RadioListTile<String>(
              value: 'builtin_v2',
              groupValue: appConfig.videoPlayerMode,
              // onChanged: null → disabled state (grayed out, no tap)
              onChanged: null,
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      appConfig.translate('video_player_2'),
                      style: TextStyle(
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white12 : Colors.black12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      appConfig.languageCode == 'my' ? 'ဆောက်ဆဲ' : 'Soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
              subtitle: Text(
                appConfig.translate('video_player_2_desc'),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white30 : Colors.black38,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, AppConfig appConfig) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor:
          isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  appConfig.translate('select_language'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
            ),
            RadioListTile<String>(
              value: 'my',
              groupValue: appConfig.languageCode,
              activeColor: _kAccent,
              title: const Text('မြန်မာ'),
              subtitle: const Text('Myanmar'),
              onChanged: (v) {
                if (v != null) appConfig.setLanguage(v);
                Navigator.pop(ctx);
              },
            ),
            RadioListTile<String>(
              value: 'en',
              groupValue: appConfig.languageCode,
              activeColor: _kAccent,
              title: const Text('English'),
              subtitle: const Text('English'),
              onChanged: (v) {
                if (v != null) appConfig.setLanguage(v);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  // ---- Reusable building blocks ----

  Widget _buildSectionHeader(String text, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required List<Widget> children,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.05),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _buildInnerDivider(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 64),
      child: Divider(
        height: 1,
        thickness: 0.5,
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.black.withOpacity(0.05),
      ),
    );
  }

  Widget _buildTintedIcon(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(icon, color: color, size: 19),
    );
  }

  // Switch row inside a settings card
  Widget _buildSwitchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _buildTintedIcon(icon, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: value,
            activeColor: _kAccent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // Selector row: shows current value as a red chip + chevron, opens sheet on tap
  Widget _buildSelectorRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String currentValue,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _buildTintedIcon(icon, iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _kAccent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      currentValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _kAccent,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Navigable / action row: icon + title (+ optional subtitle) + chevron
  Widget _buildNavRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              _buildTintedIcon(icon, iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- VIP prominent card at the top ----
  Widget _buildVipCard(AppConfig appConfig, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final isVip = appConfig.currentUser?['isVip'] == true;
    final isMy = appConfig.languageCode == 'my';

    if (isVip) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VipPage()),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFA500).withOpacity(0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.verified,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isMy ? 'VIP သုံးစွဲနေပါပြီ' : 'VIP Active',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isMy
                            ? 'VIP အကျိုးခံစားခွင့်အားလုံး ရရှိနေပါသည်'
                            : 'Enjoying all VIP benefits',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Colors.black54, size: 24),
              ],
            ),
          ),
        ),
      );
    }

    // Non-VIP: gold-outline card with lock icon and Get button
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD700), width: 1.4),
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withOpacity(0.10),
            const Color(0xFFFFA500).withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.lock, color: Colors.black87, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isMy ? 'VIP သို့ ဝင်ရောက်ပါ' : 'Unlock VIP',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isMy
                      ? 'Download များ + နောက်ထပ်အကျိုးခံစားခွင့်များ'
                      : 'Get downloads & more perks',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: const Color(0xFFFFD700),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VipPage()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Text(
                  isMy ? 'ရယူရန်' : 'Get',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        radioTheme: RadioThemeData(
          splashRadius: 0,
          fillColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return _kAccent;
            }
            return theme.brightness == Brightness.dark
                ? Colors.white38
                : Colors.black38;
          }),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // 1. VIP prominent card
          _buildVipCard(appConfig, theme),
          const SizedBox(height: 24),

          // 2. Preferences group (Theme + Video Player + Storage)
          _buildSectionHeader(
              appConfig.languageCode == 'my'
                  ? 'ဆက်တင်များ'
                  : 'Preferences',
              theme),
          _buildSettingsCard(
            theme: theme,
            children: [
              _buildSwitchRow(
                icon: appConfig.isDarkMode
                    ? Icons.dark_mode
                    : Icons.light_mode,
                iconColor: _cTheme,
                title: appConfig.translate('dark_mode'),
                value: appConfig.isDarkMode,
                onChanged: (v) => appConfig.setThemeMode(
                    v ? ThemeMode.dark : ThemeMode.light),
                theme: theme,
              ),
              _buildInnerDivider(theme),
              _buildSelectorRow(
                icon: Icons.play_circle_outline,
                iconColor: _cPlayer,
                title: appConfig.translate('video_player'),
                currentValue: appConfig.videoPlayerMode == 'builtin'
                    ? appConfig.translate('built_in_player')
                    : appConfig.translate('external_player'),
                onTap: () => _showVideoPlayerSheet(context, appConfig),
                theme: theme,
              ),
              _buildInnerDivider(theme),
              _buildNavRow(
                icon: Icons.cleaning_services_outlined,
                iconColor: _cStorage,
                title: appConfig.translate('clear_cache'),
                subtitle: appConfig.translate('clear_cache_desc'),
                onTap: () => _clearCache(context),
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Notifications group
          _buildSectionHeader(appConfig.translate('notifications'), theme),
          _buildSettingsCard(
            theme: theme,
            children: [
              _buildSwitchRow(
                icon: Icons.download_done_rounded,
                iconColor: _cDownloadNotif,
                title: appConfig.translate('downloads_notification'),
                subtitle: appConfig.translate('downloads_notification_desc'),
                value: appConfig.downloadsNotification,
                onChanged: (v) => appConfig.setDownloadsNotification(v),
                theme: theme,
              ),
              _buildInnerDivider(theme),
              _buildSwitchRow(
                icon: Icons.notifications_active_outlined,
                iconColor: _cPushNotif,
                title: appConfig.translate('push_notification'),
                subtitle: appConfig.translate('push_notification_desc'),
                value: appConfig.notificationEnabled,
                onChanged: (v) => appConfig.setNotificationEnabled(v),
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 4. Language group (single selector row)
          _buildSectionHeader(appConfig.translate('language'), theme),
          _buildSettingsCard(
            theme: theme,
            children: [
              _buildSelectorRow(
                icon: Icons.language,
                iconColor: _cLanguage,
                title: appConfig.translate('language'),
                currentValue: appConfig.languageCode == 'my'
                    ? 'မြန်မာ'
                    : 'English',
                onTap: () => _showLanguageSheet(context, appConfig),
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 5. About group
          _buildSectionHeader(appConfig.translate('about'), theme),
          _buildSettingsCard(
            theme: theme,
            children: [
              _buildNavRow(
                icon: Icons.info_outline,
                iconColor: _cAbout,
                title: appConfig.translate('about_cm_movies'),
                subtitle: '${appConfig.translate("version")}: 2.0.0',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutKmmPage()),
                ),
                theme: theme,
              ),
              _buildInnerDivider(theme),
              _buildNavRow(
                icon: Icons.help_outline_rounded,
                iconColor: _cHelp,
                title: appConfig.translate('help_support'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpSupportPage()),
                ),
                theme: theme,
              ),
              _buildInnerDivider(theme),
              _buildNavRow(
                icon: Icons.privacy_tip_outlined,
                iconColor: _cPrivacy,
                title: appConfig.translate('privacy_policy'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyPage()),
                ),
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
