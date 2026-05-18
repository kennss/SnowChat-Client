/// @file        voice_message_bubble.dart
/// @description Voice-message bubble widget — play/pause, waveform visualization, playback-speed toggle, dark theme
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-05-12 (Moved off `metadata['localPath']` onto the
///              attachmentWatchProvider stream — the same path
///              ImageMessageBubble / FileMessageBubble use. Sender now
///              writes a real attachment row in chat_provider; recipient
///              gets one from MessageQueue._processIncomingAttachments
///              after the encrypted blob downloads and decrypts. Until
///              this round voice was a special case that only ever
///              consulted in-memory metadata, so cross-device delivery +
///              receiver-side playback never worked — the metadata-only
///              path didn't even include fileId. resolveAttachmentPath
///              handles iOS container UUID rotation. Earlier 2026-04-26
///              header English translation; 2026-03-30 init.)
///
/// @functions
///  - VoiceMessageBubble: ConsumerStatefulWidget rendering the voice-message bubble
///  - _VoiceMessageBubbleState: manages playback state, speed toggle, and progress bar

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/database.dart';
import '../../../core/storage/tables/attachments_table.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../models/message.dart';
import '../providers/attachment_provider.dart';
import 'image_message_bubble.dart' show resolveAttachmentPath;

/// Voice message bubble with play/pause, waveform, duration, and speed toggle.
///
/// Design: Session-style dark bubble.
/// - Play/pause button on the left
/// - Waveform progress bar in the middle
/// - Duration label on the right
/// - Speed toggle: 1x → 1.5x → 2x
class VoiceMessageBubble extends ConsumerStatefulWidget {
  final Message message;
  final bool isMine;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  ConsumerState<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends ConsumerState<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;
  double _progress = 0.0;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;

  /// Resolved absolute path (from the attachment row). Null until the
  /// download completes on the recipient side.
  String? _resolvedPath;
  String? _lastResolvedFromStored;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _durationSub;

  @override
  void initState() {
    super.initState();
    _setupPlayer();
  }

  void _setupPlayer() {
    final durationSeconds = widget.message.metadata?['duration'] as int? ?? 0;
    _totalDuration = Duration(seconds: durationSeconds);

    _positionSub = _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
        if (_totalDuration.inMilliseconds > 0) {
          _progress = pos.inMilliseconds / _totalDuration.inMilliseconds;
          _progress = _progress.clamp(0.0, 1.0);
        }
      });
    });

    _durationSub = _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() {
        _totalDuration = dur;
      });
    });

    _stateSub = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (state == PlayerState.completed) {
          _progress = 0.0;
          _position = Duration.zero;
        }
      });
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _stateSub?.cancel();
    _durationSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// Kick a resolve when the attachment row's localPath changes. Avoids
  /// re-resolving on every Riverpod rebuild by short-circuiting on the
  /// stored path string.
  void _maybeResolve(LocalAttachment? att) {
    final stored = att?.localPath;
    if (stored == null) {
      if (_resolvedPath != null || _lastResolvedFromStored != null) {
        setState(() {
          _resolvedPath = null;
          _lastResolvedFromStored = null;
        });
      }
      return;
    }
    if (stored == _lastResolvedFromStored && _resolvedPath != null) return;

    _lastResolvedFromStored = stored;
    resolveAttachmentPath(stored).then((abs) {
      if (!mounted) return;
      if (abs == _resolvedPath) return;
      setState(() => _resolvedPath = abs);
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }

    final path = _resolvedPath;
    if (path == null) {
      _showError('Audio not ready yet');
      return;
    }

    try {
      await _player.play(DeviceFileSource(path));
      await _player.setPlaybackRate(_playbackSpeed);
    } catch (e, st) {
      debugPrint('[VoiceMessageBubble] play threw: $e\n$st');
      _showError('Playback failed: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleSpeed() {
    setState(() {
      if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 1.0;
      }
    });
    _player.setPlaybackRate(_playbackSpeed);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final durationSeconds = widget.message.metadata?['duration'] as int? ?? 0;
    final displayDuration = _isPlaying
        ? _position
        : Duration(seconds: durationSeconds);

    final attachments = ref.watch(attachmentWatchProvider(widget.message.id));
    final att = attachments.maybeWhen(
      data: (atts) => atts.isEmpty ? null : atts.first,
      orElse: () => null,
    );
    final isDownloading =
        att != null && att.transferState == TransferState.started;
    final isFailed =
        att != null && att.transferState == TransferState.failed;

    // Schedule resolve outside build to avoid setState-during-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeResolve(att);
    });

    final playReady = _resolvedPath != null;
    final IconData playIcon = _isPlaying
        ? Icons.pause_rounded
        : isDownloading
            ? Icons.downloading_rounded
            : isFailed
                ? Icons.error_outline_rounded
                : playReady
                    ? Icons.play_arrow_rounded
                    : Icons.hourglass_empty_rounded;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
            widget.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(
              maxWidth: SnowSizes.bubbleMaxWidth,
              minWidth: 200,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: SnowSizes.bubblePaddingH,
              vertical: SnowSizes.bubblePaddingV,
            ),
            decoration: BoxDecoration(
              color: widget.isMine
                  ? SnowColors.bubbleOut
                  : SnowColors.bubbleIn,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(SnowSizes.bubbleRadius),
                topRight: const Radius.circular(SnowSizes.bubbleRadius),
                bottomLeft: Radius.circular(
                    widget.isMine ? SnowSizes.bubbleRadius : 4),
                bottomRight: Radius.circular(
                    widget.isMine ? 4 : SnowSizes.bubbleRadius),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Play/Pause button
                    GestureDetector(
                      onTap: playReady ? _togglePlayback : null,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.isMine
                              ? SnowColors.background.withValues(alpha: 0.2)
                              : SnowColors.primary.withValues(alpha: 0.2),
                        ),
                        child: Icon(
                          playIcon,
                          size: 22,
                          color: widget.isMine
                              ? SnowColors.bubbleOutText
                              : SnowColors.primary,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Waveform progress bar
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Waveform visualization (simplified as progress bar)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: SizedBox(
                              height: 24,
                              child: CustomPaint(
                                painter: _WaveformPainter(
                                  progress: _progress,
                                  isMine: widget.isMine,
                                ),
                                size: const Size(double.infinity, 24),
                              ),
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Duration + Speed
                          Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(displayDuration),
                                style: TextStyle(
                                  color: widget.isMine
                                      ? SnowColors.bubbleOutText
                                          .withValues(alpha: 0.6)
                                      : SnowColors.textTertiary,
                                  fontSize: 11,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: _toggleSpeed,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    color: widget.isMine
                                        ? SnowColors.background
                                            .withValues(alpha: 0.15)
                                        : SnowColors.surfaceLight,
                                  ),
                                  child: Text(
                                    '${_playbackSpeed}x',
                                    style: TextStyle(
                                      color: widget.isMine
                                          ? SnowColors.bubbleOutText
                                          : SnowColors.textSecondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for a simplified waveform visualization.
class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool isMine;

  _WaveformPainter({required this.progress, required this.isMine});

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = 3.0;
    final barSpacing = 2.0;
    final totalBars =
        (size.width / (barWidth + barSpacing)).floor();
    final progressedBars = (totalBars * progress).floor();

    final activeColor = isMine
        ? SnowColors.bubbleOutText
        : SnowColors.primary;
    final inactiveColor = isMine
        ? SnowColors.bubbleOutText.withValues(alpha: 0.25)
        : SnowColors.textTertiary.withValues(alpha: 0.3);

    // Generate pseudo-random bar heights for visual interest
    for (var i = 0; i < totalBars; i++) {
      final isActive = i < progressedBars;

      // Deterministic "random" heights based on index
      final seed = ((i * 7 + 3) % 11) / 11.0;
      final barHeight = size.height * (0.3 + seed * 0.7);
      final y = (size.height - barHeight) / 2;

      final paint = Paint()
        ..color = isActive ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * (barWidth + barSpacing),
          y,
          barWidth,
          barHeight,
        ),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
