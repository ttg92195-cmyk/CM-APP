import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// MethodChannel used to fetch Settings.Secure.ANDROID_ID from the
  /// Android native side. device_info_plus 10.x removed direct access
  /// to ANDROID_ID for privacy reasons, so we fetch it via a custom
  /// MethodChannel registered in MainActivity.kt.
  static const MethodChannel _androidIdChannel =
      MethodChannel('cm_movies/android_id');

  /// SharedPreferences key under which we persist a fallback device ID for
  /// iOS devices whose `identifierForVendor` returns null. Without this,
  /// all such devices would share the literal string 'unknown_ios' and
  /// collapse into a single device-limit slot, bypassing the limit entirely.
  static const String _iosFallbackDeviceIdKey = 'ios_fallback_device_id';

  /// SharedPreferences key for Android fallback UUID, used when the
  /// MethodChannel call to fetch ANDROID_ID fails or returns empty.
  static const String _androidFallbackDeviceIdKey =
      'android_fallback_device_id';

  /// Generate a fresh fallback device ID (UUIDv4-like) when none is stored.
  /// We avoid adding a `uuid` package dep — this 32-hex-char format is
  /// sufficient for uniqueness on a single device. The [prefix] is
  /// 'ios-' or 'android-' so we can distinguish platform origin in logs
  /// and prevent cross-platform ID collisions.
  String _generateFallbackDeviceId({required String prefix}) {
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
    return '$prefix${buf.toString()}';
  }

  /// Get the persisted iOS fallback device ID, generating + persisting a
  /// new one on first call. Used only when identifierForVendor is null.
  Future<String> _getIosFallbackDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_iosFallbackDeviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final fresh = _generateFallbackDeviceId(prefix: 'ios-');
      await prefs.setString(_iosFallbackDeviceIdKey, fresh);
      return fresh;
    } catch (e) {
      // If SharedPreferences fails, fall back to an in-memory random ID.
      // This is suboptimal (changes on every app start) but better than
      // sharing 'unknown_ios' across devices.
      debugPrint('_getIosFallbackDeviceId failed: $e — using ephemeral ID');
      return _generateFallbackDeviceId(prefix: 'ios-');
    }
  }

  /// Get the persisted Android fallback device ID (UUID), generating +
  /// persisting a new one on first call. Used when the MethodChannel
  /// call to fetch ANDROID_ID fails or returns empty.
  Future<String> _getAndroidFallbackDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_androidFallbackDeviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final fresh = _generateFallbackDeviceId(prefix: 'android-');
      await prefs.setString(_androidFallbackDeviceIdKey, fresh);
      return fresh;
    } catch (e) {
      debugPrint(
          '_getAndroidFallbackDeviceId failed: $e — using ephemeral ID');
      return _generateFallbackDeviceId(prefix: 'android-');
    }
  }

  /// Fetch Settings.Secure.ANDROID_ID via a custom MethodChannel.
  ///
  /// ANDROID_ID is a 64-bit hex string (16 chars) unique per device-user
  /// pair. It is stable across app reinstalls and only changes on factory
  /// reset. On Android 8.0+ it is also scoped per signing key, so apps
  /// signed with different keys see different ANDROID_ID values for the
  /// same device-user pair — preventing cross-app tracking.
  ///
  /// Returns null if the call fails, the channel is unregistered, or the
  /// returned value is empty. Caller is expected to fall back to a
  /// persisted UUID in that case.
  Future<String?> _fetchAndroidIdViaChannel() async {
    try {
      final result = await _androidIdChannel.invokeMethod<String>('getAndroidId');
      if (result == null || result.isEmpty) return null;
      return result;
    } on PlatformException catch (e) {
      debugPrint('_fetchAndroidIdViaChannel PlatformException: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException catch (e) {
      // Channel not registered — likely running on non-Android or
      // MainActivity.kt hasn't been updated yet. Fall back gracefully.
      debugPrint('_fetchAndroidIdViaChannel MissingPluginException: $e');
      return null;
    } catch (e) {
      debugPrint('_fetchAndroidIdViaChannel failed: $e');
      return null;
    }
  }

  /// Get unique device ID and name for the current device
  ///
  /// SECURITY FIX (H5): Previously this used `androidInfo.id` which is
  /// `android.os.Build.ID` — a firmware build identifier that is
  /// IDENTICAL across every device running the same firmware build.
  /// All Pixel 6s on the same Android 14 OTA shared the same device ID,
  /// collapsing into one device-limit slot and effectively bypassing
  /// the device-limit feature.
  ///
  /// Now we fetch `Settings.Secure.ANDROID_ID` directly via a custom
  /// MethodChannel ('cm_movies/android_id') registered in MainActivity.kt.
  /// device_info_plus 10.x removed direct access to ANDROID_ID for
  /// privacy reasons, so a custom channel is the cleanest way to get
  /// the real per-device ID.
  ///
  /// If the MethodChannel call fails (e.g. native side not updated,
  /// running on non-Android, or platform error), we generate + persist
  /// a UUID to SharedPreferences as a fallback. This is still better
  /// than Build.ID because it's at least unique per app install on
  /// identical-firmware devices.
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
      deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
      // Capitalize first letter
      if (deviceName.isNotEmpty) {
        deviceName = deviceName[0].toUpperCase() + deviceName.substring(1);
      }

      // Try fetching ANDROID_ID via the custom MethodChannel first.
      final androidId = await _fetchAndroidIdViaChannel();
      if (androidId != null && androidId.isNotEmpty) {
        // Real per-device ID. Prefixed with 'android-' so it cannot
        // collide with iOS fallback IDs (which start with 'ios-').
        deviceId = 'android-$androidId';
      } else {
        // MethodChannel unavailable or returned empty — fall back to a
        // persisted UUID. This still uniquely identifies the device
        // (per app install) and is far better than Build.ID.
        deviceId = await _getAndroidFallbackDeviceId();
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
      deviceId = _generateFallbackDeviceId(prefix: 'unknown-');
      deviceName = 'Unknown Device';
    }

    return DeviceInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      loginTime: DateTime.now(),
    );
  }

  /// Compute the per-user max device count from Firestore user data.
  ///
  /// - Admin users get 999 (effectively unlimited).
  /// - VIP users get 4, but only if VIP has not expired.
  /// - Non-VIP (or expired VIP) users get 2.
  ///
  /// Extracted as a helper so both registerDevice and (future) admin
  /// tooling can share the same logic without drift.
  int _computeMaxDevicesFromData(Map<String, dynamic> data) {
    if (data['isAdmin'] == true) return 999;

    final isVip = data['isVip'] == true;
    if (!isVip) return 2;

    final vipExpiry = data['vipExpiry'] as String?;
    if (vipExpiry == null || vipExpiry.isEmpty) return 4;

    final expiryDate = DateTime.tryParse(vipExpiry);
    if (expiryDate == null || expiryDate.isBefore(DateTime.now())) {
      return 2; // VIP expired — treat as Free
    }
    return 4;
  }

  /// Register current device on login, ATOMICALLY checking the device
  /// limit inside a Firestore transaction.
  ///
  /// SECURITY FIX (H6): Previously this used a non-atomic
  /// read-modify-write pattern, with a SEPARATE pre-check via
  /// checkDeviceLimit. Two concurrent logins (e.g. user logging in on
  /// two devices at the same moment) could both pass the pre-check,
  /// both read the same device list, both append, and the second write
  /// would either overwrite the first (losing a device entry) or both
  /// succeed past the limit (breaking the device-limit feature).
  ///
  /// Now we use a Firestore transaction so the read + limit-check +
  /// write happen atomically. If another concurrent transaction
  /// modified the user doc between our read and write, Firestore
  /// retries the whole transaction — so the limit check is always
  /// evaluated against the freshest data.
  ///
  /// Returns a [DeviceLimitResult] describing the outcome:
  ///   - allowed=true:  device was registered (or already registered,
  ///                    login time refreshed). Caller proceeds.
  ///   - allowed=false: device limit was reached. Caller must sign out
  ///                    the user and show the device-limit dialog using
  ///                    the returned device list.
  ///
  /// On hard failure (Firestore unreachable, permission denied), the
  /// method returns allowed=true (fail-open) to not block login — the
  /// device-limit feature is a soft enforcement, not a security control.
  ///
  /// Phase 4.6 — Self-create the user doc if it doesn't exist. The
  /// previous fail-open branch (return allowed=true with empty devices
  /// when the doc wasn't found) was the root cause of the Profile-tab
  /// "No devices registered" bug: if signup's _tryCreateUserDocBlocking
  /// failed silently (or hit a race with Firestore SDK auth-state
  /// propagation), the user doc never existed, so every registerDevice
  /// call returned allowed=true with no write — leaving the device list
  /// permanently empty. Now we create the doc inline (with all required
  /// admin-only fields set to safe defaults so the preservesAdminOnlyFields
  /// rule passes) and add the current device in the same transaction.
  Future<DeviceLimitResult> registerDevice(String uid) async {
    try {
      final currentDevice = await getCurrentDeviceInfo();

      return await _firestore.runTransaction<DeviceLimitResult>((tx) async {
        final userDocRef = _firestore.collection('users').doc(uid);
        final userDoc = await tx.get(userDocRef);

        if (!userDoc.exists) {
          // Phase 4.6 — User doc not created yet (race with signup flow
          // OR signup's doc creation failed silently). Previously this
          // returned allowed=true with empty devices and NO write —
          // causing the "No devices registered" bug on the Profile tab.
          //
          // Now we create the doc inline with the same field set as
          // _tryCreateUserDocBlocking in app_config.dart, plus the
          // current device in logged_in_devices. This makes
          // registerDevice self-sufficient — it no longer depends on
          // signup having completed the doc creation.
          //
          // Note: tx.set() inside a transaction goes through the
          // /users/{userId} `create` rule (isOwner + safeSignupFields).
          // Both conditions are satisfied: the caller is the Auth user
          // matching `uid`, and the payload sets all admin fields to
          // safe non-elevated values (false / 'user').
          final now = DateTime.now();
          final regDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          // Extract username/email from auth user if available, fall
          // back to UID-derived placeholders. We avoid passing these
          // as parameters to keep registerDevice's signature stable.
          final authUser = _auth.currentUser;
          final email = authUser?.email ?? '';
          String username = email.isNotEmpty
              ? email.split('@').first
              : 'user_${uid.substring(0, 8)}';
          if (email.endsWith('@cmmovies.app')) {
            username = email.replaceAll('@cmmovies.app', '');
          }

          final newDevicesList = <Map<String, dynamic>>[currentDevice.toMap()];
          tx.set(userDocRef, {
            'username': username,
            'email': email,
            'isAdmin': false,
            'role': 'user',
            'isVip': false,
            'isBanned': false,
            'forceLogout': false,
            'registrationDate': regDate,
            'createdAt': FieldValue.serverTimestamp(),
            'logged_in_devices': newDevicesList,
          }, SetOptions(merge: true));
          final parsed = newDevicesList
              .map((e) => DeviceInfo.fromMap(e))
              .toList();
          return DeviceLimitResult(
            allowed: true,
            maxDevices: 2,
            currentDevices: 1,
            devices: parsed,
          );
        }

        final data = userDoc.data()!;
        final isAdmin = data['isAdmin'] == true;
        final maxDevices = _computeMaxDevicesFromData(data);

        // Parse existing devices.
        final devicesList = List<Map<String, dynamic>>.from(
          (data['logged_in_devices'] as List?)
                  ?.map((e) => e as Map<String, dynamic>)
                  .toList() ??
              [],
        );

        // If this device is already registered, refresh its login time.
        final existingIndex = devicesList
            .indexWhere((d) => d['deviceId'] == currentDevice.deviceId);
        if (existingIndex >= 0) {
          devicesList[existingIndex] = currentDevice.toMap();
          tx.update(userDocRef, {'logged_in_devices': devicesList});
          final parsed = devicesList
              .map((e) => DeviceInfo.fromMap(e))
              .toList();
          return DeviceLimitResult(
            allowed: true,
            maxDevices: maxDevices,
            currentDevices: devicesList.length,
            devices: parsed,
          );
        }

        // === Phase 4.13 — Smart Deduplication (same device name) ===
        // HISTORY: When a user reinstalls the app (or updates it) on the
        // SAME physical phone, Android's ANDROID_ID is stable across
        // reinstalls — but our fallback UUID path (used when the
        // MethodChannel call fails or on iOS where identifierForVendor
        // is null) generates a FRESH UUID on each reinstall. This caused
        // the "Oppo A16" clone bug: the same phone appeared TWICE in the
        // device list, once with the old UUID and once with the new one.
        //
        // FIX: If deviceId doesn't match but deviceName DOES match an
        // existing entry, overwrite that entry in-place with the new
        // device's info (new ID, fresh login time). This keeps the
        // device count stable (no clone) and refreshes the stale entry.
        //
        // EDGE CASE — two distinct phones with the same model name
        // (e.g. two "Oppo A16" phones owned by the same user): the
        // second phone would overwrite the first. This is acceptable
        // because (a) it's rare for a single user to own two identical
        // models, (b) the device-limit feature's purpose is to limit
        // DISTINCT physical phones, and (c) the alternative (treating
        // them as separate) would let users bypass the limit by
        // clearing app data on the same phone. The trade-off favors
        // preventing clone-bypass over supporting the rare 2-same-model
        // case.
        final sameNameIndex = devicesList
            .indexWhere((d) => d['deviceName'] == currentDevice.deviceName);
        if (sameNameIndex >= 0) {
          devicesList[sameNameIndex] = currentDevice.toMap();
          tx.update(userDocRef, {'logged_in_devices': devicesList});
          final parsed = devicesList
              .map((e) => DeviceInfo.fromMap(e))
              .toList();
          return DeviceLimitResult(
            allowed: true,
            maxDevices: maxDevices,
            currentDevices: devicesList.length,
            devices: parsed,
          );
        }

        // Admin bypasses limit.
        if (isAdmin) {
          devicesList.add(currentDevice.toMap());
          tx.update(userDocRef, {'logged_in_devices': devicesList});
          final parsed = devicesList
              .map((e) => DeviceInfo.fromMap(e))
              .toList();
          return DeviceLimitResult(
            allowed: true,
            maxDevices: maxDevices,
            currentDevices: devicesList.length,
            devices: parsed,
          );
        }

        // Limit check — atomic, evaluated against freshest data.
        if (devicesList.length >= maxDevices) {
          final parsed = devicesList
              .map((e) => DeviceInfo.fromMap(e))
              .toList();
          return DeviceLimitResult(
            allowed: false,
            maxDevices: maxDevices,
            currentDevices: devicesList.length,
            devices: parsed,
            message: 'Device limit reached! You can have up to $maxDevices '
                'devices connected. Please remove an old device first.',
          );
        }

        // Add new device.
        devicesList.add(currentDevice.toMap());
        tx.update(userDocRef, {'logged_in_devices': devicesList});
        final parsed = devicesList
            .map((e) => DeviceInfo.fromMap(e))
            .toList();
        return DeviceLimitResult(
          allowed: true,
          maxDevices: maxDevices,
          currentDevices: devicesList.length,
          devices: parsed,
        );
      });
    } catch (e) {
      debugPrint('registerDevice failed: $e');
      // Fail open — device-limit is a soft enforcement, not a security
      // control. Better to let the user log in than block them on a
      // transient Firestore issue.
      return DeviceLimitResult(
        allowed: true,
        maxDevices: 2,
        currentDevices: 0,
        devices: [],
        message: 'Could not verify device limit. Login allowed.',
      );
    }
  }

  /// Remove a device from the user's logged_in_devices, atomically.
  ///
  /// SECURITY FIX (H6): Previously this used a non-atomic
  /// read-modify-write. If two concurrent removeDevice calls (e.g.
  /// user removing one device from profile page while admin removing
  /// another from admin panel) overlapped, the second write could
  /// revert the first — the removed device would reappear on next read.
  ///
  /// Now we use a Firestore transaction so concurrent removes are
  /// serialized and both take effect. Removing a device that's already
  /// absent is treated as success (idempotent).
  Future<bool> removeDevice(String uid, String deviceId) async {
    try {
      return await _firestore.runTransaction<bool>((tx) async {
        final userDocRef = _firestore.collection('users').doc(uid);
        final userDoc = await tx.get(userDocRef);
        if (!userDoc.exists) return false;

        final data = userDoc.data()!;
        final devicesList = List<Map<String, dynamic>>.from(
          (data['logged_in_devices'] as List?)
                  ?.map((e) => e as Map<String, dynamic>)
                  .toList() ??
              [],
        );

        final wasPresent =
            devicesList.any((d) => d['deviceId'] == deviceId);
        if (!wasPresent) {
          // Already removed by a concurrent operation — idempotent success.
          return true;
        }

        devicesList.removeWhere((d) => d['deviceId'] == deviceId);
        tx.update(userDocRef, {'logged_in_devices': devicesList});
        return true;
      });
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
}
