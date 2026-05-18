/// @file        settings_screen.dart
/// @description Settings screen — profile, privacy (read receipts / typing / link previews / blocked contacts), notifications, security (biometric / recovery phrase / linked devices), account deletion.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-11 (Privacy section: added read-only status tile
///              "Screenshot blocked — always on" at top. App-wide capture
///              protection is wired one-shot in main.dart and cannot be
///              toggled — this tile exists so users see the policy and don't
///              think their phone is malfunctioning. Earlier 2026-04-26
///              header + inline English translation.)
///
/// @functions
///  - SettingsScreen: settings ConsumerWidget
///  - _showLanguagePicker(): translation target-language picker bottom sheet

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../shared/widgets/snow_id_display.dart';
import '../../../app/providers.dart';
import '../../../utils/version.dart';
import '../../ai/service/supported_languages.dart';
import '../settings_provider.dart';
import 'network_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentSnowIdProvider) ?? '';
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Profile section
          Padding(
            padding: const EdgeInsets.all(SnowSizes.lg),
            child: Row(
              children: [
                FutureBuilder<String?>(
                  future: ref.read(secureStorageProvider).getDisplayName(),
                  builder: (context, snap) {
                    final name = snap.data ?? 'Me';
                    return SnowAvatar(
                      snowId: myId,
                      size: 60,
                      displayName: name,
                    );
                  },
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<String?>(
                        future: ref.read(secureStorageProvider).getDisplayName(),
                        builder: (context, snap) {
                          final name = snap.data ?? 'My Identity';
                          return Text(
                            name,
                            style: const TextStyle(
                              color: SnowColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 4),
                      SnowIdDisplay(
                        snowId: myId,
                        compact: true,
                        fontSize: 12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Privacy section
          _buildSectionHeader('Privacy'),
          _buildStatusTile(
            icon: Icons.no_photography_rounded,
            title: 'Screenshot Protection',
            // Two-line subtitle: status + honest platform caveat. Users see
            // the policy explicitly so they don't think their phone is broken
            // when a screenshot comes out black, and the iOS line manages
            // expectations (texture-backed GPU surfaces may bypass).
            subtitle:
                'Always on. Screenshots and screen recordings show black.\n'
                'iOS: best-effort (Apple does not allow apps to fully block '
                'captures). Out-of-band photos with another camera cannot '
                'be prevented.',
          ),
          _buildSwitchTile(
            icon: Icons.visibility_rounded,
            title: 'Read Receipts',
            subtitle: 'Let others know you\'ve read their messages',
            value: settings.readReceipts,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setReadReceipts(v),
          ),
          _buildSwitchTile(
            icon: Icons.keyboard_rounded,
            title: 'Typing Indicators',
            subtitle: 'Show when you are typing',
            value: settings.typingIndicators,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setTypingIndicators(v),
          ),
          _buildSwitchTile(
            icon: Icons.link_rounded,
            title: 'Link Previews',
            subtitle: 'Generate previews for URLs',
            value: settings.linkPreviews,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setLinkPreviews(v),
          ),
          _buildNavTile(
            icon: Icons.block_rounded,
            title: 'Blocked Contacts',
            subtitle: 'View and unblock contacts you have blocked',
            onTap: () => context.push('/settings/blocked-contacts'),
          ),

          const Divider(),

          // Translation
          _buildSectionHeader('Translation'),
          _buildLanguageTile(context, ref, settings.preferredLanguage),

          const Divider(),

          // Notifications
          _buildSectionHeader('Notifications'),
          _buildSwitchTile(
            icon: Icons.notifications_rounded,
            title: 'Push Notifications',
            subtitle: 'Receive notifications for new messages',
            value: settings.notificationsEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setNotifications(v),
          ),

          const Divider(),

          // Security
          _buildSectionHeader('Security'),
          _buildSwitchTile(
            icon: Icons.fingerprint_rounded,
            title: 'Biometric Lock',
            subtitle: 'Require Face ID / fingerprint to open',
            value: settings.biometricLockEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setBiometricLock(v),
          ),
          _buildSwitchTile(
            icon: Icons.shield_rounded,
            title: 'Always Relay Calls',
            subtitle:
                'Hide your IP from contacts during calls (routes through TURN — slight latency cost)',
            value: settings.callAlwaysRelay,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setCallAlwaysRelay(v),
          ),
          _buildSwitchTile(
            icon: Icons.lock_clock_rounded,
            title: 'Require PIN for Incoming Calls',
            subtitle:
                'When enabled, you must unlock the app before answering. Default off — Signal/WhatsApp style.',
            value: settings.callRequirePin,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setCallRequirePin(v),
          ),
          _buildNavTile(
            icon: Icons.devices_rounded,
            title: 'Linked Devices',
            subtitle: 'Manage devices connected to your account',
            onTap: () => context.push('/settings/devices'),
          ),
          _buildNavTile(
            icon: Icons.key_rounded,
            title: 'Recovery Phrase',
            subtitle: 'View your backup recovery phrase',
            onTap: () => context.push('/backup'),
          ),

          const Divider(),

          // Wallet / Network
          _buildSectionHeader('Wallet'),
          _buildNetworkTile(context, ref),
          _buildNavTile(
            icon: Icons.visibility_off_rounded,
            title: 'Hidden Accounts',
            subtitle: 'Restore derived sub-wallets you have hidden',
            onTap: () => context.push('/settings/hidden-wallets'),
          ),

          const Divider(),

          // About
          _buildSectionHeader('About'),
          _buildNavTile(
            icon: Icons.info_outline_rounded,
            title: 'Version',
            subtitle: ref.watch(appDisplayVersionProvider).maybeWhen(
                  data: (v) => v,
                  orElse: () => '...',
                ),
            onTap: () {},
          ),

          const SizedBox(height: SnowSizes.xl),

          // Danger zone
          _buildSectionHeader('Danger Zone'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SnowSizes.lg),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showResetConfirm(context, ref),
                    icon: const Icon(Icons.restart_alt_rounded, size: 20),
                    label: const Text('Reset App'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SnowColors.warning,
                      side: const BorderSide(color: SnowColors.warning),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showDeleteConfirm(context, ref),
                    icon: const Icon(Icons.delete_forever_rounded, size: 20),
                    label: const Text('Delete Account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: SnowColors.error,
                      side: const BorderSide(color: SnowColors.error),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: SnowSizes.xxl),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      leading: Icon(icon, color: SnowColors.textSecondary, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
        ),
      ),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: SnowColors.primary,
      ),
    );
  }

  /// Read-only status tile — like a switch tile but no toggle, no tap.
  /// Used for policies the user cannot configure (e.g. always-on screenshot
  /// protection). The "Always on" badge marks it as informational not interactive.
  Widget _buildStatusTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: SnowColors.textSecondary, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
          height: 1.4,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: SnowColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text(
          'Always on',
          style: TextStyle(
            color: SnowColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: SnowColors.textSecondary, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: SnowColors.textTertiary,
      ),
      onTap: onTap,
    );
  }

  Widget _buildLanguageTile(BuildContext context, WidgetRef ref, String current) {
    final nativeLabel = SupportedLanguages.nativeLabel(current);
    return ListTile(
      leading: const Icon(
        Icons.translate_rounded,
        color: SnowColors.textSecondary,
        size: 22,
      ),
      title: const Text(
        'Translation Language',
        style: TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 15,
        ),
      ),
      subtitle: const Text(
        'Auto-translate incoming messages to this language',
        style: TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nativeLabel,
            style: const TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: SnowColors.textTertiary,
          ),
        ],
      ),
      onTap: () => _showLanguagePicker(context, ref, current),
    );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, String current) {
    final languages = SupportedLanguages.forPlatform();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SnowColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Translation Language',
                  style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: languages.map((lang) {
              final isSelected = lang.name == current;
              return ListTile(
                title: Text(
                  lang.nativeLabel,
                  style: const TextStyle(
                    color: SnowColors.textPrimary,
                    fontSize: 15,
                  ),
                ),
                subtitle: Text(
                  lang.name,
                  style: const TextStyle(
                    color: SnowColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        color: SnowColors.primary,
                      )
                    : null,
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .setPreferredLanguage(lang.name);
                  Navigator.pop(ctx);
                },
              );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkTile(BuildContext context, WidgetRef ref) {
    final network = ref.watch(solanaNetworkProvider);
    return ListTile(
      leading: const Icon(
        Icons.swap_horiz_rounded,
        color: SnowColors.textSecondary,
        size: 22,
      ),
      title: const Text(
        'Network',
        style: TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 15,
        ),
      ),
      subtitle: const Text(
        'Solana RPC network selection',
        style: TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NetworkBadge(network: network, compact: true),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: SnowColors.textTertiary,
          ),
        ],
      ),
      onTap: () => context.push('/settings/network'),
    );
  }

  /// Reset app: clear all local data and return to onboarding.
  /// Identity keys and recovery phrase are deleted from secure storage.
  void _showResetConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Reset App',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'This will clear all local data and return to the welcome screen.\n\n'
          'Your identity, messages, and wallet data will be deleted from this device. '
          'Make sure you have backed up your recovery phrase before proceeding.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performReset(context, ref);
            },
            child: const Text(
              'Reset',
              style: TextStyle(color: SnowColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  /// Delete account: call server API then local reset.
  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Delete Account',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: const Text(
          'This will permanently delete your identity and all data.\n\n'
          'Active marketplace listings remain on-chain and will need '
          'to be cancelled from this device before deletion — '
          'otherwise the listed NFT stays locked in the on-chain PDA.\n\n'
          'Make sure you have backed up your recovery phrase. '
          'This action cannot be undone.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _performDeleteAccount(context, ref);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: SnowColors.error),
            ),
          ),
        ],
      ),
    );
  }

  /// Request account delete on server, then local reset.
  Future<void> _performDeleteAccount(BuildContext context, WidgetRef ref) async {
    // Step 1: server delete request (cancel market listings + escrow refund + data cleanup)
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.delete('/users/me');
    } catch (e) {
      debugPrint('[Settings] Server account deletion failed: $e');
      // Even if server delete fails, proceed with local reset — warn the user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server cleanup failed. Active listings may remain.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    // Step 2: local reset
    await _performReset(context, ref);
  }

  Future<void> _performReset(BuildContext context, WidgetRef ref) async {
    // 1. Disconnect socket
    ref.read(socketManagerProvider).disconnect();

    // 2. Wipe E2EE session data (sessions + signal_session_store.bin)
    await ref.read(signalSessionManagerProvider).resetSessionData();

    // 3. Clear TokenManager (Phase 11) — wipes the v2 envelope + legacy slots
    //    and emits logout event so listeners (sealedSender / push) tear down.
    await ref.read(tokenManagerProvider).clear();

    // 4. Clear secure storage (identity, PIN, Signal keys — token already
    //    wiped in step 3, but deleteAll covers everything else).
    await ref.read(secureStorageProvider).deleteAll();

    // 5. Delete drift database
    await ref.read(snowDatabaseProvider).close();

    // 6. Reset remaining app state
    ref.read(currentSnowIdProvider.notifier).state = null;
    ref.read(isOnboardedProvider.notifier).state = false;
    ref.read(isLockedProvider.notifier).state = false;

    // 7. Navigate to welcome
    if (context.mounted) {
      context.go('/welcome');
    }
  }
}
