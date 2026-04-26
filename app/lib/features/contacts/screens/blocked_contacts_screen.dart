/// @file        blocked_contacts_screen.dart
/// @description Blocked-users list screen — fetch /users/blocked from server + unblock.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - BlockedContactsScreen: blocked-contacts list ConsumerWidget
///  - _confirmUnblock(): unblock confirmation dialog

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../contact_provider.dart';

class BlockedContactsScreen extends ConsumerWidget {
  const BlockedContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedContactsProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Blocked Contacts'),
      ),
      body: blockedAsync.when(
        data: (blocked) {
          if (blocked.isEmpty) return _buildEmptyState();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(blockedContactsProvider),
            color: SnowColors.primary,
            backgroundColor: SnowColors.surface,
            child: ListView.separated(
              itemCount: blocked.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: SnowColors.divider,
              ),
              itemBuilder: (_, i) {
                final c = blocked[i];
                final name = (c.displayName?.isNotEmpty ?? false)
                    ? c.displayName!
                    : c.snowChatId;
                return ListTile(
                  leading: SnowAvatar(
                    snowId: c.snowChatId,
                    size: 44,
                    displayName: name,
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(color: SnowColors.textPrimary),
                  ),
                  subtitle: Text(
                    _shortenSnowId(c.snowChatId),
                    style: const TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: TextButton(
                    onPressed: () =>
                        _confirmUnblock(context, ref, c.snowChatId, name),
                    child: const Text(
                      'Unblock',
                      style: TextStyle(color: SnowColors.primary),
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text(
            'Failed to load blocked contacts',
            style: TextStyle(color: SnowColors.textTertiary),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.block_rounded,
            size: 64,
            color: SnowColors.textTertiary,
          ),
          SizedBox(height: SnowSizes.md),
          Text(
            'No blocked contacts',
            style: TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 16,
            ),
          ),
          SizedBox(height: SnowSizes.sm),
          Text(
            'Contacts you block will appear here',
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmUnblock(
    BuildContext context,
    WidgetRef ref,
    String snowchatId,
    String displayName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text(
          'Unblock contact',
          style: TextStyle(color: SnowColors.textPrimary),
        ),
        content: Text(
          'Unblock $displayName? They will be able to send you messages again.',
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: SnowColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(contactProvider.notifier).unblockContact(snowchatId);
              // Refresh the blocked list (server roundtrip).
              ref.invalidate(blockedContactsProvider);
            },
            child: const Text(
              'Unblock',
              style: TextStyle(color: SnowColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  static String _shortenSnowId(String snowId) {
    if (snowId.length <= 14) return snowId;
    return '${snowId.substring(0, 8)}…${snowId.substring(snowId.length - 4)}';
  }
}
