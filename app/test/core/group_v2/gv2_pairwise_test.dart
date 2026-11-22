/// @file        gv2_pairwise_test.dart
/// @description Group protocol v2 pairwise message format: every type round
///              trips, the bytes are exactly the documented layout (golden
///              vectors in test/fixtures/gv2_pairwise_v1.json, assembled here
///              by hand and compared), and the decoder takes one encoding
///              only.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (the Sender Key manager is v4 only)
///
/// @functions
///  - main(): format, vectors and decoder strictness.
///
/// Notes:
///  - GV2_PAIRWISE_WRITE_VECTORS=1 rewrites the fixture after an INTENDED
///    format change. Every value in it comes from fixed labels.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/sender_key.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise.dart';

import 'gv2_test_support.dart';

const _fixturePath = 'test/fixtures/gv2_pairwise_v1.json';

final _groupId = gv2TestSha('gv2 pairwise test — group');
final _sender = gv2TestBytes('gv2 pairwise test — sender', 16);
final _recipient = gv2TestBytes('gv2 pairwise test — recipient', 16);

Gv2SignedHead _head(String label) => Gv2SignedHead(
  revision: 0x01020304,
  chain: gv2TestSha('$label chain'),
  headSig: gv2TestBytes('$label sig', 64),
);

Map<String, Gv2PairwiseBody> _bodies() => {
  'senderKey': Gv2SenderKeyBody(
    chainId: 0x7ffffffe,
    iteration: 0xfffffffe,
    chainKey: gv2TestSha('gv2 pairwise test — chain key'),
    signingKey: gv2TestSha('gv2 pairwise test — signing key'),
  ),
  'keyRequest': Gv2KeyRequestBody(0x12345678),
  'headConfirm': Gv2HeadConfirmBody(_head('confirm')),
  'behind': Gv2BehindBody(_head('behind')),
  'sessionReset': const Gv2SessionResetBody(),
  'headRequest': const Gv2HeadRequestBody(),
  'headProof': Gv2HeadProofBody(_head('proof')),
};

Gv2PairwiseMessage _message(Gv2PairwiseBody body) => Gv2PairwiseMessage(
  groupId: _groupId,
  sender: _sender,
  recipient: _recipient,
  body: body,
);

/// The layout of the notes in gv2_pairwise.dart, built here without the
/// module.
Uint8List _byHand(int type, List<int> body) => Uint8List.fromList([
  0xF2,
  0x01,
  type,
  ..._groupId,
  ..._sender,
  ..._recipient,
  ...body,
]);

List<int> _u32(int v) => [
  (v >> 24) & 255,
  (v >> 16) & 255,
  (v >> 8) & 255,
  v & 255,
];

List<int> _headBytes(Gv2SignedHead h) => [
  ..._u32(h.revision),
  ...h.chain,
  ...h.headSig,
];

