import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig extends ChangeNotifier {
  static const String _themeKey = 'app_theme';
  static const String _langKey = 'app_language';

  ThemeMode _themeMode = ThemeMode.dark;
  String _languageCode = 'my';
  Map<String, String> _translations = {};

  ThemeMode get themeMode => _themeMode;
  String get languageCode => _languageCode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

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
    await _loadTranslations();
    notifyListeners();
  }

  Future<void> _loadTranslations() async {
    // Default translations embedded for offline support
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

  void toggleTheme() {
    setThemeMode(isDarkMode ? ThemeMode.light : ThemeMode.dark);
  }

  Map<String, String> _getDefaultTranslations(String code) {
    if (code == 'en') {
      return {
        'app_name': 'CM Movies',
        'home': 'Home',
        'movies': 'Movies',
        'search': 'Search',
        'bookmarks': 'Bookmarks',
        'settings': 'Settings',
        'trending_movies': 'Trending Movies',
        'trending_tv_shows': 'Trending TV Shows',
        'genre': 'Genre',
        'tag': 'Tag',
        'year': 'Year',
        'overview': 'Overview',
        'cast': 'Cast',
        'download': 'Download',
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
      };
    }
    return {
      'app_name': 'CM Movies',
      'home': 'ပင်မ',
      'movies': 'ရုပ်ရှင်များ',
      'search': 'ရှာဖွေရန်',
      'bookmarks': 'သိမ်းဆည်းမှု',
      'settings': 'ဆက်တင်',
      'trending_movies': 'လူကြိုက်များရုပ်ရှင်',
      'trending_tv_shows': 'လူကြိုက်များတီဗွီ',
      'genre': 'အမျိုးအစား',
      'tag': 'တက်ဂ်',
      'year': 'နှစ်',
      'overview': 'အကျဉ်းချုပ်',
      'cast': 'သရုပ်ဆောင်များ',
      'download': 'ဒေါင်းလုဒ်',
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
    };
  }
}
