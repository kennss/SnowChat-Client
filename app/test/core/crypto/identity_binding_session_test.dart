/// @file        identity_binding_session_test.dart
/// @description B-2 Identity Binding v1 end-to-end over the REAL Signal layer
///              (X3DH + Double Ratchet, pinenacl): send-side admission inside
///              SignalProtocolService.createSession, receive-side verification
///              of the binding embedded in type-2 messages, the Signal-style
///              legacy policy (unverified → continue + notice, verified →
///              block until re-verify), multi-device selection, §5.6 session
///              purge, and Safety Number v2 symmetry.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10
///
/// @functions
///  - main(): createSession / receive / legacy / selection / safety tests
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/identity_admission.dart';
import 'package:snowchat/core/crypto/identity_binding.dart';
import 'package:snowchat/core/crypto/identity_binding_exception.dart';
import 'package:snowchat/core/crypto/identity_key_changed_exception.dart';
import 'package:snowchat/core/crypto/safety_number.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';

import 'identity_test_support.dart';

const _devA = 'aaaaaaaa-1111-4111-8111-111111111111';
const _devB = 'bbbbbbbb-2222-4222-8222-222222222222';
const _devB2 = 'bbbbbbbb-3333-4333-8333-333333333333';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Matcher _bindingRejected(IdentityBindingFailure reason) => isA<
        IdentityBindingInvalidException>()
    .having((e) => e.reason, 'reason', reason);