void main() {
  final bodies = _bodies();
  final built = <String, Object?>{
    'groupIdHex': gv2Hex(_groupId),
    'senderHex': gv2Hex(_sender),
    'recipientHex': gv2Hex(_recipient),
    for (final e in bodies.entries) e.key: gv2Hex(_message(e.value).encode()),
  };
  if (Platform.environment['GV2_PAIRWISE_WRITE_VECTORS'] == '1') {
    File(_fixturePath).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(built)}\n',
    );
  }
  final fixture =
      jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;

  group('format', () {
    test('the fixture is what this implementation builds', () {
      expect(jsonDecode(jsonEncode(built)), fixture);
    });

    test('the vectors are the documented layout', () {
      final key = bodies['senderKey'] as Gv2SenderKeyBody;
      final confirm = bodies['headConfirm'] as Gv2HeadConfirmBody;
      final behind = bodies['behind'] as Gv2BehindBody;
      final proof = bodies['headProof'] as Gv2HeadProofBody;
      final expected = {
        'senderKey': _byHand(0x01, [
          ..._u32(key.chainId),
          ..._u32(key.iteration),
          ...key.chainKey,
          ...key.signingKey,
        ]),
        'keyRequest': _byHand(0x02, _u32(0x12345678)),
        'headConfirm': _byHand(0x03, _headBytes(confirm.head)),
        'behind': _byHand(0x04, _headBytes(behind.head)),
        'sessionReset': _byHand(0x05, const []),
        'headRequest': _byHand(0x06, const []),
        'headProof': _byHand(0x07, _headBytes(proof.head)),
      };
      for (final e in expected.entries) {
        expect(fixture[e.key], gv2Hex(e.value), reason: e.key);
      }
      expect(gv2PairwiseHeaderLen, 67);
      expect((expected['senderKey']!).length, 67 + 72);
      expect((expected['headConfirm']!).length, 67 + 100);
    });

    test('every type decodes to what was encoded', () {
      for (final e in bodies.entries) {
        final bytes = gv2Unhex(fixture[e.key] as String);
        final m = Gv2PairwiseMessage.decode(bytes)!;
        expect(m.groupId, _groupId);
        expect(m.sender, _sender);
        expect(m.recipient, _recipient);
        expect(m.body.type, e.value.type, reason: e.key);
        expect(m.encode(), bytes, reason: e.key);
      }
      final m = Gv2PairwiseMessage.decode(
        gv2Unhex(fixture['senderKey'] as String),
      )!;
      final key = m.body as Gv2SenderKeyBody;
      expect(key.chainId, 0x7ffffffe);
      expect(key.iteration, 0xfffffffe);
      expect(m.senderSnowId, 'snow${gv2Hex(_sender)}');
      expect(m.recipientSnowId, 'snow${gv2Hex(_recipient)}');
    });

    test('the first byte is not the start of a JSON object', () {
      for (final e in bodies.entries) {
        expect(_message(e.value).encode()[0], isNot(0x7B));
      }
    });

    test('a Sender Key body converts to and from a distribution message', () {
      final key = bodies['senderKey'] as Gv2SenderKeyBody;
      final d = key.toDistribution('g', 'snow-sender');
      expect(d.groupId, 'g');
      expect(d.senderId, 'snow-sender');
      final back = Gv2SenderKeyBody.of(d);
      expect(back.encode(), key.encode());
      expect(Gv2SenderKeyBody.decode(key.encode())!.encode(), key.encode());
      expect(Gv2SenderKeyBody.decode(Uint8List(71)), isNull);
    });

    test('a manager key round trips through a body', () {
      final m = SenderKeyManager();
      final created = m.createSenderKey('g', 'snow-me');
      final body = Gv2SenderKeyBody.of(created);
      final other = SenderKeyManager();
      expect(
        other.processSenderKey(body.toDistribution('g', 'snow-me')),
        isTrue,
      );
      expect(other.hasSenderKey('g', 'snow-me'), isTrue);
    });
  });

  group('one encoding only', () {
    Uint8List vector(String name) => gv2Unhex(fixture[name] as String);

    test('another format or version byte', () {
      for (final name in bodies.keys) {
        final v = vector(name);
        expect(
          Gv2PairwiseMessage.decode(Uint8List.fromList(v)..[0] = 0x7B),
          isNull,
        );
        expect(
          Gv2PairwiseMessage.decode(Uint8List.fromList(v)..[1] = 0x02),
          isNull,
        );
        expect(
          Gv2PairwiseMessage.decode(Uint8List.fromList(v)..[1] = 0x00),
          isNull,
        );
      }
    });

    test('unknown types', () {
      final v = vector('sessionReset');
      for (final type in [0x00, 0x08, 0x7F, 0xFF]) {
        expect(
          Gv2PairwiseMessage.decode(Uint8List.fromList(v)..[2] = type),
          isNull,
          reason: '$type',
        );
      }
    });

    test('a body one byte too short or too long, for every type', () {
      for (final name in bodies.keys) {
        final v = vector(name);
        if (v.length > gv2PairwiseHeaderLen) {
          expect(
            Gv2PairwiseMessage.decode(v.sublist(0, v.length - 1)),
            isNull,
            reason: name,
          );
        }
        expect(
          Gv2PairwiseMessage.decode(Uint8List.fromList([...v, 0])),
          isNull,
          reason: name,
        );
      }
    });

    test('a body of another type\'s length', () {
      final confirm = vector('headConfirm');
      final asKey = Uint8List.fromList(confirm)..[2] = gv2PairwiseTypeSenderKey;
      expect(Gv2PairwiseMessage.decode(asKey), isNull);
      // Same length, other meaning: headConfirm and behind share a layout but
      // keep their type.
      final asBehind = Uint8List.fromList(confirm)..[2] = gv2PairwiseTypeBehind;
      expect(Gv2PairwiseMessage.decode(asBehind)!.body, isA<Gv2BehindBody>());
      final asProof = Uint8List.fromList(confirm)
        ..[2] = gv2PairwiseTypeHeadProof;
      expect(Gv2PairwiseMessage.decode(asProof)!.body, isA<Gv2HeadProofBody>());
    });

    test('every truncation of every vector', () {
      for (final name in bodies.keys) {
        final v = vector(name);
        for (var n = 0; n < v.length; n++) {
          expect(
            Gv2PairwiseMessage.decode(v.sublist(0, n)),
            isNull,
            reason: '$name/$n',
          );
        }
      }
    });

    test('a chain id of 2^31 or more', () {
      final key = vector('senderKey');
      final bad = Uint8List.fromList(key)..[gv2PairwiseHeaderLen] = 0x80;
      expect(Gv2PairwiseMessage.decode(bad), isNull);
      final request = vector('keyRequest');
      final badRequest = Uint8List.fromList(request)
        ..[gv2PairwiseHeaderLen] = 0x80;
      expect(Gv2PairwiseMessage.decode(badRequest), isNull);
    });

    test('the constructors refuse what cannot be encoded', () {
      expect(() => Gv2KeyRequestBody(-1), throwsArgumentError);
      expect(() => Gv2KeyRequestBody(0x80000000), throwsArgumentError);
      expect(
        () => Gv2SenderKeyBody(
          chainId: 1,
          iteration: 0x100000000,
          chainKey: Uint8List(32),
          signingKey: Uint8List(32),
        ),
        throwsArgumentError,
      );
      expect(
        () => Gv2SenderKeyBody(
          chainId: 1,
          iteration: 0,
          chainKey: Uint8List(31),
          signingKey: Uint8List(32),
        ),
        throwsArgumentError,
      );
      expect(
        () => Gv2SignedHead(
          revision: 0,
          chain: Uint8List(31),
          headSig: Uint8List(64),
        ),
        throwsArgumentError,
      );
      expect(
        () => Gv2PairwiseMessage(
          groupId: Uint8List(31),
          sender: _sender,
          recipient: _recipient,
          body: const Gv2SessionResetBody(),
        ),
        throwsArgumentError,
      );
    });
  });
}
