/// @file        callkit_manager_test.dart
/// @description What CallKitManager hands the flutter_callkit_incoming plugin (mocked method
///              channel): showIncoming is anonymous ("SnowChat Call", empty handle) and both iOS
///              paths pass includesCallsInRecents=false (core/call/CLAUDE.md §7.1);
///              startOutgoing carries the given name and an empty handle; updateCallerName sends
///              the window id and name, and nothing for an empty name.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-23
/// @lastUpdated 2026-11-23
///
/// @functions
///  - main(): the cases

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/call/callkit_manager.dart';

const _callId = '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel('flutter_callkit_incoming');
  // The event channel's listen / cancel calls go over this method channel.
  const events = MethodChannel('flutter_callkit_incoming_events');

  late List<MethodCall> calls;
  late CallKitManager manager;

  setUp(() {
    calls = [];
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return true;
    });
    messenger.setMockMethodCallHandler(events, (_) async => null);
    manager = CallKitManager();
  });

  tearDown(() async {
    await manager.dispose();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  Map<String, dynamic> argsOf(String method) {
    final call = calls.singleWhere((c) => c.method == method);
    return Map<String, dynamic>.from(call.arguments as Map);
  }

  test('showIncoming: anonymous, empty handle, not in Recents', () async {
    await manager.showIncoming(callId: _callId);
    final args = argsOf('showCallkitIncoming');
    expect(args['id'], _callId);
    expect(args['nameCaller'], 'SnowChat Call');
    expect(args['handle'], '');
    expect((args['ios'] as Map)['includesCallsInRecents'], isFalse);
  });

  test('startOutgoing: the given name, empty handle, not in Recents', () async {
    await manager.startOutgoing(callId: _callId, calleeName: 'Alice');
    final args = argsOf('startCall');
    expect(args['nameCaller'], 'Alice');
    expect(args['handle'], '');
    expect((args['ios'] as Map)['includesCallsInRecents'], isFalse);
  });

  test('updateCallerName: id and name to the plugin', () async {
    await manager.updateCallerName(callId: _callId, callerName: 'Alice');
    expect(argsOf('updateCallerName'), {'id': _callId, 'nameCaller': 'Alice'});
  });

  test('updateCallerName: an empty name is not sent', () async {
    await manager.updateCallerName(callId: _callId, callerName: '');
    expect(calls.where((c) => c.method == 'updateCallerName'), isEmpty);
  });
}
