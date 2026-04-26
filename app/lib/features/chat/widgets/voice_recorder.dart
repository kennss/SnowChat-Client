/// @file        voice_recorder.dart
/// @description Voice-message recorder widget — hold to record, release to send, slide-left to cancel, max 5 minutes, AAC format
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-30)
///
/// @functions
///  - VoiceRecorder: voice-recording overlay widget
///  - _VoiceRecorderState: manages recording state, timer, and waveform animation

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
// import 'package:record/record.dart'; // disabled — record_linux incompatibility

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';

/// Callback when a voice recording is completed.
/// [path] — file path to the recorded AAC audio.
/// [duration] — recording duration in seconds.
typedef VoiceRecordingCallback = void Function(String path, int duration);

/// Voice recording widget with hold-to-record, release-to-send, slide-to-cancel.
///
/// - Long press starts recording
/// - Release sends the voice message
/// - Slide left to cancel
/// - Max recording duration: 5 minutes
/// - Output format: AAC/M4A
class VoiceRecorder extends StatefulWidget {
  final VoiceRecordingCallback onRecordingComplete;
  final VoidCallback onCancel;

  const VoiceRecorder({
    super.key,
    required this.onRecordingComplete,
    required this.onCancel,
  });

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

// Stub AudioRecorder until record package is re-enabled
class _StubAudioRecorder {
  Future<bool> hasPermission() async => false;
  Future<void> start(dynamic config, {String? path}) async {}
  Future<String?> stop() async => null;
  void dispose() {}
}

class _VoiceRecorderState extends State<VoiceRecorder>
    with SingleTickerProviderStateMixin {
  final _StubAudioRecorder _recorder = _StubAudioRecorder();

  bool _isRecording = false;
  int _durationSeconds = 0;
  Timer? _timer;
  String? _recordingPath;

  /// Slide offset for cancel gesture (negative = sliding left).
  double _slideOffset = 0.0;
  static const double _cancelThreshold = -100.0;
  static const int _maxDurationSeconds = 300; // 5 minutes

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _startRecording();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _stopRecording(send: false);
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        widget.onCancel();
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        null, // RecordConfig stub
        path: path,
      );

      _recordingPath = path;

      setState(() {
        _isRecording = true;
        _durationSeconds = 0;
      });

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _durationSeconds++;
        });
        // Auto-stop at max duration
        if (_durationSeconds >= _maxDurationSeconds) {
          _stopRecording(send: true);
        }
      });
    } catch (e) {
      debugPrint('[VoiceRecorder] Failed to start recording: $e');
      widget.onCancel();
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _timer?.cancel();

    if (!_isRecording) return;

    setState(() => _isRecording = false);

    try {
      final path = await _recorder.stop();

      if (send && path != null && _durationSeconds > 0) {
        widget.onRecordingComplete(path, _durationSeconds);
      } else {
        // Clean up cancelled recording
        if (_recordingPath != null) {
          final file = File(_recordingPath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
        widget.onCancel();
      }
    } catch (e) {
      debugPrint('[VoiceRecorder] Failed to stop recording: $e');
      widget.onCancel();
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _slideOffset += details.delta.dx;
          _slideOffset = _slideOffset.clamp(-150.0, 0.0);
        });
      },
      onHorizontalDragEnd: (_) {
        if (_slideOffset <= _cancelThreshold) {
          _stopRecording(send: false);
        } else {
          setState(() => _slideOffset = 0.0);
        }
      },
      child: Container(
        padding: EdgeInsets.only(
          left: SnowSizes.md,
          right: SnowSizes.md,
          top: SnowSizes.sm,
          bottom: MediaQuery.of(context).padding.bottom + SnowSizes.sm,
        ),
        decoration: const BoxDecoration(
          color: SnowColors.surface,
          border: Border(
            top: BorderSide(color: SnowColors.divider, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Recording indicator
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SnowColors.error.withValues(
                      alpha: 0.5 + _pulseController.value * 0.5,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(width: SnowSizes.sm),

            // Duration
            Text(
              _formatDuration(_durationSeconds),
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),

            const Spacer(),

            // Slide to cancel hint
            Transform.translate(
              offset: Offset(_slideOffset * 0.5, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    color: SnowColors.textTertiary.withValues(
                      alpha: (_slideOffset.abs() / 100.0).clamp(0.3, 1.0),
                    ),
                    size: 20,
                  ),
                  Text(
                    'Slide to cancel',
                    style: TextStyle(
                      color: SnowColors.textTertiary.withValues(
                        alpha: (_slideOffset.abs() / 100.0).clamp(0.3, 1.0),
                      ),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: SnowSizes.sm),

            // Send button
            GestureDetector(
              onTap: () => _stopRecording(send: true),
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: SnowColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: SnowColors.background,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
