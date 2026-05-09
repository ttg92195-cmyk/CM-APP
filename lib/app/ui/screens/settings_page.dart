import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/notification_service.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return ListView(
      children: [
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

        // Notification Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('notifications'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Consumer<NotificationService>(
          builder: (context, notifService, _) {
            return Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_outlined),
                  title: Text(appConfig.translate('notifications_toggle')),
                  subtitle: Text(
                    appConfig.translate('notifications_toggle_desc'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                  value: notifService.notificationsEnabled,
                  onChanged: (val) {
                    notifService.setNotificationsEnabled(val);
                  },
                ),
                // New Movies notification sub-toggle
                AnimatedCrossFade(
                  firstChild: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: SwitchListTile(
                      secondary: const Icon(Icons.movie_filter_outlined),
                      title: Text(appConfig.translate('new_movies_notif')),
                      subtitle: Text(
                        appConfig.translate('new_movies_notif_desc'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                      value: notifService.newMoviesEnabled,
                      onChanged: notifService.notificationsEnabled
                          ? (val) {
                              notifService.setNewMoviesEnabled(val);
                            }
                          : null,
                    ),
                  ),
                  secondChild: const SizedBox.shrink(),
                  crossFadeState: notifService.notificationsEnabled
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  duration: const Duration(milliseconds: 300),
                ),
                // Test notification button
                if (notifService.notificationsEnabled)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.send_outlined),
                      title: Text(appConfig.translate('test_notification')),
                      trailing: const Icon(Icons.chevron_right),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                        ),
                      ),
                      onTap: () async {
                        await notifService.showTestNotification();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(appConfig.translate('test_notification_sent')),
                              backgroundColor: const Color(0xFFE50914),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
              ],
            );
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

        // About Section
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            appConfig.translate('about_app'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // CM Movies - About
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(appConfig.translate('about_cm_movies')),
          subtitle: Text('${appConfig.translate("version")}: 1.0.0'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _AboutCMMoviesPage(),
              ),
            );
          },
        ),

        // Privacy and Policy
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(appConfig.translate('privacy_policy')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const _PrivacyPolicyPage(),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AboutCMMoviesPage extends StatelessWidget {
  const _AboutCMMoviesPage();

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('about_cm_movies')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Icon(
              Icons.play_circle_fill,
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'CM Movies',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Version 1.0.0',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                appConfig.translate('about_cm_movies_text'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.8,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildFeatureCard(theme, Icons.movie_filter, 'Browse & Discover', 'Explore trending movies and TV series'),
            const SizedBox(height: 12),
            _buildFeatureCard(theme, Icons.search, 'Smart Search', 'Find movies by title, genre, or tag'),
            const SizedBox(height: 12),
            _buildFeatureCard(theme, Icons.bookmark, 'Bookmarks', 'Save your favorite movies for later'),
            const SizedBox(height: 12),
            _buildFeatureCard(theme, Icons.notifications_active, 'Push Notifications', 'Get notified when new movies arrive'),
            const SizedBox(height: 12),
            _buildFeatureCard(theme, Icons.cloud_done, 'Cloud Sync', 'Sync bookmarks across devices with Firebase'),
            const SizedBox(height: 12),
            _buildFeatureCard(theme, Icons.language, 'Multi-Language', 'Supports Myanmar and English'),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(ThemeData theme, IconData icon, String title, String subtitle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPolicyPage extends StatelessWidget {
  const _PrivacyPolicyPage();

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('privacy_policy')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Icon(Icons.privacy_tip_rounded, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text(appConfig.translate('privacy_policy'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Last updated: 2026', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withOpacity(0.5))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                appConfig.translate('privacy_policy_text'),
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.8),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contact', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.language),
                      title: const Text('www.cmmovies.app'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    ListTile(
                      leading: const Icon(Icons.email_outlined),
                      title: const Text('support@cmmovies.app'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
