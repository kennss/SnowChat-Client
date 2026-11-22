/// @file        call_fingerprint_signature_test.dart
/// @description SC-10: a call's DTLS fingerprint is signed with the sender's Signal-layer Ed25519
///              key for that call (fpSig), and a received one is checked: the peer's own
///              signature for this call verifies; a signature of another call, of another
///              fingerprint, by another key, malformed, or with no key for the peer is refused;
///              no signature at all is refused too — fpSig is mandatory (Part 3 E).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (signatureField throws when it cannot sign — no unsigned SDP is sent).
///              Earlier 2026-11-22 (Part 3 E: an SDP without fpSig is refused). Earlier 2026-11-22
///
/// @functions
///  - main(): the cases above
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/call/call_verification.dart';

const _callId = '6f1c2b8e-1d2a-4c3b-9e8f-0a1b2c3d4e5f';
const _otherCall = '7a2d3c9f-2e3b-4d4c-8f90-1b2c3d4e5f60';

String _sdp(String fp) => 'v=0\r\no=- 1 2 IN IP4 127.0.0.1\r\n'
    'a=fingerprint:sha-256 $fp\r\na=setup:actpass\r\n';

const _fp = 'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
    'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';
const _otherFp = '00:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
    'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';

void main() {
  final seed = Uint8List.fromList(List.filled(32, 5));
  final peerKey = Uint8List.fromList(ed.SigningKey(seed: seed).verifyKey.asTypedList);
  final strangerKey = Uint8List.fromList(
      ed.SigningKey(seed: Uint8List.fromList(List.filled(32, 6))).verifyKey.asTypedList);

  Future<RemoteFingerprintCheck> check(
    Object? fpSig, {
    Object? callId = _callId,
    String fp = _fp,
    Uint8List? key,
    bool noKey = false,
  }) =>
      CallVerification.checkRemote(
        fpSig: fpSig,
        callId: callId,
        sdp: _sdp(fp),
        peerKey: () async => noKey ? null : (key ?? peerKey),
      );

  String sign({String callId = _callId, String fp = _fp}) =>
      CallVerification.signatureField(
        callId: callId,
        sdp: _sdp(fp),
        signingKeySeed: seed,
      )['fpSig']!;

  test('the peer\'s signature of this call and this fingerprint verifies',
      () async {
    expect(await check(sign()), RemoteFingerprintCheck.verified);
  });

  test('the fingerprint is compared in lower case (as parsed from the SDP)',
      () async {
    expect(await check(sign(fp: _fp.toLowerCase())), RemoteFingerprintCheck.verified);
  });

  test('a signature of another call is refused', () async {
    expect(await check(sign(callId: _otherCall)), RemoteFingerprintCheck.refused);
  });

  test('a signature of another fingerprint is refused', () async {
    expect(await check(sign(fp: _otherFp)), RemoteFingerprintCheck.refused);
  });

  test('a signature by another key is refused', () async {
    expect(await check(sign(), key: strangerKey), RemoteFingerprintCheck.refused);
  });

  test('no key for the peer: a signed SDP cannot be checked and is refused',
      () async {
    expect(await check(sign(), noKey: true), RemoteFingerprintCheck.refused);
    expect(
      await CallVerification.checkRemote(
        fpSig: sign(),
        callId: _callId,
        sdp: _sdp(_fp),
        peerKey: () async => throw StateError('directory unreachable'),
      ),
      RemoteFingerprintCheck.refused,
    );
  });

  test('malformed: not base64, wrong type, no call id, no fingerprint line',
      () async {
    expect(await check('***'), RemoteFingerprintCheck.refused);
    expect(await check(42), RemoteFingerprintCheck.refused);
    expect(await check(base64Encode(List.filled(64, 0))), RemoteFingerprintCheck.refused);
    expect(await check(sign(), callId: null), RemoteFingerprintCheck.refused);
    expect(
      await CallVerification.checkRemote(
        fpSig: sign(),
        callId: _callId,
        sdp: 'v=0\r\n',
        peerKey: () async => peerKey,
      ),
      RemoteFingerprintCheck.refused,
    );
  });

  test('no signature at all: refused — the signature is mandatory', () async {
    expect(await check(null, noKey: true), RemoteFingerprintCheck.refused);
    expect(await check(null), RemoteFingerprintCheck.refused);
  });

  test('nothing to sign with, no call id or no fingerprint: no unsigned field — '
      'it throws (the caller ends the call)', () {
    final cannot = throwsA(isA<CallVerificationException>());
    expect(
      () => CallVerification.signatureField(
          callId: _callId, sdp: _sdp(_fp), signingKeySeed: null),
      cannot,
    );
    expect(
      () => CallVerification.signatureField(
          callId: null, sdp: _sdp(_fp), signingKeySeed: seed),
      cannot,
    );
    expect(
      () => CallVerification.signatureField(
          callId: _callId, sdp: 'v=0\r\n', signingKeySeed: seed),
      cannot,
    );
  });
}
