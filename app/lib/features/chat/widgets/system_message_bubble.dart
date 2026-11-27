/// @file        system_message_bubble.dart
/// @description System-message bubble widget — renders group-event (member added/removed, name change, etc.) system notices
///              as centered gray text. Phase 10: includes decryption-failed placeholder rendering.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-11-27 (wallet removed: no transfer_completed bubble, no explorer link).
///              Earlier 2026-11-21 (no safety_number_changed bubble — nothing writes that event since the legacy TOFU policy is gone). Earlier 2026-11-20 (group protocol v2: a line that carries a group event is worded here
///              with the names the user knows the accounts by — _Gv2EventLine; a v2 message
///              whose key has not come says that it may still arrive).
///              Earlier 2026-05-06 (missed-call countdown anchor switched from
///              metadata['insertedAtMs'] to ChatScreen's _screenEnteredAt
///              when provided. Tester report 2026-05-06 — "user enters chat
///              several minutes after a missed call and barely sees the
///              countdown" — fixed by giving them up to the full 5-minute
///              window from when they actually see the bubble. drift
///              row expiry stays insertion-based per call/CLAUDE.md §2.2
///              zero-trace cap. Earlier 2026-04-26: header English
///              translation; 2026-04-20 Wallet V2 Phase G:
///              _TransferCompletedBubble.)
///
/// @functions
///  - SystemMessageBubble: StatelessWidget rendering WhatsApp-style system messages
///  - _buildDecryptionFailedBubble(): decryption-failed placeholder UI (lock icon + guidance copy)
///  - _Gv2EventLine: a change of a group protocol v2 group, worded with local names
///  - _MissedCallBubble: missed call — 5-min countdown + red call_missed icon (StatefulWidget)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart' show currentSnowIdProvider;
import '../../../core/group_v2/gv2_events.dart' show gv2EventText;
import '../../group/providers/group_detail_provider.dart';
import '../../group/providers/gv2_group_provider.dart';
import '../../../shared/constants/colors.dart';
import '../models/message.dart';

/// WhatsApp-style centered system message (no sender bubble).
/// Used for group events like member added/removed, name changes, etc.
/// Also renders decryption failure placeholders (Phase 10 P0-B).
class SystemMessageBubble extends StatelessWidget {
  final Message message;

  /// 2026-05-06: missed-call countdown anchor. Passed down from ChatScreen
  /// so every missed-call bubble in the same chat session shares the same
  /// "entered at" timestamp. Optional for back-compat — null falls back
  /// to the metadata insertedAt anchor (legacy behaviour).
  final DateTime? screenEnteredAt;

  const SystemMessageBubble({
    super.key,
    required this.message,
    this.screenEnteredAt,
  });

  /// Returns the message metadata map, or an empty map if absent.
  Map<String, dynamic> _decodeMetadata() {
    final raw = message.metadata;
    if (raw == null) return const {};
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    // Phase 10 P0-B: decryption failure placeholder
    if (message.status == MessageStatus.decryptionFailed) {
      return _buildDecryptionFailedBubble(context);
    }

    final metadata = _decodeMetadata();
    final eventType = metadata['eventType'] as String?;
    // V1.0.1: missed-call system message — dynamic countdown display.
    // Per call/CLAUDE.md §2.2 restrictive notification policy (forced 5-min TTL).
    // Phase I follow-up (2026-04-21): caller-side busy/offline result messages
    // also render the same bubble — reuses the 5-min TTL countdown.
    if (eventType == 'missed_voice_call' ||
        (eventType != null && eventType.startsWith('outgoing_voice_call_'))) {
      return _MissedCallBubble(
        message: message,
        metadata: metadata,
        screenEnteredAt: screenEnteredAt,
      );
    }
    // Group protocol v2: a change of the group, worded here with the names
    // this user knows the accounts by (the stored text names them by
    // nickname or id).
    if (metadata['gv2Event'] is String) {
      return _Gv2EventLine(message: message, metadata: metadata);
    }

    return _plainLine(message.plaintext);
  }

