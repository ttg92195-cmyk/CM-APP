import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/screens/help_support_page.dart';
import 'package:cm_movies/app/ui/screens/about_kmm_page.dart';
import 'package:cm_movies/app/ui/screens/privacy_policy_page.dart';
import 'package:cm_movies/app/ui/screens/vip_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
