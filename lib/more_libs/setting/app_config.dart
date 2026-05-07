import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _langKey = 'app_language';
  static const String _downloadEnabledKey = 'download_enabled';
  static const String _adminLoggedInKey = 'admin_logged_in';
  static const String _registeredUsersKey = 'registered_users';
  static const String _currentUserKey = 'current_user';

  ThemeMode _themeMode = ThemeMode.dark;
  String _languageCode = 'my';
  Map<String, String> _translations = {};
  bool _downloadEnabled = true;
  bool _adminLoggedIn = false;
  List<Map<String, String>> _registeredUsers = [];
  Map<String, dynamic>? _currentUser; // {username, isAdmin, loginDate, registrationDate}

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool get downloadEnabled => _downloadEnabled;
  bool get adminLoggedIn => _adminLoggedIn;
  List<Map<String, String>> get registeredUsers => _registeredUsers;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  String? get currentUsername => _currentUser?['username'] as String?;
  bool get isCurrentUserAdmin => _currentUser?['isAdmin'] == true;

  String translate(String key) {
    return _translations[key] ?? key;
  }

  AppConfig() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? ThemeMode.dark.index;
    _themeMode = ThemeMode.values[themeIndex];
    _languageCode = prefs.getString(_langKey) ?? 'my';
    _downloadEnabled = prefs.getBool(_downloadEnabledKey) ?? true;
    _adminLoggedIn = prefs.getBool(_adminLoggedInKey) ?? false;

    // Load registered users
    final usersJson = prefs.getString(_registeredUsersKey);
    if (usersJson != null) {
      try {
        final decoded = json.decode(usersJson) as List;
        _registeredUsers = decoded.map((u) => Map<String, String>.from(u as Map)).toList();
      } catch (_) {
        _registeredUsers = [];
      }
    }

    // Load current user
    final currentUserJson = prefs.getString(_currentUserKey);
    if (currentUserJson != null) {
      try {
        _currentUser = json.decode(currentUserJson) as Map<String, dynamic>;
      } catch (_) {
        _currentUser = null;
      }
    }

    await _loadTranslations();
    notifyListeners();
  }

  Future<void> _loadTranslations() async {
    _translations = _getDefaultTranslations(_languageCode);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
    await _loadTranslations();
    notifyListeners();
  }

  Future<void> setDownloadEnabled(bool enabled) async {
    _downloadEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_downloadEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> setAdminLoggedIn(bool loggedIn) async {
    _adminLoggedIn = loggedIn;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adminLoggedInKey, loggedIn);
    if (loggedIn) {
      _currentUser = {
        'username': 'Chitminzaw',
        'isAdmin': true,
        'loginDate': DateTime.now().toIso8601String(),
        'registrationDate': 'Admin',
      };
      await prefs.setString(_currentUserKey, json.encode(_currentUser));
    } else {
      _currentUser = null;
      await prefs.remove(_currentUserKey);
    }
    notifyListeners();
  }

  // Register a new user
  Future<bool> registerUser(String username, String password) async {
    // Check if username already exists
    final exists = _registeredUsers.any((u) => u['username']?.toLowerCase() == username.toLowerCase());
    if (exists) return false;

    final now = DateTime.now();
    final regDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    _registeredUsers.add({
      'username': username,
      'password': password,
      'registrationDate': regDate,
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registeredUsersKey, json.encode(_registeredUsers));

    // Auto login after registration
    _currentUser = {
      'username': username,
      'isAdmin': false,
      'loginDate': now.toIso8601String(),
      'registrationDate': regDate,
    };
    await prefs.setString(_currentUserKey, json.encode(_currentUser));

    notifyListeners();
    return true;
  }

  // Login user (regular or admin)
  Future<bool> loginUser(String username, String password) async {
    // Check admin credentials
    if (username == 'Chitminzaw' && password == 'Chitmin7') {
      _adminLoggedIn = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_adminLoggedInKey, true);
      _currentUser = {
        'username': 'Chitminzaw',
        'isAdmin': true,
        'loginDate': DateTime.now().toIso8601String(),
        'registrationDate': 'Admin',
      };
      await prefs.setString(_currentUserKey, json.encode(_currentUser));
      notifyListeners();
      return true;
    }

    // Check registered users
    final match = _registeredUsers.where(
      (u) => u['username'] == username && u['password'] == password,
    ).toList();

    if (match.isEmpty) return false;

    _currentUser = {
      'username': match.first['username'],
      'isAdmin': false,
      'loginDate': DateTime.now().toIso8601String(),
      'registrationDate': match.first['registrationDate'] ?? '',
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, json.encode(_currentUser));
    notifyListeners();
    return true;
  }

  // Logout
  Future<void> logoutUser() async {
    _adminLoggedIn = false;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adminLoggedInKey, false);
    await prefs.remove(_currentUserKey);
    notifyListeners();
  }

  // Change password
  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (_currentUser == null) return false;

    final username = _currentUser!['username'] as String;
    final isAdmin = _currentUser!['isAdmin'] as bool;

    if (isAdmin) {
      // Admin password change
      if (oldPassword != 'Chitmin7') return false;
      return true; // Admin password is hardcoded, can't really change
    }

    // Regular user password change
    final userIndex = _registeredUsers.indexWhere(
      (u) => u['username'] == username && u['password'] == oldPassword,
    );
    if (userIndex == -1) return false;

    _registeredUsers[userIndex]['password'] = newPassword;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registeredUsersKey, json.encode(_registeredUsers));
    notifyListeners();
    return true;
  }

  void toggleTheme() {
    setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  Map<String, String> _getDefaultTranslations(String code) {
    if (code == 'en') {
      return {
        'app_name': 'CM Movies',
        'home': 'Home',
        'movies': 'Movies',
        'series': 'Series',
        'search': 'Search',
        'bookmarks': 'Bookmarks',
        'settings': 'Settings',
        'trending_movies': 'Trending Movies',
        'trending_tv_shows': 'Trending TV Shows',
        'genre': 'Genre',
        'genres': 'Genres',
        'tag': 'Tag',
        'tags': 'Tags',
        'collections': 'Collections',
        'year': 'Year',
        'overview': 'Overview',
        'cast': 'Cast',
        'download': 'Download',
        'downloads': 'Downloads',
        'director': 'Director',
        'rating': 'Rating',
        'resolution': 'Resolution',
        'quality': 'Quality',
        'server': 'Server',
        'size': 'Size',
        'search_hint': 'Search movies...',
        'no_results': 'No results found',
        'loading': 'Loading...',
        'error_occurred': 'An error occurred',
        'retry': 'Retry',
        'bookmark_added': 'Added to bookmarks',
        'bookmark_removed': 'Removed from bookmarks',
        'no_bookmarks': 'No bookmarks yet',
        'add_to_bookmark': 'Add to Bookmark',
        'remove_from_bookmark': 'Remove from Bookmark',
        'language': 'Language',
        'theme': 'Theme',
        'dark_mode': 'Dark Mode',
        'light_mode': 'Light Mode',
        'recently_viewed': 'Recently Viewed',
        'all': 'All',
        'movies_count': 'Movies Count',
        'filter_by_genre': 'Filter by Genre',
        'filter_by_tag': 'Filter by Tag',
        'filter_by_year': 'Filter by Year',
        'view_detail': 'View Detail',
        'more': 'More',
        'categories': 'Categories',
        'adult_content': 'Adult Content',
        'clear_history': 'Clear History',
        'no_history': 'No viewing history',
        'about_app': 'About App',
        'version': 'Version',
        'register': 'Register',
        'admin_login': 'Admin Login',
        'username': 'Username',
        'password': 'Password',
        'login': 'Login',
        'logout': 'Logout',
        'login_success': 'Login successful',
        'login_failed': 'Invalid username or password',
        'register_success': 'Registration successful',
        'register_failed': 'Username already exists',
        'privacy_policy': 'Privacy and Policy',
        'about_cm_movies': 'About CM Movies',
        'download_toggle': 'Show Download Links',
        'download_toggle_desc': 'Enable to show download links in movie details',
        'download_disabled_msg': 'Download links are currently disabled. Go to Download settings to enable them.',
        'no_downloads': 'No downloads available',
        'genres_tags_collections': 'Genres/Tags/Collections',
        'profile': 'Profile',
        'account_information': 'Account Information',
        'account_name': 'Account Name',
        'account_active': 'Account Active',
        'change_password': 'Change Password',
        'old_password': 'Old Password',
        'new_password': 'New Password',
        'confirm_new_password': 'Confirm New Password',
        'password_changed': 'Password changed successfully',
        'password_change_failed': 'Old password is incorrect',
        'k_drama': 'K Drama',
        'trending': 'Trending',
        '4k_movies': '4K Movies',
        '4k_series': '4K Series',
        'animation': 'Animation',
        'anime': 'Anime',
        'bollywood': 'Bollywood',
        'donghua': 'Donghua',
        'c_drama': 'C Drama',
        'total_posts': 'Total',
        'back': 'Back',
        'confirm_password': 'Confirm Password',
        'create_account': 'Create Account',
        'already_have_account': 'Already have an account?',
        'dont_have_account': "Don't have an account?",
        'privacy_policy_text': 'Privacy Policy\n\nCM Movies is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and safeguard your information when you use our application.\n\nInformation We Collect:\n- Usage data and preferences\n- Bookmark and history data (stored locally)\n- App settings and configuration\n\nHow We Use Your Information:\n- To provide and improve our services\n- To personalize your experience\n- To maintain your bookmarks and viewing history\n\nData Storage:\nAll your personal data including bookmarks, viewing history, and settings are stored locally on your device. We do not transmit your personal data to external servers.\n\nThird-Party Services:\nOur app may use third-party services that have their own privacy policies. We encourage you to review their privacy policies.\n\nContact Us:\nIf you have any questions about this Privacy Policy, please contact us through the app settings.\n\nLast updated: 2026',
        'about_cm_movies_text': 'CM Movies\n\nYour ultimate movie and series companion app. Browse, search, and discover movies and TV series from around the world.\n\nFeatures:\n- Browse trending movies and TV shows\n- Search by title, genre, or tag\n- Bookmark your favorites\n- Download management\n- Multi-language support (Myanmar & English)\n- Dark & Light theme\n\nVersion 1.0.0\nDeveloped with love for movie enthusiasts.',
      };
    }
    return {
      'app_name': 'CM Movies',
      'home': 'ပင်မ',
      'movies': 'ရုပ်ရှင်များ',
      'series': 'ဇာတ်လမ်းတွဲများ',
      'search': 'ရှာဖွေရန်',
      'bookmarks': 'သိမ်းဆည်းမှု',
      'settings': 'ဆက်တင်',
      'trending_movies': 'လူကြိုက်များရုပ်ရှင်',
      'trending_tv_shows': 'လူကြိုက်များတီဗွီ',
      'genre': 'အမျိုးအစား',
      'genres': 'အမျိုးအစားများ',
      'tag': 'တက်ဂ်',
      'tags': 'တက်ဂ်များ',
      'collections': 'စုစည်းမှုများ',
      'year': 'နှစ်',
      'overview': 'အကျဉ်းချုပ်',
      'cast': 'သရုပ်ဆောင်များ',
      'download': 'ဒေါင်းလုဒ်',
      'downloads': 'ဒေါင်းလုဒ်များ',
      'director': 'ဒါရိုက်တာ',
      'rating': 'ရမတ်',
      'resolution': 'ရီဇော်လူရှင်',
      'quality': 'အရည်အသွေး',
      'server': 'ဆာဗာ',
      'size': 'အရွယ်အစား',
      'search_hint': 'ရုပ်ရှင်အမည် ရှာဖွေရန်...',
      'no_results': 'ရလဒ်မတွေ့ပါ',
      'loading': 'ခဏစောင့်ပါ...',
      'error_occurred': 'အမှားတစ်ခုဖြစ်ပွားခဲ့ပါသည်',
      'retry': 'ထပ်စမ်းကြည့်ပါ',
      'bookmark_added': 'သိမ်းဆည်းပြီးပါပြီ',
      'bookmark_removed': 'သိမ်းဆည်းမှုမှ ဖယ်ရှားပြီးပါပြီ',
      'no_bookmarks': 'သိမ်းဆည်းထားသော ရုပ်ရှင်မရှိပါ',
      'add_to_bookmark': 'သိမ်းဆည်းရန်',
      'remove_from_bookmark': 'သိမ်းဆည်းမှုမှ ဖယ်ရှားရန်',
      'language': 'ဘာသာစကား',
      'theme': 'အပြင်အဆင်',
      'dark_mode': 'အမှောင်မုဒ်',
      'light_mode': 'အလင်းမုဒ်',
      'recently_viewed': 'မကြာသေးမီက ကြည့်ရှုခဲ့သည်',
      'all': 'အားလုံး',
      'movies_count': 'ရုပ်ရှင်အရေအတွက်',
      'filter_by_genre': 'အမျိုးအစားအလိုက် စစ်ထုတ်ရန်',
      'filter_by_tag': 'တက်ဂ်အလိုက် စစ်ထုတ်ရန်',
      'filter_by_year': 'နှစ်အလိုက် စစ်ထုတ်ရန်',
      'view_detail': 'အသေးစိတ်ကြည့်ရန်',
      'more': 'ပိုမို',
      'categories': 'အမျိုးအစားများ',
      'adult_content': 'လူကြီးများအတွက်',
      'clear_history': 'မှတ်တမ်းရှင်းလင်းရန်',
      'no_history': 'ကြည့်ရှုမှုမှတ်တမ်း မရှိပါ',
      'about_app': 'အက်ပ်အကြောင်း',
      'version': 'ဗားရှင်း',
      'register': 'မှတ်ပုံတင်ရန်',
      'admin_login': 'အက်ဒမင့် ဝင်ရောက်ရန်',
      'username': 'အသုံးပြုသူအမည်',
      'password': 'စကားဝှက်',
      'login': 'ဝင်ရောက်ရန်',
      'logout': 'ထွက်ရန်',
      'login_success': 'ဝင်ရောက်ပြီးပါပြီ',
      'login_failed': 'အသုံးပြုသူအမည် သို့မဟုတ် စကားဝှက် မှားယွင်းနေပါသည်',
      'register_success': 'မှတ်ပုံတင်ပြီးပါပြီ',
      'register_failed': 'အသုံးပြုသူအမည် ရှိပီးသားဖြစ်ပါသည်',
      'privacy_policy': 'Privacy and Policy',
      'about_cm_movies': 'CM Movies အကြောင်း',
      'download_toggle': 'Download Link များ ပြသရန်',
      'download_toggle_desc': 'Movie အသေးစိတ်တွင် Download Link များ ပြသလိုပါက ဖွင့်ပါ',
      'download_disabled_msg': 'Download Link များကို လက်ရှိ ပိတ်ထားပါသည်။ Download Settings တွင် ဖွင့်ပါ။',
      'no_downloads': 'ဒေါင်းလုဒ် မရှိပါ',
      'genres_tags_collections': 'အမျိုးအစား/တက်ဂ်/စုစည်းမှု',
      'profile': 'ကိုယ်ရေးအချက်အလက်',
      'account_information': 'အကောင့် အချက်အလက်',
      'account_name': 'အသုံးပြုသူ အမည်',
      'account_active': 'အကောင့် စတင်ရက်',
      'change_password': 'စကားဝှက် ပြောင်းရန်',
      'old_password': 'ယခင် စကားဝှက်',
      'new_password': 'စကားဝှက်အသစ်',
      'confirm_new_password': 'စကားဝှက်အသစ် အတည်ပြုရန်',
      'password_changed': 'စကားဝှက် ပြောင်းလဲပြီးပါပြီ',
      'password_change_failed': 'ယခင် စကားဝှက် မှားယွင်းနေပါသည်',
      'k_drama': 'K Drama',
      'trending': 'လူကြိုက်များ',
      '4k_movies': '4K ရုပ်ရှင်များ',
      '4k_series': '4K ဇာတ်လမ်းတွဲများ',
      'animation': 'Animation',
      'anime': 'Anime',
      'bollywood': 'Bollywood',
      'donghua': 'Donghua',
      'c_drama': 'C Drama',
      'total_posts': 'စုစုပေါင်း',
      'back': 'နောက်သို့',
      'confirm_password': 'စကားဝှက် အတည်ပြုရန်',
      'create_account': 'အကောင့်သစ် ဖွင့်ရန်',
      'already_have_account': 'အကောင့်ရှိပီးသားလား?',
      'dont_have_account': 'အကောင့်မရှိသေးဘူးလား?',
      'privacy_policy_text': 'ကိုယ်ရေးအချက်အလက် မူဝါဒ\n\nCM Movies သည် သင့်ကိုယ်ရေးအချက်အလက်များကို ကာကွယ်ရန် ကတိကဝတ် ပြုထားပါသည်။ ဤ ကိုယ်ရေးအချက်အလက် မူဝါဒသည် သင် App ကို အသုံးပြုသောအခါ သင့်အချက်အလက်များကို မည်သို့ စုဆောင်း၊ အသုံးပြု၊ ကာကွယ်သည်ကို ရှင်းပြပါသည်။\n\nစုဆောင်းသော အချက်အလက်များ:\n- အသုံးပြုမှုဒေတာနှင့် ကိုယ်ကြိုက်ဆန္ဒများ\n- သိမ်းဆည်းမှုနှင့် ကြည့်ရှုမှတ်တမ်းဒေတာ (ဒေသန္တရသိုလ်တွင် သိမ်းဆည်း)\n- App ဆက်တင်နှင့် ပြင်ဆင်မှုများ\n\nအချက်အလက် အသုံးပြုပုံ:\n- ဝန်ဆောင်မှုများ ပေးရန်နှင့် တိုးတက်စေရန်\n- သင့်အတွေ့အကြုံကို ပိုမိုကောင်းမွန်စေရန်\n- သိမ်းဆည်းမှုနှင့် ကြည့်ရှုမှတ်တမ်းကို ထိန်းသိမ်းရန်\n\nဒေတာ သိမ်းဆည်းမှု:\nသင့်ကိုယ်ရေးအချက်အလက်အားလုံးကို သင့်စက်ပေါ်တွင်သာ ဒေသန္တရအားဖြင့် သိမ်းဆည်းထားပါသည်။ ကျွန်တော်တို့သည် သင့်ကိုယ်ရေးအချက်အလက်ကို ပြင်ပဆာဗာများသို့ မထုတ်ပိုးပါ။\n\nနောက်ဆုံး အသစ်ပြင်ဆင်ချက်: ၂၀၂၆',
      'about_cm_movies_text': 'CM Movies\n\nရုပ်ရှင်နှင့် ဇာတ်လမ်းတွဲများ ကြည့်ရှုရန် အကောင်းဆုံး App ဖြစ်ပါသည်။ ကမ္ဘာအနှံ့ရုပ်ရှင်နှင့် TV ဇာတ်လမ်းတွဲများကို ရှာဖွေ၊ ကြည့်ရှုနိုင်ပါသည်။\n\nအသွင်အပြင်များ:\n- လူကြိုက်များရုပ်ရှင်နှင့် TV ရှိုးများ ကြည့်ရှုရန်\n- ခေါင်းစဉ်၊ အမျိုးအစား၊ တက်ဂ်အလိုက် ရှာဖွေရန်\n- နှစ်သက်ရာများ သိမ်းဆည်းရန်\n- Download စီမံခန့်ခွဲရန်\n- ဘာသာစကား ၂ မျိုး ပံ့ပိုးမှု (မြန်မာ & English)\n- အမှောင်နှင့် အလင်း Theme\n\nဗားရှင်း 1.0.0\nရုပ်ရှင်ချစ်သူများအတွက် ချစ်ခြင်းမေတ္တာဖြင့် ဖန်တီးထားပါသည်။',
    };
  }
}