/// Collects identity events emitted by [store].
List<IdentityStoreEvent> _collect(VerifiedIdentityStore store) {
  final out = <IdentityStoreEvent>[];
  store.events.listen(out.add);
  return out;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('send side — createSession admission', () {
    late TestParty alice;
    late TestParty bob;

    setUp(() async {
      alice = await TestParty.create(seedByte: 1, deviceId: _devA);
      bob = await TestParty.create(seedByte: 2, deviceId: _devB);
    });

    test('valid binding → session created, record bound, latch = epoch',
        () async {
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub),
      );
      expect(await alice.signal.hasSession(bob.snowId, _devB), isTrue);
      final rec = await alice.store.get(bob.snowId);
      expect(rec!.bound, isTrue);
      expect(rec.identityKey, bob.identityKey);
      expect(rec.accountPublicKey, bob.accountPub);
      expect(await alice.store.latchedEpoch(bob.snowId), 1000);
    });

    test('tampered signature → rejected, no session, event emitted', () async {
      final events = _collect(alice.store);
      final good = bob.bindingFor(epoch: 1000);
      final sig = Uint8List.fromList(good.signature)..[0] ^= 1;
      await expectLater(
        alice.signal.createSession(
          recipientId: bob.snowId,
          deviceId: _devB,
          preKeyBundle: bob.bundle(
              binding: IdentityBinding(signature: sig, epoch: 1000),
              accountPublicKey: bob.accountPub),
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.signatureInvalid)),
      );
      expect(await alice.signal.hasSession(bob.snowId, _devB), isFalse);
      await _flush();
      expect(events.single.kind, IdentityEventKind.bindingRejected);
    });

    test('binding for a different snowId (server substitutes a bundle) → '
        'rejected', () async {
      final carol = await TestParty.create(seedByte: 3, deviceId: _devB);
      // Server answers a request for Carol with Bob's fully valid bundle.
      await expectLater(
        alice.signal.createSession(
          recipientId: carol.snowId,
          deviceId: _devB,
          preKeyBundle: bob.bundle(
              binding: bob.bindingFor(epoch: 1000),
              accountPublicKey: bob.accountPub),
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.signatureInvalid)),
      );
    });

    test('latched peer without binding → downgrade rejected', () async {
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub),
      );
      await alice.signal.deleteSession(bob.snowId, _devB);
      await expectLater(
        alice.signal.createSession(
          recipientId: bob.snowId,
          deviceId: _devB,
          preKeyBundle: bob.bundle(opkIndex: 1),
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.downgrade)),
      );
    });

    test('epoch regression (older binding for other keys) → rejected',
        () async {
      // Bob reinstalls (new keys, new device) and binds at epoch 2000.
      final bobNew = await TestParty.create(seedByte: 2, deviceId: _devB2);
      await alice.signal.createSession(
        recipientId: bobNew.snowId,
        deviceId: _devB2,
        preKeyBundle: bobNew.bundle(
            binding: bobNew.bindingFor(epoch: 2000),
            accountPublicKey: bobNew.accountPub),
      );
      // A hostile server replays Bob's OLD (validly signed) bundle.
      await expectLater(
        alice.signal.createSession(
          recipientId: bob.snowId,
          deviceId: _devB,
          preKeyBundle: bob.bundle(
              binding: bob.bindingFor(epoch: 1000),
              accountPublicKey: bob.accountPub),
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.epochRegression)),
      );
    });

    test('same keys re-signed later → accepted; same keys older epoch → '
        'accepted without store write', () async {
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub),
      );
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1500),
            accountPublicKey: bob.accountPub,
            opkIndex: 1),
      );
      expect(await alice.store.latchedEpoch(bob.snowId), 1500);
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub,
            opkIndex: 2),
      );
      expect((await alice.store.get(bob.snowId))!.epoch, 1500);
    });

    test('bound reinstall of the same account → non-blocking device notice '
        'and old sessions purged (§5.6)', () async {
      final events = _collect(alice.store);
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub),
      );
      final bobNew = await TestParty.create(seedByte: 2, deviceId: _devB2);
      await alice.signal.createSession(
        recipientId: bobNew.snowId,
        deviceId: _devB2,
        preKeyBundle: bobNew.bundle(
            binding: bobNew.bindingFor(epoch: 2000),
            accountPublicKey: bobNew.accountPub),
      );
      await _flush();
      expect(events.map((e) => e.kind),
          contains(IdentityEventKind.deviceKeysChanged));
      expect(await alice.signal.hasSession(bob.snowId, _devB), isFalse,
          reason: 'session with the superseded IK must be purged');
      expect(await alice.signal.hasSession(bobNew.snowId, _devB2), isTrue);
    });

    test('legacy → bound promotion with different keys → interception '
        'warning', () async {
      final events = _collect(alice.store);
      final mitm = await TestParty.create(seedByte: 9, deviceId: _devB);
      // Transition period: the server hands out an unbound attacker bundle
      // under Bob's snowId (accepted as legacy TOFU)…
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: mitm.bundle(),
      );
      // …then Bob upgrades and presents his real, bound keys.
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub),
      );
      await _flush();
      expect(events.map((e) => e.kind),
          contains(IdentityEventKind.interceptionSuspected));
      expect((await alice.store.get(bob.snowId))!.identityKey, bob.identityKey);
    });
  });

  group('legacy policy (§5.5, Signal style)', () {
    late TestParty alice;

    setUp(() async {
      alice = await TestParty.create(seedByte: 1, deviceId: _devA);
    });

    test('unverified key change → updated, notice, session continues',
        () async {
      final events = _collect(alice.store);
      final old = await TestParty.create(seedByte: 4, deviceId: _devB);
      final reinstalled = await TestParty.create(seedByte: 4, deviceId: _devB2);
      await alice.signal.createSession(
          recipientId: old.snowId, deviceId: _devB, preKeyBundle: old.bundle());
      await alice.signal.createSession(
          recipientId: old.snowId,
          deviceId: _devB2,
          preKeyBundle: reinstalled.bundle());
      await _flush();
      expect(events.single.kind, IdentityEventKind.legacyKeyChanged);
      expect((await alice.store.get(old.snowId))!.identityKey,
          reinstalled.identityKey);
      expect(await alice.signal.hasSession(old.snowId, _devB2), isTrue);
    });

    test('verified key change → blocked until re-verify; re-verify unblocks',
        () async {
      alice.store.verifiedLookup = (_) async => true;
      final events = _collect(alice.store);
      final old = await TestParty.create(seedByte: 5, deviceId: _devB);
      final reinstalled = await TestParty.create(seedByte: 5, deviceId: _devB2);
      await alice.signal.createSession(
          recipientId: old.snowId, deviceId: _devB, preKeyBundle: old.bundle());

      await expectLater(
        alice.signal.createSession(
            recipientId: old.snowId,
            deviceId: _devB2,
            preKeyBundle: reinstalled.bundle()),
        throwsA(isA<IdentityKeyChangedException>()),
      );
      await _flush();
      expect(events.single.kind, IdentityEventKind.legacyKeyChangeBlocked);
      expect((await alice.store.get(old.snowId))!.hasPendingChange, isTrue);

      // Still blocked even though the DAO flag would now read unverified.
      alice.store.verifiedLookup = (_) async => false;
      await expectLater(
        alice.signal.createSession(
            recipientId: old.snowId,
            deviceId: _devB2,
            preKeyBundle: reinstalled.bundle(opkIndex: 1)),
        throwsA(isA<IdentityKeyChangedException>()),
      );

      // Verify screen: user re-verifies → pending keys adopted.
      expect(await alice.store.acceptPendingChange(old.snowId), isTrue);
      await alice.signal.createSession(
          recipientId: old.snowId,
          deviceId: _devB2,
          preKeyBundle: reinstalled.bundle(opkIndex: 2));
      expect(await alice.signal.hasSession(old.snowId, _devB2), isTrue);
    });
  });

  group('receive side — binding embedded in type-2', () {
    late TestParty alice;
    late TestParty bob;

    Future<Map<String, dynamic>> aliceFirstMessage(String text,
        {bool embed = true}) async {
      if (embed) {
        alice.signal.setLocalIdentityBinding(alice.localBinding(epoch: 5000));
      }
      await alice.signal.createSession(
        recipientId: bob.snowId,
        deviceId: _devB,
        preKeyBundle: bob.bundle(
            binding: bob.bindingFor(epoch: 1000),
            accountPublicKey: bob.accountPub),
      );
      return alice.signal.encryptMessage(
          recipientId: bob.snowId, deviceId: _devB, plaintext: _utf8(text));
    }

    setUp(() async {
      alice = await TestParty.create(seedByte: 1, deviceId: _devA);
      bob = await TestParty.create(seedByte: 2, deviceId: _devB);
    });

    test('valid embedded binding → decrypts offline, sender recorded bound',
        () async {
      final enc = await aliceFirstMessage('hello');
      expect(enc['messageType'], 2);
      final json = jsonDecode(utf8.decode(enc['ciphertext'] as Uint8List));
      expect(json['identityBinding'], isNotNull);
      var lookups = 0;
      final pt = await bob.signal.decryptMessage(
        senderId: alice.snowId,
        deviceId: _devA,
        ciphertext: enc['ciphertext'] as Uint8List,
        messageType: 2,
        envelopeDeviceId: _devA,
        identityDirectoryLookup: () async {
          lookups++;
          return null;
        },
      );
      expect(utf8.decode(pt), 'hello');
      expect(lookups, 0, reason: 'bound sender must not hit the network');
      final rec = await bob.store.get(alice.snowId);
      expect(rec!.bound, isTrue);
      expect(rec.identityKey, alice.identityKey);
      expect(await bob.store.latchedEpoch(alice.snowId), 5000);
    });

    test('header IK swapped → rejected BEFORE any OPK is consumed', () async {
      final enc = await aliceFirstMessage('hello');
      final json = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(enc['ciphertext'] as Uint8List)) as Map);
      final mitm = await TestParty.create(seedByte: 9, deviceId: _devA);
      final tampered = Map<String, dynamic>.from(json)
        ..['identityKey'] = bytesToHexLower(mitm.identityKey);
      await expectLater(
        bob.signal.decryptMessage(
          senderId: alice.snowId,
          deviceId: _devA,
          ciphertext: _utf8(jsonEncode(tampered)),
          messageType: 2,
          envelopeDeviceId: _devA,
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.signatureInvalid)),
      );
      // The genuine message still decrypts → Bob's OPK was not burned.
      final pt = await bob.signal.decryptMessage(
        senderId: alice.snowId,
        deviceId: _devA,
        ciphertext: enc['ciphertext'] as Uint8List,
        messageType: 2,
        envelopeDeviceId: _devA,
      );
      expect(utf8.decode(pt), 'hello');
    });

    test('binding deviceId ≠ envelope / certificate deviceId → rejected',
        () async {
      final enc = await aliceFirstMessage('hello');
      await expectLater(
        bob.signal.decryptMessage(
          senderId: alice.snowId,
          deviceId: _devA,
          ciphertext: enc['ciphertext'] as Uint8List,
          messageType: 2,
          envelopeDeviceId: 'cccccccc-4444-4444-8444-444444444444',
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.deviceMismatch)),
      );
    });

    test('binding-less sender (old client) → directory fallback, legacy accept',
        () async {
      final enc = await aliceFirstMessage('legacy hi', embed: false);
      final json = jsonDecode(utf8.decode(enc['ciphertext'] as Uint8List));
      expect(json['identityBinding'], isNull);
      var lookups = 0;
      final pt = await bob.signal.decryptMessage(
        senderId: alice.snowId,
        deviceId: _devA,
        ciphertext: enc['ciphertext'] as Uint8List,
        messageType: 2,
        envelopeDeviceId: _devA,
        identityDirectoryLookup: () async {
          lookups++;
          return RemoteIdentityDirectory(
            accountPublicKey: alice.accountPub,
            devices: [
              RemoteDeviceIdentity(
                deviceId: _devA,
                identityKey: alice.identityKey,
                ed25519: alice.ed25519,
                binding: null,
                bindingUnparseable: false,
                index: 0,
              ),
            ],
          );
        },
      );
      expect(utf8.decode(pt), 'legacy hi');
      expect(lookups, 1);
      final rec = await bob.store.get(alice.snowId);
      expect(rec!.bound, isFalse);
      expect(rec.identityKey, alice.identityKey);
      expect(rec.accountPublicKey, alice.accountPub);
    });

    test('binding-less message from a latched sender → downgrade rejected',
        () async {
      await bob.store.raiseLatch(alice.snowId, 10);
      final enc = await aliceFirstMessage('hi', embed: false);
      await expectLater(
        bob.signal.decryptMessage(
          senderId: alice.snowId,
          deviceId: _devA,
          ciphertext: enc['ciphertext'] as Uint8List,
          messageType: 2,
          envelopeDeviceId: _devA,
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.downgrade)),
      );
    });

    test('binding-less message whose IK differs from the server-bound IK → '
        'rejected', () async {
      final enc = await aliceFirstMessage('hi', embed: false);
      final other = await TestParty.create(seedByte: 1, deviceId: _devA);
      await expectLater(
        bob.signal.decryptMessage(
          senderId: alice.snowId,
          deviceId: _devA,
          ciphertext: enc['ciphertext'] as Uint8List,
          messageType: 2,
          envelopeDeviceId: _devA,
          identityDirectoryLookup: () async => RemoteIdentityDirectory(
            accountPublicKey: other.accountPub,
            devices: [
              RemoteDeviceIdentity(
                deviceId: _devA,
                identityKey: other.identityKey,
                ed25519: other.ed25519,
                binding: other.bindingFor(epoch: 7),
                bindingUnparseable: false,
                index: 0,
              ),
            ],
          ),
        ),
        throwsA(_bindingRejected(IdentityBindingFailure.identityKeyMismatch)),
      );
    });

    test('directory lookup failure for an unknown sender is transient',
        () async {
      final enc = await aliceFirstMessage('hi', embed: false);
      await expectLater(
        bob.signal.decryptMessage(
          senderId: alice.snowId,
          deviceId: _devA,
          ciphertext: enc['ciphertext'] as Uint8List,
          messageType: 2,
          envelopeDeviceId: _devA,
          identityDirectoryLookup: () async => throw StateError('offline'),
        ),
        throwsA(isA<SignalProtocolException>().having(
            (e) => e is IdentityBindingInvalidException, 'hard', isFalse)),
      );
    });
  });

  group('device selection', () {
    test('highest valid epoch wins; invalid-only → rejected; none → first',
        () async {
      final bob = await TestParty.create(seedByte: 2, deviceId: _devB);
      final admission = IdentityAdmission(bob.store);
      RemoteDeviceIdentity dev(String id, IdentityBinding? b, int i,
              {bool unparseable = false}) =>
          RemoteDeviceIdentity(
            deviceId: id,
            identityKey: bob.identityKey,
            ed25519: bob.ed25519,
            binding: b,
            bindingUnparseable: unparseable,
            index: i,
          );

      final pick = admission.selectDevice(
        snowId: bob.snowId,
        accountPublicKey: bob.accountPub,
        devices: [
          dev(_devB, bob.bindingFor(epoch: 1), 0),
          dev(_devB2, bob.bindingFor(epoch: 5, deviceIdOverride: _devB2), 1),
          dev(_devA, bob.bindingFor(epoch: 9), 2), // signed for _devB → invalid
        ],
      );
      expect(pick!.deviceId, _devB2);

      expect(
        () => admission.selectDevice(
          snowId: bob.snowId,
          accountPublicKey: bob.accountPub,
          devices: [dev(_devA, bob.bindingFor(epoch: 9), 0)],
        ),
        throwsA(isA<IdentityBindingInvalidException>()),
      );
      expect(
        () => admission.selectDevice(
          snowId: bob.snowId,
          accountPublicKey: bob.accountPub,
          devices: [dev(_devB, null, 0, unparseable: true)],
        ),
        throwsA(isA<IdentityBindingInvalidException>()),
      );
      final legacy = admission.selectDevice(
        snowId: bob.snowId,
        accountPublicKey: bob.accountPub,
        devices: [dev(_devB, null, 0), dev(_devB2, null, 1)],
      );
      expect(legacy!.deviceId, _devB);
    });
  });

  group('Safety Number v2', () {
    test('both sides compute identical digits over account keys', () async {
      final a = await TestParty.create(seedByte: 1, deviceId: _devA);
      final b = await TestParty.create(seedByte: 2, deviceId: _devB);
      final fromA = SafetyNumber.compute(
        mySnowId: a.snowId,
        myEd25519: a.accountPub,
        theirSnowId: b.snowId,
        theirEd25519: b.accountPub,
        version: 2,
      );
      final fromB = SafetyNumber.compute(
        mySnowId: b.snowId,
        myEd25519: b.accountPub,
        theirSnowId: a.snowId,
        theirEd25519: a.accountPub,
        version: 2,
      );
      expect(fromA, fromB);
      expect(fromA.length, 60);
      final v1 = SafetyNumber.compute(
        mySnowId: a.snowId,
        myEd25519: a.accountPub,
        theirSnowId: b.snowId,
        theirEd25519: b.accountPub,
      );
      expect(v1, isNot(fromA), reason: 'v1/v2 numbers must never collide');
    });
  });

}