  static Widget _plainLine(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SnowColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: SnowColors.textTertiary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// Renders a decryption failure placeholder with a lock icon and (legacy doc).
  /// Below: missed call bubble with live countdown (Auto-deletes in mm:ss).
  /// informative text. Matches Signal's "Waiting for this message.
  /// This may take a moment." UX pattern.
  Widget _buildDecryptionFailedBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: SnowColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: SnowColors.textTertiary.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: SnowColors.textTertiary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  // A v2 group message whose key has not come: only its
                  // sender's device can give the key.
                  _decodeMetadata()['gv2Waiting'] == true
                      ? 'This message cannot be read yet. It appears once '
                          'its sender is back online.'
                      : 'Waiting for this message. This may take a moment.',
                  style: TextStyle(
                    color: SnowColors.textTertiary.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// V1.0.1: missed-call bubble — forced 5-min TTL countdown (Auto-deletes in mm:ss).
/// 1-second setState driven off the chat-screen-entered anchor (preferred) or
/// `metadata['insertedAtMs']` (legacy fallback). call/CLAUDE.md §2.2.
///
/// 2026-05-06 anchor change: when ChatScreen provides `screenEnteredAt`, the
/// countdown starts from the moment the user opened the chat, not from when
/// the system message was inserted. Earlier behaviour gave the user only
/// the residual portion of the 5-minute window — if they opened the chat 4
/// minutes after the call, they had 1 minute or less to act on the
/// callback hint. Anchoring on the screen-open moment gives them up to the
/// full 5 minutes from the time they actually see the bubble. drift expiry
/// remains insertion-based, so the bubble may unmount earlier than the
/// countdown suggests when the row deletes — that is expected behaviour
/// (zero-trace cap, not a bug).
class _MissedCallBubble extends StatefulWidget {
  final Message message;
  final Map<String, dynamic> metadata;
  final DateTime? screenEnteredAt;

  const _MissedCallBubble({
    required this.message,
    required this.metadata,
    this.screenEnteredAt,
  });

  @override
  State<_MissedCallBubble> createState() => _MissedCallBubbleState();
}

class _MissedCallBubbleState extends State<_MissedCallBubble> {
  static const _ttl = Duration(minutes: 5);
  Timer? _timer;
  late DateTime _anchor;

  @override
  void initState() {
    super.initState();
    if (widget.screenEnteredAt != null) {
      _anchor = widget.screenEnteredAt!;
    } else {
      // Legacy fallback — used if a future caller renders the bubble
      // outside ChatScreen and does not pass screenEnteredAt. Same
      // semantics as before the 2026-05-06 anchor change.
      final ms = widget.metadata['insertedAtMs'];
      _anchor = ms is int
          ? DateTime.fromMillisecondsSinceEpoch(ms)
          : DateTime.now();
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration get _remaining {
    final elapsed = DateTime.now().difference(_anchor);
    final remaining = _ttl - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatRemaining(Duration d) {
    final mm = d.inMinutes.toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    const accent = SnowColors.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call_missed, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.message.plaintext,
                      style: const TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Auto-deletes in ${_formatRemaining(_remaining)}',
                style: TextStyle(
                  color: accent.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The system line of a change in a group protocol v2 group. The row holds
/// the event itself ({gv2Event, by, about, title}); the accounts are named
/// here in the order of design §5.7 — "You", a contact's or friend's name,
/// the nickname looked up for the member, a short form of the id. A name is
/// for reading only: who did what was decided by the group's change log.
class _Gv2EventLine extends ConsumerWidget {
  final Message message;
  final Map<String, dynamic> metadata;

  const _Gv2EventLine({required this.message, required this.metadata});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentSnowIdProvider);
    final known = ref.watch(gv2KnownNamesProvider);
    final members = ref.watch(groupDetailProvider(message.conversationId)).members;

    String name(Object? snowId) {
      if (snowId is! String || snowId.isEmpty) return 'Someone';
      if (snowId == me) return 'You';
      String? nickname;
      for (final m in members) {
        if (m.snowchatId == snowId) nickname = m.displayName;
      }
      return gv2DisplayName(snowId, known: known, nickname: nickname);
    }

    final title = metadata['title'];
    final text = gv2EventText(
      event: metadata['gv2Event'] as String,
      by: name(metadata['by']),
      about: name(metadata['about']),
      title: title is String ? title : null,
    );
    return SystemMessageBubble._plainLine(text ?? message.plaintext);
  }
}
