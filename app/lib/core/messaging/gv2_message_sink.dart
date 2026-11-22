/// @file        gv2_message_sink.dart
/// @description Where the verified messages of group protocol v2 groups
///              enter the app: the local message store (LocalMessages,
///              Conversations, LocalAttachments). Implements Gv2MessageSink
///              for the v2 messaging layer — the writes run inside the
///              inbox transaction, so a message row, the conversation
///              snippet, the moved Sender Key chain and the inbox row
///              commit together or not at all — and defines the app's
///              message payload (what a content envelope of type "message"
///              carries).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6: at most gv2WaitingShownPerGroup "cannot be read" places per group; P5.6: system lines are written in one transaction with the check that the conversation exists — a removed chat got a line after its removal; P5.6: outgoing() — the status of a message of this account, written in the outbox's transaction). Earlier 2026-11-20 (comment: the payload is the 1:1 message object — no v1 rooms)
///
/// @functions
///  - Gv2AppMessagePayload: the app's message payload (encode / tryDecode)
///  - Gv2AppMessageSink.message(): store a received message
///  - Gv2AppMessageSink.unsent(): remove a message its sender took back
///  - Gv2AppMessageSink.historyCleared(): remove the messages before a time
///  - Gv2AppMessageSink.outgoing(): a message of this account was sent or given up
///  - Gv2AppMessageSink.waiting(): keep the place of a message that cannot
///    be read (its key has not come)
///  - Gv2AppMessageSink.committed(): after the commit — follow-ups (preview,
///    banner, notification, attachment downloads; deleting attachment files)
///  - Gv2AppMessageSink.groupChanged(): keep the group's conversation row
///    (it exists once this account is a member) and its title in step, and
///    write the system lines of the entries that were applied
///  - Gv2StoredMessage: what the follow-ups of a stored message need
///
/// Notes:
///  - Payload (UTF-8 JSON object), the fields a 1:1 message uses:
///      text (string), type ("text" | "file" | "voice"), metadata (object,
///      file and voice messages: fileId, fileName, mimeType, size, fileKey,
///      contentHash, attachments, duration), ttl (seconds, a disappearing
///      message), replyToId / replyToPreview / replyToSenderId.
///    No timestamp: the envelope header carries the sender's (authenticated)
///    time. A payload that is not such an object is not stored.
///  - A message is stored under its local message id (64 hex characters).
///    The conversation id of a v2 group is its group id.
///  - dateSent is the sender's time, but never later than the time this
///    device received the message: a sender with a fast clock cannot put its
///    messages after everyone else's.
///  - The three write methods touch only the database. Files are deleted,
///    and anything the user sees is triggered, in committed() — which the
///    messaging layer calls only after the transaction committed.
///  - System lines are type "system" rows with English text and, in their
///    metadata, the event itself ({gv2Event, by, about, title, revision}):
///    the text is what shows until a screen words the event in the user's
///    language. Their ids are deterministic (group, revision, position), so
///    an entry seen twice writes one line.
///  - A message that cannot be read (yet) is a "system" row with the status
///    decryption_failed — what the chat shows as a message that could not
///    be decrypted — stored under the id the message itself would get, with
///    no sender and counted as nothing unread. When the key comes the
///    message is stored over it (same id) and counts like any message.
///  - groupChanged() tells the app (onGroupChanged) only after the
///    conversation row and the system lines are written: what the app then
///    reads is what the change left.
///  - Nothing here logs: messages, groups and senders.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../group_v2/gv2_codec.dart';
import '../group_v2/gv2_events.dart';
import '../group_v2/gv2_messaging.dart';
import '../group_v2/gv2_store.dart';
import '../storage/daos/attachment_dao.dart';
import '../storage/daos/conversation_dao.dart';
import '../storage/daos/message_dao.dart';
import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';

/// The longest disappearing-message timer a payload may ask for (the
/// server keeps nothing longer either).
const int gv2MaxTtlSeconds = 30 * 24 * 60 * 60;

/// The app's message payload.
class Gv2AppMessagePayload {
  static const Set<String> types = {'text', 'file', 'voice'};

  final String text;

  /// One of [types].
  final String type;
  final Map<String, dynamic>? metadata;

