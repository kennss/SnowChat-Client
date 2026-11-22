/// @file        gv2_chat_actions.dart
/// @description What a chat does in a group protocol v2 group: queue a
///              message of this account (with its own copy stored in the
///              same transaction), take one back, clear the history, leave
///              and end the group. ChatNotifier calls these in place of the
///              v1 group paths (authenticated socket and REST), which a v2
///              group never touches.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-21 (P5.6: forgetGroup() — removing the chat of a group this account left erases the group; P5.6: leaving with one's messages unsends nothing unless the leave can follow (checkLeave first), and takes back what did not go out). Earlier 2026-11-20
///
/// @functions
///  - Gv2ChatActions.send(): queue a text, file or voice message
///  - Gv2ChatActions.unsend(): take back a message of this account
///  - Gv2ChatActions.clearHistory(): clear the history for everyone (owner
///    or admin)
///  - Gv2ChatActions.leave(): leave the group, first taking back this
///    account's messages when asked to
///  - Gv2ChatActions.end(): end the group (owner)
///  - gv2OwnMessageIdKey: where an own message row keeps its 16-byte id
///
/// Notes:
///  - A message is stored under its local message id from the start (the id
///    every member derives from the group, the sender and the 16-byte
///    message id of the envelope header) — there is no temporary id that is
///    swapped later. The row is written in the transaction that queues the
///    message: either both exist or neither.
///  - The row of an own message keeps the 16-byte message id (hex) in its
///    metadata under [gv2OwnMessageIdKey]: an unsend names that id, and the
///    local id cannot be turned back into it. The key never leaves the
///    device (the payload sent to the group carries the app's metadata
///    only).
///  - A queued message leaves when the group can send (this account
///    confirmed, no hold) — until then it waits in the outbox, shown as
///    "sending". What became of it arrives as an outbox event
///    (Gv2Runtime.sendEvents), which the app writes to the row's status.
///  - Nothing here logs: messages and groups.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/group_v2/gv2_codec.dart';
import '../../../core/group_v2/gv2_content.dart';
import '../../../core/group_v2/gv2_groups.dart'
    show Gv2GroupException, Gv2GroupFailure;
import '../../../core/group_v2/gv2_messaging.dart';
import '../../../core/group_v2/gv2_runtime.dart';
import '../../../core/group_v2/gv2_store.dart';
import '../../../core/messaging/gv2_message_sink.dart';
import '../../../core/storage/daos/attachment_dao.dart';
import '../../../core/storage/daos/message_dao.dart';
import '../../../core/storage/database.dart';

/// Metadata key of an own message row: lowercase hex of the 16-byte message
/// id of its envelope header.
const String gv2OwnMessageIdKey = 'gv2MessageId';

class Gv2ChatActions {
  /// Lowercase hex of the group id: also the conversation id.
  final String groupId;
  final Gv2Runtime? Function() _runtime;
  final MessageDao _messages;
  final AttachmentDao _attachments;
  final String _me;

  /// [runtime] returns the account's v2 runtime, or null while there is
  /// none (it is rebuilt when the session changes, so it is asked for at
  /// each use). [mySnowId] is this device's account.
  Gv2ChatActions({
    required this.groupId,
    required Gv2Runtime? Function() runtime,
    required MessageDao messages,
    required AttachmentDao attachments,
    required Gv2Store groups,
    required String mySnowId,
  }) : _runtime = runtime,
       _messages = messages,
       _attachments = attachments,
       _groups = groups,
       _me = mySnowId;

  final Gv2Store _groups;

  /// The chat of a group this account is no longer in was removed: the
  /// group goes from this device with it (its master key included) — it is
  /// kept only while its chat shows it as left. A group this account is in
  /// is not touched. Works without the runtime (the rows are local).
  Future<void> forgetGroup() async {
    if (await _groups.forgetGone(groupId)) {
      _runtime()?.inbox.groupsChanged();
    }
  }

  Gv2Runtime get _ready {
    final runtime = _runtime();
    if (runtime == null) throw const Gv2NotSendable();
    return runtime;
  }

