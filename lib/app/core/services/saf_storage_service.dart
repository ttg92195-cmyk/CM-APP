import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for Android Storage Access Framework (SAF) folder picker.
/// Uses ACTION_OPEN_DOCUMENT_TREE to let users pick any folder for downloads,
/// and takes persistable URI permission so the app can read/write to that folder.
class SafStorageService {
  static const MethodChannel _channel = MethodChannel('com.cmmovies/saf_storage');
  static const String _safUriKey = 'saf_tree_uri';
  static const String _safPathKey = 'saf_tree_path';

  static SafStorageService? _instance;
  static SafStorageService get instance => _instance ??= SafStorageService._();

  SafStorageService._();

  String? _cachedTreeUri;
  String? _cachedTreePath;

  /// Get the stored SAF tree URI (content://...)
  Future<String?> getStoredTreeUri() async {
    if (_cachedTreeUri != null) return _cachedTreeUri;
    final prefs = await SharedPreferences.getInstance();
    _cachedTreeUri = prefs.getString(_safUriKey);
    return _cachedTreeUri;
  }

  /// Get the stored SAF tree path (human-readable file path)
  Future<String?> getStoredTreePath() async {
    if (_cachedTreePath != null) return _cachedTreePath;
    final prefs = await SharedPreferences.getInstance();
    _cachedTreePath = prefs.getString(_safPathKey);
    return _cachedTreePath;
  }

  /// Open the system folder picker (SAF - ACTION_OPEN_DOCUMENT_TREE)
  /// Returns the selected folder info, or null if user cancelled.
  Future<SafFolderResult?> openFolderPicker() async {
    if (!Platform.isAndroid) return null;

    try {
      final result = await _channel.invokeMethod<Map>('openFolderPicker');
      if (result == null) return null;

      final treeUri = result['treeUri'] as String? ?? '';
      final treePath = result['treePath'] as String? ?? '';

      if (treeUri.isEmpty) return null;

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_safUriKey, treeUri);
      await prefs.setString(_safPathKey, treePath);

      _cachedTreeUri = treeUri;
      _cachedTreePath = treePath;

      return SafFolderResult(
        treeUri: treeUri,
        treePath: treePath,
      );
    } on PlatformException catch (e) {
      debugPrint('SAF folder picker error: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      debugPrint('SAF folder picker error: $e');
      return null;
    }
  }

  /// Clear the stored SAF folder selection
  Future<void> clearStoredFolder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_safUriKey);
    await prefs.remove(_safPathKey);
    _cachedTreeUri = null;
    _cachedTreePath = null;
  }

  /// Check if a SAF folder has been selected
  Future<bool> hasStoredFolder() async {
    final uri = await getStoredTreeUri();
    return uri != null && uri.isNotEmpty;
  }

  /// Save a file to the SAF folder from a source file path
  /// This is used when we download to a temp location first, then copy to SAF folder
  Future<bool> saveFileToSafFolder({
    required String sourceFilePath,
    required String fileName,
  }) async {
    if (!Platform.isAndroid) return false;

    final treeUri = await getStoredTreeUri();
    if (treeUri == null || treeUri.isEmpty) return false;

    try {
      final result = await _channel.invokeMethod<bool>('saveFileToFolder', {
        'treeUri': treeUri,
        'sourceFilePath': sourceFilePath,
        'fileName': fileName,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SAF save file error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('SAF save file error: $e');
      return false;
    }
  }

  /// Check if a file exists in the SAF folder
  Future<bool> fileExistsInSafFolder(String fileName) async {
    if (!Platform.isAndroid) return false;

    final treeUri = await getStoredTreeUri();
    if (treeUri == null || treeUri.isEmpty) return false;

    try {
      final result = await _channel.invokeMethod<bool>('fileExistsInFolder', {
        'treeUri': treeUri,
        'fileName': fileName,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SAF file exists check error: ${e.code} - ${e.message}');
      return false;
    }
  }

  /// Open a file from the SAF folder using the system's default app.
  /// This finds the file in the SAF folder and opens it via ACTION_VIEW Intent.
  Future<bool> openFileFromSafFolder(String fileName) async {
    if (!Platform.isAndroid) return false;

    final treeUri = await getStoredTreeUri();
    if (treeUri == null || treeUri.isEmpty) return false;

    try {
      final result = await _channel.invokeMethod<bool>('openFileFromSaf', {
        'treeUri': treeUri,
        'fileName': fileName,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SAF open file error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('SAF open file error: $e');
      return false;
    }
  }

  /// Check if the SAF permission is still valid for the stored tree URI.
  /// Permissions can be revoked by the user or system.
  Future<bool> isSafPermissionValid() async {
    if (!Platform.isAndroid) return false;

    final treeUri = await getStoredTreeUri();
    if (treeUri == null || treeUri.isEmpty) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isSafPermissionValid', {
        'treeUri': treeUri,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('SAF permission check error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      debugPrint('SAF permission check error: $e');
      return false;
    }
  }
}

/// Result from SAF folder picker
class SafFolderResult {
  final String treeUri; // content://com.android.externalstorage.documents/tree/...
  final String treePath; // /storage/emulated/0/Download etc.

  SafFolderResult({
    required this.treeUri,
    required this.treePath,
  });
}