  /// Disappearing-message timer in SECONDS; 0 = none.
  final int ttlSeconds;
  final String? replyToId;
  final String? replyToPreview;
  final String? replyToSenderId;

  Gv2AppMessagePayload({
    required this.text,
    this.type = 'text',
    this.metadata,
    this.ttlSeconds = 0,
    this.replyToId,
    this.replyToPreview,
    this.replyToSenderId,
  }) {
    if (!types.contains(type)) {
      throw ArgumentError('gv2 payload: unknown message type');
    }
    if (ttlSeconds < 0 || ttlSeconds > gv2MaxTtlSeconds) {
      throw ArgumentError('gv2 payload: ttl out of range');
    }
  }

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'text': text,
        'type': type,
        if (metadata != null) 'metadata': metadata,
        if (ttlSeconds > 0) 'ttl': ttlSeconds,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToPreview != null) 'replyToPreview': replyToPreview,
        if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      }),
    ),
  );

  /// The payload in [bytes], or null when they are not one. A field of the
  /// wrong type makes the whole payload unreadable (nothing is guessed);
  /// an unknown message type is read as text, so that a newer build's
  /// message still shows its text.
  static Gv2AppMessagePayload? tryDecode(Uint8List bytes) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;
    final text = json['text'];
    final type = json['type'];
    final metadata = json['metadata'];
    final ttl = json['ttl'] ?? 0;
    final replyToId = json['replyToId'];
    final replyToPreview = json['replyToPreview'];
    final replyToSenderId = json['replyToSenderId'];
    if (text is! String ||
        (type != null && type is! String) ||
        (metadata != null && metadata is! Map) ||
        ttl is! int ||
        ttl < 0 ||
        ttl > gv2MaxTtlSeconds ||
        (replyToId != null && replyToId is! String) ||
        (replyToPreview != null && replyToPreview is! String) ||
        (replyToSenderId != null && replyToSenderId is! String)) {
      return null;
    }
    return Gv2AppMessagePayload(
      text: text,
      type: types.contains(type) ? type as String : 'text',
      metadata: metadata == null
          ? null
          : Map<String, dynamic>.from(metadata as Map),
      ttlSeconds: ttl,
      replyToId: replyToId as String?,
      replyToPreview: replyToPreview as String?,
      replyToSenderId: replyToSenderId as String?,
    );
  }
}

/// At most this many "cannot be read" places a group's chat shows at a
/// time (Gv2AppMessageSink.waiting).
const int gv2WaitingShownPerGroup = 50;

/// A message that was stored and committed: what its follow-ups need.
class Gv2StoredMessage {
  final String groupId;
  final String messageId;
  final String senderSnowId;
  final Gv2AppMessagePayload payload;

  /// Whether the group's chat was open when the message was stored (it was
  /// then stored as read, with its disappearing timer started).
  final bool viewing;

  /// The group's name and the sender's nickname, as far as this device
  /// knows them.
  final String? groupName;
  final String? senderName;
  final int receivedAtMs;

  const Gv2StoredMessage({
    required this.groupId,
    required this.messageId,
    required this.senderSnowId,
    required this.payload,
    required this.viewing,
    required this.groupName,
    required this.senderName,
    required this.receivedAtMs,
  });
}

class Gv2AppMessageSink implements Gv2MessageSink {
  final Gv2Store _groups;
  final MessageDao _messages;
  final ConversationDao _conversations;
  final AttachmentDao _attachments;
  final bool Function(String conversationId) _viewing;
  final Future<String> Function() _documentsDir;
  final void Function(Gv2StoredMessage stored) _onStored;
  final void Function(String groupId) _onRemoved;
  final void Function(String groupId) _onWaiting;
  final void Function(String groupId, List<Gv2Entry> applied) _onGroupChanged;
  final int Function() _nowMs;

  /// What committed() announces, by local message id.
  final Map<String, Gv2StoredMessage> _stored = {};

  /// Attachment files to delete once the removal of their rows committed,
  /// by what removed them.
  final Map<String, List<String>> _files = {};

