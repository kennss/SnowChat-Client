/// @file        community_explore.dart
/// @description Reusable community discovery UI — persistent search bar + trending
///              (member-count ranked) discover feed + tiles. Embedded directly in
///              the Communities tab so a new user lands on a live list of
///              communities to join instead of an empty two-button dead-end
///              (onboarding fix, design 2026-08-05). Also usable standalone.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-08-05
/// @lastUpdated 2026-08-05
///
/// @functions
///  - CommunityExplore: search bar + (search results | trending discover feed)
///  - CommunityTile: single community row (avatar, member count/category, join-policy badge)
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';

/// Search bar + discover feed. [headerSliver] renders above the discover list
/// when NOT searching (e.g. the Communities tab uses it for the "My
/// Communities" section, so search + discovery live in one scroll view).
class CommunityExplore extends ConsumerStatefulWidget {
  const CommunityExplore({super.key, this.header});

  /// Optional widget shown above the trending feed (only when not searching).
  final Widget? header;

  @override
  ConsumerState<CommunityExplore> createState() => _CommunityExploreState();
}

class _CommunityExploreState extends ConsumerState<CommunityExplore> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.length >= 2;

    return Column(
      children: [
        // Persistent search bar.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SnowSizes.md, SnowSizes.sm, SnowSizes.md, SnowSizes.sm),
          child: TextField(
            controller: _searchController,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search communities...',
              prefixIcon: const Icon(Icons.search_rounded,
                  color: SnowColors.textTertiary),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: SnowColors.textTertiary),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
            ),
          ),
        ),
        Expanded(
          child: isSearching
              ? _SearchResults(query: _query)
              : _TrendingFeed(header: widget.header),
        ),
      ],
    );
  }
}

/// Trending discover feed (server ranks public, non-invite-only communities by
/// member count; low-activity curation is a server follow-up). Renders an
/// optional [header] above the list.
class _TrendingFeed extends ConsumerWidget {
  const _TrendingFeed({this.header});

  final Widget? header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(channelDiscoverProvider(null));

    return RefreshIndicator(
      color: SnowColors.primary,
      backgroundColor: SnowColors.surface,
      onRefresh: () async => ref.invalidate(channelDiscoverProvider(null)),
      child: feed.when(
        data: (list) {
          return ListView(
            children: [
              if (header != null) header!,
              const Padding(
                padding: EdgeInsets.fromLTRB(SnowSizes.md, 12, SnowSizes.md, 8),
                child: Text(
                  'Discover communities',
                  style: TextStyle(
                    color: SnowColors.textTertiary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No communities to discover yet.\nTap + to create the first one!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: SnowColors.textTertiary),
                    ),
                  ),
                )
              else
                for (final c in list) CommunityTile(channel: c),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ListView(
          children: const [
            Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Failed to load communities',
                    style: TextStyle(color: SnowColors.textTertiary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(channelSearchProvider(query));

    return results.when(
      data: (channels) {
        if (channels.isEmpty) {
          return const Center(
            child: Text('No communities found',
                style: TextStyle(color: SnowColors.textTertiary)),
          );
        }
        return ListView.builder(
          itemCount: channels.length,
          itemBuilder: (_, i) => CommunityTile(channel: channels[i]),
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

/// One community row: avatar, name, member count + category, join-policy badge.
class CommunityTile extends StatelessWidget {
  const CommunityTile({super.key, required this.channel});

  final ChannelInfo channel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: SnowAvatar(
        snowId: channel.id,
        size: 44,
        displayName: channel.name ?? '',
      ),
      title: Text(
        channel.name ?? 'Community',
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        '${channel.memberCount} members${channel.category != null ? ' • ${channel.category}' : ''}',
        style: const TextStyle(color: SnowColors.textTertiary, fontSize: 12),
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
