/// @file        voice_message_bubble.dart
/// @description Voice-message bubble widget — play/pause, waveform visualization, playback-speed toggle, dark theme
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - VoiceMessageBubble: StatefulWidget rendering the voice-message bubble
///  - _VoiceMessageBubbleState: manages playback state, speed toggle, and progress bar

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../models/message.dart';

/// Voice message bubble with play/pause, waveform, duration, and speed toggle.
///
/// Design: Session-style dark bubble.
/// - Play/pause button on the left
/// - Waveform progress bar in the middle
/// - Duration label on the right
/// - Speed toggle: 1x → 1.5x → 2x
class VoiceMessageBubble extends StatefulWidget {
  final Message message;
  final bool isMine;

  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();

  bool _isPlaying = false;
  double _progress = 0.0;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;

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
          _progress =
              pos.inMilliseconds / _totalDuration.inMilliseconds;
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

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      final fileId = widget.message.metadata?['fileId'] as String?;
      if (fileId == null) return;

      // In production, this would download and decrypt the file first.
      // For now, attempt to play from a local cache path if available.
      final localPath = widget.message.metadata?['localPath'] as String?;
      if (localPath != null) {
        await _player.play(DeviceFileSource(localPath));
      } else {
        debugPrint('[VoiceMessageBubble] No local audio path available');
      }

      await _player.setPlaybackRate(_playbackSpeed);
    }
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
                      onTap: _togglePlayback,
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
                          _isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
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
