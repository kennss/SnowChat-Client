/// @file        message.dart
/// @description Message model definition — chat message data structure, reply/quote, deletion state, file/voice metadata handling
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-12 Phase 10: added decryptionFailed state — for placeholder messages)
///
/// @functions
///  - MessageType: message type enum (text, file, voice, system)
///  - MessageStatus: message send-status enum (sending, sent, delivered, read, failed, decryptionFailed)
///  - Message: chat message data model class
///  - isMine(): checks whether the message was sent by me
///  - copyWith(): immutable copy method
///  - ttlSeconds: expiring-message TTL (in seconds, null = don't delete)
///  - isExpired: checks whether the message has expired
///  - replyToId: target message ID for reply (null = not a reply)
///  - replyToPreview: preview text of the reply target message
///  - isDeleted: whether the message is deleted
///  - isImageFile: checks whether this is an image file message
///  - fileId/fileKey/fileName/fileMimeType/fileSize: file metadata accessors

enum MessageType { text, file, voice, system }

enum MessageStatus { sending, sent, delivered, read, failed, decryptionFailed }

class Message {
  final String id;
  final String conversationId;
  final String senderSnowchatId;
  final String plaintext;
  final DateTime timestamp;
  final MessageType type;
  final MessageStatus status;
  final Map<String, dynamic>? metadata;
  final DateTime? expiresAt;
  final int? ttlSeconds;

  /// Reply/quote: ID of the message being replied to.
  final String? replyToId;

  /// Reply/quote: preview text of the original message (from E2EE payload).
  final String? replyToPreview;

  /// Reply/quote: sender SnowChat ID of the original message.
  final String? replyToSenderId;

  /// Whether this message has been deleted (for everyone).
  final bool isDeleted;

  /// Display name of the sender (for group chat sender label).
  final String? senderDisplayName;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderSnowchatId,
    required this.plaintext,
    required this.timestamp,
    this.type = MessageType.text,
    this.status = MessageStatus.sent,
    this.metadata,
    this.expiresAt,
    this.ttlSeconds,
    this.replyToId,
    this.replyToPreview,
    this.replyToSenderId,
    this.isDeleted = false,
    this.senderDisplayName,
  });

  /// Whether this message has expired.
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool isMine(String mySnowId) => senderSnowchatId == mySnowId;

  /// For voice messages, extract duration in seconds.
  int? get voiceDuration => metadata?['duration'] as int?;

  /// For file messages, extract file metadata.
  String? get fileId => metadata?['fileId'] as String?;
  String? get fileKey => metadata?['fileKey'] as String?;
  String? get fileName => metadata?['fileName'] as String?;
  String? get fileMimeType => metadata?['mimeType'] as String?;
  int? get fileSize => metadata?['size'] as int?;

  /// Whether this is an image file message.
  bool get isImageFile =>
      type == MessageType.file &&
      (fileMimeType?.startsWith('image/') ?? false);

  /// Attachment list for multi-attachment messages.
  List<Map<String, dynamic>>? get attachments {
    final att = metadata?['attachments'];
    if (att is List) return att.cast<Map<String, dynamic>>();
    return null;
  }

  /// Number of attachments (supports both single and multi format).
  int get attachmentCount => attachments?.length ?? (fileId != null ? 1 : 0);

  /// Whether all attachments are images.
  bool get isAllImages =>
      attachments?.every(
          (a) => (a['mimeType'] as String? ?? '').startsWith('image/')) ??
      isImageFile;

  Message copyWith({
    String? plaintext,
    MessageStatus? status,
    Map<String, dynamic>? metadata,
    DateTime? expiresAt,
    int? ttlSeconds,
    String? replyToId,
    String? replyToPreview,
    String? replyToSenderId,
    bool? isDeleted,
    String? senderDisplayName,
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderSnowchatId: senderSnowchatId,
      plaintext: plaintext ?? this.plaintext,
      timestamp: timestamp,
      type: type,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
      expiresAt: expiresAt ?? this.expiresAt,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      replyToId: replyToId ?? this.replyToId,
      replyToPreview: replyToPreview ?? this.replyToPreview,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      isDeleted: isDeleted ?? this.isDeleted,
      senderDisplayName: senderDisplayName ?? this.senderDisplayName,
    );
  }
}
