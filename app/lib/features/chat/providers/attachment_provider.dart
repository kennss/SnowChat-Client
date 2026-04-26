/// @file        attachment_provider.dart
/// @description Attachment Riverpod Provider — real-time watch of attachments per message
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-02
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-04-02)
///
/// @functions
///  - attachmentWatchProvider: real-time watch of the attachment list per message ID

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../../../core/storage/database.dart';

/// Watch attachments for a specific message (reactive stream).
/// Used by ImageMessageBubble and FileMessageBubble to auto-update
/// when download completes (transferState changes).
final attachmentWatchProvider =
    StreamProvider.family<List<LocalAttachment>, String>(
  (ref, messageId) {
    ref.keepAlive(); // Prevent dispose during ListView rebuilds
    final dao = ref.read(attachmentDaoProvider);
    return dao.watchForMessage(messageId);
  },
);
