import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/device_management_service.dart';
import 'package:cm_movies/app/ui/screens/watchlist_screen.dart';
import 'package:cm_movies/app/ui/screens/movie_bookmark_screen.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isChangingPassword = false;
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isChangingPwd = false;

  // Device Management
  final DeviceManagementService _deviceService = DeviceManagementService();
  List<DeviceInfo> _devices = [];
  bool _isLoadingDevices = true;
  bool _isRemovingDevice = false;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final uid = appConfig.currentUser?['uid'] as String?;
    if (uid == null) {
      if (mounted) setState(() => _isLoadingDevices = false);
      return;
    }
    final devices = await _deviceService.getDevices(uid);
    if (mounted) {
      setState(() {
        _devices = devices;
        _isLoadingDevices = false;
      });
    }
  }

  Future<void> _removeDevice(String deviceId) async {
    setState(() => _isRemovingDevice = true);
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final uid = appConfig.currentUser?['uid'] as String?;
    if (uid == null) return;

    final success = await _deviceService.removeDevice(uid, deviceId);
    if (mounted) {
      if (success) {
        setState(() {
          _devices.removeWhere((d) => d.deviceId == deviceId);
          _isRemovingDevice = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device removed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() => _isRemovingDevice = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove device'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleChangePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isChangingPwd = true);
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    final success = await appConfig.changePassword(
      _oldPasswordController.text.trim(),
      _newPasswordController.text.trim(),
    );

    if (mounted) {
      setState(() => _isChangingPwd = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('password_changed')),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _isChangingPassword = false);
        _oldPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('password_change_failed')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // M8: Delete account confirmation dialog (GDPR)
  Future<void> _showDeleteAccountDialog(AppConfig appConfig) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Delete Account'),
          ],
        ),
        content: const Text(
          'This action is permanent and cannot be undone. All your data including '
          'bookmarks, watchlist, and viewing history will be permanently deleted.\n\n'
          'Are you sure you want to delete your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await appConfig.deleteAccount();
      if (mounted) {
        if (success) {
          Navigator.pop(context); // Go back to login page (auth gate handles navigation)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete account. Please login again and retry.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  String _formatDeviceDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _confirmRemoveDevice(DeviceInfo device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text('Are you sure you want to remove "${device.deviceName}"?\n\n'
            'This device will need to log in again to access the account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _removeDevice(device.deviceId);
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    // If still loading auth state
    if (appConfig.isLoadingAuth) {
      return Scaffold(
        appBar: AppBar(
          title: Text(appConfig.translate('profile')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // If not logged in, redirect to login
    if (!appConfig.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(
          title: Text(appConfig.translate('profile')),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline,
                size: 80,
                color: theme.colorScheme.onSurface.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Please login to view your profile',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final username = appConfig.currentUsername ?? 'User';
    final isAdmin = appConfig.isCurrentUserAdmin;
    final isVip = appConfig.isCurrentUserVip;
    final email = appConfig.currentUser?['email'] as String? ?? '';
    final regDate = appConfig.currentUser?['registrationDate'] as String? ?? '';

    // Load devices if not yet loaded
    if (_isLoadingDevices) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDevices());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('profile')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFE50914).withOpacity(0.15),
                        border: Border.all(
                          color: const Color(0xFFE50914),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          username[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE50914),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.5),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isAdmin
                                      ? Colors.green.withOpacity(0.2)
                                      : const Color(0xFFE50914).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isAdmin ? 'Admin' : 'User',
                                  style: TextStyle(
                                    color: isAdmin ? Colors.green : const Color(0xFFE50914),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isVip) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Text(
                                    'VIP',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Account Information Section
            Text(
              appConfig.translate('account_information'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // Account Name
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.person_outline,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  appConfig.translate('account_name'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                subtitle: Text(
                  username,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Account Active Date
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.calendar_today_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  appConfig.translate('account_active'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                subtitle: Text(
                  regDate.isNotEmpty ? regDate : 'N/A',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Cloud Sync Status
            Card(
              child: ListTile(
                leading: Icon(
                  Icons.cloud_done_outlined,
                  color: Colors.green,
                ),
                title: Text(
                  'Cloud Sync',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                subtitle: Text(
                  'Bookmarks synced to cloud',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Bookmarks
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.bookmark_outline,
                  color: Color(0xFFE50914),
                ),
                title: const Text(
                  'Bookmarks',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('View your bookmarked movies'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MovieBookmarkScreen()),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            // Watchlist
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.watch_later_outlined,
                  color: Color(0xFFE50914),
                ),
                title: const Text(
                  'Watchlist',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('View your saved watchlist'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WatchlistScreen()),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Connected Devices Section
            Text(
              'Connected Devices',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            if (_isLoadingDevices)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_devices.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(Icons.devices, color: theme.colorScheme.onSurface.withOpacity(0.3), size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'No devices registered',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              ..._devices.map((device) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.phone_android,
                            color: Color(0xFFE50914),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                device.deviceName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Logged in: ${_formatDeviceDate(device.loginTime)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _isRemovingDevice
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red.shade400,
                                  size: 20,
                                ),
                                onPressed: () => _confirmRemoveDevice(device),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                tooltip: 'Remove device',
                              ),
                      ],
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 24),

            // Change Password Section
            if (!_isChangingPassword)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _isChangingPassword = true);
                  },
                  icon: const Icon(Icons.lock_outline),
                  label: Text(appConfig.translate('change_password')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

            if (_isChangingPassword)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appConfig.translate('change_password'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Old Password
                        TextFormField(
                          controller: _oldPasswordController,
                          obscureText: _obscureOld,
                          decoration: InputDecoration(
                            labelText: appConfig.translate('old_password'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureOld
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () {
                                setState(() => _obscureOld = !_obscureOld);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter old password';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // New Password
                        TextFormField(
                          controller: _newPasswordController,
                          obscureText: _obscureNew,
                          decoration: InputDecoration(
                            labelText: appConfig.translate('new_password'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureNew
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () {
                                setState(() => _obscureNew = !_obscureNew);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please enter new password';
                            }
                            if (val.trim().length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            if (!RegExp(r'[A-Z]').hasMatch(val)) {
                              return 'Must contain an uppercase letter';
                            }
                            if (!RegExp(r'[a-z]').hasMatch(val)) {
                              return 'Must contain a lowercase letter';
                            }
                            if (!RegExp(r'[0-9]').hasMatch(val)) {
                              return 'Must contain a number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),

                        // Confirm New Password
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          decoration: InputDecoration(
                            labelText: appConfig.translate('confirm_new_password'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(_obscureConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () {
                                setState(() => _obscureConfirm = !_obscureConfirm);
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Please confirm new password';
                            }
                            if (val != _newPasswordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Buttons row
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  setState(() => _isChangingPassword = false);
                                  _oldPasswordController.clear();
                                  _newPasswordController.clear();
                                  _confirmPasswordController.clear();
                                },
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _isChangingPwd ? null : _handleChangePassword,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFE50914),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _isChangingPwd
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(appConfig.translate('change_password')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // Logout button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await appConfig.logoutUser();
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(appConfig.translate('logout')),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.logout),
                label: Text(appConfig.translate('logout')),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: const Color(0xFFE50914),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // M8: Delete Account button (GDPR compliance)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showDeleteAccountDialog(appConfig),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Delete Account'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200),
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
