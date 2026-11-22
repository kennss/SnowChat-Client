/// @file        gv2_keys_test.dart
/// @description Group protocol v2 client keys, payloads and member checks:
///              key derivations against an independent HKDF, the golden
///              vectors of test/fixtures/gv2_keys_v1.json (this Dart
///              implementation is the reference for these formats — the
///              server never sees them in the clear), the member certificate,
///              the sealed member and title payloads, entries signed here and
///              accepted by the state machine, confirming the account behind
///              a member, deletion verdicts, and the IdentityManager methods
///              that reach the account key.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - main(): the test groups below.
///  - _buildVectors(): the golden vectors, derived from fixed labels.
///  - _hkdf(): HKDF-SHA256 on package:crypto, independent of core/crypto/hkdf.dart.
///  - _Person: an account with its member key and payload in the test group.
///
/// Notes:
///  - `GV2_KEYS_WRITE_VECTORS=1 flutter test test/core/group_v2/gv2_keys_test.dart`
///    rewrites the fixture after an INTENDED format change. Every value in it
///    is deterministic, so the file must otherwise equal what this test
///    rebuilds.
///  - Member ciphertexts are arbitrary 65-byte values here and the account id
///    is passed in directly: decrypting a ciphertext is zkgroup's job (native)
///    and is tested with the sync module.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as nacl;
import 'package:snowchat/core/crypto/account_deletion_proof.dart';
import 'package:snowchat/core/crypto/ed25519_strict.dart';
import 'package:snowchat/core/crypto/hkdf.dart' show hkdfDerive;
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_member_check.dart';
import 'package:snowchat/core/group_v2/gv2_payloads.dart';
import 'package:snowchat/core/group_v2/gv2_state_machine.dart';

import '../crypto/identity_test_support.dart';

const _fixturePath = 'test/fixtures/gv2_keys_v1.json';
const _issuedAtMs = 1794528000000;

Uint8List _sha(String label) =>
    Uint8List.fromList(hash.sha256.convert(utf8.encode(label)).bytes);

Uint8List _bytes(String label, int length) {
  final b = BytesBuilder();
  for (var i = 0; b.length < length; i++) {
    b.add(_sha('$label #$i'));
  }
  return Uint8List.fromList(b.takeBytes().sublist(0, length));
}

