import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

class DownloadPage extends StatefulWidget {
  const DownloadPage({super.key});

  @override
  State<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends State<DownloadPage> {
  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('downloads')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Download Toggle
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.download_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appConfig.translate('download_toggle'),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              appConfig.translate('download_toggle_desc'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: appConfig.downloadEnabled,
                        onChanged: (val) {
                          appConfig.setDownloadEnabled(val);
                        },
                        activeColor: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    appConfig.downloadEnabled
                        ? Icons.download_done_rounded
                        : Icons.cloud_off,
                    size: 64,
                    color: appConfig.downloadEnabled
                        ? Colors.green
                        : theme.colorScheme.onSurface.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appConfig.downloadEnabled
                        ? appConfig.translate('download')
                        : appConfig.translate('download_disabled_msg'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: appConfig.downloadEnabled
                          ? Colors.green
                          : theme.colorScheme.onSurface.withOpacity(0.6),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!appConfig.downloadEnabled)
                    OutlinedButton.icon(
                      onPressed: () {
                        appConfig.setDownloadEnabled(true);
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: Text(appConfig.translate('download_toggle')),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Info Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appConfig.downloadEnabled ? '✅ Enabled' : '❌ Disabled',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: appConfig.downloadEnabled
                          ? Colors.green
                          : Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appConfig.downloadEnabled
                        ? 'Download links are visible in movie detail pages. You can download movies directly from the Download tab in each movie.'
                        : 'Download links are hidden from movie detail pages. Enable the toggle above to see download options.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
