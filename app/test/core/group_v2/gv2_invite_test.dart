/// @file        gv2_invite_test.dart
/// @description Group protocol v2 invite message format: round trip, the
///              bytes are the documented layout (golden vector in
///              test/fixtures/gv2_invite_v1.json, assembled here by hand and
///              compared), and the decoder takes one encoding only.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - main(): format, vector and decoder strictness.
///
/// Notes:
///  - GV2_INVITE_WRITE_VECTORS=1 rewrites the fixture after an INTENDED
///    format change. Every value in it comes from fixed labels.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_invite.dart';

import 'gv2_test_support.dart';

const _fixturePath = 'test/fixtures/gv2_invite_v1.json';

Gv2InviteMessage _invite() => Gv2InviteMessage(
  groupId: gv2TestSha('gv2 invite test — group'),
  masterKey: gv2TestSha('gv2 invite test — master key'),
  revision: 0x01020304,
  chain: gv2TestSha('gv2 invite test — chain'),
  stateHash: gv2TestSha('gv2 invite test — state hash'),
  inviteSeed: gv2TestSha('gv2 invite test — invite seed'),
);

void main() {
  final invite = _invite();
  final built = <String, Object?>{'invite': gv2Hex(invite.encode())};
  if (Platform.environment['GV2_INVITE_WRITE_VECTORS'] == '1') {
    File(_fixturePath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(built)}\n',
    );
  }
  final fixture =
      jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
  final vector = gv2Unhex(fixture['invite'] as String);

  test('the fixture is what this implementation builds', () {
    expect(built, fixture);
  });

  test('the vector is the documented layout', () {
    final byHand = Uint8List.fromList([
      0xF4,
      0x01,
      ...invite.groupId,
      ...invite.masterKey,
      1, 2, 3, 4,
      ...invite.chain,
      ...invite.stateHash,
      ...invite.inviteSeed,
    ]);
    expect(vector, byHand);
    expect(vector.length, gv2InviteLen);
    expect(gv2InviteLen, 166);
    // Not a JSON object by its first byte.
    expect(vector[0], isNot(0x7B));
  });

  test('it decodes to what was encoded', () {
    final back = Gv2InviteMessage.decode(vector)!;
    expect(back.groupId, invite.groupId);
    expect(back.masterKey, invite.masterKey);
    expect(back.revision, 0x01020304);
    expect(back.chain, invite.chain);
    expect(back.stateHash, invite.stateHash);
    expect(back.inviteSeed, invite.inviteSeed);
    expect(back.encode(), vector);
  });

  test('one encoding only', () {
    expect(Gv2InviteMessage.decode(Uint8List.fromList(vector)..[0] = 0x7B), isNull);
    expect(Gv2InviteMessage.decode(Uint8List.fromList(vector)..[1] = 0x02), isNull);
    expect(Gv2InviteMessage.decode(Uint8List.fromList([...vector, 0])), isNull);
    for (var n = 0; n < vector.length; n++) {
      expect(Gv2InviteMessage.decode(vector.sublist(0, n)), isNull, reason: '$n');
    }
  });

  test('the constructor refuses what cannot be encoded', () {
    Gv2InviteMessage make({int revision = 0, int keyLen = 32}) =>
        Gv2InviteMessage(
          groupId: Uint8List(32),
          masterKey: Uint8List(keyLen),
          revision: revision,
          chain: Uint8List(32),
          stateHash: Uint8List(32),
          inviteSeed: Uint8List(32),
        );
    expect(() => make(revision: -1), throwsArgumentError);
    expect(() => make(revision: 0x100000000), throwsArgumentError);
    expect(() => make(keyLen: 31), throwsArgumentError);
  });
}