  /// [viewing]: whether a conversation is open on screen. [documentsDir]:
  /// the directory attachment paths are relative to. [onStored] /
  /// [onRemoved] / [onWaiting] / [onGroupChanged] run after the commit.
  Gv2AppMessageSink({
    required Gv2Store groups,
    required MessageDao messages,
    required ConversationDao conversations,
    required AttachmentDao attachments,
    required bool Function(String conversationId) viewing,
    required Future<String> Function() documentsDir,
    required void Function(Gv2StoredMessage stored) onStored,
    required void Function(String groupId) onRemoved,
    void Function(String groupId)? onWaiting,
    void Function(String groupId, List<Gv2Entry> applied)? onGroupChanged,
    int Function()? nowMs,
  }) : _groups = groups,
       _messages = messages,
       _conversations = conversations,
       _attachments = attachments,
       _viewing = viewing,
       _documentsDir = documentsDir,
       _onStored = onStored,
       _onRemoved = onRemoved,
       _onWaiting = onWaiting ?? ((_) {}),
       _onGroupChanged = onGroupChanged ?? ((_, _) {}),
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  // ---------------------------------------------------------------------------
  // Inside the inbox transaction: the database only
  // ---------------------------------------------------------------------------

  @override
  Future<void> message(Gv2IncomingMessage message) async {
    final payload = Gv2AppMessagePayload.tryDecode(message.payload);
    if (payload == null) return; // not a payload this build reads
    final groupId = message.groupId;
    final group = await _groups.group(groupId);
    final from = await _groups.memberBySnowId(groupId, message.senderSnowId);
    await _conversations.findOrCreate(
      id: groupId,
      type: 'group',
      participantIds: const [],
      title: group?.title,
      groupId: groupId,
    );

    final viewing = _viewing(groupId);
    final now = _nowMs();
    final ttl = payload.ttlSeconds;
    final metadata = payload.metadata;
    // One message per (sender, time, conversation) fits the table: two of
    // one sender at the same millisecond are stored a millisecond apart.
    final dateSent = await _messages.freeDateSent(
      conversationId: groupId,
      sender: message.senderSnowId,
      dateSent: min(message.sentAtMs, message.receivedAtMs),
      messageId: message.localMessageId,
    );
    await _messages.insertIncomingMessage(
      message: LocalMessagesCompanion(
        id: Value(message.localMessageId),
        conversationId: Value(groupId),
        senderSnowchatId: Value(message.senderSnowId),
        plaintext: Value(payload.text),
        dateSent: Value(dateSent),
        dateReceived: Value(message.receivedAtMs),
        type: Value(payload.type),
        metadata: Value(metadata == null ? null : jsonEncode(metadata)),
        expiresIn: Value(ttl),
        expireStarted: Value(viewing && ttl > 0 ? now : 0),
        read: Value(viewing),
        outgoingStatus: const Value('delivered'),
        senderDisplayName: Value(from?.nickname),
        replyToId: Value(payload.replyToId),
        replyToPreview: Value(payload.replyToPreview),
        replyToSenderId: Value(payload.replyToSenderId),
      ),
      conversationId: groupId,
      snippetText: payload.text,
      receivedTimestamp: now,
      senderId: message.senderSnowId,
      mentionsSelf: false,
      isCurrentlyViewing: viewing,
    );
    _stored[message.localMessageId] = Gv2StoredMessage(
      groupId: groupId,
      messageId: message.localMessageId,
      senderSnowId: message.senderSnowId,
      payload: payload,
      viewing: viewing,
      groupName: group?.title,
      senderName: from?.nickname,
      receivedAtMs: now,
    );
  }

  @override
  Future<void> unsent({
    required String groupId,
    required String localMessageId,
    required String senderSnowId,
  }) async {
    final row = await _messages.getMessageById(localMessageId);
    // The id can only name a message of the unsender (it is built from its
    // account); the row is compared all the same.
    if (row == null ||
        row.conversationId != groupId ||
        row.senderSnowchatId != senderSnowId) {
      return;
    }
    _files[_unsendKey(localMessageId)] = await _removeAttachments([
      localMessageId,
    ]);
    await _messages.deleteMessage(localMessageId);
  }

  @override
  Future<void> historyCleared({
    required String groupId,
    required int beforeMs,
    required String bySnowId,
  }) async {
    final ids = await _messages.messageIdsSentBefore(groupId, beforeMs);
    _files[_clearKey(groupId, beforeMs)] = await _removeAttachments(ids);
    await _messages.deleteMessagesSentBefore(groupId, beforeMs);
  }

