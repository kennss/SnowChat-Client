/// @file        voip_native_bridge.dart
/// @description MethodChannel `snowchat/voip_native` — Dart-side counterpart
///              to VoipNativeBridge.swift. Bridges four flows:
///
///                Dart → Native:
///                  - setBaseUrl(url): push resolved API base before any
///                    accept can fetch.
///                  - drainPending(): request immediate drain (idempotent).
///                  - ack(nonce): tell native this nonce is fully handed off
///                    to call_provider (coordinator already drops on drain).
///
///                Native → Dart (incoming MethodCall):
///                  - voipAcceptedEnvelopes: { nonce, envelopes:List<String> }
///                    Coordinator finished fetching /calls/pending/<nonce>;
///                    Dart should inject the envelopes and accept the call.
///                  - audioSessionActivated: { sampleRate:Double }
///                    AppDelegate.providerDidActivateAudioSession backup path —
///                    fires alongside the plugin's ACTION_CALL_TOGGLE_AUDIO_SESSION
///                    EventChannel broadcast. CallService awaits whichever
///                    arrives first.
///                  - audioSessionDeactivated: {}
///                    Telemetry only — cleanup is end-call-driven, not session-driven.
///                  - systemReset: {}
///                    CallKit provider:didReset → trigger CallService cleanup.
///
///              iOS-only. On Android the channel is unused (Android has no
///              CallKit-accept-then-fetch model — accept is in-process, audio
///              session is managed by ConnectionService).
///
///              P4 (v3.1): the events stream is *replay-buffered* until at
///              least one listener attaches, so a hot-restart drain that
///              fires before Riverpod has rebuilt the listener doesn't lose
///              the envelope. Buffer is capped at 16 entries to bound memory
///              if a never-listening environment exists (defensive only).
///
///              v2.5 (2026-05-03): channel is single-owner now. Earlier
///              CallService.dart registered its OWN setMethodCallHandler on
///              the same channel for audio session events; whichever provider
///              initialized last won, silently dropping the other side's
///              method calls. Bridge owns the channel exclusively and exposes
///              audio session / system reset events as broadcast streams.
///              CallService subscribes via `wireNativeBridge` from the
///              callServiceProvider in providers.dart.
///
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-30
/// @lastUpdated 2026-05-03 (v2.5: channel single-owner refactor — added
///              audioSessionActivated/Deactivated/systemReset streams. Replaces
///              the conflicting setMethodCallHandler in CallService.)
///
/// @functions
///  - VoipNativeBridge: bridge class
///  - VoipNativeBridge.start(): attach handler (idempotent)
///  - VoipNativeBridge.setBaseUrl(url): push API base to native
///  - VoipNativeBridge.drainPending(): request native drain
///  - VoipNativeBridge.ack(nonce): mark hand-off complete
///  - VoipNativeBridge.events: stream of accepted-call envelopes
///  - VoipNativeBridge.audioSessionActivated: stream of CallKit didActivate
///  - VoipNativeBridge.audioSessionDeactivated: stream of CallKit didDeactivate
///  - VoipNativeBridge.systemReset: stream of CallKit provider:didReset
///  - VoipAcceptedEvent: event class (nonce, envelopes)

library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VoipAcceptedEvent {
  final String nonce;
  final List<String> envelopes;
  const VoipAcceptedEvent({required this.nonce, required this.envelopes});
}

class VoipNativeBridge {
  static const _channelName = 'snowchat/voip_native';
  static const int _bufferCap = 16;

  final MethodChannel _channel = const MethodChannel(_channelName);

  // P4: replay buffer for events that arrive before a listener is attached.
  // This handles the cold-launch + hot-restart race where the native
  // CallAcceptCoordinator drains the queue immediately on attachMessenger,
  // but the Dart Riverpod listener has not yet been wired up.
  final List<VoipAcceptedEvent> _pending = [];
  StreamController<VoipAcceptedEvent>? _controller;
  bool _started = false;

