/// @file        gv2_transport_test.dart
/// @description What Gv2Transport takes from a server's answer, against a local HTTP server: the
///              integers that are hashed or signed are range-checked — a snapshot's joined and
///              pending revisions are never later than the snapshot (and so fit the 32 bits the
///              state hash holds of them), its version is a byte, a head's revision is a u32. A
///              value cut to 32 bits in the hash would pass the hash check while meaning
///              something else.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - main(): the test cases.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_transport.dart';

void main() {
  late HttpServer server;
  late Gv2Transport transport;

  /// What the local server answers next (JSON body, status 200).
  late Map<String, Object?> answer;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(answer));
      await request.response.close();
    });
    transport = Gv2Transport(
      authenticatedPost: (_) async => throw StateError('not used'),
      baseUrl: 'http://127.0.0.1:${server.port}',
    );
  });
  tearDown(() async {
    transport.close();
    await server.close(force: true);
  });

  String b64(int length, int fill) =>
      base64Encode(Uint8List(length)..fillRange(0, length, fill));

  /// A snapshot answer for revision [at], with one member and one invite.
  Map<String, Object?> snapshotAt(
    int at, {
    int joinedRevision = 1,
    int pendingRevision = 2,
    int version = 1,
  }) => {
    'revision': at,
    'version': version,
    'chain': b64(gv2HashLen, 1),
    'deleted': false,
    'titlePayload': '',
    'headSig': b64(gv2SignatureLen, 2),
    'members': [
      {
        'ciphertext': b64(gv2CiphertextLen, 3),
        'role': gv2RoleOwner,
        'memberPub': b64(gv2PublicKeyLen, 4),
        'joinedRevision': joinedRevision,
        'memberPayload': b64(8, 5),
      },
    ],
    'pending': [
      {
        'ciphertext': b64(gv2CiphertextLen, 6),
        'invitedBy': b64(gv2CiphertextLen, 3),
        'invitePub': b64(gv2PublicKeyLen, 7),
        'revision': pendingRevision,
      },
    ],
  };

  Future<Gv2Snapshot> snapshot(int at) => transport.snapshot(
    groupId: Uint8List(32),
    presentation: Uint8List(8),
    at: at,
  );

  Matcher refused(String field) => throwsA(
    isA<Gv2ProtocolException>().having((e) => e.toString(), 'field',
        contains(field)),
  );

  test('a snapshot whose integers fit is taken', () async {
    answer = snapshotAt(5, joinedRevision: 5, pendingRevision: 5);
    final s = await snapshot(5);
    expect(s.state.members.values.single.joinedRevision, 5);
    expect(s.state.pending.values.single.revision, 5);
  });

  test('a joined or pending revision later than the snapshot — or past 32 '
      'bits — is refused', () async {
    for (final bad in [6, 0x100000001]) {
      answer = snapshotAt(5, joinedRevision: bad);
      await expectLater(snapshot(5), refused('joinedRevision'));
      answer = snapshotAt(5, pendingRevision: bad);
      await expectLater(snapshot(5), refused('revision'));
    }
  });

  test('a version past a byte is refused', () async {
    answer = snapshotAt(5, version: 0x101);
    await expectLater(snapshot(5), refused('version'));
  });

  test('a head revision past 32 bits is refused (its signature covers 32 '
      'bits of it)', () async {
    answer = {
      'revision': 0x100000005,
      'chain': b64(gv2HashLen, 1),
      'headSig': b64(gv2SignatureLen, 2),
    };
    await expectLater(
      transport.change(
        groupId: Uint8List(32),
        presentation: Uint8List(8),
        entry: Uint8List(4),
      ),
      refused('revision'),
    );
  });
}
