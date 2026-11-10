import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

// Task 4-about-kmm-localization (2026-11-10): every visible string on this
// page now goes through AppConfig.translate() so the Myanmar language
// switch applies to the FULL page, not just the section headers. The long
// body texts were previously hardcoded English strings and never changed
// when the user picked "မြန်မာ" in Settings.
// Version/Build rows now read live from package_info_plus instead of the
// hardcoded '2.0.0' / '2026.06' that had drifted out of date.

class AboutKmmPage extends StatelessWidget {
  const AboutKmmPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('about_kmm')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 12),

            // App Logo / Icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFFE50914).withOpacity(0.15)
                    : theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_circle_fill,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'KMM',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '2.0.2';
                return Text(
                  '${appConfig.translate("version")} $version',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // App Description
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appConfig.translate('about_kmm'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appConfig.translate('about_kmm_desc_1'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appConfig.translate('about_kmm_desc_2'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Features Section
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                appConfig.translate('features'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.play_circle_outline,
              appConfig.translate('streaming'),
              appConfig.translate('feature_streaming_desc'),
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.download_for_offline_outlined,
              appConfig.translate('downloading'),
              appConfig.translate('feature_downloading_desc'),
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.playlist_add_check_rounded,
              appConfig.translate('watchlist'),
              appConfig.translate('feature_watchlist_desc'),
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.bookmark_outline_rounded,
              appConfig.translate('bookmarks'),
              appConfig.translate('feature_bookmarks_desc'),
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.search_rounded,
              appConfig.translate('search'),
              appConfig.translate('feature_search_desc'),
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.cloud_sync_outlined,
              appConfig.translate('feature_cloud_sync'),
              appConfig.translate('feature_cloud_sync_desc'),
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.language_rounded,
              appConfig.translate('feature_multi_language'),
              appConfig.translate('feature_multi_language_desc'),
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.dark_mode_outlined,
              appConfig.translate('dark_mode'),
              appConfig.translate('feature_dark_mode_desc'),
            ),
            const SizedBox(height: 24),

            // Version Info
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '2.0.2';
                      final buildNumber = snapshot.data?.buildNumber ?? '22';
                      return Column(
                        children: [
                          _buildInfoRow(theme, appConfig.translate('version'), version),
                          const SizedBox(height: 8),
                          _buildInfoRow(theme, appConfig.translate('info_build'), buildNumber),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, appConfig.translate('info_platform'), 'Android'),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, appConfig.translate('info_framework'), 'Flutter'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Credits Section
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                appConfig.translate('credits'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E1E)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appConfig.translate('credits_intro'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCreditItem(
                    theme,
                    isDark,
                    Icons.code,
                    appConfig.translate('credits_development'),
                    appConfig.translate('credits_development_desc'),
                  ),
                  const SizedBox(height: 10),
                  _buildCreditItem(
                    theme,
                    isDark,
                    Icons.cloud_outlined,
                    appConfig.translate('credits_backend'),
                    appConfig.translate('credits_backend_desc'),
                  ),
                  const SizedBox(height: 10),
                  _buildCreditItem(
                    theme,
                    isDark,
                    Icons.palette_outlined,
                    appConfig.translate('credits_design'),
                    appConfig.translate('credits_design_desc'),
                  ),
                  const SizedBox(height: 10),
                  _buildCreditItem(
                    theme,
                    isDark,
                    Icons.translate_rounded,
                    appConfig.translate('credits_localization'),
                    appConfig.translate('credits_localization_desc'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appConfig.translate('credits_thanks'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                      height: 1.7,
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

  Widget _buildFeatureCard(
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
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFFE50914).withOpacity(0.15)
                  : theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
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

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildCreditItem(
    ThemeData theme,
    bool isDark,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: theme.colorScheme.primary,
          size: 20,
        ),
        const SizedBox(width: 12),
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
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
