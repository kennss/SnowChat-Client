/// @file        add_channel_screen.dart
/// @description Add-channel screen — search + popular channel list + create button.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-05
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - AddChannelScreen: entry point for channel search/discover/create

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';

class AddChannelScreen extends ConsumerStatefulWidget {
  const AddChannelScreen({super.key});

  @override
  ConsumerState<AddChannelScreen> createState() => _AddChannelScreenState();
}

class _AddChannelScreenState extends ConsumerState<AddChannelScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _searchQuery = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchQuery.length >= 2;

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Add Channel'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(SnowSizes.md),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Search channels...',
                prefixIcon:
                    Icon(Icons.search_rounded, color: SnowColors.textTertiary),
              ),
            ),
          ),

          // Create new channel button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SnowSizes.md),
            child: OutlinedButton.icon(
              onPressed: () => context.push('/create-channel'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create New Channel'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

          const SizedBox(height: SnowSizes.md),
          const Divider(color: SnowColors.divider, height: 1),

          // Results
          Expanded(
            child: isSearching
                ? _SearchResults(query: _searchQuery)
                : _PopularChannels(),
          ),
        ],
      ),
    );
  }
}

/// Search results widget.
class _SearchResults extends ConsumerWidget {
  final String query;
  const _SearchResults({required this.query});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(channelSearchProvider(query));

    return results.when(
      data: (channels) {
        if (channels.isEmpty) {
          return const Center(
            child: Text('No channels found',
                style: TextStyle(color: SnowColors.textTertiary)),
          );
        }
        return ListView.builder(
          itemCount: channels.length,
          itemBuilder: (_, i) => _ChannelTile(channel: channels[i]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text('Search failed',
            style: TextStyle(color: SnowColors.textTertiary)),
      ),
    );
  }
}

/// Popular channels (discover) widget.
class _PopularChannels extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[AddChannel] _PopularChannels build — watching channelDiscoverProvider');
    final channels = ref.watch(channelDiscoverProvider(null));

    return channels.when(
      data: (list) {
        if (list.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No public channels yet.\nBe the first to create one!',
                textAlign: TextAlign.center,
                style: TextStyle(color: SnowColors.textTertiary),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Popular Channels',
                  style: TextStyle(
                      color: SnowColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _ChannelTile(channel: list[i]),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(
        child: Text('Failed to load channels',
            style: TextStyle(color: SnowColors.textTertiary)),
      ),
    );
  }
}

/// Single channel tile in the list.
class _ChannelTile extends StatelessWidget {
  final ChannelInfo channel;
  const _ChannelTile({required this.channel});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SnowAvatar(
        snowId: channel.id,
        size: 44,
        displayName: channel.name ?? '',
      ),
      title: Text(
        channel.name ?? 'Channel',
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${channel.memberCount} members${channel.category != null ? ' • ${channel.category}' : ''}',
        style:
            const TextStyle(color: SnowColors.textTertiary, fontSize: 12),
      ),
      trailing: _joinPolicyBadge(channel.joinPolicy),
      onTap: () => context.push('/channel-info/${channel.id}'),
    );
  }

  Widget _joinPolicyBadge(JoinPolicy policy) {
    switch (policy) {
      case JoinPolicy.open:
        return const Icon(Icons.public_rounded,
            color: SnowColors.primary, size: 20);
      case JoinPolicy.approval:
        return const Icon(Icons.how_to_reg_rounded,
            color: Colors.amber, size: 20);
      case JoinPolicy.inviteOnly:
        return const Icon(Icons.lock_rounded,
            color: SnowColors.textTertiary, size: 20);
    }
  }
}