  @override
  Future<bool> waiting({
    required String groupId,
    required String localMessageId,
    required int sentAtMs,
    required int receivedAtMs,
  }) async {
    if (await _messages.getMessageById(localMessageId) != null) return false;
    // Only where the group has a conversation (this account is a member).
    if (await _conversations.getConversation(groupId) == null) return false;
    // At most gv2WaitingShownPerGroup at a time: the header that asks for a
    // place is not verified (anyone who holds the master key and a send
    // token could fill the chat with them). Beyond, the message still waits
    // for its key — it is shown when the key comes — but gets no place.
    if (await _messages.countWaitingPlaces(
          groupId,
          atMost: gv2WaitingShownPerGroup,
        ) >=
        gv2WaitingShownPerGroup) {
      return false;
    }
    final dateSent = await _messages.freeDateSent(
      conversationId: groupId,
      sender: '',
      dateSent: min(sentAtMs, receivedAtMs),
      messageId: localMessageId,
    );
    await _messages.upsertMessage(
      LocalMessagesCompanion(
        id: Value(localMessageId),
        conversationId: Value(groupId),
        senderSnowchatId: const Value(''),
        plaintext: const Value(''),
        dateSent: Value(dateSent),
        dateReceived: Value(receivedAtMs),
        type: const Value('system'),
        read: const Value(true),
        outgoingStatus: const Value('decryption_failed'),
        metadata: Value(jsonEncode({'gv2Waiting': true})),
      ),
    );
    return true;
  }

  /// Delete the attachment rows of [messageIds]; returns the paths of their
  /// local files (deleted after the commit).
  Future<List<String>> _removeAttachments(List<String> messageIds) async {
    final paths = <String>[];
    for (final id in messageIds) {
      final rows = await _attachments.getForMessage(id);
      if (rows.isEmpty) continue;
      for (final a in rows) {
        final path = a.localPath;
        if (path != null && path.isNotEmpty) paths.add(path);
      }
      await _attachments.deleteForMessage(id);
    }
    return paths;
  }

  @override
  Future<void> outgoing({
    required String groupId,
    required String localMessageId,
    required bool sent,
  }) =>
      _messages.updateOutgoingStatus(localMessageId, sent ? 'sent' : 'failed');

  static String _unsendKey(String localMessageId) => 'unsend:$localMessageId';
  static String _clearKey(String groupId, int beforeMs) =>
      'clear:$groupId:$beforeMs';

  // ---------------------------------------------------------------------------
  // After the commit
  // ---------------------------------------------------------------------------

  @override
  void committed(Gv2SinkEvent event) {
    switch (event) {
      case Gv2MessageStored(:final message):
        final stored = _stored.remove(message.localMessageId);
        if (stored != null) _onStored(stored);
      case Gv2MessageUnsent(:final groupId, :final localMessageId):
        _deleteFiles(_files.remove(_unsendKey(localMessageId)));
        _onRemoved(groupId);
      case Gv2HistoryCleared(:final groupId, :final beforeMs):
        _deleteFiles(_files.remove(_clearKey(groupId, beforeMs)));
        _onRemoved(groupId);
      case Gv2MessageWaiting(:final groupId):
        // The chat shows the new row; the list's preview does not change.
        _onWaiting(groupId);
    }
  }

  @override
  void groupChanged(String groupId, List<Gv2Entry> applied) {
    unawaited(() async {
      await _mirrorConversation(groupId);
      await _systemLines(groupId, applied);
      _onGroupChanged(groupId, applied);
    }());
  }

