/// @file        voice_recorder.dart
/// @description Voice-message recorder widget — hold to record, release to send, slide-left to cancel, max 5 minutes, AAC format
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-05-12 (+285 dropped aacLc/m4a for WAV. +284's
///              polling fix assumed record_ios eventually finalized the
///              m4a — iPhone 17 logcat 2026-05-12 02:04 disproved that
///              outright: a 12-second recording with 1-second polling
///              still ended at 28 bytes (ftyp box only, no moov atom).
///              The AAC encoder itself runs fine (ACMP4AACBaseEncoder
///              prints the bitstream config) but record_ios's m4a
///              container wrapping is broken — there's no async race to
///              wait out, the moov atom is simply never written. WAV is
///              raw PCM under a RIFF header whose only mutable field is
///              the data chunk length, patched synchronously inside
///              stop(). File size jumps from ~500 KB (m4a 64 kbps) to
///              ~1.9 MB (wav 16 kHz mono 16-bit) per minute but the
///              E2EE upload path already handles 5 MB+ images, so it's
///              fine. Earlier 2026-05-12 +284 polling fix; +283 size
///              guard; 2026-05-11 real record 6.x AudioRecorder;
///              2026-04-26 header English translation; 2026-03-30 init.)
///
/// @functions
///  - VoiceRecorder: voice-recording overlay widget
///  - _VoiceRecorderState: manages recording state, timer, and waveform animation

library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

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

class _VoiceRecorderState extends State<VoiceRecorder>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();

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
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      // WAV (raw PCM + RIFF header). Originally we shipped aacLc/m4a to
      // match WhatsApp / Signal voice notes, but record 6.x on iOS never
      // writes the m4a moov atom — iPhone 17 logcat 2026-05-12 confirmed
      // that even a 12-second recording with 1-second post-stop polling
      // stayed at 28 bytes (ftyp box only). The AAC encoder itself runs
      // (ACMP4AACBaseEncoder logs the bitstream) but record_ios's m4a
      // wrapping is broken, so AVPlayer rejects every file with AVError
      // -11829 "Cannot Open". WAV sidesteps the container race
      // entirely — the data chunk's length is the only header field that
      // gets patched on stop, and that's done synchronously inside
      // _recorder.stop(). 16 kHz mono 16-bit gives 32 KB/s, so a 1-minute
      // voice note is ~1.9 MB; the existing file/upload path handles 5 MB+
      // images so the size isn't an issue. We can move back to a better
      // codec (opus via record's experimental backend, or a native
      // AVAudioRecorder channel) once record_ios fixes m4a.
      const config = RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );

      await _recorder.start(config, path: path);

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
        // record 6.x iOS race: stop() returns synchronously but the actual
        // m4a moov/mdat finalize lands later inside AudioQueueDispose's
        // async path. iPhone 17 logcat 2026-05-12 captured the exact
        // sequence — `AudioQueueStop: ->immediate` → `AudioQueueDispose:
        // ->async` → file.length() called by us → 28 bytes (ftyp only).
        // A blanket size guard then false-positives 7-second recordings.
        //
        // Poll the file until it grows past the ftyp stub, with a 1-second
        // cap. record_android does this work synchronously inside stop(),
        // so on Galaxy the first read already shows the full size and the
        // loop exits immediately.
        final file = File(path);
        int size = 0;
        final deadline = DateTime.now().add(const Duration(seconds: 1));
        while (DateTime.now().isBefore(deadline)) {
          size = await file.exists() ? await file.length() : 0;
          if (size >= 1024) break;
          await Future.delayed(const Duration(milliseconds: 50));
        }
        debugPrint('[VoiceRecorder] finalize wait done: size=$size '
            'duration=${_durationSeconds}s path=$path');

        if (size < 1024) {
          debugPrint('[VoiceRecorder] discarding truncated recording '
              '($size bytes, duration=${_durationSeconds}s, path=$path)');
          if (await file.exists()) {
            await file.delete();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Recording failed — please try again'),
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 2),
              ),
            );
          }
          widget.onCancel();
          return;
        }
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
