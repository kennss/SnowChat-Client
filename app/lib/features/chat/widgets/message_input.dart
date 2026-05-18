/// @file        message_input.dart
/// @description Message-input widget — text input field, send/mic button, attachment / expiring-message timer buttons, typing callback included
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-11 (Reverted voice mic disable in disappearing mode
///              — was based on wrong assumption that voice routes through
///              OpenFilex. Actually voice_message_bubble.dart plays via
///              audioplayers in-app (DeviceFileSource), same threat class as
///              images. Signal/Telegram/WhatsApp all allow voice in
///              disappearing mode. Earlier same-day Tier 2A disabled voice;
///              2026-04-26 header English translation; 2026-04-08 wallet
///              transfer button removed.)
///
/// @functions
///  - MessageInput: StatefulWidget rendering the message-input bar (voice recording / typing indicator supported)
///  - _ttlLabel(): convert TTL seconds value to a short label string

import 'package:flutter/material.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import 'voice_recorder.dart';

/// Callback when a voice recording is completed.
/// [path] — file path to the recorded audio.
/// [duration] — recording duration in seconds.
typedef VoiceRecordingCallback = void Function(String path, int duration);

class MessageInput extends StatefulWidget {
  final void Function(String text) onSend;
  final VoidCallback? onAttachment;
  final VoidCallback? onTimerTap;
  final int? disappearingTTL;
  final VoiceRecordingCallback? onVoiceRecording;

  /// Called each time the user types a character, for typing indicator debounce.
  final VoidCallback? onTypingChanged;

  const MessageInput({
    super.key,
    required this.onSend,
    this.onAttachment,
    this.onTimerTap,
    this.disappearingTTL,
    this.onVoiceRecording,
    this.onTypingChanged,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final _controller = TextEditingController();
  bool _hasText = false;
  bool _isRecording = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    setState(() => _hasText = false);
  }

  static String? _ttlLabel(int? ttl) {
    if (ttl == null) return null;
    // Disappearing options (disappearing_timer_selector.dart): 60, 300,
    // 1800, 3600. Bug 2026-05-07 — earlier the 60-second selection (1m)
    // fell through to the 5m branch because there was no <= 60 bucket.
    // Same bug previously fixed on chat_screen.dart's AppBar label;
    // missed this duplicate copy until tester reported the chip in the
    // input area still showed "5m" after picking 1m.
    if (ttl <= 60) return '1m';
    if (ttl <= 300) return '5m';
    if (ttl <= 1800) return '30m';
    return '1h';
  }

  @override
  Widget build(BuildContext context) {
    // While recording, swap the entire input bar for the VoiceRecorder
    // overlay (hold-to-record, slide-to-cancel, send button). Same footprint
    // — the overlay paints in the same bottom slot as the input row, so the
    // chat scroll area never reflows.
    if (_isRecording && widget.onVoiceRecording != null) {
      return VoiceRecorder(
        onRecordingComplete: (path, duration) {
          widget.onVoiceRecording!(path, duration);
          if (mounted) setState(() => _isRecording = false);
        },
        onCancel: () {
          if (mounted) setState(() => _isRecording = false);
        },
      );
    }

    final ttlLabel = _ttlLabel(widget.disappearingTTL);

    return Container(
      padding: EdgeInsets.only(
        left: SnowSizes.sm,
        right: SnowSizes.sm,
        top: SnowSizes.sm,
        bottom: MediaQuery.of(context).padding.bottom + SnowSizes.sm,
      ),
      decoration: const BoxDecoration(
        color: SnowColors.background,
        border: Border(
          top: BorderSide(color: SnowColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment button
          if (widget.onAttachment != null)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              color: SnowColors.textTertiary,
              iconSize: 22,
              onPressed: widget.onAttachment,
            ),

          // Disappearing timer button
          if (widget.onTimerTap != null)
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: Icon(
                    ttlLabel != null
                        ? Icons.timer_rounded
                        : Icons.timer_off_outlined,
                  ),
                  color: ttlLabel != null
                      ? SnowColors.primary
                      : SnowColors.textTertiary,
                  iconSize: 22,
                  onPressed: widget.onTimerTap,
                ),
                if (ttlLabel != null)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: SnowColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ttlLabel,
                        style: const TextStyle(
                          color: SnowColors.background,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

          // Text input
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: SnowColors.surfaceVariant,
                borderRadius: BorderRadius.circular(SnowSizes.inputRadius),
              ),
              child: TextField(
                controller: _controller,
                onChanged: (text) {
                  setState(() => _hasText = text.trim().isNotEmpty);
                  if (text.trim().isNotEmpty) {
                    widget.onTypingChanged?.call();
                  }
                },
                onSubmitted: (_) => _send(),
                maxLines: null,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 15,
                ),
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 6),

          // Send button (text) or Mic button (voice)
          if (_hasText)
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: SnowColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: SnowColors.background,
                ),
                onPressed: _send,
                padding: EdgeInsets.zero,
              ),
            )
          else if (widget.onVoiceRecording != null)
            GestureDetector(
              // Long-press swaps the input bar for the VoiceRecorder overlay
              // (see top of build()). Real recording is owned by the overlay;
              // this button just flips `_isRecording`.
              onLongPress: () {
                setState(() => _isRecording = true);
              },
              onTap: () {
                // Short-tap hint — WhatsApp/Telegram users expect long-press.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hold to record a voice message'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: SnowColors.surfaceLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mic_rounded,
                  size: 20,
                  color: SnowColors.textTertiary,
                ),
              ),
            )
          else
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: SnowColors.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.send_rounded,
                size: 20,
                color: SnowColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}
