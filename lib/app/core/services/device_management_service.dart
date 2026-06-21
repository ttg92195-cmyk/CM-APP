import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a logged-in device
class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final DateTime loginTime;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.loginTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'loginTime': Timestamp.fromDate(loginTime),
    };
  }

  factory DeviceInfo.fromMap(Map<String, dynamic> map) {
    return DeviceInfo(
      deviceId: map['deviceId'] as String? ?? '',
      deviceName: map['deviceName'] as String? ?? 'Unknown Device',
      loginTime: map['loginTime'] is Timestamp
          ? (map['loginTime'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}

/// Device limit check result
class DeviceLimitResult {
  final bool allowed;
  final int maxDevices;
  final int currentDevices;
  final List<DeviceInfo> devices;
  final String? message;

  DeviceLimitResult({
    required this.allowed,
    required this.maxDevices,
    required this.currentDevices,
    required this.devices,
    this.message,
  });
}

/// Service for managing device logins and enforcing device limits
class DeviceManagementService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  /// SharedPreferences key under which we persist a fallback device ID for
  /// iOS devices whose `identifierForVendor` returns null. Without this,
  /// all such devices would share the literal string 'unknown_ios' and
  /// collapse into a single device-limit slot, bypassing the limit entirely.
  static const String _iosFallbackDeviceIdKey = 'ios_fallback_device_id';

  /// Generate a fresh fallback device ID (UUIDv4-like) when none is stored.
  /// We avoid adding a `uuid` package dep — this 32-hex-char format is
  /// sufficient for uniqueness on a single device.
  String _generateFallbackDeviceId() {
    final rng = Random();
    final hexChars = '0123456789abcdef';
    // 32 hex chars + 4 hyphens in UUID positions: 8-4-4-4-12
    final buf = StringBuffer();
    for (var i = 0; i < 32; i++) {
      // Variant: RFC 4122 (10xx) at position 12 (i==12 -> 0x8..0xb)
      // Version: 4 at position 16 (i==16 -> 0x4)
      if (i == 12) {
        buf.write(hexChars[(rng.nextInt(4)) + 8]); // 8..b
      } else if (i == 16) {
        buf.write('4');
      } else {
        buf.write(hexChars[rng.nextInt(16)]);
      }
      if (i == 7 || i == 11 || i == 15 || i == 19) buf.write('-');
    }
    return 'ios-${buf.toString()}';
  }

  /// Get the persisted iOS fallback device ID, generating + persisting a
  /// new one on first call. Used only when identifierForVendor is null.
  Future<String> _getIosFallbackDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_iosFallbackDeviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final fresh = _generateFallbackDeviceId();
      await prefs.setString(_iosFallbackDeviceIdKey, fresh);
      return fresh;
    } catch (e) {
      // If SharedPreferences fails, fall back to an in-memory random ID.
      // This is suboptimal (changes on every app start) but better than
      // sharing 'unknown_ios' across devices.
      debugPrint('_getIosFallbackDeviceId failed: $e — using ephemeral ID');
      return _generateFallbackDeviceId();
    }
  }

  /// Get unique device ID and name for the current device
  ///
  /// SECURITY FIX (H5): Previously this used `androidInfo.id` which is
  /// `android.os.Build.ID` — a firmware build identifier that is
  /// IDENTICAL across every device running the same firmware build.
  /// All Pixel 6s on the same Android 14 OTA shared the same device ID,
  /// collapsing into one device-limit slot and effectively bypassing
  /// the device-limit feature. Now we use `androidInfo.androidId` which
  /// is `Settings.Secure.ANDROID_ID` — a 64-bit hex string unique per
  /// device-user pair, stable across app reinstalls, changes only on
  /// factory reset.
  ///
  /// For iOS, `identifierForVendor` is the correct per-vendor ID but can
  /// return null on some devices/configs. When null, we generate a fresh
  /// UUID and persist it to SharedPreferences so subsequent calls return
  /// the same value. Previously the literal string 'unknown_ios' was used,
  /// causing all such devices to share one device-limit slot.
  Future<DeviceInfo> getCurrentDeviceInfo() async {
    String deviceId;
    String deviceName;

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      // Use Settings.Secure.ANDROID_ID instead of Build.ID. androidId is
      // a 64-bit hex string unique per device-user pair (changes only on
      // factory reset). Prefixed with 'android-' so it cannot collide
      // with iOS fallback IDs (which start with 'ios-').
      deviceId = 'android-${androidInfo.androidId}';
      deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
      // Capitalize first letter
      if (deviceName.isNotEmpty) {
        deviceName = deviceName[0].toUpperCase() + deviceName.substring(1);
      }
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      final ifv = iosInfo.identifierForVendor;
      if (ifv != null && ifv.isNotEmpty) {
        deviceId = 'ios-$ifv';
      } else {
        // identifierForVendor is null — generate + persist a stable fallback.
        deviceId = await _getIosFallbackDeviceId();
      }
      deviceName = iosInfo.utsname.machine;
    } else {
      // Unsupported platform — generate an ephemeral ID. Device limit will
      // effectively be bypassed on these platforms, but they're rare.
      deviceId = 'unknown-${_generateFallbackDeviceId()}';
      deviceName = 'Unknown Device';
    }

    return DeviceInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      loginTime: DateTime.now(),
    );
  }

  /// Check if a user can log in on the current device
  /// Returns DeviceLimitResult with allowed/denied status and device info
  /// Admin users always bypass device limit checks
  Future<DeviceLimitResult> checkDeviceLimit(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        return DeviceLimitResult(
          allowed: true,
          maxDevices: 2,
          currentDevices: 0,
          devices: [],
        );
      }

      final data = userDoc.data()!;
      final isAdmin = data['isAdmin'] == true;
      
      // Admin always bypasses device limit
      if (isAdmin) {
        return DeviceLimitResult(
          allowed: true,
          maxDevices: 999,
          currentDevices: 0,
          devices: [],
        );
      }
      
      final isVip = data['isVip'] == true;
      
      // Check VIP expiry — if expired, treat as non-VIP for device limit
      bool effectiveVip = isVip;
      if (isVip) {
        final vipExpiry = data['vipExpiry'] as String?;
        if (vipExpiry != null && vipExpiry.isNotEmpty) {
          final expiryDate = DateTime.tryParse(vipExpiry);
          if (expiryDate != null && expiryDate.isBefore(DateTime.now())) {
            effectiveVip = false;
          }
        }
      }
      
      final maxDevices = effectiveVip ? 4 : 2;
      final currentDevice = await getCurrentDeviceInfo();

      // Parse existing logged_in_devices
      final devicesList = (data['logged_in_devices'] as List?)
              ?.map((e) => DeviceInfo.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [];

      // Check if current device is already registered
      final isCurrentDeviceRegistered =
          devicesList.any((d) => d.deviceId == currentDevice.deviceId);

      if (isCurrentDeviceRegistered) {
        // Update login time for this device
        await _updateDeviceLoginTime(uid, currentDevice.deviceId);
        return DeviceLimitResult(
          allowed: true,
          maxDevices: maxDevices,
          currentDevices: devicesList.length,
          devices: devicesList,
        );
      }

      // Check if limit is reached
      if (devicesList.length >= maxDevices) {
        return DeviceLimitResult(
          allowed: false,
          maxDevices: maxDevices,
          currentDevices: devicesList.length,
          devices: devicesList,
          message: 'Device limit reached! You can have up to $maxDevices '
              '${isVip ? '(VIP)' : '(Free)'} devices connected. '
              'Please remove an old device first.',
        );
      }

      // Limit not reached, allow login
      return DeviceLimitResult(
        allowed: true,
        maxDevices: maxDevices,
        currentDevices: devicesList.length,
        devices: devicesList,
      );
    } catch (e) {
      debugPrint('checkDeviceLimit failed: $e');
      // On error, allow login (fail open)
      return DeviceLimitResult(
        allowed: true,
        maxDevices: 2,
        currentDevices: 0,
        devices: [],
        message: 'Could not verify device limit. Login allowed.',
      );
    }
  }

  /// Register current device on login
  Future<void> registerDevice(String uid) async {
    try {
      final currentDevice = await getCurrentDeviceInfo();
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final devicesList = List<Map<String, dynamic>>.from(
          (data['logged_in_devices'] as List?)
                  ?.map((e) => e as Map<String, dynamic>)
                  .toList() ??
              []);

      // Check if device already registered
      final existingIndex = devicesList
          .indexWhere((d) => d['deviceId'] == currentDevice.deviceId);

      if (existingIndex >= 0) {
        // Update login time
        devicesList[existingIndex] = currentDevice.toMap();
      } else {
        // Add new device
        devicesList.add(currentDevice.toMap());
      }

      await _firestore.collection('users').doc(uid).update({
        'logged_in_devices': devicesList,
      });
    } catch (e) {
      debugPrint('registerDevice failed: $e');
    }
  }

  /// Remove a device from the user's logged_in_devices
  Future<bool> removeDevice(String uid, String deviceId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return false;

      final data = userDoc.data()!;
      final devicesList = List<Map<String, dynamic>>.from(
          (data['logged_in_devices'] as List?)
                  ?.map((e) => e as Map<String, dynamic>)
                  .toList() ??
              []);

      devicesList.removeWhere((d) => d['deviceId'] == deviceId);

      await _firestore.collection('users').doc(uid).update({
        'logged_in_devices': devicesList,
      });

      return true;
    } catch (e) {
      debugPrint('removeDevice failed: $e');
      return false;
    }
  }

  /// Get all logged-in devices for a user
  Future<List<DeviceInfo>> getDevices(String uid) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return [];

      final data = userDoc.data()!;
      return (data['logged_in_devices'] as List?)
              ?.map((e) => DeviceInfo.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [];
    } catch (e) {
      debugPrint('getDevices failed: $e');
      return [];
    }
  }

  /// Update login time for an existing device
  Future<void> _updateDeviceLoginTime(String uid, String deviceId) async {
    try {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return;

      final data = userDoc.data()!;
      final devicesList = List<Map<String, dynamic>>.from(
          (data['logged_in_devices'] as List?)
                  ?.map((e) => e as Map<String, dynamic>)
                  .toList() ??
              []);

      final index = devicesList.indexWhere((d) => d['deviceId'] == deviceId);
      if (index >= 0) {
        devicesList[index]['loginTime'] = Timestamp.now();
        await _firestore.collection('users').doc(uid).update({
          'logged_in_devices': devicesList,
        });
      }
    } catch (e) {
      debugPrint('_updateDeviceLoginTime failed: $e');
    }
  }

}
