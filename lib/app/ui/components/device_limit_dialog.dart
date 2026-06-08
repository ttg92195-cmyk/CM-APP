import 'package:flutter/material.dart';
import 'package:cm_movies/app/core/services/device_management_service.dart';

/// A dialog shown when the device limit is reached
/// Shows the list of connected devices and allows removing old ones
class DeviceLimitDialog extends StatefulWidget {
  final DeviceLimitResult limitResult;
  final String uid;
  final VoidCallback onDeviceRemoved; // Called when a device is removed, allowing retry

  const DeviceLimitDialog({
    super.key,
    required this.limitResult,
    required this.uid,
    required this.onDeviceRemoved,
  });

  @override
  State<DeviceLimitDialog> createState() => _DeviceLimitDialogState();
}

class _DeviceLimitDialogState extends State<DeviceLimitDialog> {
  final DeviceManagementService _deviceService = DeviceManagementService();
  bool _isRemoving = false;
  String? _removingDeviceId;

  Future<void> _removeDevice(String deviceId) async {
    setState(() {
      _isRemoving = true;
      _removingDeviceId = deviceId;
    });

    final success = await _deviceService.removeDevice(widget.uid, deviceId);

    if (mounted) {
      if (success) {
        setState(() {
          widget.limitResult.devices.removeWhere((d) => d.deviceId == deviceId);
          _isRemoving = false;
          _removingDeviceId = null;
        });

        // Check if now under limit
        if (widget.limitResult.devices.length < widget.limitResult.maxDevices) {
          widget.onDeviceRemoved();
          if (mounted) Navigator.pop(context);
        }
      } else {
        setState(() {
          _isRemoving = false;
          _removingDeviceId = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to remove device. Please try again.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFE50914).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.devices,
                color: Color(0xFFE50914),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Device Limit Reached',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.limitResult.message ?? '',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.limitResult.currentDevices}/${widget.limitResult.maxDevices} devices used',
              style: TextStyle(
                color: const Color(0xFFE50914),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),

            // Connected Devices List
            if (widget.limitResult.devices.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Connected Devices',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.limitResult.devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final device = widget.limitResult.devices[index];
                    final isRemoving = _isRemoving && _removingDeviceId == device.deviceId;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white12 : Colors.grey.shade200,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.phone_android,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                            size: 24,
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
                                  'Logged in: ${_formatDate(device.loginTime)}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          isRemoving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFE50914),
                                    size: 20,
                                  ),
                                  onPressed: () => _removeDevice(device.deviceId),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  tooltip: 'Remove device',
                                ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),

            // Close button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Close',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
