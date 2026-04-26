/// @file        message_search_screen.dart
/// @description Message search screen. Real-time search in the local DB (E2EE — server search not possible)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - MessageSearchScreen: message-search screen ConsumerStatefulWidget
///  - _buildSearchBar(): search-input bar widget
///  - _buildResults(): show search results grouped by conversation
///  - _buildResultTile(): individual search-result tile

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../providers/message_search_provider.dart';

class MessageSearchScreen extends ConsumerStatefulWidget {
  const MessageSearchScreen({super.key});

  @override
  ConsumerState<MessageSearchScreen> createState() =>
      _MessageSearchScreenState();
}

class _MessageSearchScreenState extends ConsumerState<MessageSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search bar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(messageSearchProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            ref.read(messageSearchProvider.notifier).clearSearch();
            context.pop();
          },
        ),
        title: _buildSearchBar(),
        titleSpacing: 0,
      ),
      body: _buildBody(searchState),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      onChanged: (value) {
        ref.read(messageSearchProvider.notifier).updateQuery(value);
      },
      style: const TextStyle(
        color: SnowColors.textPrimary,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        hintText: 'Search messages...',
        hintStyle: const TextStyle(
          color: SnowColors.textTertiary,
          fontSize: 16,
        ),
        border: InputBorder.none,
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: SnowColors.textTertiary,
                  size: 20,
                ),
                onPressed: () {
                  _searchController.clear();
                  ref.read(messageSearchProvider.notifier).clearSearch();
                },
              )
            : null,
      ),
    );
  }

  Widget _buildBody(MessageSearchState searchState) {
    if (searchState.query.isEmpty) {
      return _buildEmptyHint();
    }

    if (searchState.isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: SnowColors.primary),
      );
    }

    if (searchState.results.isEmpty) {
      return _buildNoResults();
    }

    return _buildResults(searchState);
  }

  Widget _buildEmptyHint() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_rounded,
            size: 48,
            color: SnowColors.textTertiary,
          ),
          SizedBox(height: SnowSizes.md),
          Text(
            'Search your messages',
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 14,
            ),
          ),
          SizedBox(height: SnowSizes.sm),
          Text(
            'Messages are searched locally on your device',
            style: TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 48,
            color: SnowColors.textTertiary,
          ),
          const SizedBox(height: SnowSizes.md),
          Text(
            'No results for "${_searchController.text}"',
            style: const TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(MessageSearchState searchState) {
    final grouped = searchState.groupedByConversation;
    final conversationIds = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: SnowSizes.sm),
      itemCount: conversationIds.length,
      itemBuilder: (context, index) {
        final convId = conversationIds[index];
        final results = grouped[convId]!;
        final convName = results.first.conversationName;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Conversation group header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SnowSizes.md,
                vertical: SnowSizes.sm,
              ),
              child: Text(
                convName,
                style: const TextStyle(
                  color: SnowColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Result tiles
            ...results.map((result) => _buildResultTile(result)),
            if (index < conversationIds.length - 1)
              const Divider(
                color: SnowColors.divider,
                height: 1,
                indent: SnowSizes.md,
                endIndent: SnowSizes.md,
              ),
          ],
        );
      },
    );
  }

  Widget _buildResultTile(SearchResult result) {
    return InkWell(
      onTap: () {
        // Navigate to the chat screen at the matched message
        context.push('/chat/${result.conversationId}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SnowSizes.md,
          vertical: SnowSizes.sm + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Message icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SnowColors.surfaceVariant,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 16,
                color: SnowColors.textTertiary,
              ),
            ),
            const SizedBox(width: 12),
            // Message content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.messagePreview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SnowColors.textPrimary,
                      fontSize: 14,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(result.timestamp),
                    style: const TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.month}/${time.day}/${time.year}';
  }
}
