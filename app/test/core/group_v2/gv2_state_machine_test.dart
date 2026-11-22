/// @file        gv2_state_machine_test.dart
/// @description Group protocol v2 codec + state machine against the vectors
///              shared with the server (test/fixtures/gv2_state_machine_v1.json,
///              a byte-identical copy of
///              server/src/gv2/__fixtures__/gv2_state_machine_v1.json): the
///              accepted log must replay to the same chain and state hash at
///              every revision, and every rejected entry must be refused with
///              the SAME code the server gives. Also: the canonical byte
///              format (re-encoding, decoder strictness), the writer-side
///              preview, and the two signatures a lax Ed25519 verifier would
///              let through.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-21 (P5.6 vectors: a change of exactly 64 actions taken, 65 refused as shape). Earlier 2026-11-13
///
/// @functions
///  - main(): the test groups below.
///  - _signer(): the key an entry must be signed with, read from the state.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/ed25519_strict.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_state_machine.dart';

const _appFixture = 'test/fixtures/gv2_state_machine_v1.json';
const _serverFixture = '../server/src/gv2/__fixtures__/gv2_state_machine_v1.json';

/// What plain TweetNaCl says, without the strict checks.
bool _laxVerify(Uint8List key, Uint8List message, Uint8List sig) {
  try {
    return ed.VerifyKey(key).verify(signature: ed.Signature(sig), message: message);
  } catch (_) {
    return false;
  }
}

/// The key an entry must verify under, by the rules of the state machine.
Uint8List _signer(Gv2GroupState? state, Gv2Entry entry) {
  final first = entry.actions.first;
  if (first is Gv2Create) return first.memberPub;
  if (first is Gv2Accept) return first.memberPub;
  final key = gv2Hex(entry.actor);
  if (first is Gv2Decline) return state!.pending[key]!.invitePub;
  return state!.members[key]!.memberPub;
}