  /// Queue a message of this account and store its own copy. [type] is one
  /// of Gv2AppMessagePayload.types; [snippet] is what the chat list shows.
  /// [attachment] builds the row of the message's local file, given the id
  /// the message is stored under. Returns that id.
  ///
  /// Throws [Gv2NotSendable] when this account cannot write in the group
  /// (not in it, the group frozen, or no runtime), [ArgumentError] when the
  /// payload is too long.
  Future<String> send({
    required String text,
    required String snippet,
    String type = 'text',
    Map<String, dynamic>? metadata,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
    LocalAttachmentsCompanion Function(String messageId)? attachment,
  }) async {
    final ttl = ttlSeconds ?? 0;
    final payload = Gv2AppMessagePayload(
      text: text,
      type: type,
      metadata: metadata,
      ttlSeconds: ttl,
      replyToId: replyToId,
      replyToPreview: replyToPreview,
      replyToSenderId: replyToSenderId,
    );
    final queued = await _ready.messaging.send(
      groupId,
      Gv2MessageContent(payload.encode()),
      expiresInSeconds: ttl,
      alsoWrite: (q) async {
        final dateSent = await _messages.freeDateSent(
          conversationId: groupId,
          sender: _me,
          dateSent: q.timestampMs,
          messageId: q.localMessageId,
        );
        await _messages.insertOutgoingMessage(
          message: LocalMessagesCompanion(
            id: Value(q.localMessageId),
            conversationId: Value(groupId),
            senderSnowchatId: Value(_me),
            plaintext: Value(text),
            dateSent: Value(dateSent),
            dateReceived: Value(q.timestampMs),
            type: Value(type),
            metadata: Value(
              jsonEncode({
                ...?metadata,
                gv2OwnMessageIdKey: gv2Hex(q.messageId),
              }),
            ),
            read: const Value(true),
            outgoingStatus: const Value('sending'),
            expiresIn: Value(ttl),
            expireStarted: Value(ttl > 0 ? q.timestampMs : 0),
            replyToId: Value(replyToId),
            replyToPreview: Value(replyToPreview),
            replyToSenderId: Value(replyToSenderId),
          ),
          conversationId: groupId,
          snippetText: snippet,
          sentTimestamp: q.timestampMs,
        );
        final row = attachment?.call(q.localMessageId);
        if (row != null) await _attachments.insertAttachment(row);
      },
    );
    return queued.localMessageId;
  }

  /// The 16-byte message id an own message row keeps, or null when the row
  /// is not an own v2 message.
  static Uint8List? ownMessageId(LocalMessage row) {
    final raw = row.metadata;
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      final hex = json is Map ? json[gv2OwnMessageIdKey] : null;
      if (hex is! String || hex.length != 32) return null;
      return gv2Unhex(hex);
    } catch (_) {
      return null;
    }
  }

  /// Take back the message stored under [localMessageId]: the members
  /// remove their copy. Returns false when it is not an own message of this
  /// group or cannot be said (the caller then keeps its own copy). The own
  /// copy is the caller's to remove.
  Future<bool> unsend(String localMessageId) async {
    final row = await _messages.getMessageById(localMessageId);
    if (row == null ||
        row.conversationId != groupId ||
        row.senderSnowchatId != _me) {
      return false;
    }
    final messageId = ownMessageId(row);
    if (messageId == null) return false;
    try {
      await _ready.messaging.send(groupId, Gv2UnsendContent(messageId));
      return true;
    } on Gv2NotSendable {
      return false;
    }
  }

  /// Clear the history for everyone: the members remove what was sent
  /// before now (they honour it only from an owner or admin). The own copy
  /// is the caller's to remove. Throws [Gv2NotSendable].
  Future<void> clearHistory() async {
    await _ready.messaging.send(
      groupId,
      // Never honoured beyond the time it is sent at (the header's).
      Gv2ClearHistoryContent(DateTime.now().millisecondsSinceEpoch + 1000),
    );
  }

  /// Leave the group. With [deleteMyMessages] this account's messages are
  /// taken back first, as far as the group can be told now (what cannot be
  /// sent before the leave is not sent after it). Throws
  /// [Gv2GroupException] (gv2_groups.dart) when the leave could not be
  /// made; nothing is removed from this device then.
  Future<void> leave({bool deleteMyMessages = false}) async {
    final runtime = _ready;
    if (deleteMyMessages) {
      // Nothing is unsent unless the leave can follow: checked on the log as
      // the server has it, before anything goes out (unsent messages of an
      // account that stays in the group would be gone for everyone).
      await runtime.groups.checkLeave(groupId);
      final unsends = <Uint8List>[];
      try {
        for (final row in await _messages.getMessagesForConversation(groupId)) {
          if (row.senderSnowchatId != _me) continue;
          final messageId = ownMessageId(row);
          if (messageId == null) continue;
          final queued =
              await runtime.messaging.send(groupId, Gv2UnsendContent(messageId));
          unsends.add(queued.messageId);
        }
        await runtime.outbox.flush();
      } on Gv2NotSendable {
        // A frozen group is only erased from this device.
      }
      // What did not go out (the connection went meanwhile) is taken back:
      // it would go later, while this account is still in the group. Asking
      // again unsends the rest and leaves.
      if (unsends.isNotEmpty &&
          await runtime.outbox.takeBackContent(groupId, unsends) > 0) {
        throw const Gv2GroupException(Gv2GroupFailure.unavailable);
      }
    }
    await runtime.groups.leave(groupId);
  }

  /// End the group for everyone (owner). Throws [Gv2GroupException].
  Future<void> end() => _ready.groups.end(groupId);
}
