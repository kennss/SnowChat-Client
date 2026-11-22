/// @file        settings_screen.dart
/// @description Settings screen — profile, privacy (read receipts / typing / link previews / blocked contacts), notifications, security (biometric / recovery phrase / linked devices), account deletion.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (Security: Change Passcode, Auto-Lock (default 1 min); biometric unlock
///              wording). Earlier 2026-11-20 (group protocol v2 has no build flag: the retention tile shows where groups can run, and account deletion always goes through deleteAccountWithProof). Earlier 2026-11-20 (group protocol v2: "Offline group messages" — how long the server keeps group messages for this account; a progress dialog while the account leaves its groups and is deleted; account deletion with group protocol v2 on: leave every v2 group first, then delete with the account key's deletion proof — core/network/account_deletion.dart). Earlier 2026-11-12 (account deletion: removed the marketplace-listing warning copy). Earlier 2026-11-11 (at-rest protection level 1: _performReset closes + deletes the encrypted drift DB and its SQLCipher key BEFORE the secure-storage wipe — files first, key last). Earlier 2026-11-08 (ENABLE_WALLET=false hardening: the Wallet section (network tile + Hidden Accounts) is hidden when AppConfig.enableWallet is false). Earlier 2026-08-07 (added Android-only "Lock-screen calls" tile in Notifications — opens the system USE_FULL_SCREEN_INTENT toggle via CallPermissionHelper.promptFromSettings so users can (re-)enable full-screen incoming calls over the lock screen on Android 14+). Earlier 2026-08-04 (Reset App / Delete Account now actually WIPE local data: _performReset deletes the drift DB file (+ WAL/SHM) and invalidates snowDatabaseProvider instead of only close()ing the connection, and clears currentDisplayNameProvider — previously a new identity created after a reset inherited the prior account's conversations + display name). Earlier 2026-08-03 (Profile header is now tappable (InkWell + trailing
///              chevron) and pushes /settings/profile → ProfileEditScreen to
///              edit the nickname. Previously 2026-05-11: Privacy section: added read-only status tile
///              "Screenshot blocked — always on" at top. App-wide capture
///              protection is wired one-shot in main.dart and cannot be
///              toggled — this tile exists so users see the policy and don't
///              think their phone is malfunctioning. Earlier 2026-04-26
///              header + inline English translation.)
///
/// @functions
///  - SettingsScreen: settings ConsumerWidget
///  - _showLanguagePicker(): translation target-language picker bottom sheet

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/call/call_permission_helper.dart';
import '../../../core/network/account_deletion.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../shared/widgets/snow_id_display.dart';
import '../../../app/providers.dart';
import '../../../app/app_config.dart';
import '../../../core/group_v2/gv2_trusted_keys.dart' show gv2GroupsAvailable;
import '../../../app/restart_widget.dart';
import '../../../utils/version.dart';
import '../../ai/service/supported_languages.dart';
import '../providers/gv2_retention_provider.dart';
import '../settings_provider.dart';
import 'network_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentSnowIdProvider) ?? '';
    final settings = ref.watch(settingsProvider);
    // Reactive display name so editing the nickname (ProfileEditScreen) updates
    // the header immediately, not only on the next rebuild.
    final displayName = ref.watch(currentDisplayNameProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Profile section — tap to edit the nickname (SnowChat ID is immutable)
          InkWell(
            onTap: () => context.push('/settings/profile'),
            child: Padding(
              padding: const EdgeInsets.all(SnowSizes.lg),
              child: Row(
                children: [
                SnowAvatar(
                  snowId: myId,
                  size: 60,
                  displayName: displayName ?? 'Me',
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName ?? 'My Identity',
                        style: const TextStyle(
                          color: SnowColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
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
                const Icon(Icons.chevron_right_rounded,
                    color: SnowColors.textTertiary),
              ],
            ),
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
          // Android 14+ only: the full-screen-intent permission that lets an
          // incoming call show full-screen over the lock screen (otherwise it's
          // just a heads-up notification). Opens the system settings toggle.
          if (Platform.isAndroid)
            _buildNavTile(
              icon: Icons.phone_in_talk_rounded,
              title: 'Lock-screen calls',
              subtitle:
                  'Show incoming calls full-screen when your phone is locked',
              onTap: () => CallPermissionHelper.promptFromSettings(context),
            ),
          // Group protocol v2: how long the server keeps group messages for
          // this account while it is offline (design §12). Hidden where
          // groups cannot run (no server keys pinned).
          if (gv2GroupsAvailable) _buildRetentionTile(context, ref),

          const Divider(),

          // Security
          _buildSectionHeader('Security'),
          _buildNavTile(
            icon: Icons.password_rounded,
            title: 'Change Passcode',
            subtitle: 'Digits or letters — the code that unlocks the app',
            onTap: () => context.push('/settings/passcode'),
          ),
          _buildNavTile(
            icon: Icons.timer_outlined,
            title: 'Auto-Lock',
            subtitle: _autoLockLabel(settings.autoLockSeconds),
            onTap: () => _pickAutoLock(context, ref, settings.autoLockSeconds),
          ),
          _buildSwitchTile(
            icon: Icons.fingerprint_rounded,
            title: 'Biometric Unlock',
            subtitle: 'Unlock with Face ID / Touch ID / fingerprint first',
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

          // Wallet / Network — omitted entirely in an ENABLE_WALLET=false build
          // (its routes do not exist there).
          if (AppConfig.enableWallet) ...[
            _buildSectionHeader('Wallet'),
            _buildNetworkTile(context, ref),
            _buildNavTile(
              icon: Icons.visibility_off_rounded,
              title: 'Hidden Accounts',
              subtitle: 'Restore derived sub-wallets you have hidden',
              onTap: () => context.push('/settings/hidden-wallets'),
            ),

            const Divider(),
          ],

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

  static String _autoLockLabel(int seconds) => switch (seconds) {
        0 => 'Lock as soon as you leave the app',
        < 3600 => 'Lock after ${seconds ~/ 60} min in the background',
        _ => 'Lock after ${seconds ~/ 3600} h in the background',
      };

  Future<void> _pickAutoLock(
      BuildContext context, WidgetRef ref, int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: SnowColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final seconds in kAutoLockChoices)
              ListTile(
                title: Text(
                  seconds == 0
                      ? 'Immediately'
                      : seconds < 3600
                          ? 'After ${seconds ~/ 60} min'
                          : 'After ${seconds ~/ 3600} h',
                  style: const TextStyle(color: SnowColors.textPrimary),
                ),
                trailing: seconds == current
                    ? const Icon(Icons.check_rounded, color: SnowColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(seconds),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).setAutoLockSeconds(picked);
    }
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

  /// "Offline group messages": the period the server keeps group messages
  /// for this account. The value is the server's; a tap offers the three
  /// periods it accepts.
  Widget _buildRetentionTile(BuildContext context, WidgetRef ref) {
    final retention = ref.watch(gv2RetentionProvider);
    final current = retention.valueOrNull;
    return _buildNavTile(
      icon: Icons.cloud_queue_rounded,
      title: 'Offline group messages',
      subtitle: retention.when(
        data: (days) =>
            'Kept on the server for ${gv2RetentionLabel(days)} while you are '
            'offline',
        loading: () => 'Loading…',
        error: (_, _) => 'Could not be loaded. Tap to try again.',
      ),
      onTap: () {
        if (current == null) {
          ref.invalidate(gv2RetentionProvider);
          return;
        }
        _showRetentionPicker(context, ref, current);
      },
    );
  }

  void _showRetentionPicker(BuildContext context, WidgetRef ref, int current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SnowColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                SnowSizes.md,
                SnowSizes.md,
                SnowSizes.md,
                SnowSizes.sm,
              ),
              child: Text(
                'Group messages that arrive while you are offline wait on '
                'the server this long. After that they are deleted there '
                'and cannot be delivered.',
                style: TextStyle(color: SnowColors.textSecondary, fontSize: 13),
              ),
            ),
            for (final days in gv2RetentionChoices)
              ListTile(
                title: Text(
                  gv2RetentionLabel(days),
                  style: const TextStyle(color: SnowColors.textPrimary),
                ),
                trailing: days == current
                    ? const Icon(Icons.check_rounded, color: SnowColors.primary)
                    : null,
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  if (days == current) return;
                  try {
                    await ref.read(gv2RetentionProvider.notifier).choose(days);
                  } catch (_) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('The setting could not be saved.'),
                        backgroundColor: SnowColors.error,
                      ),
                    );
                  }
                },
              ),
            const SizedBox(height: SnowSizes.sm),
          ],
        ),
      ),
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
    // Step 1: server delete request (data cleanup). With group protocol v2
    // the account first leaves its groups and the request carries the
    // account key's deletion proof (design §9.7). Leaving takes a request
    // per group: a dialog that cannot be dismissed shows that it is going on.
    final navigator = Navigator.of(context, rootNavigator: true);
    var progressShown = false;
    if (context.mounted) {
      progressShown = true;
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (_) => const PopScope(
            canPop: false,
            child: AlertDialog(
              backgroundColor: SnowColors.surface,
              content: Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: SnowColors.primary,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Deleting your account…',
                      style: TextStyle(color: SnowColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    try {
      final apiClient = ref.read(apiClientProvider);
      final groups = ref.read(gv2RuntimeProvider);
      await deleteAccountWithProof(
        api: apiClient,
        sign: ref.read(identityManagerProvider).signAccountDeleted,
        leaveGroups: groups?.leaveAllGroups,
      );
    } catch (e) {
      debugPrint('[Settings] Server account deletion failed: $e');
      // Even if server delete fails, proceed with local reset — warn the user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Server cleanup failed.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    if (progressShown && navigator.mounted) navigator.pop();

    // Step 2: local reset
    // The reset must follow the server delete whatever became of this
    // screen.
    // ignore: use_build_context_synchronously
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

    // 4. Delete the encrypted drift database. Close the connection first to
    //    release the handle, then remove the DB (+ WAL/SHM) and only THEN its
    //    SQLCipher key, so the key never disappears while the database it
    //    belongs to is still on disk. Previously this only close()d the
    //    connection, leaving the file on disk → a new identity reopened it and
    //    inherited the prior account's conversations and messages
    //    (data-isolation leak). Runs before step 5 for that ordering reason.
    await ref.read(snowDatabaseProvider).close();
    await deleteDriftDatabaseFile(ref.read(secureStorageProvider));

    // 5. Clear secure storage (identity, PIN, Signal keys — token already
    //    wiped in step 3, DB key in step 4, deleteAll covers everything else).
    await ref.read(secureStorageProvider).deleteAll();

    // 6. Full in-app restart. Wiping secure storage + the drift file is not
    //    enough on its own: identity-scoped providers (conversation list,
    //    contacts, channels, display name) keep the previous account's data in
    //    memory until the next cold start, so an identity created in the same
    //    session would still see the old chats. Rebuilding the root
    //    ProviderScope disposes all of that and re-runs startup against the
    //    now-empty storage → the router lands on /welcome with a clean slate.
    //    (Supersedes the manual currentSnowId/displayName/onboarded resets and
    //    a GoRouter navigation — the restart clears every provider at once.)
    if (context.mounted) {
      RestartWidget.restartApp(context);
    }
  }
}
