import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';

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

  /// Get unique device ID and name for the current device
  Future<DeviceInfo> getCurrentDeviceInfo() async {
    String deviceId;
    String deviceName;

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      deviceId = androidInfo.id; // Unique Android ID
      deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
      // Capitalize first letter
      if (deviceName.isNotEmpty) {
        deviceName = deviceName[0].toUpperCase() + deviceName.substring(1);
      }
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? 'unknown_ios';
      deviceName = iosInfo.utsname.machine;
    } else {
      deviceId = 'unknown_device';
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
      final isVip = data['isVip'] == true;
      final maxDevices = isVip ? 4 : 2;
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

  /// Remove all devices except the current one (for cleanup)
  Future<void> removeAllOtherDevices(String uid) async {
    try {
      final currentDevice = await getCurrentDeviceInfo();
      await _firestore.collection('users').doc(uid).update({
        'logged_in_devices': [currentDevice.toMap()],
      });
    } catch (e) {
      debugPrint('removeAllOtherDevices failed: $e');
    }
  }
}
