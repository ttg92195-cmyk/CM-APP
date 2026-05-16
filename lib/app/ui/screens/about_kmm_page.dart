import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

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
            Text(
              '${appConfig.translate("version")} 1.9.0',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
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
                    'KMM (CM Movies) is a comprehensive streaming platform designed for movie and TV series enthusiasts. Whether you are looking for the latest blockbusters, classic films, trending series, or hidden gems from around the world, KMM brings everything together in one beautifully designed application. Our mission is to make discovering and enjoying entertainment as seamless and enjoyable as possible, with a focus on the Myanmar audience while also serving a global user base.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Built with modern technology and a user-first approach, KMM offers a rich set of features including high-quality streaming, offline downloads, personalized watchlists, and cloud-synced bookmarks. The app supports both Myanmar and English languages, and adapts to both dark and light visual preferences. Every aspect of the experience is crafted to deliver speed, reliability, and visual delight.',
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
              'Watch movies and series in multiple resolutions including HD and 4K. Our adaptive streaming technology automatically adjusts quality based on your connection speed for a smooth, buffer-free experience.',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.download_for_offline_outlined,
              appConfig.translate('downloading'),
              'Download your favorite movies and episodes for offline viewing. Choose from multiple resolutions and servers, manage your downloads with a built-in download manager, and enjoy content anywhere without an internet connection.',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.playlist_add_check_rounded,
              appConfig.translate('watchlist'),
              'Create a personal watchlist of movies and series you plan to watch. Your watchlist syncs across all devices via your account, so you can add a movie on your phone and watch it later on your tablet.',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.bookmark_outline_rounded,
              appConfig.translate('bookmarks'),
              'Save your favorite movies and series to your bookmarks for quick access. Bookmarks are cloud-synced through Firebase, ensuring your collection is always available no matter which device you use.',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.search_rounded,
              appConfig.translate('search'),
              'Find movies and series instantly with our powerful search engine. Search by title, genre, tag, or year. Use advanced filters to narrow down results and discover exactly what you are looking for.',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.cloud_sync_outlined,
              'Cloud Sync',
              'All your data — bookmarks, watchlist, viewing history, and preferences — is securely synced to the cloud via Firebase Firestore. Switch devices seamlessly without losing any of your personal content.',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.language_rounded,
              'Multi-Language',
              'Full support for both Myanmar and English languages. Switch between languages instantly from the Settings page, and the entire app interface updates in real time to match your preference.',
            ),
            const SizedBox(height: 10),
            _buildFeatureCard(
              theme,
              isDark,
              Icons.dark_mode_outlined,
              appConfig.translate('dark_mode'),
              'Choose between a sleek dark theme and a clean light theme. Your preference is saved automatically and persists across sessions. The dark theme uses a rich #121212 background with vibrant red accents for comfortable viewing at night.',
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
                  _buildInfoRow(theme, '${appConfig.translate("version")}', '1.9.0'),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, 'Build', '2026.03'),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, 'Platform', 'Android / iOS'),
                  const SizedBox(height: 8),
                  _buildInfoRow(theme, 'Framework', 'Flutter'),
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
                    'KMM is developed and maintained by a dedicated team of developers and designers who are passionate about delivering the best entertainment experience to Myanmar and beyond.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCreditItem(theme, isDark, Icons.code, 'Development', 'Flutter & Dart framework for cross-platform development'),
                  const SizedBox(height: 10),
                  _buildCreditItem(theme, isDark, Icons.cloud_outlined, 'Backend & Cloud', 'Google Firebase (Authentication, Firestore, Storage, App Check) for secure and scalable cloud infrastructure'),
                  const SizedBox(height: 10),
                  _buildCreditItem(theme, isDark, Icons.palette_outlined, 'Design', 'Material Design 3 with custom theming and user experience patterns'),
                  const SizedBox(height: 10),
                  _buildCreditItem(theme, isDark, Icons.translate_rounded, 'Localization', 'Community-driven Myanmar and English translations'),
                  const SizedBox(height: 16),
                  Text(
                    'Special thanks to all our beta testers, community members, and users who provide feedback and help us improve KMM with every release. Your support drives us to build a better experience.',
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
