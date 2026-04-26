/// @file        message_search_provider.dart
/// @description Message search Provider. Plaintext search in the local drift DB (E2EE — server search not possible)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - SearchResult: search-result data class (message + conversation info)
///  - MessageSearchState: search state (query, result list, loading state)
///  - messageSearchProvider: message-search StateNotifierProvider
///  - MessageSearchNotifier: runs search queries and manages results

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../providers/conversation_list_provider.dart';

/// A search result containing the matched message and its conversation context.
class SearchResult {
  final String messageId;
  final String conversationId;
  final String conversationName;
  final String messagePreview;
  final DateTime timestamp;
  final String senderSnowchatId;
  final MessageType messageType;

  const SearchResult({
    required this.messageId,
    required this.conversationId,
    required this.conversationName,
    required this.messagePreview,
    required this.timestamp,
    required this.senderSnowchatId,
    this.messageType = MessageType.text,
  });
}

class MessageSearchState {
  final String query;
  final List<SearchResult> results;
  final bool isSearching;

  const MessageSearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
  });

  MessageSearchState copyWith({
    String? query,
    List<SearchResult>? results,
    bool? isSearching,
  }) {
    return MessageSearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
    );
  }

  /// Group results by conversationId for display.
  Map<String, List<SearchResult>> get groupedByConversation {
    final map = <String, List<SearchResult>>{};
    for (final result in results) {
      map.putIfAbsent(result.conversationId, () => []).add(result);
    }
    return map;
  }
}

final messageSearchProvider =
    StateNotifierProvider<MessageSearchNotifier, MessageSearchState>((ref) {
  return MessageSearchNotifier(ref);
});

class MessageSearchNotifier extends StateNotifier<MessageSearchState> {
  final Ref _ref;
  Timer? _debounce;

  /// Current user's SnowChat ID, read from provider.

  MessageSearchNotifier(this._ref) : super(const MessageSearchState());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Update the search query with 300ms debounce.
  void updateQuery(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = const MessageSearchState();
      return;
    }

    state = state.copyWith(query: query, isSearching: true);

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _executeSearch(query.trim());
    });
  }

  /// Execute the search against drift DB (SSoT).
  /// Searches plaintext across all conversations.
  Future<void> _executeSearch(String query) async {
    if (!mounted) return;

    final myId = _ref.read(currentSnowIdProvider) ?? '';
    final lowerQuery = query.toLowerCase();
    final conversations = _ref.read(conversationListProvider);
    final messageDao = _ref.read(messageDaoProvider);
    final results = <SearchResult>[];

    // Build conversation name lookup
    final convNames = <String, String>{};
    for (final conv in conversations) {
      convNames[conv.id] = conv.displayName(myId);
    }

    // Search across all conversations using drift DB
    for (final conv in conversations) {
      try {
        final dbRows = await messageDao
            .getMessagesForConversation(conv.id);
        for (final row in dbRows) {
          if (row.plaintext.toLowerCase().contains(lowerQuery)) {
            results.add(SearchResult(
              messageId: row.id,
              conversationId: row.conversationId,
              conversationName: convNames[row.conversationId] ?? 'Unknown',
              messagePreview: row.plaintext,
              timestamp: DateTime.fromMillisecondsSinceEpoch(row.dateSent),
              senderSnowchatId: row.senderSnowchatId,
              messageType: MessageType.text,
            ));
          }
        }
      } catch (_) {}
    }

    // Sort by timestamp descending and limit to 50
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final limitedResults = results.take(50).toList();

    if (mounted) {
      state = state.copyWith(
        results: limitedResults,
        isSearching: false,
      );
    }
  }

  void clearSearch() {
    _debounce?.cancel();
    state = const MessageSearchState();
  }
}
