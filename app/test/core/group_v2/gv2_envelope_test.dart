/// @file        gv2_envelope_test.dart
/// @description Group protocol v2 envelopes: the golden vectors of
///              test/fixtures/gv2_envelope_v1.json (this Dart implementation
///              is the reference — the server stores an envelope as opaque
///              bytes), the header codec, padding, finding the group of an
///              envelope, and what each kind lets a receiver believe: a
///              content envelope whose header was swapped fails the sender's
///              signature, a change notice proves nothing, a member notice
///              is bound to its header by the member signing key.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (the Sender Key manager is v4 only — the case of a v3 manager is gone
///              with it)
///
/// @functions
///  - main(): the test groups below.
///  - _buildVectors(): the golden vectors, derived from fixed labels.
///  - _sealRaw(): an envelope around any inner plaintext, built without the
///    module under test.
///  - _Member: a test account with its Sender Key manager in one group.
///
/// Notes:
///  - `GV2_ENVELOPE_WRITE_VECTORS=1 flutter test test/core/group_v2/gv2_envelope_test.dart`
///    rewrites the fixture after an INTENDED format change. Every value in it
///    is deterministic, so the file must otherwise equal what this test
///    rebuilds.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as nacl;
import 'package:snowchat/core/crypto/sender_key.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_envelope.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';

import 'gv2_test_support.dart';

const _fixturePath = 'test/fixtures/gv2_envelope_v1.json';
const _deviceA = '0b8f6c1e-5a52-4f0e-9a43-6d2c8f1b7e10';
const _deviceB = '7c1d9e42-3b6a-4d8f-8e21-90ab54cd3f77';
const _timestampMs = 1794528000123;

Uint8List _sha(String label) => gv2TestSha('gv2 envelope v1 — $label');
Uint8List _bytes(String label, int length) =>
    gv2TestBytes('gv2 envelope v1 — $label', length);
