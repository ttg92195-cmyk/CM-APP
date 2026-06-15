import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/screens/help_support_page.dart';
import 'package:cm_movies/app/ui/screens/about_kmm_page.dart';
import 'package:cm_movies/app/ui/screens/privacy_policy_page.dart';
import 'package:cm_movies/app/ui/screens/vip_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Feature 3: Clear cache method — clears cached images, temp files, and non-critical preferences
  Future<void> _clearCache(BuildContext context) async {
    try {
      // 1. Clear CachedNetworkImage cache (libcached_network_image)
      await DefaultCacheManager().emptyCache();

      // 2. Clear temporary directory files
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

      // 3. Clear SharedPreferences except critical keys (theme, language, video player mode)
      final prefs = await SharedPreferences.getInstance();
      final criticalKeys = {
        'app_theme',
        'app_language',
        'video_player_mode',
        'download_enabled',
        'downloads_notification',
        'notification_enabled',
      };
      final allKeys = prefs.getKeys();
      final keysToRemove = allKeys.where((key) => !criticalKeys.contains(key)).toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }

      if (mounted) {
        final appConfig = Provider.of<AppConfig>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('cache_cleared')),
            backgroundColor: const Color(0xFFE50914),
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
              return const Color(0xFFE50914);
            }
            return theme.brightness == Brightness.dark ? Colors.white38 : Colors.black38;
          }),
        ),
      ),
      child: ListView(
      children: [
        // VIP Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.languageCode == 'my' ? 'အကောင့်' : 'Account',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.verified, color: Colors.black87, size: 20),
          ),
          title: Text(
            'VIP',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: appConfig.currentUser?['isVip'] == true
                  ? const Color(0xFFFFD700)
                  : null,
            ),
          ),
          subtitle: Text(
            appConfig.currentUser?['isVip'] == true
                ? (appConfig.languageCode == 'my' ? 'VIP သုံးစွဲနေပါပြီ' : 'VIP Active')
                : (appConfig.languageCode == 'my' ? 'VIP အဆင့်ကို ရွေးချယ်ပါ' : 'Choose your VIP plan'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const VipPage(),
              ),
            );
          },
        ),
        const Divider(),

        // Theme Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('theme'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SwitchListTile(
          secondary: Icon(
            appConfig.isDarkMode ? Icons.dark_mode : Icons.light_mode,
          ),
          title: Text(appConfig.translate('dark_mode')),
          value: appConfig.isDarkMode,
          onChanged: (val) {
            appConfig.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
          },
        ),
        const Divider(),

        // Player Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('video_player'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        RadioListTile<String>(
          secondary: const Icon(Icons.play_circle_outline),
          title: Text(appConfig.translate('built_in_player')),
          subtitle: Text(appConfig.translate('video_player_desc')),
          value: 'builtin',
          groupValue: appConfig.videoPlayerMode,
          onChanged: (val) {
            if (val != null) appConfig.setVideoPlayerMode(val);
          },
        ),
        RadioListTile<String>(
          secondary: const Icon(Icons.open_in_new),
          title: Text(appConfig.translate('external_player')),
          value: 'external',
          groupValue: appConfig.videoPlayerMode,
          onChanged: (val) {
            if (val != null) appConfig.setVideoPlayerMode(val);
          },
        ),
        const Divider(),

        // Feature 3: Storage Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('storage'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: Text(appConfig.translate('clear_cache')),
          subtitle: Text(appConfig.translate('clear_cache_desc')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _clearCache(context),
        ),
        const Divider(),

        // Notifications Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('notifications'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.download_done_rounded),
          title: Text(appConfig.translate('downloads_notification')),
          subtitle: Text(appConfig.translate('downloads_notification_desc')),
          value: appConfig.downloadsNotification,
          activeColor: const Color(0xFFE50914),
          onChanged: (val) {
            appConfig.setDownloadsNotification(val);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: Text(appConfig.translate('push_notification')),
          subtitle: Text(appConfig.translate('push_notification_desc')),
          value: appConfig.notificationEnabled,
          activeColor: const Color(0xFFE50914),
          onChanged: (val) {
            appConfig.setNotificationEnabled(val);
          },
        ),
        const Divider(),

        // Language Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('language'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        RadioListTile<String>(
          title: const Text('မြန်မာ'),
          subtitle: const Text('Myanmar'),
          value: 'my',
          groupValue: appConfig.languageCode,
          onChanged: (val) {
            if (val != null) appConfig.setLanguage(val);
          },
        ),
        RadioListTile<String>(
          title: const Text('English'),
          subtitle: const Text('English'),
          value: 'en',
          groupValue: appConfig.languageCode,
          onChanged: (val) {
            if (val != null) appConfig.setLanguage(val);
          },
        ),
        const Divider(),

        // About Section (renamed from "About App" to "About")
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('about'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // KMM - About (existing)
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(appConfig.translate('about_cm_movies')),
          subtitle: Text('${appConfig.translate("version")}: 1.9.0'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AboutKmmPage(),
              ),
            );
          },
        ),

        // Help & Support (new)
        ListTile(
          leading: const Icon(Icons.help_outline_rounded),
          title: Text(appConfig.translate('help_support')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const HelpSupportPage(),
              ),
            );
          },
        ),

        // Privacy and Policy (new — navigates to standalone page)
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(appConfig.translate('privacy_policy')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrivacyPolicyPage(),
              ),
            );
          },
        ),
      ],
    ),
    );
  }
}