Uint8List _concat(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

/// HKDF-SHA256 (RFC 5869) built on package:crypto.
Uint8List _hkdf(List<int> ikm, List<int> salt, List<int> info, int length) {
  final prk = hash.Hmac(hash.sha256, salt).convert(ikm).bytes;
  final out = <int>[];
  var previous = <int>[];
  for (var i = 1; out.length < length; i++) {
    previous =
        hash.Hmac(hash.sha256, prk).convert([...previous, ...info, i]).bytes;
    out.addAll(previous);
  }
  return Uint8List.fromList(out.sublist(0, length));
}

/// SecretBox with a FIXED nonce — for golden vectors only.
Uint8List _sealWithNonce(Uint8List key, Uint8List nonce, Uint8List plain) {
  final sealed = nacl.SecretBox(key).encrypt(plain, nonce: nonce);
  return _concat([nonce, sealed.cipherText]);
}

/// What plain TweetNaCl says, without the strict checks.
bool _laxVerify(Uint8List key, Uint8List message, Uint8List sig) {
  try {
    return ed.VerifyKey(key).verify(signature: ed.Signature(sig), message: message);
  } catch (_) {
    return false;
  }
}

/// The same signature with the group order added to its scalar half.
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

/// An account with everything it brings to the test group.
class _Person {
  final Uint8List accountSeed;
  final Uint8List accountPub;
  final Uint8List accountId;
  final String snowId;
  final Uint8List ciphertext;
  final Gv2SigningKey memberKey;

  _Person._(this.accountSeed, this.accountPub, this.ciphertext, this.memberKey)
      : accountId = Uint8List.fromList(accountPub.sublist(0, 16)),
        snowId = KeyDerivation.deriveSnowChatId(accountPub);

  factory _Person(String name, Uint8List groupId) {
    final seed = _sha('gv2 keys v1 — account $name');
    final pub = Uint8List.fromList(ed.SigningKey(seed: seed).verifyKey.asTypedList);
    return _Person._(
      seed,
      pub,
      _bytes('gv2 keys v1 — ciphertext $name', gv2CiphertextLen),
      Gv2SigningKey.fromSeed(gv2DeriveMemberSeed(seed, groupId)),
    );
  }

  Uint8List certSignature(Uint8List groupId, {int issuedAtMs = _issuedAtMs}) =>
      Uint8List.fromList(ed.SigningKey(seed: accountSeed)
          .sign(gv2MemberCertMessage(
              groupId: groupId,
              memberPub: memberKey.publicKey,
              issuedAtMs: issuedAtMs))
          .signature
          .asTypedList);

  Gv2MemberPayload payload(Uint8List groupId, {int issuedAtMs = _issuedAtMs}) =>
      Gv2MemberPayload(
        accountPublicKey: accountPub,
        issuedAtMs: issuedAtMs,
        certSignature: certSignature(groupId, issuedAtMs: issuedAtMs),
      );
}

/// Every golden value, rebuilt from fixed labels.
Map<String, dynamic> _buildVectors() {
  final masterKey = _sha('gv2 keys v1 — master key');
  final groupId = _sha('gv2 keys v1 — group id');
  final alice = _Person('alice', groupId);
  final stateKey = gv2DeriveStateKey(masterKey, groupId);

  final certMessage = gv2MemberCertMessage(
      groupId: groupId, memberPub: alice.memberKey.publicKey, issuedAtMs: _issuedAtMs);
  final memberPlain = gv2EncodeMemberPayload(alice.payload(groupId));

  final serverPublicParams = _bytes('gv2 keys v1 — server public params', 97);
  final headKey = Gv2SigningKey.fromSeed(_sha('gv2 keys v1 — head key'));
  final serverKeyHash = gv2ServerKeyHash(
      serverPublicParams: serverPublicParams, headPublicKey: headKey.publicKey);
  const name = 'Snow ❄ 눈 내리는 방';
  final titlePlain = gv2EncodeTitlePayload(
      Gv2TitlePayload(name: name, serverKeyHash: serverKeyHash));

  final inviteKey = Gv2SigningKey.fromSeed(_sha('gv2 keys v1 — invite key'));
  final acceptMessage = gv2InviteAcceptMessage(
      groupId, alice.ciphertext, alice.memberKey.publicKey);

  return {
    'version': 1,
    'note': 'Golden vectors for the client-side formats of group protocol v2 '
        '(app/lib/core/group_v2/gv2_keys.dart, gv2_payloads.dart). The Dart '
        'implementation is the reference: the server stores these values as '
        'opaque bytes. Every value is derived from fixed labels '
        '(seed = SHA256(label)); groupId and ciphertext are arbitrary bytes '
        'here, not zkgroup outputs.',
    'masterKeyHex': gv2Hex(masterKey),
    'groupIdHex': gv2Hex(groupId),
    'derived': {
      'stateKeyHex': gv2Hex(stateKey),
      'envelopeKeyHex': gv2Hex(gv2DeriveEnvelopeKey(masterKey, groupId)),
      'hintKeyHex': gv2Hex(gv2DeriveHintKey(masterKey, groupId)),
    },
    'account': {
      'seedHex': gv2Hex(alice.accountSeed),
      'publicKeyHex': gv2Hex(alice.accountPub),
      'snowId': alice.snowId,
      'ciphertextHex': gv2Hex(alice.ciphertext),
    },
    'memberKey': {
      'seedHex': gv2Hex(alice.memberKey.seed),
      'publicKeyHex': gv2Hex(alice.memberKey.publicKey),
    },
    'memberCert': {
      'issuedAtMs': _issuedAtMs.toString(),
      'messageHex': gv2Hex(certMessage),
      'sigHex': gv2Hex(alice.certSignature(groupId)),
    },
    'memberPayload': {
      'plainHex': gv2Hex(memberPlain),
      'sealedHex': gv2Hex(_sealWithNonce(
          stateKey, _bytes('gv2 keys v1 — member nonce', 24), memberPlain)),
    },
    'serverKeys': {
      'publicParamsHex': gv2Hex(serverPublicParams),
      'headPublicKeyHex': gv2Hex(headKey.publicKey),
      'hashHex': gv2Hex(serverKeyHash),
    },
    'titlePayload': {
      'name': name,
      'plainHex': gv2Hex(titlePlain),
      'sealedHex': gv2Hex(_sealWithNonce(
          stateKey, _bytes('gv2 keys v1 — title nonce', 24), titlePlain)),
    },
    'invite': {
      'seedHex': gv2Hex(inviteKey.seed),
      'publicKeyHex': gv2Hex(inviteKey.publicKey),
      'acceptMessageHex': gv2Hex(acceptMessage),
      'inviteSigHex': gv2Hex(gv2SignInviteAccept(
        inviteKey: inviteKey,
        groupId: groupId,
        ciphertext: alice.ciphertext,
        memberPub: alice.memberKey.publicKey,
      )),
    },
  };
}

void main() {
  final built = _buildVectors();
  if (Platform.environment['GV2_KEYS_WRITE_VECTORS'] == '1') {
    File(_fixturePath).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(built)}\n');
  }
  final fixture =
      jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> section(String name) =>
      Map<String, dynamic>.from(fixture[name] as Map);

  final masterKey = gv2Unhex(fixture['masterKeyHex'] as String);
  final groupId = gv2Unhex(fixture['groupIdHex'] as String);
  final stateKey = gv2DeriveStateKey(masterKey, groupId);
  final alice = _Person('alice', groupId);
  final bob = _Person('bob', groupId);
  final carol = _Person('carol', groupId);
  final serverKeyHash = gv2Unhex(section('serverKeys')['hashHex'] as String);

  test('the fixture is exactly what this implementation produces', () {
    expect(fixture, built);
  });

  group('derivations', () {
    test('HKDF matches RFC 5869 test case 1', () {
      final okm = hkdfDerive(
        ikm: Uint8List.fromList(List.filled(22, 0x0b)),
        salt: gv2Unhex('000102030405060708090a0b0c'),
        info: gv2Unhex('f0f1f2f3f4f5f6f7f8f9'),
        length: 42,
      );
      expect(
          gv2Hex(okm),
          '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
          '34007208d5b887185865');
    });

    test('group keys equal an independent HKDF of the documented inputs', () {
      final derived = section('derived');
      expect(derived['stateKeyHex'],
          gv2Hex(_hkdf(masterKey, groupId, ascii.encode('SnowChat_GV2_State_v1'), 32)));
      expect(derived['envelopeKeyHex'],
          gv2Hex(_hkdf(masterKey, groupId, ascii.encode('SnowChat_GV2_Envelope_v1'), 32)));
      expect(
          derived['hintKeyHex'],
          gv2Hex(_hkdf(
              masterKey, groupId, ascii.encode('SnowChat_GV2_EnvelopeHint_v1'), 32)));
      expect({derived['stateKeyHex'], derived['envelopeKeyHex'], derived['hintKeyHex']}.length, 3);
    });

    test('the member seed equals an independent HKDF of the documented inputs', () {
      expect(
          section('memberKey')['seedHex'],
          gv2Hex(_hkdf(alice.accountSeed, ascii.encode('SnowChat_GV2_MemberKey_v1'),
              groupId, 32)));
    });

    test('member keys differ per group and per account', () {
      final otherGroup = _sha('gv2 keys v1 — another group');
      final here = gv2DeriveMemberSeed(alice.accountSeed, groupId);
      expect(gv2DeriveMemberSeed(alice.accountSeed, groupId), here);
      expect(gv2DeriveMemberSeed(alice.accountSeed, otherGroup), isNot(here));
      expect(gv2DeriveMemberSeed(bob.accountSeed, groupId), isNot(here));
      expect(here, isNot(alice.accountSeed));
    });

    test('another master key or group id gives other group keys', () {
      final otherGroup = _sha('gv2 keys v1 — another group');
      final otherMaster = _sha('gv2 keys v1 — another master key');
      expect(gv2DeriveStateKey(masterKey, otherGroup), isNot(stateKey));
      expect(gv2DeriveStateKey(otherMaster, groupId), isNot(stateKey));
    });

    test('inputs of the wrong length are refused', () {
      expect(() => gv2DeriveStateKey(Uint8List(31), groupId), throwsArgumentError);
      expect(() => gv2DeriveStateKey(masterKey, Uint8List(33)), throwsArgumentError);
      expect(() => gv2DeriveMemberSeed(Uint8List(64), groupId), throwsArgumentError);
      expect(() => Gv2SigningKey.fromSeed(Uint8List(31)), throwsArgumentError);
    });

    test('a new master key is 32 random bytes', () {
      final a = gv2NewMasterKey();
      expect(a.length, gv2MasterKeyLen);
      expect(gv2NewMasterKey(), isNot(a));
    });
  });

  group('member certificate', () {
    final sig = gv2Unhex(section('memberCert')['sigHex'] as String);
    bool verify({
      Uint8List? account,
      Uint8List? group,
      Uint8List? member,
      int issuedAtMs = _issuedAtMs,
      Uint8List? signature,
    }) =>
        gv2VerifyMemberCert(
          accountPublicKey: account ?? alice.accountPub,
          groupId: group ?? groupId,
          memberPub: member ?? alice.memberKey.publicKey,
          issuedAtMs: issuedAtMs,
          signature: signature ?? sig,
        );

    test('the message has the documented layout', () {
      final message = gv2Unhex(section('memberCert')['messageHex'] as String);
      expect(message.length, gv2MemberCertMessageLen);
      expect(message[0], 0xff);
      expect(ascii.decode(message.sublist(1, 27)), 'SnowChat_GV2_MemberCert_v1');
      expect(message.sublist(27, 59), groupId);
      expect(message.sublist(59, 91), alice.memberKey.publicKey);
      expect(ByteData.sublistView(message).getUint64(91), _issuedAtMs);
    });

    test('verifies only for exactly what was signed', () {
      expect(verify(), isTrue);
      expect(verify(group: _sha('gv2 keys v1 — another group')), isFalse);
      expect(verify(member: bob.memberKey.publicKey), isFalse);
      expect(verify(issuedAtMs: _issuedAtMs + 1), isFalse);
      expect(verify(account: bob.accountPub), isFalse);
      final tampered = Uint8List.fromList(sig)..[5] ^= 0x01;
      expect(verify(signature: tampered), isFalse);
      expect(verify(signature: Uint8List(63)), isFalse);
      expect(verify(member: Uint8List(31)), isFalse);
    });

    test('a signature only a lax verifier accepts is refused', () {
      final message = gv2Unhex(section('memberCert')['messageHex'] as String);
      final malleated = _plusGroupOrder(sig);
      expect(_laxVerify(alice.accountPub, message, malleated), isTrue);
      expect(verifyEd25519Strict(alice.accountPub, message, malleated), isFalse);
      expect(verify(signature: malleated), isFalse);
    });
  });

  group('member payload', () {
    final plain = gv2Unhex(section('memberPayload')['plainHex'] as String);
    final sealed = gv2Unhex(section('memberPayload')['sealedHex'] as String);

    test('the golden bytes open to the account and its certificate', () {
      expect(plain.length, gv2MemberPayloadPlainLen);
      expect(sealed.length, gv2MemberPayloadSealedLen);
      final payload = gv2OpenMemberPayload(stateKey, sealed)!;
      expect(payload.accountPublicKey, alice.accountPub);
      expect(payload.issuedAtMs, _issuedAtMs);
      expect(payload.certSignature, gv2Unhex(section('memberCert')['sigHex'] as String));
      expect(gv2EncodeMemberPayload(payload), plain);
    });

    test('sealing uses a fresh nonce and round-trips', () {
      final a = gv2SealMemberPayload(stateKey, alice.payload(groupId));
      final b = gv2SealMemberPayload(stateKey, alice.payload(groupId));
      expect(a, isNot(b));
      expect(a.length, gv2MemberPayloadSealedLen);
      expect(gv2EncodeMemberPayload(gv2OpenMemberPayload(stateKey, a)!), plain);
      expect(gv2EncodeMemberPayload(gv2OpenMemberPayload(stateKey, b)!), plain);
    });

    test('fits the size the server allows', () {
      expect(gv2MemberPayloadSealedLen, lessThanOrEqualTo(gv2MaxMemberPayload));
      expect(gv2TitlePayloadSealedLen, lessThanOrEqualTo(gv2MaxTitlePayload));
    });

    test('does not open with another key, altered, cut or extended', () {
      expect(gv2OpenMemberPayload(gv2DeriveEnvelopeKey(masterKey, groupId), sealed), isNull);
      expect(gv2OpenMemberPayload(Uint8List(31), sealed), isNull);
      for (final index in [0, 23, 24, 40, sealed.length - 1]) {
        final altered = Uint8List.fromList(sealed)..[index] ^= 0x01;
        expect(gv2OpenMemberPayload(stateKey, altered), isNull, reason: 'byte $index');
      }
      expect(gv2OpenMemberPayload(stateKey, sealed.sublist(0, sealed.length - 1)), isNull);
      expect(gv2OpenMemberPayload(stateKey, _concat([sealed, [0]])), isNull);
      expect(gv2OpenMemberPayload(stateKey, Uint8List(0)), isNull);
    });

    test('a title payload is not a member payload, and the reverse', () {
      final title = gv2Unhex(section('titlePayload')['sealedHex'] as String);
      expect(gv2OpenMemberPayload(stateKey, title), isNull);
      expect(gv2OpenTitlePayload(stateKey, sealed), isNull);
    });

    test('only the one encoding decodes', () {
      Uint8List mutate(void Function(Uint8List b) f) {
        final copy = Uint8List.fromList(plain);
        f(copy);
        return copy;
      }

      expect(gv2DecodeMemberPayload(plain), isNotNull);
      expect(gv2DecodeMemberPayload(mutate((b) => b[0] = 0x02)), isNull, reason: 'kind');
      expect(gv2DecodeMemberPayload(mutate((b) => b[1] = 0x02)), isNull, reason: 'version');
      expect(gv2DecodeMemberPayload(mutate((b) => b[34] = 0x80)), isNull,
          reason: 'time beyond 2^63');
      expect(gv2DecodeMemberPayload(plain.sublist(0, plain.length - 1)), isNull);
      expect(gv2DecodeMemberPayload(_concat([plain, [0]])), isNull);
      // Sealed correctly but with a body of another shape.
      final odd = _sealWithNonce(stateKey, Uint8List(24), mutate((b) => b[1] = 0x09));
      expect(gv2OpenMemberPayload(stateKey, odd), isNull);
    });

    test('fields of the wrong length are refused when encoding', () {
      expect(
          () => gv2EncodeMemberPayload(Gv2MemberPayload(
              accountPublicKey: Uint8List(31),
              issuedAtMs: 1,
              certSignature: Uint8List(64))),
          throwsArgumentError);
      expect(
          () => gv2EncodeMemberPayload(Gv2MemberPayload(
              accountPublicKey: Uint8List(32),
              issuedAtMs: -1,
              certSignature: Uint8List(64))),
          throwsArgumentError);
    });
  });

  group('title payload', () {
    final plain = gv2Unhex(section('titlePayload')['plainHex'] as String);
    final sealed = gv2Unhex(section('titlePayload')['sealedHex'] as String);

    test('the golden bytes open to the name and the server key hash', () {
      final title = gv2OpenTitlePayload(stateKey, sealed)!;
      expect(title.name, section('titlePayload')['name']);
      expect(title.serverKeyHash, serverKeyHash);
      expect(gv2EncodeTitlePayload(title), plain);
    });

    test('every name seals to the same length', () {
      for (final name in ['', 'a', '눈', 'x' * 256, '눈' * 85]) {
        final s = gv2SealTitlePayload(
            stateKey, Gv2TitlePayload(name: name, serverKeyHash: serverKeyHash));
        expect(s.length, gv2TitlePayloadSealedLen, reason: 'name of ${name.length}');
        expect(gv2OpenTitlePayload(stateKey, s)!.name, name);
      }
    });

    test('a name that is too long or has no canonical bytes is refused', () {
      Uint8List encode(String name) => gv2EncodeTitlePayload(
          Gv2TitlePayload(name: name, serverKeyHash: serverKeyHash));
      expect(() => encode('x' * 257), throwsArgumentError);
      expect(() => encode('눈' * 86), throwsArgumentError, reason: '258 bytes');
      expect(() => encode('﻿name'), throwsArgumentError, reason: 'byte-order mark');
      expect(() => encode('a${String.fromCharCode(0xD800)}b'), throwsArgumentError,
          reason: 'unpaired surrogate');
      expect(
          () => gv2EncodeTitlePayload(
              Gv2TitlePayload(name: 'a', serverKeyHash: Uint8List(31))),
          throwsArgumentError);
    });

    test('only the one encoding decodes', () {
      Uint8List mutate(void Function(Uint8List b) f) {
        final copy = Uint8List.fromList(plain);
        f(copy);
        return copy;
      }

      final nameLength = ByteData.sublistView(plain).getUint16(34);
      expect(gv2DecodeTitlePayload(plain), isNotNull);
      expect(gv2DecodeTitlePayload(mutate((b) => b[0] = 0x01)), isNull, reason: 'kind');
      expect(gv2DecodeTitlePayload(mutate((b) => b[1] = 0x00)), isNull, reason: 'version');
      expect(gv2DecodeTitlePayload(mutate((b) => b[291] = 0x01)), isNull,
          reason: 'non-zero padding');
      expect(gv2DecodeTitlePayload(mutate((b) => b[36 + nameLength] = 0x20)), isNull,
          reason: 'byte after the name');
      expect(gv2DecodeTitlePayload(mutate((b) => b[34] = 0x01)), isNull,
          reason: 'length beyond the field');
      expect(gv2DecodeTitlePayload(mutate((b) => b[36] = 0xff)), isNull,
          reason: 'not UTF-8');
      expect(
          gv2DecodeTitlePayload(mutate((b) {
            // A name that starts with a byte-order mark.
            b[35] = 4;
            b.setAll(36, [0xef, 0xbb, 0xbf, 0x61]);
            b.fillRange(40, b.length, 0);
          })),
          isNull,
          reason: 'byte-order mark');
      expect(gv2DecodeTitlePayload(plain.sublist(0, plain.length - 1)), isNull);
      expect(gv2DecodeTitlePayload(_concat([plain, [0]])), isNull);
    });

    test('does not open with another key or altered', () {
      expect(gv2OpenTitlePayload(gv2DeriveHintKey(masterKey, groupId), sealed), isNull);
      final altered = Uint8List.fromList(sealed)..[100] ^= 0x01;
      expect(gv2OpenTitlePayload(stateKey, altered), isNull);
    });
  });

  group('server key hash', () {
    final keys = section('serverKeys');
    final params = gv2Unhex(keys['publicParamsHex'] as String);
    final headPub = gv2Unhex(keys['headPublicKeyHex'] as String);

    test('is SHA256 of label, length-prefixed params and the head key', () {
      final expected = hash.sha256.convert([
        ...ascii.encode('SnowChat_GV2_ServerKeys_v1'),
        0, 0, 0, params.length,
        ...params,
        ...headPub,
      ]).bytes;
      expect(keys['hashHex'], gv2Hex(expected));
    });

    test('changes with either key, and the boundary cannot be moved', () {
      Uint8List h(Uint8List p, Uint8List k) =>
          gv2ServerKeyHash(serverPublicParams: p, headPublicKey: k);
      final base = h(params, headPub);
      expect(h(Uint8List.fromList(params)..[0] ^= 1, headPub), isNot(base));
      expect(h(params, Uint8List.fromList(headPub)..[0] ^= 1), isNot(base));
      // Same concatenated bytes, one byte moved across the boundary.
      final all = _concat([params, headPub]);
      expect(
          h(Uint8List.fromList(all.sublist(0, params.length + 1)),
              _concat([all.sublist(params.length + 1), [0]])),
          isNot(base));
      expect(() => h(params, Uint8List(31)), throwsArgumentError);
    });
  });

  group('signing entries', () {
    final bobInvite = Gv2SigningKey.fromSeed(_sha('gv2 keys v1 — invite bob'));
    final carolInvite = Gv2SigningKey.fromSeed(_sha('gv2 keys v1 — invite carol'));
    final none = Uint8List(0);

    Gv2EntryDraft createDraft() => Gv2EntryDraft(
          version: gv2ProtocolVersion,
          revision: 0,
          prevChain: gv2GenesisPrevChain(),
          actor: alice.ciphertext,
          actions: [
            Gv2Create(alice.memberKey.publicKey),
            Gv2Invite(bob.ciphertext, bobInvite.publicKey),
            Gv2Invite(carol.ciphertext, carolInvite.publicKey),
          ],
          memberPayload: gv2SealMemberPayload(stateKey, alice.payload(groupId)),
          titlePayload: gv2SealTitlePayload(stateKey,
              Gv2TitlePayload(name: 'Snow', serverKeyHash: serverKeyHash)),
        );

    Gv2EntryDraft acceptDraft(Gv2GroupState state, Gv2SigningKey inviteKey) =>
        Gv2EntryDraft(
          version: gv2ProtocolVersion,
          revision: state.revision + 1,
          prevChain: state.chain,
          actor: bob.ciphertext,
          actions: [
            Gv2Accept(
              bob.memberKey.publicKey,
              gv2SignInviteAccept(
                inviteKey: inviteKey,
                groupId: groupId,
                ciphertext: bob.ciphertext,
                memberPub: bob.memberKey.publicKey,
              ),
            ),
          ],
          memberPayload: gv2SealMemberPayload(stateKey, bob.payload(groupId)),
          titlePayload: none,
        );

    test('create, accept and decline are accepted by the state machine', () {
      final created = gv2SignEntry(
          state: null, groupId: groupId, draft: createDraft(), key: alice.memberKey);
      expect(created.next.revision, 0);
      expect(created.next.members.keys, [gv2Hex(alice.ciphertext)]);
      expect(created.next.pending.length, 2);
      // The bytes on the wire replay to the same state.
      final replayed = gv2ApplyEntry(
          null, groupId, gv2DecodeEntry(gv2EncodeEntry(created.entry)));
      expect(gv2StateHash(replayed), created.entry.stateHashAfter);
      expect(replayed.chain, created.next.chain);

      final accepted = gv2SignEntry(
        state: created.next,
        groupId: groupId,
        draft: acceptDraft(created.next, bobInvite),
        key: bob.memberKey,
      );
      expect(accepted.next.members.length, 2);
      expect(accepted.next.pending.keys, [gv2Hex(carol.ciphertext)]);

      final declined = gv2SignEntry(
        state: accepted.next,
        groupId: groupId,
        draft: Gv2EntryDraft(
          version: gv2ProtocolVersion,
          revision: 2,
          prevChain: accepted.next.chain,
          actor: carol.ciphertext,
          actions: const [Gv2Decline()],
          memberPayload: none,
          titlePayload: none,
        ),
        // A DECLINE is signed with the one-time invite key.
        key: carolInvite,
      );
      expect(declined.next.pending, isEmpty);
      expect(declined.next.members.length, 2);
    });

    test('an entry signed with the wrong key is not produced', () {
      Gv2RejectCode codeOf(void Function() f) {
        try {
          f();
        } on Gv2Reject catch (e) {
          return e.code;
        }
        fail('expected a Gv2Reject');
      }

      expect(
          codeOf(() => gv2SignEntry(
              state: null, groupId: groupId, draft: createDraft(), key: bob.memberKey)),
          Gv2RejectCode.signature);

      final created = gv2SignEntry(
          state: null, groupId: groupId, draft: createDraft(), key: alice.memberKey);
      // ACCEPT with an invite signature from another invite's key.
      expect(
          codeOf(() => gv2SignEntry(
                state: created.next,
                groupId: groupId,
                draft: acceptDraft(created.next, carolInvite),
                key: bob.memberKey,
              )),
          Gv2RejectCode.inviteSignature);
      // DECLINE signed with the member key instead of the invite key.
      expect(
          codeOf(() => gv2SignEntry(
                state: created.next,
                groupId: groupId,
                draft: Gv2EntryDraft(
                  version: gv2ProtocolVersion,
                  revision: 1,
                  prevChain: created.next.chain,
                  actor: carol.ciphertext,
                  actions: const [Gv2Decline()],
                  memberPayload: none,
                  titlePayload: none,
                ),
                key: carol.memberKey,
              )),
          Gv2RejectCode.signature);
    });

    test('a change the rules forbid is refused before anything is signed', () {
      final created = gv2SignEntry(
          state: null, groupId: groupId, draft: createDraft(), key: alice.memberKey);
      final joined = gv2SignEntry(
        state: created.next,
        groupId: groupId,
        draft: acceptDraft(created.next, bobInvite),
        key: bob.memberKey,
      );
      // Bob is a plain member: he may not remove the owner.
      expect(
        () => gv2SignEntry(
          state: joined.next,
          groupId: groupId,
          draft: Gv2EntryDraft(
            version: gv2ProtocolVersion,
            revision: 2,
            prevChain: joined.next.chain,
            actor: bob.ciphertext,
            actions: [Gv2Remove(alice.ciphertext)],
            memberPayload: none,
            titlePayload: none,
          ),
          key: bob.memberKey,
        ),
        throwsA(isA<Gv2Reject>()
            .having((e) => e.code, 'code', Gv2RejectCode.permission)),
      );
    });
  });

  group('confirming a member', () {
    Gv2MemberState stateOf(_Person p, {Uint8List? payload, Uint8List? memberPub}) =>
        Gv2MemberState(
          role: gv2RoleMember,
          memberPub: memberPub ?? p.memberKey.publicKey,
          joinedRevision: 0,
          memberPayload: payload ?? gv2SealMemberPayload(stateKey, p.payload(groupId)),
        );

    Gv2MemberCheck check(
      Gv2MemberState member, {
      Uint8List? accountId,
      Uint8List? key,
      Uint8List? pinned,
    }) =>
        gv2CheckMember(
          stateKey: key ?? stateKey,
          groupId: groupId,
          accountId: accountId ?? alice.accountId,
          member: member,
          pinnedAccountKey: pinned,
        );

    test('a member with a valid certificate is confirmed', () {
      final result = check(stateOf(alice));
      expect(result.confirmed, isTrue);
      expect(result.failure, isNull);
      expect(result.member!.snowId, alice.snowId);
      expect(result.member!.accountPublicKey, alice.accountPub);
      expect(result.member!.issuedAtMs, _issuedAtMs);
      expect(gv2SnowIdOfAccountId(alice.accountId), alice.snowId);
      // The same key already pinned for that snowId is fine.
      expect(check(stateOf(alice), pinned: alice.accountPub).confirmed, isTrue);
    });

    test('a payload that does not open: payload', () {
      expect(check(stateOf(alice), key: gv2DeriveHintKey(masterKey, groupId)).failure,
          Gv2MemberCheckFailure.payload);
      expect(check(stateOf(alice, payload: Uint8List(146))).failure,
          Gv2MemberCheckFailure.payload);
      expect(check(stateOf(alice, payload: Uint8List(0))).failure,
          Gv2MemberCheckFailure.payload);
    });

    test('a ciphertext that decrypts to another account: accountId', () {
      // Bob's slot carrying a copy of Alice's whole payload.
      expect(check(stateOf(alice), accountId: bob.accountId).failure,
          Gv2MemberCheckFailure.accountId);
      expect(check(stateOf(alice), accountId: Uint8List(15)).failure,
          Gv2MemberCheckFailure.accountId);
    });

    test('an account key that differs from the pinned one: pinnedKey', () {
      // Same first 16 bytes (same snowId), different key: what a server
      // substituting an account key would have to present.
      final lookalike = Uint8List.fromList(alice.accountPub)..[31] ^= 0x01;
      expect(check(stateOf(alice), pinned: lookalike).failure,
          Gv2MemberCheckFailure.pinnedKey);
    });

    test('a certificate that does not cover this member key: certificate', () {
      // Alice's payload on a slot registered with another member key.
      expect(check(stateOf(alice, memberPub: bob.memberKey.publicKey)).failure,
          Gv2MemberCheckFailure.certificate);
      // A certificate made for another group.
      final otherGroup = _sha('gv2 keys v1 — another group');
      final foreign = gv2SealMemberPayload(
          stateKey,
          Gv2MemberPayload(
            accountPublicKey: alice.accountPub,
            issuedAtMs: _issuedAtMs,
            certSignature: Uint8List.fromList(ed.SigningKey(seed: alice.accountSeed)
                .sign(gv2MemberCertMessage(
                    groupId: otherGroup,
                    memberPub: alice.memberKey.publicKey,
                    issuedAtMs: _issuedAtMs))
                .signature
                .asTypedList),
          ));
      expect(check(stateOf(alice, payload: foreign)).failure,
          Gv2MemberCheckFailure.certificate);
      // A key with the right first 16 bytes that signed nothing.
      final lookalike = Uint8List.fromList(alice.accountPub)..[31] ^= 0x01;
      final forged = gv2SealMemberPayload(
          stateKey,
          Gv2MemberPayload(
            accountPublicKey: lookalike,
            issuedAtMs: _issuedAtMs,
            certSignature: alice.certSignature(groupId),
          ));
      expect(check(stateOf(alice, payload: forged)).failure,
          Gv2MemberCheckFailure.certificate);
    });

    test('an account id of the wrong length has no snowId', () {
      expect(() => gv2SnowIdOfAccountId(Uint8List(32)), throwsArgumentError);
    });
  });

  group('deletion verdict', () {
    final member = Gv2ConfirmedMember(
        snowId: alice.snowId, accountPublicKey: alice.accountPub, issuedAtMs: _issuedAtMs);

    AccountDeletionProof proofBy(_Person signer, String snowId, int deletedAtMs) =>
        AccountDeletionProof(
          deletedAtMs: deletedAtMs,
          signature: Uint8List.fromList(ed.SigningKey(seed: signer.accountSeed)
              .sign(AccountDeletionProofV1.buildMessage(
                  snowId: snowId, deletedAtMs: deletedAtMs))
              .signature
              .asTypedList),
        );

    test('the account signed it after joining: deleted', () {
      expect(
          gv2JudgeDeletion(
              member: member, proof: proofBy(alice, alice.snowId, _issuedAtMs + 1)),
          Gv2DeletionVerdict.deleted);
    });

    test('not signed by the member account: signature', () {
      expect(
          gv2JudgeDeletion(
              member: member, proof: proofBy(bob, alice.snowId, _issuedAtMs + 1)),
          Gv2DeletionVerdict.signature);
      expect(
          gv2JudgeDeletion(
              member: member, proof: proofBy(bob, bob.snowId, _issuedAtMs + 1)),
          Gv2DeletionVerdict.signature);
      final good = proofBy(alice, alice.snowId, _issuedAtMs + 1);
      expect(
          gv2JudgeDeletion(
              member: member,
              proof: AccountDeletionProof(
                  deletedAtMs: good.deletedAtMs + 1000, signature: good.signature)),
          Gv2DeletionVerdict.signature,
          reason: 'time moved after signing');
    });

    test('the certificate is not older than the deletion: reissued', () {
      expect(
          gv2JudgeDeletion(
              member: member, proof: proofBy(alice, alice.snowId, _issuedAtMs)),
          Gv2DeletionVerdict.reissued);
      expect(
          gv2JudgeDeletion(
              member: member, proof: proofBy(alice, alice.snowId, _issuedAtMs - 5000)),
          Gv2DeletionVerdict.reissued);
    });
  });

  group('IdentityManager', () {
    Future<IdentityManager> managerOf(_Person p) async => IdentityManager(
        InMemorySecureStorage()
          ..data['identity_private_key'] = bytesToHexLower(p.accountSeed)
          ..data['identity_public_key'] = bytesToHexLower(p.accountPub)
          ..data['snow_chat_id'] = p.snowId);

    test('deriveGroupMemberKey is the documented derivation', () async {
      final manager = await managerOf(alice);
      final key = await manager.deriveGroupMemberKey(groupId);
      expect(gv2Hex(key.seed), section('memberKey')['seedHex']);
      expect(gv2Hex(key.publicKey), section('memberKey')['publicKeyHex']);
      final other =
          await manager.deriveGroupMemberKey(_sha('gv2 keys v1 — another group'));
      expect(other.publicKey, isNot(key.publicKey));
    });

    test('signGroupMemberCert certifies its own member key only', () async {
      final manager = await managerOf(alice);
      final sig = await manager.signGroupMemberCert(
          groupId: groupId, issuedAtMs: _issuedAtMs);
      expect(gv2Hex(sig), section('memberCert')['sigHex']);
      expect(
          gv2VerifyMemberCert(
            accountPublicKey: alice.accountPub,
            groupId: groupId,
            memberPub: alice.memberKey.publicKey,
            issuedAtMs: _issuedAtMs,
            signature: sig,
          ),
          isTrue);
    });

    test('the same recovery phrase gives the same member key after a reinstall',
        () async {
      final first = IdentityManager(InMemorySecureStorage());
      final mnemonic = await first.createIdentity();
      final before = await first.deriveGroupMemberKey(groupId);

      final second = IdentityManager(InMemorySecureStorage());
      await second.restoreIdentity(mnemonic);
      final after = await second.deriveGroupMemberKey(groupId);
      expect(after.publicKey, before.publicKey);

      final stranger = IdentityManager(InMemorySecureStorage());
      await stranger.createIdentity();
      expect((await stranger.deriveGroupMemberKey(groupId)).publicKey,
          isNot(before.publicKey));
    });

    test('nothing is derived or signed without an identity', () {
      final empty = IdentityManager(InMemorySecureStorage());
      expect(empty.deriveGroupMemberKey(groupId), throwsStateError);
      expect(empty.signGroupMemberCert(groupId: groupId, issuedAtMs: 1),
          throwsStateError);
    });
  });
}
