import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/bookmark_service.dart';

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
  String? _loginError;
  String? _registerError;

  // L2: Login rate limiting
  static const int _maxLoginAttempts = 5;
  static const Duration _lockoutDuration = Duration(seconds: 30);
  int _failedLoginAttempts = 0;
  DateTime? _lockoutUntil;

  bool get _isLockedOut {
    if (_lockoutUntil == null) return false;
    if (DateTime.now().isAfter(_lockoutUntil!)) {
      _lockoutUntil = null;
      _failedLoginAttempts = 0;
      return false;
    }
    return true;
  }

  Duration get _remainingLockout {
    if (_lockoutUntil == null) return Duration.zero;
    return _lockoutUntil!.difference(DateTime.now());
  }

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
    // L2: Check rate limit before attempting login
    if (_isLockedOut) {
      final remaining = _remainingLockout.inSeconds;
      final appConfig = Provider.of<AppConfig>(context, listen: false);
      setState(() {
        _loginError = appConfig
            .translate('too_many_attempts')
            .replaceAll('{seconds}', remaining.toString());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appConfig
                .translate('too_many_attempts_short')
                .replaceAll('{seconds}', remaining.toString()),
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_loginFormKey.currentState!.validate()) return;

    setState(() {
      _isLoggingIn = true;
      _loginError = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    final success = await appConfig.loginUser(username, password);

    if (mounted) {
      setState(() => _isLoggingIn = false);
      if (success) {
        // L2: Reset failed attempts on successful login
        _failedLoginAttempts = 0;
        _lockoutUntil = null;

        // Merge local bookmarks to cloud after login
        final bookmarkService = BookmarkService();
        await bookmarkService.mergeLocalBookmarksToCloud();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.translate('login_success')),
            backgroundColor: Colors.green,
          ),
        );
        _usernameController.clear();
        _passwordController.clear();

        // Auth state change in AppConfig will automatically navigate to HomePage
        // No manual navigation needed — CMMoviesApp watches isLoggedIn
      } else {
        // L2: Increment failed login attempts
        _failedLoginAttempts++;
        if (_failedLoginAttempts >= _maxLoginAttempts) {
          _lockoutUntil = DateTime.now().add(_lockoutDuration);
          setState(() {
            _loginError = appConfig
                .translate('too_many_attempts')
                .replaceAll('{seconds}', _lockoutDuration.inSeconds.toString());
          });
        } else {
          setState(() {
            _loginError = appConfig.translate('login_failed');
          });
        }
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

    setState(() {
      _isRegistering = true;
      _registerError = null;
    });

    final username = _regUsernameController.text.trim();
    final password = _regPasswordController.text.trim();
    final appConfig = Provider.of<AppConfig>(context, listen: false);

    try {
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

          // Auth state change in AppConfig will automatically navigate to HomePage
          // No manual navigation needed — CMMoviesApp watches isLoggedIn
        } else {
          setState(() {
            _registerError = appConfig.translate('register_failed');
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appConfig.translate('register_failed')),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isRegistering = false;
          _registerError = appConfig.getAuthErrorMessage(e.code);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appConfig.getAuthErrorMessage(e.code)),
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
    final isDark = theme.brightness == Brightness.dark;

    // Input decoration style for both light and dark modes
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE50914), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(appConfig.translate('login_and_register')),
        actions: [
          // Language toggle
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ActionChip(
              avatar: Icon(
                Icons.translate,
                size: 18,
                color: appConfig.languageCode == 'en'
                    ? const Color(0xFFE50914)
                    : theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              label: Text(
                appConfig.languageCode == 'en' ? 'MY' : 'EN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: appConfig.languageCode == 'en'
                      ? const Color(0xFFE50914)
                      : theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
              onPressed: () {
                appConfig.setLanguage(appConfig.languageCode == 'en' ? 'my' : 'en');
              },
            ),
          ),
          // Theme toggle on login page
          IconButton(
            icon: Icon(
              appConfig.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            tooltip: appConfig.isDarkMode ? 'Light Mode' : 'Dark Mode',
            onPressed: () {
              appConfig.toggleTheme();
            },
          ),
        ],
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
              appConfig.translate('sign_in'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appConfig.translate('login_subtitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),

            // Error message
            if (_loginError != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loginError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Username field
            TextFormField(
              controller: _usernameController,
              decoration: inputDecoration.copyWith(
                labelText: appConfig.translate('username'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return appConfig.translate('enter_username');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password field
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: inputDecoration.copyWith(
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
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return appConfig.translate('enter_password');
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
                  : Text(appConfig.translate('sign_in')),
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
              appConfig.translate('sign_up'),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appConfig.translate('register_subtitle'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 32),

            // Error message
            if (_registerError != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _registerError!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Username
            TextFormField(
              controller: _regUsernameController,
              decoration: inputDecoration.copyWith(
                labelText: appConfig.translate('username'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return appConfig.translate('enter_username');
                }
                if (val.trim().length < 3) {
                  return appConfig.translate('username_min_length');
                }
                // Check for invalid characters that would break email format
                if (val.contains('@') || val.contains(' ')) {
                  return appConfig.translate('username_invalid_chars');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Password
            TextFormField(
              controller: _regPasswordController,
              obscureText: _obscureRegPassword,
              decoration: inputDecoration.copyWith(
                labelText: appConfig.translate('password'),
                prefixIcon: const Icon(Icons.lock_outline),
                hintText: appConfig.translate('password_hint'),
                suffixIcon: IconButton(
                  icon: Icon(_obscureRegPassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () {
                    setState(() => _obscureRegPassword = !_obscureRegPassword);
                  },
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return appConfig.translate('enter_password');
                }
                if (val.trim().length < 8) {
                  return appConfig.translate('password_min_length');
                }
                if (!RegExp(r'[A-Z]').hasMatch(val)) {
                  return appConfig.translate('password_uppercase');
                }
                if (!RegExp(r'[a-z]').hasMatch(val)) {
                  return appConfig.translate('password_lowercase');
                }
                if (!RegExp(r'[0-9]').hasMatch(val)) {
                  return appConfig.translate('password_number');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Confirm Password
            TextFormField(
              controller: _regConfirmPasswordController,
              obscureText: _obscureRegConfirmPassword,
              decoration: inputDecoration.copyWith(
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
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return appConfig.translate('confirm_password_empty');
                }
                if (val != _regPasswordController.text) {
                  return appConfig.translate('passwords_no_match');
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
                  : Text(appConfig.translate('sign_up')),
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