  // v2.5 — Audio session / system reset broadcast streams. CallService
  // subscribes via the providers.dart wiring; the channel handler is owned
  // exclusively by this class so audio-session methods don't collide with
  // voipAcceptedEnvelopes (the previous design had two competing
  // setMethodCallHandler calls, second overwrote first).
  final _audioSessionActivatedController = StreamController<void>.broadcast();
  final _audioSessionDeactivatedController = StreamController<void>.broadcast();
  final _systemResetController = StreamController<void>.broadcast();

  Stream<void> get audioSessionActivated =>
      _audioSessionActivatedController.stream;
  Stream<void> get audioSessionDeactivated =>
      _audioSessionDeactivatedController.stream;
  Stream<void> get systemReset => _systemResetController.stream;

  /// Stream of envelopes drained from native after a CallKit accept.
  /// First subscribe replays any buffered events.
  Stream<VoipAcceptedEvent> get events {
    if (_controller != null) return _controller!.stream;
    final controller = StreamController<VoipAcceptedEvent>.broadcast(
      onListen: () {
        // Replay buffered events to the new listener.
        if (_pending.isEmpty) return;
        for (final e in List<VoipAcceptedEvent>.from(_pending)) {
          _controller?.add(e);
        }
        _pending.clear();
      },
    );
    _controller = controller;
    return controller.stream;
  }

  /// Idempotent — calling twice is a no-op (matches Provider lifetime).
  void start() {
    if (!Platform.isIOS) return;
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler(_onMethodCall);
    debugPrint('[VoipNativeBridge] handler attached');
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'voipAcceptedEnvelopes':
        final args = call.arguments;
        if (args is! Map) return null;
        final nonce = args['nonce'];
        final raw = args['envelopes'];
        if (nonce is! String || raw is! List) return null;
        final envelopes =
            raw.whereType<String>().where((e) => e.isNotEmpty).toList();
        if (envelopes.isEmpty) return null;
        debugPrint(
            '[VoipNativeBridge] drain nonce=${nonce.length >= 8 ? nonce.substring(0, 8) : nonce} envCount=${envelopes.length}');
        _emit(VoipAcceptedEvent(nonce: nonce, envelopes: envelopes));
        return null;
      case 'audioSessionActivated':
        if (!_audioSessionActivatedController.isClosed) {
          _audioSessionActivatedController.add(null);
        }
        return null;
      case 'audioSessionDeactivated':
        if (!_audioSessionDeactivatedController.isClosed) {
          _audioSessionDeactivatedController.add(null);
        }
        return null;
      case 'systemReset':
        if (!_systemResetController.isClosed) {
          _systemResetController.add(null);
        }
        return null;
      default:
        return null;
    }
  }

  void _emit(VoipAcceptedEvent event) {
    final c = _controller;
    if (c != null && c.hasListener && !c.isClosed) {
      c.add(event);
      return;
    }
    // Buffer — first listener will drain in onListen.
    _pending.add(event);
    if (_pending.length > _bufferCap) {
      _pending.removeAt(0);
    }
  }

  /// Push the API base URL (e.g. https://snowchat.calidalab.ai/api/v2) to
  /// native. Coordinator will defer all fetches until this is set.
  Future<void> setBaseUrl(String url) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('setBaseUrl', {'url': url});
    } catch (e) {
      debugPrint('[VoipNativeBridge] setBaseUrl failed: $e');
    }
  }

  Future<void> drainPending() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('drainPending');
    } catch (_) {/* ignore */}
  }

  Future<void> ack(String nonce) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>('ack', {'nonce': nonce});
    } catch (_) {/* ignore */}
  }

  void dispose() {
    _controller?.close();
    _controller = null;
    _pending.clear();
    _audioSessionActivatedController.close();
    _audioSessionDeactivatedController.close();
    _systemResetController.close();
  }
}
