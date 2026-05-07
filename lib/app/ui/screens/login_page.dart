import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/ui/screens/profile_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
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
  bool _isRegistering = false;

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
    await Future.delayed(const Duration(milliseconds: 500));

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    final success = await appConfig.loginUser(username, password);

    if (mounted) {
      setState(() => _isLoggingIn = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('login_success')),
            backgroundColor: Colors.green,
          ),
        );
        _usernameController.clear();
        _passwordController.clear();

        // Navigate to profile page
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('login_failed')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate()) return;

    setState(() => _isRegistering = true);
    await Future.delayed(const Duration(milliseconds: 500));

    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text.trim();
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    final success = await appConfig.registerUser(username, password);

    if (mounted) {
      setState(() => _isRegistering = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('register_success')),
            backgroundColor: Colors.green,
          ),
        );
        _regUsernameController.clear();
        _regPasswordController.clear();
        _regConfirmPasswordController.clear();

        // Auto login - navigate to profile
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('register_failed')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appConfig = Provider.of<AppConfig>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('login')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.login),
              text: appConfig.translate('login'),
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
          _buildLoginTab(appConfig, theme),
          _buildRegisterTab(appConfig, theme),
        ],
      ),
    );
  }

  Widget _buildLoginTab(AppConfig appConfig, ThemeData theme) {
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
                  color: const Color(0xFFE50914).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.login_rounded,
                  size: 40,
                  color: Color(0xFFE50914),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              appConfig.translate('login'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Login to your account',
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
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
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
                backgroundColor: const Color(0xFFE50914),
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

            const SizedBox(height: 16),

            // Switch to register
            TextButton(
              onPressed: () {
                _tabController.animateTo(1);
              },
              child: Text(appConfig.translate('dont_have_account')),
            ),
          ],
        ),
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
                  color: const Color(0xFFE50914).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_add,
                  size: 40,
                  color: Color(0xFFE50914),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              appConfig.translate('create_account'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new account to get started',
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
                labelText: appConfig.translate('confirm_password'),
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
              onPressed: _isRegistering ? null : _handleRegister,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE50914),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isRegistering
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(appConfig.translate('register')),
            ),

            const SizedBox(height: 16),

            // Switch to login
            TextButton(
              onPressed: () {
                _tabController.animateTo(0);
              },
              child: Text(appConfig.translate('already_have_account')),
            ),
          ],
        ),
      ),
    );
  }
}
