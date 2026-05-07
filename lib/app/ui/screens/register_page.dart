import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _regUsernameController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureRegPassword = true;
  bool _obscureRegConfirmPassword = true;
  bool _isLoggingIn = false;

  // Admin credentials
  static const String _adminUsername = 'Chitminzaw';
  static const String _adminPassword = 'Chitmin7';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;

    setState(() => _isLoggingIn = true);

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username == _adminUsername && password == _adminPassword) {
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      await appConfig.setAdminLoggedIn(true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('login_success')),
            backgroundColor: Colors.green,
          ),
        );
        _usernameController.clear();
        _passwordController.clear();
        setState(() => _isLoggingIn = false);
      }
    } else {
      if (mounted) {
        final appConfig = Provider.of<AppConfig>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('login_failed')),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isLoggingIn = false);
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;

    final appConfig = Provider.of<AppConfig>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(appConfig.translate('register_success')),
        backgroundColor: Colors.green,
      ),
    );
    _regUsernameController.clear();
    _regPasswordController.clear();
    _regConfirmPasswordController.clear();
  }

  Future<void> _handleLogout() async {
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    await appConfig.setAdminLoggedIn(false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appConfig.translate('logout')),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('register')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.admin_panel_settings),
              text: appConfig.translate('admin_login'),
            ),
            Tab(
              icon: const Icon(Icons.person_add),
              text: appConfig.translate('register'),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAdminLoginTab(appConfig, theme),
          _buildRegisterTab(appConfig, theme),
        ],
      ),
    );
  }

  Widget _buildAdminLoginTab(AppConfig appConfig, ThemeData theme) {
    // If already logged in, show admin panel
    if (appConfig.adminLoggedIn) {
      return _buildAdminPanel(appConfig, theme);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            // Icon
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.admin_panel_settings,
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              appConfig.translate('admin_login'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Login to manage your app settings',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),

            // Username field
            TextFormField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: appConfig.translate('username'),
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter username';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password field
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: appConfig.translate('password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter password';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Login button
            FilledButton(
              onPressed: _isLoggingIn ? null : _handleLogin,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoggingIn
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(appConfig.translate('login')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminPanel(AppConfig appConfig, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Admin badge
          Center(
            child: Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user,
                    size: 40,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Welcome, $_adminUsername',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Admin Panel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Admin controls
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Controls',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: Text(appConfig.translate('download_toggle')),
                    subtitle: Text(appConfig.translate('download_toggle_desc')),
                    value: appConfig.downloadEnabled,
                    onChanged: (val) {
                      appConfig.setDownloadEnabled(val);
                    },
                    secondary: const Icon(Icons.download),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: Text(appConfig.translate('dark_mode')),
                    value: appConfig.isDarkMode,
                    onChanged: (val) {
                      appConfig.setThemeMode(
                          val ? ThemeMode.dark : ThemeMode.light);
                    },
                    secondary: Icon(
                      appConfig.isDarkMode
                          ? Icons.dark_mode
                          : Icons.light_mode,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Logout button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout),
              label: Text(appConfig.translate('logout')),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                foregroundColor: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterTab(AppConfig appConfig, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _registerFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            // Icon
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_add,
                  size: 40,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              appConfig.translate('register'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new account',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),

            // Username
            TextFormField(
              controller: _regUsernameController,
              decoration: InputDecoration(
                labelText: appConfig.translate('username'),
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter username';
                }
                if (val.trim().length < 3) {
                  return 'Username must be at least 3 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _regPasswordController,
              obscureText: _obscureRegPassword,
              decoration: InputDecoration(
                labelText: appConfig.translate('password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureRegPassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () {
                    setState(() => _obscureRegPassword = !_obscureRegPassword);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please enter password';
                }
                if (val.trim().length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Confirm Password
            TextFormField(
              controller: _regConfirmPasswordController,
              obscureText: _obscureRegConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureRegConfirmPassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () {
                    setState(() => _obscureRegConfirmPassword =
                        !_obscureRegConfirmPassword);
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Please confirm password';
                }
                if (val != _regPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),

            // Register button
            FilledButton(
              onPressed: _handleRegister,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(appConfig.translate('register')),
            ),
          ],
        ),
      ),
    );
  }
}
