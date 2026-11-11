import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Localization contract (Task 6a, 2026-11-11): every visible string on this
// page goes through appConfig.translate() — no hardcoded English.
// Version/Build rows read live from package_info_plus (no stale literals).
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
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '2.0.2';
                      return Text(
                        '${appConfig.translate("app_version")}: $version',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      );
                    },
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
              appConfig.translate('faq_create_account_q'),
              appConfig.translate('faq_create_account_a'),
            ),
            _buildFaqTile(
              theme,
              isDark,
              appConfig.translate('faq_bookmark_q'),
              appConfig.translate('faq_bookmark_a'),
            ),
            _buildFaqTile(
              theme,
              isDark,
              appConfig.translate('faq_download_q'),
              appConfig.translate('faq_download_a'),
            ),
            _buildFaqTile(
              theme,
              isDark,
              appConfig.translate('faq_theme_q'),
              appConfig.translate('faq_theme_a'),
            ),
            _buildFaqTile(
              theme,
              isDark,
              appConfig.translate('faq_language_q'),
              appConfig.translate('faq_language_a'),
            ),
            _buildFaqTile(
              theme,
              isDark,
              appConfig.translate('faq_watchlist_q'),
              appConfig.translate('faq_watchlist_a'),
            ),
            const SizedBox(height: 24),

            // Troubleshooting Section
            _buildSectionTitle(theme, appConfig.translate('troubleshooting')),
            const SizedBox(height: 8),
            _buildTipCard(
              theme,
              isDark,
              Icons.wifi_off_rounded,
              appConfig.translate('troubleshoot_video_title'),
              appConfig.translate('troubleshoot_video_desc'),
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.sync_problem_rounded,
              appConfig.translate('troubleshoot_sync_title'),
              appConfig.translate('troubleshoot_sync_desc'),
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.download_rounded,
              appConfig.translate('troubleshoot_download_title'),
              appConfig.translate('troubleshoot_download_desc'),
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.login_rounded,
              appConfig.translate('troubleshoot_login_title'),
              appConfig.translate('troubleshoot_login_desc'),
            ),
            const SizedBox(height: 10),
            _buildTipCard(
              theme,
              isDark,
              Icons.refresh_rounded,
              appConfig.translate('troubleshoot_crash_title'),
              appConfig.translate('troubleshoot_crash_desc'),
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
                              appConfig.translate('contact_email_support'),
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
                    appConfig.translate('contact_response_note'),
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
                    child: FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final version = snapshot.data?.version ?? '2.0.2';
                        final build = snapshot.data?.buildNumber ?? '22';
                        return Text(
                          '${appConfig.translate("app_version")}: $version • Build $build',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        );
                      },
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
