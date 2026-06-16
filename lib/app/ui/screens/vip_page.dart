import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

class VipPage extends StatelessWidget {
  const VipPage({super.key});

  static const String _telegramLink = 'https://t.me/Shine7162dsh';

  static const List<Map<String, dynamic>> _vipTiers = [
    {'level': 1, 'price': 1000, 'days': 10},
    {'level': 2, 'price': 2000, 'days': 20},
    {'level': 3, 'price': 3000, 'days': 30},
    {'level': 4, 'price': 4000, 'days': 40},
    {'level': 5, 'price': 5000, 'days': 50},
    {'level': 6, 'price': 6000, 'days': 60},
    {'level': 7, 'price': 7000, 'days': 70},
    {'level': 8, 'price': 8000, 'days': 80},
    {'level': 9, 'price': 9000, 'days': 90},
    {'level': 10, 'price': 10000, 'days': 100},
    {'level': 11, 'price': 11000, 'days': 110},
    {'level': 12, 'price': 12000, 'days': 120},
    {'level': 13, 'price': 13000, 'days': 130},
    {'level': 14, 'price': 14000, 'days': 140},
    {'level': 15, 'price': 15000, 'days': 150},
    {'level': 16, 'price': 16000, 'days': 160},
    {'level': 17, 'price': 17000, 'days': 170},
    {'level': 18, 'price': 18000, 'days': 180},
    {'level': 19, 'price': 19000, 'days': 190},
    {'level': 20, 'price': 20000, 'days': 200},
  ];

  static const List<String> _vipBenefits = [
    'Unlimited Download',
    'Unlimited Stream',
    'Device 4',
    '10 Download',
    '5 Days VIP Gift (All Users)',
    'Support on Request',
  ];

  Future<void> _openTelegram(BuildContext context) async {
    // Try tg:// deep link first (opens Telegram app directly)
    final tgUri = Uri.parse('tg://resolve?domain=Shine7162dsh');
    try {
      final launched = await launchUrl(tgUri, mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (_) {
      // tg:// scheme not available, try https fallback
    }

    // Fallback: https://t.me/ URL with external application mode
    final httpsUri = Uri.parse(_telegramLink);
    try {
      final launched = await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
      if (launched) return;
    } catch (_) {
      // https URL also failed
    }

    // Last resort: try platform default
    try {
      final launched = await launchUrl(httpsUri, mode: LaunchMode.platformDefault);
      if (launched) return;
    } catch (_) {}

    // All methods failed
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open Telegram. Please install Telegram first.'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if user has active VIP
    final isVip = appConfig.isCurrentUserVip;
    final vipExpiry = appConfig.currentUser?['vipExpiry'] as String?;
    final hasActiveVip = isVip;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VIP'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // VIP Status Banner
          if (hasActiveVip)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Colors.black87, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VIP Active',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Expires: $vipExpiry',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFE50914).withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appConfig.languageCode == 'my'
                        ? 'သင့် VIP အဆင့်ကို ရွေးချယ်ပါ'
                        : 'Choose your VIP plan',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    appConfig.languageCode == 'my'
                        ? 'VIP အကျိုးခံစားခွင့်များစွာ ရရှိပါမည်'
                        : 'Unlock premium features and benefits',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),

          // VIP Benefits
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.grey.shade300,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.star, color: Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      appConfig.languageCode == 'my'
                          ? 'VIP အကျိုးခံစားခွင့်များ'
                          : 'VIP Benefits',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._vipBenefits.map((benefit) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 18),
                      const SizedBox(width: 10),
                      Text(
                        benefit,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                )),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // VIP Tier List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _vipTiers.length,
              itemBuilder: (context, index) {
                final tier = _vipTiers[index];
                final level = tier['level'] as int;
                final price = tier['price'] as int;
                final days = tier['days'] as int;

                // Gradient colors based on VIP level
                final List<Color> gradientColors;
                if (level <= 5) {
                  gradientColors = [const Color(0xFF4CAF50), const Color(0xFF2E7D32)]; // Green
                } else if (level <= 10) {
                  gradientColors = [const Color(0xFF2196F3), const Color(0xFF1565C0)]; // Blue
                } else if (level <= 15) {
                  gradientColors = [const Color(0xFF9C27B0), const Color(0xFF6A1B9A)]; // Purple
                } else {
                  gradientColors = [const Color(0xFFFFD700), const Color(0xFFFF8F00)]; // Gold
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.grey.shade300,
                    ),
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openTelegram(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            // VIP Badge
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: gradientColors[0].withOpacity(0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'VIP',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    '$level',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Price & Duration
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${price}ks',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '$days Days',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? Colors.white54 : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Subscribe Button
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                appConfig.languageCode == 'my' ? 'မှာယူရန်' : 'Subscribe',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