  /// Write what [applied] did into the group's conversation, one system
  /// line per event (design §9.6: made here from the verified log — the
  /// server writes none). A line is written once (its id is the entry's
  /// place in the log), only while the conversation exists, and carries the
  /// event in its metadata so that a screen can word it in its language.
  Future<void> _systemLines(String groupId, List<Gv2Entry> applied) async {
    if (applied.isEmpty) return;
    try {
      final group = await _groups.group(groupId);
      if (group == null) return;
      final me = (await _groups.member(groupId, group.myCiphertext))?.snowId;
      final names = <String, String?>{
        for (final m in await _groups.memberRows(groupId))
          if (m.snowId != null) m.snowId!: m.nickname,
      };
      String name(String? snowId) {
        if (snowId == null) return 'Someone';
        if (snowId == me) return 'You';
        final known = names[snowId];
        if (known != null && known.isNotEmpty) return known;
        return snowId.length > 12
            ? '${snowId.substring(0, 8)}…${snowId.substring(snowId.length - 4)}'
            : snowId;
      }

      // Whether the conversation exists and the lines written into it, in
      // one transaction: a chat removed meanwhile (a leave that was made)
      // got "You left" after its removal, a line of no conversation that
      // showed again after a re-invite.
      await _messages.transaction(() async {
        if (await _conversations.getConversation(groupId) == null) return;
        for (final entry in applied) {
          final events = gv2DescribeEntry(
            masterKey: group.masterKey,
            groupId: gv2Unhex(groupId),
            entry: entry,
          );
          for (var i = 0; i < events.length; i++) {
            final event = events[i];
            final id =
                'gv2sys_${groupId.substring(0, 16)}_${entry.revision}_$i';
            if (await _messages.getMessageById(id) != null) continue;
            final text = _wording(event, name);
            final now = _nowMs();
            final dateSent = await _messages.freeDateSent(
              conversationId: groupId,
              sender: '',
              dateSent: now,
              messageId: id,
            );
            await _messages.insertIncomingMessage(
              message: LocalMessagesCompanion(
                id: Value(id),
                conversationId: Value(groupId),
                senderSnowchatId: const Value(''),
                plaintext: Value(text),
                dateSent: Value(dateSent),
                dateReceived: Value(now),
                type: const Value('system'),
                read: const Value(true),
                outgoingStatus: const Value('delivered'),
                metadata: Value(
                  jsonEncode({
                    'gv2Event': event.name,
                    'revision': entry.revision,
                    'by': ?event.by,
                    'about': ?event.about,
                    'title': ?switch (event) {
                      Gv2Created(:final title) => title,
                      Gv2Renamed(:final title) => title,
                      _ => null,
                    },
                  }),
                ),
              ),
              conversationId: groupId,
              snippetText: text,
              receivedTimestamp: now,
              senderId: '',
              mentionsSelf: false,
              // A system line is not something unread.
              isCurrentlyViewing: true,
            );
          }
        }
      });
    } catch (_) {
      // A line that could not be written does not undo the change.
    }
  }

  /// The English wording of [event]; [name] names an account.
  static String _wording(Gv2GroupEvent event, String Function(String?) name) =>
      gv2EventText(
        event: event.name,
        by: name(event.by),
        about: name(event.about),
        title: switch (event) {
          Gv2Renamed(:final title) => title,
          _ => null,
        },
      )!;

  /// Keep the conversation row of [groupId] in step with the group: it
  /// exists (under the group id) while this account is a member, and
  /// carries the group's name. A group this account only was invited to, or
  /// is creating, has no conversation yet; one it left keeps its row and
  /// history.
  Future<void> _mirrorConversation(String groupId) async {
    try {
      final group = await _groups.group(groupId);
      const member = {Gv2Membership.active, Gv2Membership.awaitingConfirm};
      if (group == null || !member.contains(group.membership)) return;
      final row = await _conversations.findOrCreate(
        id: groupId,
        type: 'group',
        participantIds: const [],
        title: group.title,
        groupId: groupId,
      );
      final title = group.title;
      if (title != null && row.title != title) {
        await _conversations.updateTitle(groupId, title);
      }
    } catch (_) {
      // The next change of the group mirrors it again.
    }
  }

  /// Delete decrypted attachment files. Paths are stored relative to the
  /// app documents directory (snowchat_attachments/…).
  void _deleteFiles(List<String>? paths) {
    if (paths == null || paths.isEmpty) return;
    unawaited(() async {
      try {
        final dir = await _documentsDir();
        for (final path in paths) {
          try {
            final file = File(path.startsWith('/') ? path : '$dir/$path');
            if (file.existsSync()) file.deleteSync();
          } catch (_) {
            // One file that cannot be deleted does not keep the others.
          }
        }
      } catch (_) {
        // No documents directory: nothing was deleted.
      }
    }());
  }
}
