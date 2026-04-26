/// @file        device_management_screen.dart
/// @description Device-management screen — list linked devices, mark current device, remove device, guide for adding a new device.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - DeviceManagementScreen: device-management ConsumerStatefulWidget
///  - _buildDeviceTile(): build per-device tile widget
///  - _confirmRemoveDevice(): device-removal confirmation dialog
///  - _formatLastSeen(): format last-seen timestamp
///  - _platformIcon(): return per-platform icon

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/toast.dart';
import '../providers/device_provider.dart';

class DeviceManagementScreen extends ConsumerStatefulWidget {
  const DeviceManagementScreen({super.key});

  @override
  ConsumerState<DeviceManagementScreen> createState() =>
      _DeviceManagementScreenState();
}

class _DeviceManagementScreenState
    extends ConsumerState<DeviceManagementScreen> {
  @override
  void initState() {
    super.initState();
    // Fetch devices on screen load
    Future.microtask(() {
      ref.read(deviceProvider.notifier).fetchDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deviceState = ref.watch(deviceProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Linked Devices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(deviceProvider.notifier).fetchDevices();
            },
          ),
        ],
      ),
      body: _buildBody(deviceState),
    );
  }

  Widget _buildBody(DeviceListState state) {
    if (state.isLoading && state.devices.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: SnowColors.primary),
      );
    }

    if (state.error != null && state.devices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SnowSizes.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: SnowColors.error,
                size: 48,
              ),
              const SizedBox(height: SnowSizes.md),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SnowColors.textSecondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: SnowSizes.lg),
              OutlinedButton(
                onPressed: () {
                  ref.read(deviceProvider.notifier).fetchDevices();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: SnowColors.primary,
      backgroundColor: SnowColors.surface,
      onRefresh: () => ref.read(deviceProvider.notifier).fetchDevices(),
      child: ListView(
        children: [
          // Header info
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Devices linked to your SnowChat account. Swipe left on a device to remove it.',
              style: TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 13,
              ),
            ),
          ),

          const SizedBox(height: SnowSizes.sm),

          // Device list
          if (state.devices.isEmpty)
            const Padding(
              padding: EdgeInsets.all(SnowSizes.xl),
              child: Center(
                child: Text(
                  'No devices found',
                  style: TextStyle(
                    color: SnowColors.textTertiary,
                    fontSize: 15,
                  ),
                ),
              ),
            )
          else
            ...state.devices.map((device) => _buildDeviceTile(device)),

          const SizedBox(height: SnowSizes.lg),

          // Link New Device button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SnowSizes.lg),
            child: OutlinedButton.icon(
              onPressed: () {
                SnowToast.show(
                  context,
                  message: 'Device linking will be available in a future update',
                  type: ToastType.info,
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Link New Device'),
            ),
          ),

          const SizedBox(height: SnowSizes.xxl),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(DeviceInfo device) {
    final tile = ListTile(
      leading: _platformIcon(device.platform),
      title: Row(
        children: [
          Flexible(
            child: Text(
              device.deviceName,
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (device.isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: SnowColors.primaryBg,
                borderRadius: BorderRadius.circular(SnowSizes.radiusFull),
                border: Border.all(
                  color: SnowColors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'This device',
                style: TextStyle(
                  color: SnowColors.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        'Last seen: ${_formatLastSeen(device.lastSeen)}',
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
        ),
      ),
    );

    // Cannot remove the current device via swipe
    if (device.isCurrent) {
      return tile;
    }

    return Slidable(
      key: ValueKey(device.deviceId),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => _confirmRemoveDevice(device),
            backgroundColor: SnowColors.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_rounded,
            label: 'Remove',
          ),
        ],
      ),
      child: tile,
    );
  }

  /// Get platform-specific icon widget.
  Widget _platformIcon(String platform) {
    final IconData icon;
    switch (platform.toLowerCase()) {
      case 'ios':
        icon = Icons.phone_iphone_rounded;
        break;
      case 'android':
        icon = Icons.phone_android_rounded;
        break;
      case 'web':
        icon = Icons.language_rounded;
        break;
      case 'desktop':
      case 'macos':
      case 'windows':
      case 'linux':
        icon = Icons.desktop_mac_rounded;
        break;
      default:
        icon = Icons.devices_rounded;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: SnowColors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        color: SnowColors.textSecondary,
        size: 22,
      ),
    );
  }

  /// Format last seen time in a human-readable way.
  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';

    return '${lastSeen.year}-${lastSeen.month.toString().padLeft(2, '0')}-${lastSeen.day.toString().padLeft(2, '0')}';
  }

  /// Show confirmation dialog before removing a device.
  void _confirmRemoveDevice(DeviceInfo device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Remove Device',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: Text(
          'Remove "${device.deviceName}" from your account? '
          'This device will no longer receive messages.',
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref
                  .read(deviceProvider.notifier)
                  .removeDevice(device.deviceId);
              if (mounted) {
                SnowToast.show(
                  this.context,
                  message: success
                      ? 'Device removed'
                      : 'Failed to remove device',
                  type: success ? ToastType.success : ToastType.error,
                );
              }
            },
            child: const Text(
              'Remove',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
