/// @file        vectors_test.dart
/// @description Host tests of the dart:ffi binding against the vectors the
///              SERVER's libsignal build produced
///              (native/snowchat_zkgroup/tests/vectors/zk_vectors.json — the
///              same file the Rust tests use). The build hook compiles the
///              Rust crate for this machine; every deterministic value must
///              match byte for byte through the C ABI.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-12
/// @lastUpdated 2026-11-12
///
/// @notes
///  - Presentations are randomized, so their server-side verification is
///    covered by the Rust tests (which can play the server role); here they
///    are only checked for shape and freshness.
///  - `now` comes from the vector file, so the vectors never expire.
///  - The isolate test proves the binding needs no per-isolate setup.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';
import 'package:test/test.dart';

void main() {
  final json =
      jsonDecode(
            File(
              '../../native/snowchat_zkgroup/tests/vectors/zk_vectors.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  Uint8List b64(Object? value) => base64Decode(value! as String);

  final now = json['now'] as int;
  final serverPublic = b64(json['serverPublicParams']);
  final masterKey = b64(json['masterKey']);
  final members = (json['members'] as List).cast<Map<String, dynamic>>();
  final accounts = [for (final m in members) b64(m['accountId'])];
  final ciphertexts = [for (final m in members) b64(m['ciphertext'])];
  final credentialJson = json['credential'] as Map<String, dynamic>;
  final endorsementsJson = json['endorsements'] as Map<String, dynamic>;
  final expiration = endorsementsJson['expiration'] as int;

  Matcher failsWith(ZkGroupError error) =>
      throwsA(isA<ZkGroupException>().having((e) => e.error, 'error', error));

  ZkEndorsements receive() => ZkGroup.receiveEndorsements(
    serverPublicParams: serverPublic,
    masterKey: masterKey,
    response: b64(endorsementsJson['response']),
    members: accounts,
    now: now,
  );

  test('group id and public params match the server implementation', () {
    final params = ZkGroup.groupParams(masterKey);
    expect(params.groupId, b64(json['groupId']));
    expect(params.publicParams, b64(json['groupPublicParams']));
    expect(params.groupId, hasLength(zkGroupIdLength));
    expect(
      () => ZkGroup.groupParams(Uint8List(31)),
      failsWith(ZkGroupError.invalidInput),
    );
    expect(
      () => ZkGroup.groupParams(Uint8List(0)),
      failsWith(ZkGroupError.invalidInput),
    );
  });

  test('member ciphertexts match and decrypt back', () {
    for (var i = 0; i < accounts.length; i++) {
      expect(
        ZkGroup.encryptMember(masterKey: masterKey, accountId: accounts[i]),
        ciphertexts[i],
      );
      expect(
        ZkGroup.decryptMember(masterKey: masterKey, ciphertext: ciphertexts[i]),
        accounts[i],
      );
    }
    final otherKey = Uint8List.fromList(List.generate(32, (i) => 200 - i));
    expect(
      () => ZkGroup.decryptMember(
        masterKey: otherKey,
        ciphertext: ciphertexts[0],
      ),
      failsWith(ZkGroupError.verificationFailed),
    );
    expect(
      () => ZkGroup.decryptMember(
        masterKey: masterKey,
        ciphertext: Uint8List.sublistView(ciphertexts[0], 0, 64),
      ),
      failsWith(ZkGroupError.invalidInput),
    );
    expect(
      () =>
          ZkGroup.encryptMember(masterKey: masterKey, accountId: Uint8List(15)),
      failsWith(ZkGroupError.invalidInput),
    );
  });

  test('received credential matches; presentations are fresh', () {
    final credential = ZkGroup.receiveAuthCredential(
      serverPublicParams: serverPublic,
      accountId: accounts[0],
      salt: b64(credentialJson['salt']),
      redemptionTime: credentialJson['redemptionTime'] as int,
      response: b64(credentialJson['response']),
    );
    expect(credential, b64(credentialJson['received']));

    final first = ZkGroup.presentAuthCredential(
      serverPublicParams: serverPublic,
      masterKey: masterKey,
      credential: credential,
    );
    final second = ZkGroup.presentAuthCredential(
      serverPublicParams: serverPublic,
      masterKey: masterKey,
      credential: credential,
    );
    expect(first, isNotEmpty);
    expect(first, isNot(second));

    expect(
      () => ZkGroup.receiveAuthCredential(
        serverPublicParams: serverPublic,
        accountId: accounts[1],
        salt: b64(credentialJson['salt']),
        redemptionTime: credentialJson['redemptionTime'] as int,
        response: b64(credentialJson['response']),
      ),
      failsWith(ZkGroupError.verificationFailed),
    );
    expect(
      () => ZkGroup.receiveAuthCredential(
        serverPublicParams: serverPublic,
        accountId: accounts[0],
        salt: Uint8List(32),
        redemptionTime: credentialJson['redemptionTime'] as int,
        response: b64(credentialJson['response']),
      ),
      failsWith(ZkGroupError.verificationFailed),
    );
  });

  test('received endorsements match the server implementation', () {
    final received = receive();
    expect(received.expiration, expiration);
    expect(received.endorsements, [
      for (final e in endorsementsJson['received'] as List) b64(e),
    ]);
  });

  test('endorsements for another roster or time are rejected', () {
    final response = b64(endorsementsJson['response']);
    ZkEndorsements receiveWith(List<Uint8List> roster, int at) =>
        ZkGroup.receiveEndorsements(
          serverPublicParams: serverPublic,
          masterKey: masterKey,
          response: response,
          members: roster,
          now: at,
        );

    expect(
      () => receiveWith(accounts.sublist(1), now),
      failsWith(ZkGroupError.verificationFailed),
    );
    expect(
      () => receiveWith([...accounts, Uint8List(16)], now),
      failsWith(ZkGroupError.verificationFailed),
    );
    expect(
      () => receiveWith(accounts, expiration + 1),
      failsWith(ZkGroupError.verificationFailed),
    );
    expect(
      () => receiveWith([...accounts.sublist(1), Uint8List(15)], now),
      failsWith(ZkGroupError.invalidInput),
    );
    expect(
      () => receiveWith(const [], now),
      failsWith(ZkGroupError.invalidInput),
    );
  });

  test('send tokens match the server implementation', () {
    final received = receive();
    for (final entry in (json['tokens'] as List).cast<Map<String, dynamic>>()) {
      final indices = (entry['members'] as List).cast<int>();
      final subset = [for (final i in indices) received.endorsements[i]];
      final token = ZkGroup.sendToken(
        masterKey: masterKey,
        endorsements: subset,
        expiration: received.expiration,
      );
      expect(token, b64(entry['token']), reason: 'members $indices');
      expect(
        ZkGroup.sendToken(
          masterKey: masterKey,
          endorsements: subset.reversed.toList(),
          expiration: received.expiration,
        ),
        token,
        reason: 'order must not matter',
      );
    }
    expect(
      () => ZkGroup.sendToken(
        masterKey: masterKey,
        endorsements: const [],
        expiration: expiration,
      ),
      failsWith(ZkGroupError.invalidInput),
    );
    expect(
      () => ZkGroup.sendToken(
        masterKey: masterKey,
        endorsements: [Uint8List(32)],
        expiration: expiration,
      ),
      failsWith(ZkGroupError.invalidInput),
    );
  });

  test('a fresh isolate needs no setup and gives the same result', () async {
    final here = ZkGroup.encryptMember(
      masterKey: masterKey,
      accountId: accounts[3],
    );
    final there = await Isolate.run(
      () => ZkGroup.encryptMember(masterKey: masterKey, accountId: accounts[3]),
    );
    expect(there, here);
    expect(here, ciphertexts[3]);
  });
}
