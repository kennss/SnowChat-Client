/// @file        ai_message_dao.dart
/// @description AI messages DAO — on-device AI conversation CRUD.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-15
/// @lastUpdated 2026-04-26 (header + inline English translation; previous: 2026-04-15)
///
/// @functions
///  - AiMessageDao.watchMessages(): per-session message stream
///  - AiMessageDao.insertMessage(): insert message
///  - AiMessageDao.getLastMessage(): fetch the last message
///  - AiMessageDao.clearSession(): delete a session
///  - AiMessageDao.clearAll(): delete everything

import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/ai_messages_table.dart';

part 'ai_message_dao.g.dart';

@DriftAccessor(tables: [AiMessages])
class AiMessageDao extends DatabaseAccessor<SnowDatabase>
    with _$AiMessageDaoMixin {
  AiMessageDao(super.db);

  /// Per-session message stream (live UI refresh)
  Stream<List<AiMessage>> watchMessages({String sessionId = 'default'}) {
    return (select(aiMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  /// Insert message
  Future<void> insertMessage(AiMessagesCompanion entry) {
    return into(aiMessages).insert(entry);
  }

  /// Fetch last message (for chat-tile preview)
  Future<AiMessage?> getLastMessage({String sessionId = 'default'}) {
    return (select(aiMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Delete session
  Future<int> clearSession({String sessionId = 'default'}) {
    return (delete(aiMessages)
          ..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }

  /// Fetch recent messages (for the agentic history window)
  Future<List<AiMessage>> getRecentMessages({
    String sessionId = 'default',
    int limit = 20,
  }) {
    return (select(aiMessages)
          ..where((t) => t.sessionId.equals(sessionId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get()
        .then((list) => list.reversed.toList()); // chronological order
  }

  /// Delete everything
  Future<int> clearAll() {
    return delete(aiMessages).go();
  }
}
