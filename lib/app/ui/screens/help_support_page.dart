import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('help_support')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.help_center_rounded,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appConfig.translate('help_support'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${appConfig.translate("app_version")}: 2.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // FAQ Section
            _buildSectionTitle(theme, appConfig.translate('faq')),
            const SizedBox(height: 8),
            _buildFaqTile(
              theme,
              isDark,
              'How do I create an account?',
              'To create an account, open the app and tap on the "Register" button on the login screen. Enter your desired username and a strong password (at least 8 characters with uppercase, lowercase, and a number). Once submitted, your account will be created and you can start exploring movies and series immediately.',
            ),
            _buildFaqTile(
              theme,
              isDark,
              'How do I add movies to my bookmarks?',
              'While browsing any movie or series detail page, simply tap the bookmark icon to save it to your bookmarks. You can access all your bookmarked content from the Bookmarks tab in the bottom navigation bar. Bookmarks are synced to your account via Firebase, so they are available across all your devices.',
            ),
            _buildFaqTile(
              theme,
              isDark,
              'How do I download movies for offline viewing?',
              'First, make sure the download feature is enabled in Settings > Show Download. Then, navigate to any movie detail page and tap the Download button. Choose your preferred resolution and server. Downloads will appear in the Download Manager where you can track progress, pause, or resume.',
            ),
            _buildFaqTile(
              theme,
              isDark,
              'How do I switch between dark and light mode?',
              'Go to Settings from the bottom navigation bar. Under the Theme section, toggle the Dark Mode switch on or off. Your preference is saved automatically and will persist across app restarts.',
            ),
            _buildFaqTile(
              theme,
              isDark,
              'How do I change the app language?',
              'Navigate to Settings and find the Language section. You can choose between Myanmar and English. The entire app interface will update immediately to reflect your selected language preference.',
            ),
            _buildFaqTile(
              theme,
              isDark,
              'How do I add movies to my watchlist?',
              'On any movie or series detail page, tap the watchlist icon (clock with a plus sign). This adds the content to your personal watchlist, which you can access from the Watchlist tab. Watchlist items are synced across devices through your account.',
            ),
            const SizedBox(height: 24),

            // Troubleshooting Section
            _buildSectionTitle(theme, appConfig.translate('troubleshooting')),
            const SizedBox(height: 8),
            _buildTipCard(
              theme,
              isDark,
              Icons.wifi_off_rounded,
              'Video not loading or buffering',
              'Check your internet connection and try switching to a different server. If the issue persists, clear the app cache from your device settings and restart the app. Slow connections may require lowering the streaming quality.',
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.sync_problem_rounded,
              'Bookmarks not syncing across devices',
              'Make sure you are logged into the same account on all devices. Check your internet connection and try pulling down to refresh. If the issue continues, log out and log back in to force a sync.',
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.download_rounded,
              'Downloads failing or not starting',
              'Ensure the download feature is enabled in Settings. Check available storage on your device. Try switching to a different server or resolution. If downloads continue to fail, restart the app and try again.',
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.login_rounded,
              'Unable to log in to my account',
              'Double-check your username and password. Make sure Caps Lock is off. If you have forgotten your password, you can reset it from the login screen. If your account was recently created, wait a few moments and try again.',
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.refresh_rounded,
              'App crashing or freezing',
              'Try closing and reopening the app. If the issue persists, clear the app cache from your device settings. Make sure you are using the latest version of KMM. If crashes continue, uninstall and reinstall the app.',
            ),
            const SizedBox(height: 24),

            // Contact Section
            _buildSectionTitle(theme, appConfig.translate('contact_us')),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFFE50914).withOpacity(0.3)
                      : theme.colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.email_outlined,
                        color: theme.colorScheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Email Support',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'guyg20985@gmail.com',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'We typically respond within 24–48 hours. Please include your app version (2.0.0), device model, and a detailed description of the issue when contacting us so we can assist you more efficiently.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // App Version Info Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${appConfig.translate("app_version")}: 2.0.0 • Build 2026.06',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildFaqTile(ThemeData theme, bool isDark, String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E1E)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: theme.colorScheme.primary,
          collapsedIconColor: theme.colorScheme.onSurface.withOpacity(0.5),
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          title: Text(
          question,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [
          Text(
            answer,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.7,
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTipCard(
    ThemeData theme,
    bool isDark,
    IconData icon,
    String title,
    String description,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E1E1E)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: theme.colorScheme.primary,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
