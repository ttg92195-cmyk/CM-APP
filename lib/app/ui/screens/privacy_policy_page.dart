import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

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
                    color: isDark ? const Color(0xFFE50914) : theme.colorScheme.primary,
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
                    'Last updated: March 2026',
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
                'KMM ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application KMM (CM Movies). Please read this policy carefully. By using the app, you agree to the practices described in this Privacy Policy.',
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
                'We collect information that you provide directly to us when you create an account, use our services, or communicate with us. This includes:',
                '',
                '• Account Credentials: Your username and email address are collected during registration. These are stored securely via Firebase Authentication, which uses industry-standard encryption to protect your credentials.',
                '',
                '• Passwords: Your password is never stored in plain text. Firebase Authentication handles password hashing and verification using bcrypt/scrypt algorithms, ensuring that even we cannot view your original password.',
                '',
                '• User Content: Bookmarks, watchlist entries, and viewing history that you create while using the app are synced to your account via Firebase Firestore. This data is associated with your authenticated user ID.',
                '',
                '• App Preferences: Theme preference (dark/light mode), language selection (Myanmar/English), download settings, and other customization options are stored locally on your device using SharedPreferences.',
                '',
                '• Usage Data: We may collect anonymized usage statistics such as feature interaction patterns and crash reports to improve app performance and user experience. This data does not contain personally identifiable information.',
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
                'We use the information we collect for the following purposes:',
                '',
                '• Service Delivery: To provide, operate, and maintain the KMM application, including user authentication, content browsing, streaming, and download functionality.',
                '',
                '• Personalization: To save your bookmarks, watchlist, and viewing history so you can pick up where you left off on any device logged into your account.',
                '',
                '• Cross-Device Syncing: To synchronize your personal data (bookmarks, watchlist, history, preferences) across all devices linked to your account via Firebase Cloud Firestore.',
                '',
                '• Account Management: To manage your account, process password changes, handle account deletion requests, and enforce session timeout policies for security.',
                '',
                '• Improvement: To analyze usage patterns, identify bugs, and improve the performance, stability, and features of the application.',
                '',
                '• Communication: To respond to your support requests, inquiries, and feedback submitted via email or in-app contact methods.',
                '',
                '• Security: To detect and prevent fraud, unauthorized access, and other illegal activities, and to enforce our terms of service.',
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
                'KMM integrates with the following third-party services, each of which has its own privacy policy governing the use of your information:',
                '',
                '• Google Firebase Authentication: Handles user registration, login, and session management. Firebase stores your email and encrypted password. Refer to Google\'s Privacy Policy at https://policies.google.com/privacy.',
                '',
                '• Google Cloud Firestore: Stores your bookmarks, watchlist, viewing history, and user profile data. Data is encrypted in transit (TLS 1.3) and at rest (AES-256). Firestore security rules ensure that only authenticated users can access their own data.',
                '',
                '• Firebase App Check: Protects our backend resources from abuse by verifying that requests originate from the genuine KMM application.',
                '',
                '• Firebase Storage: Used for storing and serving media assets and downloaded content when applicable.',
                '',
                'We do not sell, rent, or trade your personal information to any third party for marketing purposes. Third-party service providers are bound by their own privacy obligations and are only permitted to use your data as necessary to provide the services we have engaged them to perform.',
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
                'We implement robust security measures to protect your personal information from unauthorized access, alteration, disclosure, or destruction:',
                '',
                '• Encryption in Transit: All data transmitted between the KMM app and our cloud services is encrypted using TLS 1.3, ensuring that your information cannot be intercepted during transmission.',
                '',
                '• Encryption at Rest: Data stored in Firebase Firestore and Firebase Storage is encrypted at rest using AES-256, one of the strongest encryption standards available.',
                '',
                '• Authentication Security: Firebase Authentication uses modern hashing algorithms (scrypt) for password storage. Your password is never accessible to our team or stored in plain text anywhere in our systems.',
                '',
                '• Access Controls: Firebase Security Rules ensure that each user can only read and write their own data. Administrators have restricted access and all access is logged and auditable.',
                '',
                '• Session Management: We implement automatic session timeouts after 30 minutes of inactivity. Users are required to re-authenticate to regain access, reducing the risk of unauthorized access on shared or lost devices.',
                '',
                '• Account Deletion: Users can delete their accounts and all associated data at any time from the Profile page. Upon deletion, all Firestore documents, sub-collections (bookmarks, watchlist, history), and the Firebase Authentication account are permanently removed.',
                '',
                'While we strive to protect your personal information, no method of electronic storage or transmission is 100% secure. We cannot guarantee absolute security but continuously monitor and improve our security practices.',
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
                'KMM is not intended for use by children under the age of 13, and we do not knowingly collect personal information from children under 13. If we become aware that we have inadvertently collected personal data from a child under 13, we will take immediate steps to delete such information from our servers.',
                '',
                'Parents or guardians who believe that their child has provided personal information to us should contact us immediately at support@kmmovies.app, and we will take prompt action to remove the data.',
                '',
                'Some content within KMM may be rated for mature audiences (18+). We implement an age verification gate for such content, requiring users to confirm they are 18 years or older before accessing restricted material. This feature is a content advisory tool and not a substitute for parental supervision.',
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
                'We reserve the right to update or modify this Privacy Policy at any time. When we make changes, we will update the "Last updated" date at the top of this page. We encourage you to review this Privacy Policy periodically to stay informed about how we protect your information.',
                '',
                'If we make material changes to this Privacy Policy that affect how we handle your personal data, we will notify you through the app, by email, or through other communication channels before the changes take effect. Your continued use of the app after any changes constitutes your acceptance of the updated Privacy Policy.',
                '',
                'We maintain a version history of all policy changes and can provide previous versions upon request. Significant changes may include modifications to data collection practices, new third-party integrations, or changes to your rights regarding your data.',
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
                'If you have any questions, concerns, or requests regarding this Privacy Policy or our data practices, please do not hesitate to contact us:',
                '',
                '• Email: support@kmmovies.app',
                '• Website: www.kmmovies.app',
                '',
                'We are committed to addressing your concerns promptly and will respond to all privacy-related inquiries within 30 days. For account deletion requests, data access requests, or data correction needs, please include your username and a detailed description of your request.',
                '',
                'If you are not satisfied with our response, you may also contact the relevant data protection authority in your jurisdiction.',
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
                    '© 2026 KMM (CM Movies). All rights reserved.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This policy is effective as of March 2026.',
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
                  color: isDark ? const Color(0xFFE50914) : theme.colorScheme.primary,
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