Uint8List _text(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _concat(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

Uint8List _hmac(List<int> key, List<int> data) =>
    Uint8List.fromList(hash.Hmac(hash.sha256, key).convert(data).bytes);

/// 0x02 ‖ hint ‖ nonce ‖ SecretBox(K_env, nonce, inner), built here.
Uint8List _sealRaw(Gv2EnvelopeKeys keys, Uint8List inner, {Uint8List? nonce}) {
  final n = nonce ?? gv2TestBytes('raw nonce ${inner.length}', 24);
  final box = nacl.SecretBox(keys.envelopeKey).encrypt(inner, nonce: n);
  return _concat([
    [0x02],
    _hmac(keys.hintKey, n).sublist(0, 8),
    n,
    box.cipherText,
  ]);
}

/// The inner plaintext of [envelope], opened here.
Uint8List _innerOf(Gv2EnvelopeKeys keys, Uint8List envelope) =>
    Uint8List.fromList(nacl.SecretBox(keys.envelopeKey).decrypt(
      nacl.EncryptedMessage(
        nonce: Uint8List.fromList(envelope.sublist(9, 33)),
        cipherText: Uint8List.fromList(envelope.sublist(33)),
      ),
    ));

Uint8List _plusGroupOrder(Uint8List sig) {
  final order = (BigInt.one << 252) +
      BigInt.parse('27742317777372353535851937790883648493');
  var s = BigInt.zero;
  for (var i = 63; i >= 32; i--) {
    s = (s << 8) | BigInt.from(sig[i]);
  }
  s += order;
  final out = Uint8List.fromList(sig);
  for (var i = 32; i < 64; i++) {
    out[i] = (s & BigInt.from(0xff)).toInt();
    s >>= 8;
  }
  return out;
}

SenderKeyFailure? _failure(void Function() body) {
  try {
    body();
  } on SenderKeyException catch (e) {
    return e.reason;
  }
  return null;
}

/// A v4 manager that sends as [snowId] in [groupId] from a fixed position.
SenderKeyManager _fixedSender({
  required Uint8List groupId,
  required String snowId,
  required int chainId,
  required int iteration,
  required Uint8List chainKey,
  required Uint8List signingSeed,
}) =>
    SenderKeyManager(
      senderKeys: {
        '${gv2SenderKeyGroup(groupId)}:$snowId': SenderKeyRecord(states: [
          SenderKeyState(
            chainId: chainId,
            iteration: iteration,
            chainKey: Uint8List.fromList(chainKey),
            signingKeyPublic: Uint8List.fromList(
                ed.SigningKey(seed: signingSeed).verifyKey.asTypedList),
            signingKeyPrivate: Uint8List.fromList(signingSeed),
          ),
        ]),
      },
    );

/// Every golden value, rebuilt from fixed labels.
Map<String, dynamic> _buildVectors() {
  final masterKey = _sha('master key');
  final groupId = _sha('group id');
  final keys = Gv2EnvelopeKeys.derive(masterKey, groupId);

  final accountSeed = _sha('account alice');
  final accountPub =
      Uint8List.fromList(ed.SigningKey(seed: accountSeed).verifyKey.asTypedList);
  final accountId = Uint8List.fromList(accountPub.sublist(0, 16));
  final memberKey =
      Gv2SigningKey.fromSeed(gv2DeriveMemberSeed(accountSeed, groupId));
  final stamp = Gv2EnvelopeStamp(
    senderAccountId: accountId,
    senderDeviceId: _deviceA,
    messageId: _bytes('message id', 16),
    revision: 7,
    chain: _sha('chain'),
    timestampMs: _timestampMs,
  );

  // Content.
  const chainId = 0x1234abcd;
  const iteration = 41;
  final chainKey = _sha('sender chain key');
  final signingSeed = _sha('sender signing seed');
  final signingPub = Uint8List.fromList(
      ed.SigningKey(seed: signingSeed).verifyKey.asTypedList);
  const text = '눈이 온다 ❄ snow';
  final plaintext = _text(text);
  final messageNonce = _bytes('message nonce', 24);
  final contentNonce = _bytes('content nonce', 24);
  final contentHeader = Gv2EnvelopeHeader(
    kind: gv2KindContent,
    stamp: stamp,
    bodyLength: senderKeyMessageLength(plaintext.length),
  ).encode();
  final binding = gv2ContentBinding(groupId, contentHeader);
  final content = gv2SealContentEnvelope(
    keys: keys,
    stamp: stamp,
    senderKeys: _fixedSender(
      groupId: groupId,
      snowId: stamp.senderSnowId,
      chainId: chainId,
      iteration: iteration,
      chainKey: chainKey,
      signingSeed: signingSeed,
    ),
    plaintext: plaintext,
    nonce: contentNonce,
    messageNonce: messageNonce,
  );
  final senderKeyMessage = gv2OpenEnvelope(keys: keys, envelope: content)!.body;

  // Change notice.
  final changeNonce = _bytes('change nonce', 24);
  final change = gv2SealChangeNoticeEnvelope(
      keys: keys, stamp: stamp, nonce: changeNonce);

  // Member notice.
  final noticeNonce = _bytes('notice nonce', 24);
  final noticeHeader = Gv2EnvelopeHeader(
    kind: gv2KindMemberNotice,
    stamp: stamp,
    bodyLength: gv2NoticeMemberReset.length + 64,
  ).encode();
  final notice = gv2SealMemberNoticeEnvelope(
    keys: keys,
    stamp: stamp,
    memberKey: memberKey,
    payload: gv2NoticeMemberReset,
    nonce: noticeNonce,
  );

  return {
    'masterKeyHex': gv2Hex(masterKey),
    'groupIdHex': gv2Hex(groupId),
    'envelopeKeyHex': gv2Hex(keys.envelopeKey),
    'hintKeyHex': gv2Hex(keys.hintKey),
    'stamp': {
      'senderAccountIdHex': gv2Hex(accountId),
      'senderSnowId': stamp.senderSnowId,
      'senderDeviceId': _deviceA,
      'messageIdHex': gv2Hex(stamp.messageId),
      'revision': stamp.revision,
      'chainHex': gv2Hex(stamp.chain),
      'timestampMs': '$_timestampMs',
    },
    'localMessageIdHex': gv2Hex(gv2LocalMessageId(
        groupId: groupId,
        senderAccountId: accountId,
        messageId: stamp.messageId)),
    'padding': [
      for (final bodyLength in [0, 1, 395, 396, 459, 460, 1000, gv2MaxEnvelopeBody])
        {
          'bodyLength': bodyLength,
          'innerLength': gv2EnvelopeInnerLength(bodyLength),
        },
    ],
    'content': {
      'senderKey': {
        'chainId': chainId,
        'iteration': iteration,
        'chainKeyHex': gv2Hex(chainKey),
        'signingSeedHex': gv2Hex(signingSeed),
        'signingPublicHex': gv2Hex(signingPub),
      },
      'plaintextUtf8': text,
      'headerHex': gv2Hex(contentHeader),
      'bindingHex': gv2Hex(binding),
      'messageNonceHex': gv2Hex(messageNonce),
      'senderKeyMessageHex': gv2Hex(senderKeyMessage),
      'nonceHex': gv2Hex(contentNonce),
      'envelopeHex': gv2Hex(content),
    },
    'changeNotice': {
      'nonceHex': gv2Hex(changeNonce),
      'envelopeHex': gv2Hex(change),
    },
    'memberNotice': {
      'memberPublicHex': gv2Hex(memberKey.publicKey),
      'payloadHex': gv2Hex(gv2NoticeMemberReset),
      'headerHex': gv2Hex(noticeHeader),
      'signedMessageHex': gv2Hex(gv2MemberNoticeMessage(
          groupId: groupId,
          headerBytes: noticeHeader,
          payload: gv2NoticeMemberReset)),
      'nonceHex': gv2Hex(noticeNonce),
      'envelopeHex': gv2Hex(notice),
    },
  };
}

/// One account in one group, with its own Sender Key manager.
class _Member {
  final Gv2TestGroup group;
  final Gv2TestPerson person;
  final String deviceId;
  final SenderKeyManager senderKeys =
      SenderKeyManager();

  _Member(this.group, String name, this.deviceId) : person = group.person(name);

  Gv2EnvelopeKeys get keys =>
      Gv2EnvelopeKeys.derive(group.masterKey, group.groupId);

  String get keyGroup => gv2SenderKeyGroup(group.groupId);

  /// This member's key, as it is handed to the others.
  SenderKeyDistributionMessage newKey() =>
      senderKeys.createSenderKey(keyGroup, person.snowId);

  Gv2EnvelopeStamp stamp({
    Uint8List? messageId,
    int revision = 3,
    Uint8List? chain,
    int timestampMs = _timestampMs,
  }) =>
      Gv2EnvelopeStamp(
        senderAccountId: person.accountId,
        senderDeviceId: deviceId,
        messageId: messageId ?? gv2NewMessageId(),
        revision: revision,
        chain: chain ?? gv2TestSha('chain at 3'),
        timestampMs: timestampMs,
      );

  Uint8List say(String text, {Gv2EnvelopeStamp? stamp}) =>
      gv2SealContentEnvelope(
        keys: keys,
        stamp: stamp ?? this.stamp(),
        senderKeys: senderKeys,
        plaintext: _text(text),
      );

  String read(Gv2OpenedEnvelope envelope) => utf8.decode(gv2OpenContent(
      groupId: group.groupId, envelope: envelope, senderKeys: senderKeys));
}

void main() {
  final built = _buildVectors();
  if (Platform.environment['GV2_ENVELOPE_WRITE_VECTORS'] == '1') {
    File(_fixturePath).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(built)}\n');
  }
  final fixture =
      jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> section(String name) =>
      Map<String, dynamic>.from(fixture[name] as Map);
  Uint8List hex(Map<String, dynamic> from, String key) =>
      gv2Unhex(from[key] as String);

  final groupId = gv2Unhex(fixture['groupIdHex'] as String);
  final keys = Gv2EnvelopeKeys.derive(
      gv2Unhex(fixture['masterKeyHex'] as String), groupId);

  group('golden vectors', () {
    test('the fixture is what this implementation builds', () {
      expect(jsonDecode(jsonEncode(built)), fixture);
    });

    test('the keys are the derived ones', () {
      expect(gv2Hex(keys.envelopeKey), fixture['envelopeKeyHex']);
      expect(gv2Hex(keys.hintKey), fixture['hintKeyHex']);
      expect(keys.envelopeKey, isNot(keys.hintKey));
    });

    test('the content envelope has the documented layout', () {
      final content = section('content');
      final envelope = hex(content, 'envelopeHex');
      final nonce = hex(content, 'nonceHex');
      final header = hex(content, 'headerHex');
      final message = hex(content, 'senderKeyMessageHex');

      expect(envelope[0], 0x02);
      expect(envelope.sublist(1, 9), _hmac(keys.hintKey, nonce).sublist(0, 8));
      expect(envelope.sublist(9, 33), nonce);
      final inner = _innerOf(keys, envelope);
      expect(inner.length, 512);
      expect(inner.sublist(0, 117), header);
      expect(inner.sublist(117, 117 + message.length), message);
      expect(inner.sublist(117 + message.length).every((b) => b == 0), isTrue);
      expect(envelope.length, 1 + 8 + 24 + 16 + 512);
    });

    test('the header is the documented 117 bytes', () {
      final stamp = section('stamp');
      final content = section('content');
      final message = hex(content, 'senderKeyMessageHex');
      final expected = _concat([
        [0x01],
        hex(stamp, 'senderAccountIdHex'),
        ascii.encode(stamp['senderDeviceId'] as String),
        hex(stamp, 'messageIdHex'),
        (ByteData(4)..setUint32(0, stamp['revision'] as int)).buffer.asUint8List(),
        hex(stamp, 'chainHex'),
        (ByteData(8)..setUint64(0, int.parse(stamp['timestampMs'] as String)))
            .buffer
            .asUint8List(),
        (ByteData(4)..setUint32(0, message.length)).buffer.asUint8List(),
      ]);

      expect(expected.length, gv2EnvelopeHeaderLen);
      expect(hex(content, 'headerHex'), expected);
      expect(stamp['senderSnowId'],
          'snow${stamp['senderAccountIdHex']}');
    });

    test('the Sender Key signature covers the group, the header, the message',
        () {
      final content = section('content');
      final senderKey = Map<String, dynamic>.from(content['senderKey'] as Map);
      final header = hex(content, 'headerHex');
      final message = hex(content, 'senderKeyMessageHex');
      final binding =
          Uint8List.fromList(hash.sha256.convert([...groupId, ...header]).bytes);

      expect(hex(content, 'bindingHex'), binding);
      expect(message[0], 4);
      expect(ByteData.sublistView(message).getUint32(1), senderKey['chainId']);
      expect(ByteData.sublistView(message).getUint32(5), senderKey['iteration']);
      expect(message.sublist(73, 97), hex(content, 'messageNonceHex'));
      final signed = _concat([
        [0xfe],
        ascii.encode('SnowChat_GV2_Msg_v1'),
        binding,
        message.sublist(0, 9),
        message.sublist(73),
      ]);
      expect(
          ed.VerifyKey(hex(senderKey, 'signingPublicHex')).verify(
              signature:
                  ed.Signature(Uint8List.fromList(message.sublist(9, 73))),
              message: signed),
          isTrue);
    });

    test('a receiver holding the key reads the content envelope', () {
      final stamp = section('stamp');
      final content = section('content');
      final senderKey = Map<String, dynamic>.from(content['senderKey'] as Map);
      final receiver = SenderKeyManager()
        ..processSenderKey(SenderKeyDistributionMessage(
          groupId: gv2SenderKeyGroup(groupId),
          senderId: stamp['senderSnowId'] as String,
          chainId: senderKey['chainId'] as int,
          iteration: senderKey['iteration'] as int,
          chainKey: hex(senderKey, 'chainKeyHex'),
          signingKey: hex(senderKey, 'signingPublicHex'),
        ));

      final opened =
          gv2OpenEnvelope(keys: keys, envelope: hex(content, 'envelopeHex'))!;
      expect(opened.kind, gv2KindContent);
      expect(opened.stamp.senderSnowId, stamp['senderSnowId']);
      expect(opened.stamp.senderDeviceId, stamp['senderDeviceId']);
      expect(opened.stamp.revision, stamp['revision']);
      expect(gv2Hex(opened.stamp.chain), stamp['chainHex']);
      expect('${opened.stamp.timestampMs}', stamp['timestampMs']);
      expect(
          utf8.decode(gv2OpenContent(
              groupId: groupId, envelope: opened, senderKeys: receiver)),
          content['plaintextUtf8']);
      expect(
          gv2Hex(gv2LocalMessageId(
              groupId: groupId,
              senderAccountId: opened.stamp.senderAccountId,
              messageId: opened.stamp.messageId)),
          fixture['localMessageIdHex']);
    });

    test('the change notice carries the revision', () {
      final opened = gv2OpenEnvelope(
          keys: keys, envelope: hex(section('changeNotice'), 'envelopeHex'))!;
      expect(opened.kind, gv2KindChangeNotice);
      expect(opened.body, [0, 0, 0, 7]);
      expect(gv2ChangeNoticeRevision(opened), 7);
    });

    test('the member notice is signed over the group, the header, the payload',
        () {
      final notice = section('memberNotice');
      final opened =
          gv2OpenEnvelope(keys: keys, envelope: hex(notice, 'envelopeHex'))!;
      final header = hex(notice, 'headerHex');
      final signed = _concat([
        [0xff],
        ascii.encode('SnowChat_GV2_MemberNotice_v1'),
        groupId,
        header,
        hex(notice, 'payloadHex'),
      ]);

      expect(opened.kind, gv2KindMemberNotice);
      expect(opened.headerBytes, header);
      expect(hex(notice, 'signedMessageHex'), signed);
      expect(
          ed.VerifyKey(hex(notice, 'memberPublicHex')).verify(
              signature:
                  ed.Signature(Uint8List.fromList(opened.body.sublist(1))),
              message: signed),
          isTrue);
      expect(
          gv2VerifyMemberNotice(
              groupId: groupId,
              envelope: opened,
              memberPub: hex(notice, 'memberPublicHex')),
          gv2NoticeMemberReset);
    });

    test('padding: at least 512, then steps of 64', () {
      for (final row in (fixture['padding'] as List).cast<Map>()) {
        expect(gv2EnvelopeInnerLength(row['bodyLength'] as int),
            row['innerLength'],
            reason: 'body ${row['bodyLength']}');
      }
      expect(gv2EnvelopeInnerLength(395), 512);
      expect(gv2EnvelopeInnerLength(396), 576);
      expect(
          gv2EnvelopeInnerLength(gv2MaxEnvelopeBody) + gv2EnvelopeOverhead,
          lessThanOrEqualTo(gv2MaxEnvelopeBytes));
      expect(
          gv2EnvelopeInnerLength(gv2MaxEnvelopeBody + 1) + gv2EnvelopeOverhead,
          greaterThan(gv2MaxEnvelopeBytes));
    });
  });

  group('header', () {
    final stamp = Gv2EnvelopeStamp(
      senderAccountId: gv2TestBytes('account id', 16),
      senderDeviceId: _deviceA,
      messageId: gv2TestBytes('message id', 16),
      revision: 0xfffffffe,
      chain: gv2TestSha('chain'),
      timestampMs: _timestampMs,
    );
    Gv2EnvelopeHeader header({
      int kind = gv2KindContent,
      Gv2EnvelopeStamp? with_,
      int bodyLength = 200,
    }) =>
        Gv2EnvelopeHeader(
            kind: kind, stamp: with_ ?? stamp, bodyLength: bodyLength);
    Gv2EnvelopeStamp changed({
      Uint8List? senderAccountId,
      String? senderDeviceId,
      Uint8List? messageId,
      int? revision,
      Uint8List? chain,
      int? timestampMs,
    }) =>
        Gv2EnvelopeStamp(
          senderAccountId: senderAccountId ?? stamp.senderAccountId,
          senderDeviceId: senderDeviceId ?? stamp.senderDeviceId,
          messageId: messageId ?? stamp.messageId,
          revision: revision ?? stamp.revision,
          chain: chain ?? stamp.chain,
          timestampMs: timestampMs ?? stamp.timestampMs,
        );

    test('every field survives encoding', () {
      final bytes = header().encode();
      final decoded = Gv2EnvelopeHeader.tryDecode(bytes)!;

      expect(bytes.length, gv2EnvelopeHeaderLen);
      expect(decoded.kind, gv2KindContent);
      expect(decoded.stamp.senderAccountId, stamp.senderAccountId);
      expect(decoded.stamp.senderDeviceId, _deviceA);
      expect(decoded.stamp.messageId, stamp.messageId);
      expect(decoded.stamp.revision, 0xfffffffe);
      expect(decoded.stamp.chain, stamp.chain);
      expect(decoded.stamp.timestampMs, _timestampMs);
      expect(decoded.bodyLength, 200);
      expect(decoded.encode(), bytes);
    });

    test('a field that does not fit is not encoded', () {
      expect(() => header(with_: changed(senderAccountId: Uint8List(15))).encode(),
          throwsArgumentError);
      expect(() => header(with_: changed(messageId: Uint8List(17))).encode(),
          throwsArgumentError);
      expect(() => header(with_: changed(chain: Uint8List(31))).encode(),
          throwsArgumentError);
      expect(() => header(with_: changed(revision: 0x100000000)).encode(),
          throwsArgumentError);
      expect(() => header(with_: changed(revision: -1)).encode(),
          throwsArgumentError);
      expect(() => header(with_: changed(timestampMs: -1)).encode(),
          throwsArgumentError);
      expect(() => header(bodyLength: gv2MaxEnvelopeBody + 1).encode(),
          throwsArgumentError);
      expect(() => header(kind: 256).encode(), throwsArgumentError);
      for (final deviceId in [
        'short',
        '${_deviceA}x',
        '${_deviceA.substring(0, 35)} ',
        '${_deviceA.substring(0, 35)}\u007f',
      ]) {
        expect(() => header(with_: changed(senderDeviceId: deviceId)).encode(),
            throwsArgumentError,
            reason: deviceId);
      }
      // Not ASCII at all.
      expect(
          () => header(
                  with_: changed(
                      senderDeviceId: '${_deviceA.substring(0, 35)}é'))
              .encode(),
          throwsArgumentError);
    });

    test('bytes that are not a header are not decoded', () {
      final bytes = header().encode();

      expect(Gv2EnvelopeHeader.tryDecode(Uint8List.fromList(bytes.sublist(1))),
          isNull);
      expect(Gv2EnvelopeHeader.tryDecode(Uint8List.fromList([...bytes, 0])),
          isNull);
      // A device id with a control character, a space, a byte above ASCII.
      for (final b in [0x00, 0x20, 0x7f, 0xc3]) {
        expect(
            Gv2EnvelopeHeader.tryDecode(Uint8List.fromList(bytes)..[30] = b),
            isNull,
            reason: 'device id byte $b');
      }
      // A time of 2^63 ms or more.
      expect(Gv2EnvelopeHeader.tryDecode(Uint8List.fromList(bytes)..[105] = 0x80),
          isNull);
      // A body longer than any envelope.
      expect(
          Gv2EnvelopeHeader.tryDecode(Uint8List.fromList(bytes)..[113] = 0x01),
          isNull);
    });

    test('a kind this client does not know is still a header', () {
      final decoded = Gv2EnvelopeHeader.tryDecode(header(kind: 0x7e).encode())!;
      expect(decoded.kind, 0x7e);
    });
  });

  group('sealing and opening', () {
    final stamp = Gv2EnvelopeStamp(
      senderAccountId: gv2TestBytes('account id', 16),
      senderDeviceId: _deviceA,
      messageId: gv2TestBytes('message id', 16),
      revision: 3,
      chain: gv2TestSha('chain'),
      timestampMs: _timestampMs,
    );
    Gv2EnvelopeKeys keysOf(String label) => Gv2EnvelopeKeys.derive(
        gv2TestSha('master key $label'), gv2TestSha('group id $label'));
    Uint8List seal(Uint8List body, {int kind = 0x7e, Gv2EnvelopeKeys? to}) =>
        gv2SealEnvelope(
          keys: to ?? keys,
          header:
              Gv2EnvelopeHeader(kind: kind, stamp: stamp, bodyLength: body.length),
          body: body,
        );

    test('what was sealed is what opens', () {
      for (final length in [0, 1, 395, 396, 5000]) {
        final body = gv2TestBytes('body $length', length);
        final envelope = seal(body);
        final opened = gv2OpenEnvelope(keys: keys, envelope: envelope)!;

        expect(envelope.length,
            gv2EnvelopeOverhead + gv2EnvelopeInnerLength(length));
        expect(opened.body, body);
        expect(opened.kind, 0x7e);
        expect(opened.header.bodyLength, length);
        expect(opened.headerBytes, opened.header.encode());
        expect(opened.stamp.messageId, stamp.messageId);
      }
    });

    test('two envelopes of the same message share no bytes after the version',
        () {
      final body = gv2TestBytes('body', 100);
      final a = seal(body);
      final b = seal(body);

      expect(a.length, b.length);
      expect(a.sublist(1, 9), isNot(b.sublist(1, 9)));
      expect(a.sublist(9, 33), isNot(b.sublist(9, 33)));
      expect(a.sublist(33, 65), isNot(b.sublist(33, 65)));
    });

    test('the largest body fits the server limit, one more byte does not', () {
      final body = Uint8List(gv2MaxEnvelopeBody);
      final envelope = seal(body);

      expect(envelope.length, lessThanOrEqualTo(gv2MaxEnvelopeBytes));
      expect(gv2OpenEnvelope(keys: keys, envelope: envelope)!.body.length,
          gv2MaxEnvelopeBody);
      expect(() => seal(Uint8List(gv2MaxEnvelopeBody + 1)), throwsArgumentError);
    });

    test('a header that misstates the body is not sealed', () {
      expect(
          () => gv2SealEnvelope(
                keys: keys,
                header:
                    Gv2EnvelopeHeader(kind: 1, stamp: stamp, bodyLength: 10),
                body: Uint8List(11),
              ),
          throwsArgumentError);
    });

    test('another group, a sealed sender envelope and altered bytes do not open',
        () {
      final envelope = seal(gv2TestBytes('body', 100));

      expect(gv2OpenEnvelope(keys: keysOf('other'), envelope: envelope), isNull);
      // The right envelope key with another hint key: not this group's.
      expect(
          gv2OpenEnvelope(
              keys: Gv2EnvelopeKeys(
                  groupId: keys.groupId,
                  envelopeKey: keys.envelopeKey,
                  hintKey: keysOf('other').hintKey),
              envelope: envelope),
          isNull);
      expect(gv2IsGroupEnvelope(Uint8List.fromList(envelope)..[0] = 0x01),
          isFalse);
      for (final offset in [0, 1, 8, 9, 32, 33, 48, envelope.length - 1]) {
        expect(
            gv2OpenEnvelope(
                keys: keys,
                envelope: Uint8List.fromList(envelope)..[offset] ^= 1),
            isNull,
            reason: 'offset $offset');
      }
      expect(
          gv2OpenEnvelope(
              keys: keys,
              envelope:
                  Uint8List.fromList(envelope.sublist(0, envelope.length - 1))),
          isNull);
      expect(gv2OpenEnvelope(keys: keys, envelope: Uint8List(0)), isNull);
      expect(
          gv2OpenEnvelope(
              keys: keys, envelope: Uint8List(gv2MaxEnvelopeBytes + 1)..[0] = 2),
          isNull);
    });

    test('an inner plaintext that is not laid out as specified does not open',
        () {
      final header = Gv2EnvelopeHeader(kind: 1, stamp: stamp, bodyLength: 10);
      Uint8List inner(int length, {int? claimedBody, int? dirtyAt}) {
        final out = Uint8List(length)
          ..setAll(
              0,
              Gv2EnvelopeHeader(
                      kind: 1, stamp: stamp, bodyLength: claimedBody ?? 10)
                  .encode());
        if (dirtyAt != null) out[dirtyAt] = 1;
        return out;
      }

      // The reference shape opens, also with more padding than the rule asks.
      expect(gv2OpenEnvelope(keys: keys, envelope: _sealRaw(keys, inner(512))),
          isNotNull);
      expect(
          gv2OpenEnvelope(keys: keys, envelope: _sealRaw(keys, inner(1024)))!
              .body
              .length,
          header.bodyLength);
      // Padding that is not zero.
      expect(
          gv2OpenEnvelope(
              keys: keys, envelope: _sealRaw(keys, inner(512, dirtyAt: 511))),
          isNull);
      expect(
          gv2OpenEnvelope(
              keys: keys, envelope: _sealRaw(keys, inner(512, dirtyAt: 127))),
          isNull);
      // A body that would end after the plaintext.
      expect(
          gv2OpenEnvelope(
              keys: keys,
              envelope: _sealRaw(keys, inner(512, claimedBody: 396))),
          isNull);
      // A header that is none.
      expect(
          gv2OpenEnvelope(
              keys: keys, envelope: _sealRaw(keys, Uint8List(512))),
          isNull);
    });

    test('the group of an envelope is found among many', () {
      final groups = [for (var i = 0; i < 300; i++) keysOf('#$i')];
      final envelope = seal(gv2TestBytes('body', 50), to: groups[217]);

      final found = gv2OpenEnvelopeAmong(envelope, groups)!;
      expect(found.keys, same(groups[217]));
      expect(found.envelope.body, gv2TestBytes('body', 50));
      expect(gv2OpenEnvelopeAmong(envelope, groups.take(217)), isNull);
      expect(gv2OpenEnvelopeAmong(envelope, const []), isNull);
      expect(gv2OpenEnvelopeAmong(Uint8List(600)..[0] = 1, groups), isNull);
    });

    test('a short text, a change notice and a member notice look alike', () {
      final g = Gv2TestGroup('sizes');
      final alice = _Member(g, 'alice', _deviceA)..newKey();
      final sizes = {
        alice.say('hi').length,
        alice.say('a few more words than "hi", still a short text').length,
        gv2SealChangeNoticeEnvelope(keys: alice.keys, stamp: alice.stamp())
            .length,
        gv2SealMemberNoticeEnvelope(
          keys: alice.keys,
          stamp: alice.stamp(),
          memberKey: alice.person.memberKey,
          payload: gv2NoticeMemberReset,
        ).length,
      };
      expect(sizes, {gv2EnvelopeOverhead + 512});
    });
  });

  group('content', () {
    late Gv2TestGroup g;
    late _Member alice;
    late _Member bob;
    late _Member mallory;
    late SenderKeyDistributionMessage aliceKey;

    setUp(() {
      g = Gv2TestGroup('content');
      alice = _Member(g, 'alice', _deviceA);
      bob = _Member(g, 'bob', _deviceB);
      mallory = _Member(g, 'mallory', _deviceB);
      aliceKey = alice.newKey();
      bob.senderKeys.processSenderKey(aliceKey);
      mallory.senderKeys.processSenderKey(aliceKey);
    });

    Gv2OpenedEnvelope open(Uint8List envelope) =>
        gv2OpenEnvelope(keys: bob.keys, envelope: envelope)!;

    /// What anyone holding the group key can do: put [body] under a header
    /// of their choosing.
    Uint8List rewrap(Uint8List body, Gv2EnvelopeStamp stamp) => gv2SealEnvelope(
          keys: mallory.keys,
          header: Gv2EnvelopeHeader(
              kind: gv2KindContent, stamp: stamp, bodyLength: body.length),
          body: body,
        );

    test('a member reads what another member said', () {
      final stamp = alice.stamp();
      final opened = open(alice.say('눈이 온다', stamp: stamp));

      expect(opened.kind, gv2KindContent);
      expect(opened.stamp.senderSnowId, alice.person.snowId);
      expect(opened.stamp.senderDeviceId, _deviceA);
      expect(opened.stamp.messageId, stamp.messageId);
      expect(opened.stamp.revision, 3);
      expect(bob.read(opened), '눈이 온다');
      expect(bob.read(open(alice.say('again'))), 'again');
    });

    test('the message under a new message id is not the sender\'s', () {
      final original = alice.stamp();
      final opened = open(alice.say('clear the history', stamp: original));
      final replay = open(rewrap(
          opened.body,
          Gv2EnvelopeStamp(
            senderAccountId: original.senderAccountId,
            senderDeviceId: original.senderDeviceId,
            messageId: gv2NewMessageId(),
            revision: original.revision,
            chain: original.chain,
            timestampMs: original.timestampMs,
          )));

      expect(_failure(() => bob.read(replay)), SenderKeyFailure.signature);
      // The key is still there and the original still reads.
      expect(bob.read(opened), 'clear the history');
    });

    test('no field of the header can be changed', () {
      final original = alice.stamp();
      final opened = open(alice.say('hello', stamp: original));
      Gv2EnvelopeStamp with_({
        String? senderDeviceId,
        int? revision,
        Uint8List? chain,
        int? timestampMs,
      }) =>
          Gv2EnvelopeStamp(
            senderAccountId: original.senderAccountId,
            senderDeviceId: senderDeviceId ?? original.senderDeviceId,
            messageId: original.messageId,
            revision: revision ?? original.revision,
            chain: chain ?? original.chain,
            timestampMs: timestampMs ?? original.timestampMs,
          );

      for (final forged in [
        with_(senderDeviceId: _deviceB),
        with_(revision: original.revision + 1),
        with_(chain: gv2TestSha('another chain')),
        with_(timestampMs: original.timestampMs + 1),
      ]) {
        expect(_failure(() => bob.read(open(rewrap(opened.body, forged)))),
            SenderKeyFailure.signature);
      }
      expect(bob.read(opened), 'hello');
    });

    test('a message cannot be passed off as another member\'s', () {
      final opened = open(alice.say('hello'));
      final asMallory = open(rewrap(opened.body, mallory.stamp()));

      // Bob has no key of Mallory's with that chain id.
      expect(_failure(() => bob.read(asMallory)), SenderKeyFailure.noKey);
      // And with a key of Mallory's under the same chain id, it is not her
      // signature.
      final chainId = ByteData.sublistView(opened.body).getUint32(1);
      bob.senderKeys.processSenderKey(SenderKeyDistributionMessage(
        groupId: bob.keyGroup,
        senderId: mallory.person.snowId,
        chainId: chainId,
        iteration: 0,
        chainKey: gv2TestSha('mallory chain key'),
        signingKey: Uint8List.fromList(ed.SigningKey(
                seed: gv2TestSha('mallory signing seed'))
            .verifyKey
            .asTypedList),
      ));
      expect(_failure(() => bob.read(asMallory)), SenderKeyFailure.signature);
    });

    test('sealed again under the same header it is the same message', () {
      final opened = open(alice.say('hello'));
      final again = open(rewrap(opened.body, opened.stamp));
      Uint8List localId(Gv2OpenedEnvelope e) => gv2LocalMessageId(
          groupId: g.groupId,
          senderAccountId: e.stamp.senderAccountId,
          messageId: e.stamp.messageId);

      expect(bob.read(opened), 'hello');
      // The key of a message reads it once: the copy is not read again.
      expect(_failure(() => bob.read(again)), SenderKeyFailure.expired);
      expect(localId(again), localId(opened));
    });

    test('a message does not move to another group', () {
      final other = Gv2TestGroup('content, another group');
      final aliceThere = _Member(other, 'alice', _deviceA);
      final bobThere = _Member(other, 'bob', _deviceB);
      bobThere.senderKeys.processSenderKey(aliceThere.newKey());
      final opened = open(alice.say('for the first group'));

      // Moved by someone who is in both groups, header untouched.
      final moved = gv2OpenEnvelope(
          keys: bobThere.keys,
          envelope: gv2SealEnvelope(
              keys: bobThere.keys, header: opened.header, body: opened.body))!;
      expect(_failure(() => bobThere.read(moved)), SenderKeyFailure.noKey);

      // Even if the sender used one Sender Key in both groups, the group id
      // is under the signature.
      final sameKey = SenderKeyManager()
        ..processSenderKey(() {
          final key = aliceKey;
          return SenderKeyDistributionMessage(
            groupId: bobThere.keyGroup,
            senderId: key.senderId,
            chainId: key.chainId,
            iteration: key.iteration,
            chainKey: key.chainKey,
            signingKey: key.signingKey,
          );
        }());
      expect(
          _failure(() => gv2OpenContent(
              groupId: other.groupId, envelope: moved, senderKeys: sameKey)),
          SenderKeyFailure.signature);
    });

    test('an envelope of another kind is not content', () {
      final notice = open(
          gv2SealChangeNoticeEnvelope(keys: alice.keys, stamp: alice.stamp()));
      expect(_failure(() => bob.read(notice)), SenderKeyFailure.malformed);

      // A content body under a kind the signature does not cover as content.
      final opened = open(alice.say('hello'));
      final asNotice = open(gv2SealEnvelope(
        keys: mallory.keys,
        header: Gv2EnvelopeHeader(
            kind: gv2KindMemberNotice,
            stamp: opened.stamp,
            bodyLength: opened.body.length),
        body: opened.body,
      ));
      expect(_failure(() => bob.read(asNotice)), SenderKeyFailure.malformed);
      expect(
          gv2VerifyMemberNotice(
              groupId: g.groupId,
              envelope: asNotice,
              memberPub: alice.person.memberKey.publicKey),
          isNull);
    });

    test('the longest content fits, one more byte does not', () {
      final longest = Uint8List(gv2MaxContentPlaintext);
      final envelope = gv2SealContentEnvelope(
          keys: alice.keys,
          stamp: alice.stamp(),
          senderKeys: alice.senderKeys,
          plaintext: longest);

      expect(envelope.length, lessThanOrEqualTo(gv2MaxEnvelopeBytes));
      expect(
          gv2OpenContent(
                  groupId: g.groupId,
                  envelope: open(envelope),
                  senderKeys: bob.senderKeys)
              .length,
          gv2MaxContentPlaintext);
      expect(
          () => gv2SealContentEnvelope(
              keys: alice.keys,
              stamp: alice.stamp(),
              senderKeys: alice.senderKeys,
              plaintext: Uint8List(gv2MaxContentPlaintext + 1)),
          throwsArgumentError);
    });
  });

  group('change notice', () {
    test('it points at a revision and proves nothing', () {
      final g = Gv2TestGroup('notice');
      final alice = _Member(g, 'alice', _deviceA);
      final opened = gv2OpenEnvelope(
          keys: alice.keys,
          envelope: gv2SealChangeNoticeEnvelope(
              keys: alice.keys, stamp: alice.stamp(revision: 12)))!;

      expect(opened.kind, gv2KindChangeNotice);
      expect(gv2ChangeNoticeRevision(opened), 12);
      expect(opened.stamp.revision, 12);

      // Anyone with the group key writes the same notice in Alice's name.
      final forged = gv2OpenEnvelope(
          keys: alice.keys,
          envelope: gv2SealChangeNoticeEnvelope(
              keys: alice.keys, stamp: alice.stamp(revision: 9999)))!;
      expect(gv2ChangeNoticeRevision(forged), 9999);
    });

    test('other envelopes are not change notices', () {
      final g = Gv2TestGroup('notice');
      final alice = _Member(g, 'alice', _deviceA)..newKey();
      Gv2OpenedEnvelope open(Uint8List e) =>
          gv2OpenEnvelope(keys: alice.keys, envelope: e)!;

      expect(gv2ChangeNoticeRevision(open(alice.say('hello'))), isNull);
      final stamp = alice.stamp();
      expect(
          gv2ChangeNoticeRevision(open(gv2SealEnvelope(
            keys: alice.keys,
            header: Gv2EnvelopeHeader(
                kind: gv2KindChangeNotice, stamp: stamp, bodyLength: 5),
            body: Uint8List(5),
          ))),
          isNull);
    });
  });

  group('member notice', () {
    late Gv2TestGroup g;
    late _Member alice;
    late _Member mallory;

    setUp(() {
      g = Gv2TestGroup('member notice');
      alice = _Member(g, 'alice', _deviceA);
      mallory = _Member(g, 'mallory', _deviceB);
    });

    Gv2OpenedEnvelope open(Uint8List e) =>
        gv2OpenEnvelope(keys: alice.keys, envelope: e)!;
    Uint8List reset(_Member from, {Gv2EnvelopeStamp? stamp}) =>
        gv2SealMemberNoticeEnvelope(
          keys: from.keys,
          stamp: stamp ?? from.stamp(),
          memberKey: from.person.memberKey,
          payload: gv2NoticeMemberReset,
        );
    Uint8List? verify(Gv2OpenedEnvelope e, _Member signer,
            {Uint8List? groupId}) =>
        gv2VerifyMemberNotice(
            groupId: groupId ?? g.groupId,
            envelope: e,
            memberPub: signer.person.memberKey.publicKey);

    test('the member signing key of the sender vouches for it', () {
      final opened = open(reset(alice));

      expect(opened.kind, gv2KindMemberNotice);
      expect(opened.body.length, 1 + 64);
      expect(verify(opened, alice), gv2NoticeMemberReset);
      expect(verify(opened, mallory), isNull);
    });

    test('it is bound to its header and its group', () {
      final stamp = alice.stamp();
      final opened = open(reset(alice, stamp: stamp));
      Uint8List under(Gv2EnvelopeStamp s) => gv2SealEnvelope(
            keys: mallory.keys,
            header: Gv2EnvelopeHeader(
                kind: gv2KindMemberNotice,
                stamp: s,
                bodyLength: opened.body.length),
            body: opened.body,
          );

      // Replayed later under a new message id, or with a newer time.
      expect(verify(open(under(alice.stamp(messageId: gv2NewMessageId()))), alice),
          isNull);
      expect(
          verify(
              open(under(alice.stamp(
                  messageId: stamp.messageId,
                  timestampMs: stamp.timestampMs + 1))),
              alice),
          isNull);
      // The same header: the same notice.
      expect(verify(open(under(stamp)), alice), gv2NoticeMemberReset);
      // Another group.
      expect(verify(opened, alice, groupId: gv2TestSha('another group')), isNull);
      expect(
          gv2VerifyMemberNotice(
              groupId: Uint8List(31),
              envelope: opened,
              memberPub: alice.person.memberKey.publicKey),
          isNull);
    });

    test('an altered payload or a twin signature is refused', () {
      final stamp = alice.stamp();
      final opened = open(reset(alice, stamp: stamp));
      Gv2OpenedEnvelope withBody(Uint8List body) => open(gv2SealEnvelope(
            keys: alice.keys,
            header: Gv2EnvelopeHeader(
                kind: gv2KindMemberNotice,
                stamp: stamp,
                bodyLength: body.length),
            body: body,
          ));

      expect(
          verify(withBody(Uint8List.fromList(opened.body)..[0] = 0x02), alice),
          isNull);
      expect(
          verify(
              withBody(_concat([
                opened.body.sublist(0, 1),
                _plusGroupOrder(Uint8List.fromList(opened.body.sublist(1))),
              ])),
              alice),
          isNull);
      // A signature and nothing else, and a body too long to be a notice.
      expect(verify(withBody(Uint8List(64)), alice), isNull);
      expect(
          verify(withBody(Uint8List(gv2MaxMemberNoticePayload + 65)), alice),
          isNull);
    });

    test('a payload has 1 to 1024 bytes', () {
      Uint8List seal(Uint8List payload) => gv2SealMemberNoticeEnvelope(
            keys: alice.keys,
            stamp: alice.stamp(),
            memberKey: alice.person.memberKey,
            payload: payload,
          );

      expect(() => seal(Uint8List(0)), throwsArgumentError);
      expect(() => seal(Uint8List(gv2MaxMemberNoticePayload + 1)),
          throwsArgumentError);
      final longest = gv2TestBytes('payload', gv2MaxMemberNoticePayload);
      expect(verify(open(seal(longest)), alice), longest);
    });
  });

  group('message ids', () {
    test('the local id is the hash of group, sender and message id', () {
      final groupId = gv2TestSha('group');
      final accountId = gv2TestBytes('account', 16);
      final messageId = gv2TestBytes('message', 16);
      final id = gv2LocalMessageId(
          groupId: groupId, senderAccountId: accountId, messageId: messageId);

      expect(
          id,
          hash.sha256
              .convert([...groupId, ...accountId, ...messageId]).bytes);
      expect(
          gv2LocalMessageId(
              groupId: gv2TestSha('group 2'),
              senderAccountId: accountId,
              messageId: messageId),
          isNot(id));
      expect(
          gv2LocalMessageId(
              groupId: groupId,
              senderAccountId: gv2TestBytes('account 2', 16),
              messageId: messageId),
          isNot(id));
      expect(
          () => gv2LocalMessageId(
              groupId: groupId,
              senderAccountId: accountId,
              messageId: Uint8List(15)),
          throwsArgumentError);
    });

    test('new message ids are 16 random bytes', () {
      final ids = {for (var i = 0; i < 100; i++) gv2Hex(gv2NewMessageId())};
      expect(ids.length, 100);
      expect(ids.every((id) => id.length == 32), isTrue);
    });
  });
}