void main() {
  final fixture =
      jsonDecode(File(_appFixture).readAsStringSync()) as Map<String, dynamic>;
  final groupId = gv2Unhex(fixture['groupId'] as String);
  final accepted = [
    for (final v in fixture['accepted'] as List) Map<String, dynamic>.from(v as Map),
  ];
  final rejected = [
    for (final v in fixture['rejected'] as List) Map<String, dynamic>.from(v as Map),
  ];

  // states[k] = the state after the first k accepted entries (states[0] = none).
  final states = <Gv2GroupState?>[null];

  test('the fixture is the server\'s file, byte for byte', () {
    final server = File(_serverFixture);
    expect(server.existsSync(), isTrue,
        reason: 'run from app/ inside the repository');
    expect(File(_appFixture).readAsBytesSync(), server.readAsBytesSync());
    expect(fixture['version'], gv2ProtocolVersion);
  });

  group('accepted log', () {
    test('replays to the same chain and state hash at every revision', () {
      expect(accepted, hasLength(15));
      for (final v in accepted) {
        final bytes = gv2Unhex(v['entry'] as String);
        final entry = gv2DecodeEntry(bytes);
        expect(gv2Hex(gv2EncodeEntry(entry)), v['entry'],
            reason: '${v['name']}: one encoding per entry');

        final before = states.last;
        final next = gv2ApplyEntry(before, groupId, entry);
        expect(gv2Hex(next.chain), v['chain'], reason: '${v['name']}: chain');
        expect(gv2Hex(gv2StateHash(next)), v['stateHash'],
            reason: '${v['name']}: state hash');
        expect(next.revision, states.length - 1);
        states.add(next);
      }
    });

    test('applying an entry leaves the previous state untouched', () {
      for (var k = 1; k < states.length - 1; k++) {
        final entry = gv2DecodeEntry(gv2Unhex(accepted[k]['entry'] as String));
        final before = gv2Hex(gv2StateHash(states[k]!));
        gv2ApplyEntry(states[k], groupId, entry);
        expect(gv2Hex(gv2StateHash(states[k]!)), before);
        expect(gv2Hex(gv2StateHash(states[k]!)), accepted[k - 1]['stateHash']);
      }
    });

    test('the writer-side preview yields the state hash each entry carries', () {
      for (var k = 0; k < accepted.length; k++) {
        final entry = gv2DecodeEntry(gv2Unhex(accepted[k]['entry'] as String));
        expect(
          gv2Hex(gv2PreviewEntry(states[k], groupId, entry)),
          gv2Hex(entry.stateHashAfter),
          reason: accepted[k]['name'] as String,
        );
      }
    });

    test('the head message is what the server signs', () {
      // The fixture records the head of one revision of the log.
      final head = Map<String, dynamic>.from(fixture['head'] as Map);
      final at = states[(head['revision'] as int) + 1]!;
      expect(at.revision, head['revision']);
      expect(gv2Hex(at.chain), head['chain']);
      final message = gv2HeadMessage(groupId, at.revision, at.chain);
      expect(gv2Hex(message), head['message']);
      expect(message.first, 0xff);
    });

    test('the log ends with the group deleted', () {
      expect(states.last!.deleted, isTrue);
    });
  });

  group('rejected entries', () {
    test('there are 53, covering ten codes', () {
      expect(rejected, hasLength(53));
      expect({for (final v in rejected) v['code']}, hasLength(10));
    });

    for (final v in rejected) {
      test('${v['code']}: ${v['name']}', () {
        final state = states[v['afterAccepted'] as int];
        final entry = gv2DecodeEntry(gv2Unhex(v['entry'] as String));
        final before = state == null ? null : gv2Hex(gv2StateHash(state));
        expect(
          () => gv2ApplyEntry(state, groupId, entry),
          throwsA(isA<Gv2Reject>().having((e) => e.code.wire, 'code', v['code'])),
        );
        if (state != null) expect(gv2Hex(gv2StateHash(state)), before);
      });
    }

    test('every reject code has the server\'s spelling', () {
      expect({for (final c in Gv2RejectCode.values) c.wire}, {
        'version', 'revision', 'prev_chain', 'deleted', 'shape', 'actor',
        'permission', 'target', 'size', 'signature', 'invite_signature',
        'state_hash',
      });
    });
  });

  group('signatures a lax verifier accepts', () {
    Map<String, dynamic> named(String part) =>
        rejected.singleWhere((v) => (v['name'] as String).contains(part));

    test('S + L: TweetNaCl alone verifies it, the strict check does not', () {
      final v = named('S + L');
      final state = states[v['afterAccepted'] as int];
      final entry = gv2DecodeEntry(gv2Unhex(v['entry'] as String));
      final key = _signer(state, entry);
      final message = gv2SignedBytes(groupId, entry, entry.stateHashAfter);
      expect(_laxVerify(key, message, entry.sig), isTrue,
          reason: 'the vector must be one only the strict rule catches');
      expect(verifyEd25519Strict(key, message, entry.sig), isFalse);
    });

    test('small-order key: TweetNaCl alone verifies a forgery, the strict check does not', () {
      final v = named('small-order');
      final entry = gv2DecodeEntry(gv2Unhex(v['entry'] as String));
      final key = _signer(null, entry);
      final message = gv2SignedBytes(groupId, entry, entry.stateHashAfter);
      expect(_laxVerify(key, message, entry.sig), isTrue,
          reason: 'the vector must be one only the strict rule catches');
      expect(verifyEd25519Strict(key, message, entry.sig), isFalse);
    });

    test('an honest signature passes both', () {
      final entry = gv2DecodeEntry(gv2Unhex(accepted[3]['entry'] as String));
      final key = _signer(states[3], entry);
      final message = gv2SignedBytes(groupId, entry, entry.stateHashAfter);
      expect(_laxVerify(key, message, entry.sig), isTrue);
      expect(verifyEd25519Strict(key, message, entry.sig), isTrue);
    });
  });

  group('decoder strictness', () {
    final good = gv2Unhex(accepted.first['entry'] as String);
    Matcher refuses = throwsA(isA<Gv2DecodeException>());

    // Offsets in the genesis entry: version 0, revision 1..4, prevChain 5..36,
    // actor 37..101, action count 102..103, first action tag 104.
    test('trailing bytes', () {
      expect(() => gv2DecodeEntry(Uint8List.fromList([...good, 0])), refuses);
    });
    test('truncation at every length', () {
      for (var n = 0; n < good.length; n++) {
        expect(() => gv2DecodeEntry(Uint8List.sublistView(good, 0, n)), refuses,
            reason: 'length $n');
      }
    });
    test('no actions', () {
      final bytes = Uint8List.fromList(good)
        ..[102] = 0
        ..[103] = 0;
      expect(() => gv2DecodeEntry(bytes), refuses);
    });
    test('unknown action tag', () {
      expect(good[104], gv2TagCreate);
      for (final tag in [0x00, 0x0c, 0xff]) {
        final bytes = Uint8List.fromList(good)..[104] = tag;
        expect(() => gv2DecodeEntry(bytes), refuses, reason: 'tag $tag');
      }
    });
    test('more actions than a full group allows', () {
      final bytes = Uint8List.fromList(good)
        ..[102] = (gv2MaxActions + 1) >> 8
        ..[103] = (gv2MaxActions + 1) & 0xff;
      expect(() => gv2DecodeEntry(bytes), refuses);
    });

    Gv2Entry withPayloads(Uint8List member, Uint8List title, {List<Gv2Action>? actions}) =>
        Gv2Entry(
          version: gv2ProtocolVersion,
          revision: 1,
          prevChain: Uint8List(gv2HashLen),
          actor: Uint8List(gv2CiphertextLen),
          actions: actions ?? const [Gv2SetTitle()],
          memberPayload: member,
          titlePayload: title,
          stateHashAfter: Uint8List(gv2HashLen),
          sig: Uint8List(gv2SignatureLen),
        );

    test('payload size limits', () {
      final atLimit = withPayloads(
          Uint8List(gv2MaxMemberPayload), Uint8List(gv2MaxTitlePayload));
      expect(gv2DecodeEntry(gv2EncodeEntry(atLimit)).titlePayload,
          hasLength(gv2MaxTitlePayload));
      expect(
        () => gv2DecodeEntry(gv2EncodeEntry(
            withPayloads(Uint8List(gv2MaxMemberPayload + 1), Uint8List(0)))),
        refuses,
      );
      expect(
        () => gv2DecodeEntry(gv2EncodeEntry(
            withPayloads(Uint8List(0), Uint8List(gv2MaxTitlePayload + 1)))),
        refuses,
      );
    });
    test('unknown role in SET_ROLE', () {
      final entry = withPayloads(Uint8List(0), Uint8List(0),
          actions: [Gv2SetRole(Uint8List(gv2CiphertextLen), 3)]);
      expect(() => gv2DecodeEntry(gv2EncodeEntry(entry)), refuses);
    });
    test('a field of the wrong length cannot be encoded', () {
      final entry = withPayloads(Uint8List(0), Uint8List(0),
          actions: [Gv2Remove(Uint8List(gv2CiphertextLen - 1))]);
      expect(() => gv2EncodeEntry(entry), refuses);
    });
    test('every action kind survives a round trip', () {
      final c = Uint8List(gv2CiphertextLen)..[0] = 7;
      final k = Uint8List(gv2PublicKeyLen)..[0] = 9;
      final entry = withPayloads(Uint8List(3), Uint8List(4), actions: [
        Gv2Create(k),
        Gv2Invite(c, k),
        Gv2RevokeInvite(c),
        Gv2Accept(k, Uint8List(gv2SignatureLen)..[5] = 1),
        const Gv2Decline(),
        Gv2Remove(c),
        const Gv2Leave(),
        Gv2SetRole(c, gv2RoleAdmin),
        Gv2TransferOwner(c),
        const Gv2SetTitle(),
        const Gv2DeleteGroup(),
      ]);
      final bytes = gv2EncodeEntry(entry);
      final back = gv2DecodeEntry(bytes);
      expect([for (final a in back.actions) a.tag],
          [for (var t = gv2TagCreate; t <= gv2TagDeleteGroup; t++) t]);
      expect(gv2EncodeEntry(back), bytes);
    });
  });

  group('unknown protocol version', () {
    test('is refused with "version", not as a security failure', () {
      final entry = gv2DecodeEntry(gv2Unhex(accepted.first['entry'] as String));
      final newer = Gv2Entry(
        version: gv2ProtocolVersion + 1,
        revision: entry.revision,
        prevChain: entry.prevChain,
        actor: entry.actor,
        actions: entry.actions,
        memberPayload: entry.memberPayload,
        titlePayload: entry.titlePayload,
        stateHashAfter: entry.stateHashAfter,
        sig: entry.sig,
      );
      expect(
        () => gv2ApplyEntry(null, groupId, newer),
        throwsA(isA<Gv2Reject>().having((e) => e.code, 'code', Gv2RejectCode.version)),
      );
    });
  });

  test('cost of one strict Ed25519 verification on this machine', () {
    final entry = gv2DecodeEntry(gv2Unhex(accepted[3]['entry'] as String));
    final key = _signer(states[3], entry);
    final message = gv2SignedBytes(groupId, entry, entry.stateHashAfter);
    for (var i = 0; i < 20; i++) {
      verifyEd25519Strict(key, message, entry.sig);
    }
    const rounds = 200;
    final watch = Stopwatch()..start();
    var ok = true;
    for (var i = 0; i < rounds; i++) {
      ok = verifyEd25519Strict(key, message, entry.sig) && ok;
    }
    watch.stop();
    expect(ok, isTrue);
    // ignore: avoid_print
    print('strict Ed25519 verify: '
        '${(watch.elapsedMicroseconds / rounds / 1000).toStringAsFixed(3)} ms each '
        '(host VM, JIT — not a device figure)');
  });
}
