/// @file        conversation_from_drift_row_test.dart
/// @description conversationFromDriftRow() — the single drift-row → in-memory
///              Conversation mapper. Guards the regression where
///              loadFromServer rebuilt the list without the per-room
///              auto-translate fields and reset the switch on every launch.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-11
/// @lastUpdated 2026-11-11
///
/// @functions
///  - main(): mapper field-carry tests (auto-translate, type, participants)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/storage/database.dart' as db;
import 'package:snowchat/features/chat/models/conversation.dart';
import 'package:snowchat/features/chat/providers/conversation_list_provider.dart';

db.Conversation _row({
  String id = 'snow1a9f21181f173b600c90d8f350ea7a25',
  String type = 'direct',
  String? groupId,
  String participantIds = 'snow1a9f21181f173b600c90d8f350ea7a25',
  bool autoTranslateEnabled = false,
  String? autoTranslateTargetLang,
  int? lastMessageTime,
}) =>
    db.Conversation(
      id: id,
      type: type,
      participantIds: participantIds,
      groupId: groupId,
      lastMessageTime: lastMessageTime,
      unreadCount: 0,
      unreadSelfMentionCount: 0,
      isRead: true,
      lastSeen: 0,
      lastScrolled: 0,
      isPinned: false,
      isMuted: false,
      isArchived: false,
      isActive: true,
      autoTranslateEnabled: autoTranslateEnabled,
      autoTranslateTargetLang: autoTranslateTargetLang,
      createdAt: 1000,
      updatedAt: 1000,
    );

void main() {
  test('auto-translate switch and target language are carried over', () {
    final conv = conversationFromDriftRow(
        _row(autoTranslateEnabled: true, autoTranslateTargetLang: 'Korean'));
    expect(conv.autoTranslateEnabled, isTrue);
    expect(conv.autoTranslateTargetLang, 'Korean');
  });

  test('defaults stay off when the row has auto-translate off', () {
    final conv = conversationFromDriftRow(_row());
    expect(conv.autoTranslateEnabled, isFalse);
    expect(conv.autoTranslateTargetLang, isNull);
  });

  test('type, participants, unread and timestamps are mapped', () {
    final direct = conversationFromDriftRow(
      _row(participantIds: 'snowa,,snowb', lastMessageTime: 5000),
      unreadCount: 3,
    );
    expect(direct.type, ConversationType.direct);
    expect(direct.participantIds, ['snowa', 'snowb']);
    expect(direct.unreadCount, 3);
    expect(direct.lastMessageTime, DateTime.fromMillisecondsSinceEpoch(5000));
    expect(direct.createdAt, DateTime.fromMillisecondsSinceEpoch(1000));

    final group = conversationFromDriftRow(
        _row(id: 'grp1', type: 'group', groupId: 'grp1', participantIds: ''));
    expect(group.type, ConversationType.group);
    expect(group.groupId, 'grp1');
    expect(group.participantIds, isEmpty);
  });
}
