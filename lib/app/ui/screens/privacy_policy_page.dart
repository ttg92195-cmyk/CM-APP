import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

// Localization contract (Task 6b, 2026-11-11): every visible string on this
// page goes through appConfig.translate() — no hardcoded English.
// Bullet paragraphs keep the leading '•' — _buildSectionCard styles them via
// p.startsWith('•').
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('privacy_policy')),
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
                    Icons.privacy_tip_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appConfig.translate('privacy_policy'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appConfig.translate('privacy_last_updated'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                appConfig.translate('privacy_intro'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 28),

            // Section 1: Data Collection
            _buildSectionCard(
              theme,
              isDark,
              appConfig.translate('data_collection'),
              Icons.storage_rounded,
              [
                appConfig.translate('data_collection_intro'),
                '',
                appConfig.translate('data_collection_credential'),
                '',
                appConfig.translate('data_collection_password'),
                '',
                appConfig.translate('data_collection_content'),
                '',
                appConfig.translate('data_collection_prefs'),
                '',
                appConfig.translate('data_collection_usage'),
              ],
            ),
            const SizedBox(height: 16),

            // Section 2: Data Usage
            _buildSectionCard(
              theme,
              isDark,
              appConfig.translate('data_usage'),
              Icons.analytics_rounded,
              [
                appConfig.translate('data_usage_intro'),
                '',
                appConfig.translate('data_usage_delivery'),
                '',
                appConfig.translate('data_usage_personalization'),
                '',
                appConfig.translate('data_usage_sync'),
                '',
                appConfig.translate('data_usage_account'),
                '',
                appConfig.translate('data_usage_improvement'),
                '',
                appConfig.translate('data_usage_communication'),
                '',
                appConfig.translate('data_usage_security'),
              ],
            ),
            const SizedBox(height: 16),

            // Section 3: Third-Party Services
            _buildSectionCard(
              theme,
              isDark,
              appConfig.translate('third_party_services'),
              Icons.share_rounded,
              [
                appConfig.translate('third_party_intro'),
                '',
                appConfig.translate('third_party_auth'),
                '',
                appConfig.translate('third_party_firestore'),
                '',
                appConfig.translate('third_party_appcheck'),
                '',
                appConfig.translate('third_party_storage'),
                '',
                appConfig.translate('third_party_closing'),
              ],
            ),
            const SizedBox(height: 16),

            // Section 4: Data Security
            _buildSectionCard(
              theme,
              isDark,
              appConfig.translate('data_security'),
              Icons.shield_rounded,
              [
                appConfig.translate('data_security_intro'),
                '',
                appConfig.translate('data_security_transit'),
                '',
                appConfig.translate('data_security_rest'),
                '',
                appConfig.translate('data_security_auth'),
                '',
                appConfig.translate('data_security_access'),
                '',
                appConfig.translate('data_security_session'),
                '',
                appConfig.translate('data_security_deletion'),
                '',
                appConfig.translate('data_security_closing'),
              ],
            ),
            const SizedBox(height: 16),

            // Section 5: Children's Privacy
            _buildSectionCard(
              theme,
              isDark,
              appConfig.translate('children_privacy'),
              Icons.child_care_rounded,
              [
                appConfig.translate('children_privacy_intro'),
                '',
                appConfig.translate('children_privacy_parents'),
                '',
                appConfig.translate('children_privacy_rating'),
              ],
            ),
            const SizedBox(height: 16),

            // Section 6: Changes to This Policy
            _buildSectionCard(
              theme,
              isDark,
              appConfig.translate('changes_to_policy'),
              Icons.update_rounded,
              [
                appConfig.translate('changes_policy_intro'),
                '',
                appConfig.translate('changes_policy_notify'),
                '',
                appConfig.translate('changes_policy_history'),
              ],
            ),
            const SizedBox(height: 16),

            // Section 7: Contact Us
            _buildSectionCard(
              theme,
              isDark,
              appConfig.translate('contact_us'),
              Icons.mail_rounded,
              [
                appConfig.translate('contact_privacy_intro'),
                '',
                appConfig.translate('contact_privacy_email'),
                appConfig.translate('contact_privacy_website'),
                '',
                appConfig.translate('contact_privacy_response'),
                '',
                appConfig.translate('contact_privacy_authority'),
              ],
            ),
            const SizedBox(height: 28),

            // Footer
            Center(
              child: Column(
                children: [
                  Divider(
                    color: theme.colorScheme.onSurface.withOpacity(0.1),
                    thickness: 1,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    appConfig.translate('privacy_footer_copyright'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appConfig.translate('privacy_footer_effective'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
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

  Widget _buildSectionCard(
    ThemeData theme,
    bool isDark,
    String title,
    IconData icon, [
    List<String> paragraphs = const [],
  ]) {
    return Container(
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
          Row(
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
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (paragraphs.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...paragraphs.map(
              (p) => p.isEmpty
                  ? const SizedBox(height: 8)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        p,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.7,
                          color: theme.colorScheme.onSurface.withOpacity(
                            p.startsWith('•') ? 0.85 : 0.7,
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
