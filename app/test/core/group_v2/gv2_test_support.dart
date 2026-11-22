/// @file        gv2_test_support.dart
/// @description Shared helpers for the group protocol v2 tests: deterministic
///              test accounts and a small group whose change log is built
///              from REAL signed entries (gv2SignEntry → the state machine),
///              so tests of storage and sync work on states the protocol
///              actually produces.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - gv2TestSha() / gv2TestBytes(): deterministic bytes from a label
///  - Gv2TestPerson: an account with its ciphertext and member key in a group
///  - Gv2TestGroup: create / invite / accept / decline / change, keeping the
///    log, every state and a stand-in head signature per revision
///
/// Notes:
///  - The group id and the member ciphertexts are the REAL zkgroup values of
///    the test master key and the test accounts (native library), so a
///    ciphertext decrypts back to its account id.
///  - Head signatures are real: the test group signs each head with its own
///    stand-in for the server's log key ([Gv2TestGroup.headKey]).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_keys.dart';
import 'package:snowchat/core/group_v2/gv2_payloads.dart';
import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

Uint8List gv2TestSha(String label) =>
    Uint8List.fromList(hash.sha256.convert(utf8.encode(label)).bytes);

Uint8List gv2TestBytes(String label, int length) {
  final b = BytesBuilder();
  for (var i = 0; b.length < length; i++) {
    b.add(gv2TestSha('$label #$i'));
  }
  return Uint8List.fromList(b.takeBytes().sublist(0, length));
}

/// One account as it appears in one group.
class Gv2TestPerson {
  final String name;
  final Uint8List accountSeed;
  final Uint8List accountPub;
  final Uint8List ciphertext;
  final Gv2SigningKey memberKey;

  Gv2TestPerson._(this.name, this.accountSeed, this.accountPub, this.ciphertext,
      this.memberKey);

  /// [name] as a member of the group with [masterKey] and [groupId].
  factory Gv2TestPerson(String name, Uint8List masterKey, Uint8List groupId) {
    final seed = gv2TestSha('gv2 test — account $name');
    final pub =
        Uint8List.fromList(ed.SigningKey(seed: seed).verifyKey.asTypedList);
    return Gv2TestPerson._(
      name,
      seed,
      pub,
      ZkGroup.encryptMember(
          masterKey: masterKey, accountId: Uint8List.fromList(pub.sublist(0, 16))),
      Gv2SigningKey.fromSeed(gv2DeriveMemberSeed(seed, groupId)),
    );
  }

  /// Member ciphertext as the key of the state maps.
  String get key => gv2Hex(ciphertext);

  Uint8List get accountId => Uint8List.fromList(accountPub.sublist(0, 16));

  String get snowId => KeyDerivation.deriveSnowChatId(accountPub);

  Gv2MemberPayload payload(Uint8List groupId, {required int issuedAtMs}) =>
      Gv2MemberPayload(
        accountPublicKey: accountPub,
        issuedAtMs: issuedAtMs,
        certSignature: Uint8List.fromList(ed.SigningKey(seed: accountSeed)
            .sign(gv2MemberCertMessage(
                groupId: groupId,
                memberPub: memberKey.publicKey,
                issuedAtMs: issuedAtMs))
            .signature
            .asTypedList),
      );
}

/// A group and its whole history.
class Gv2TestGroup {
  final String label;
  final Uint8List masterKey;
  final Uint8List groupId;
  final Uint8List stateKey;
  final Uint8List serverKeyHash;

  /// log[r] is the entry of revision r; states[r] the state after it.
  final List<Gv2Entry> log = [];
  final List<Gv2GroupState> states = [];

  final Map<String, Gv2SigningKey> _inviteKeys = {};
  final Map<String, Gv2TestPerson> _people = {};

  Gv2TestGroup._(this.label, this.masterKey, this.groupId)
      : stateKey = gv2DeriveStateKey(masterKey, groupId),
        serverKeyHash = gv2TestSha('gv2 test — server keys');

  factory Gv2TestGroup([String label = 'main']) {
    final masterKey = gv2TestSha('gv2 test — master key $label');
    return Gv2TestGroup._(
        label, masterKey, ZkGroup.groupParams(masterKey).groupId);
  }

  String get id => gv2Hex(groupId);

  Gv2GroupState get state => states.last;

  /// The same group with the same history up to [revision], to be continued
  /// differently: a second log of one group, as a server that shows two
  /// would sign. (Building the history again would not give the same
  /// bytes — payloads are sealed with random nonces.)
  Gv2TestGroup forkAt(int revision) {
    final fork = Gv2TestGroup._(label, masterKey, groupId);
    fork.log.addAll(log.sublist(0, revision + 1));
    fork.states.addAll(states.sublist(0, revision + 1));
    fork._inviteKeys.addAll(_inviteKeys);
    fork._people.addAll(_people);
    return fork;
  }

  Gv2TestPerson person(String name) =>
      _people.putIfAbsent(name, () => Gv2TestPerson(name, masterKey, groupId));

  /// Stand-in for the server's log signing key.
  final Gv2SigningKey headKey =
      Gv2SigningKey.fromSeed(gv2TestSha('gv2 test — head key'));

  /// The server's signature over the head at [revision].
  Uint8List headSig(int revision) => headKey
      .sign(gv2HeadMessage(groupId, revision, states[revision].chain));

  Uint8List titlePayload(String name, {Uint8List? key}) => gv2SealTitlePayload(
      key ?? stateKey, Gv2TitlePayload(name: name, serverKeyHash: serverKeyHash));

  Uint8List memberPayload(Gv2TestPerson p, {int issuedAtMs = 1794528000000}) =>
      gv2SealMemberPayload(stateKey, p.payload(groupId, issuedAtMs: issuedAtMs));

  Gv2SigningKey _newInviteKey(Gv2TestPerson invitee) {
    final key = Gv2SigningKey.fromSeed(gv2TestSha(
        'gv2 test — invite $label ${invitee.name} ${states.length}'));
    _inviteKeys[invitee.key] = key;
    return key;
  }

  /// The one-time key of the invite currently pending for [invitee].
  Gv2SigningKey inviteKeyOf(Gv2TestPerson invitee) => _inviteKeys[invitee.key]!;

  Gv2GroupState _append(
    Gv2TestPerson actor,
    List<Gv2Action> actions,
    Gv2SigningKey key, {
    Uint8List? member,
    Uint8List? title,
  }) {
    final previous = states.isEmpty ? null : states.last;
    final signed = gv2SignEntry(
      state: previous,
      groupId: groupId,
      draft: Gv2EntryDraft(
        version: gv2ProtocolVersion,
        revision: previous == null ? 0 : previous.revision + 1,
        prevChain: previous == null ? gv2GenesisPrevChain() : previous.chain,
        actor: actor.ciphertext,
        actions: actions,
        memberPayload: member ?? Uint8List(0),
        titlePayload: title ?? Uint8List(0),
      ),
      key: key,
    );
    log.add(signed.entry);
    states.add(signed.next);
    return signed.next;
  }

  /// Revision 0: [owner] creates the group and invites [invite].
  Gv2GroupState create(
    Gv2TestPerson owner, {
    List<Gv2TestPerson> invite = const [],
    String title = 'Snow',
    Uint8List? titlePayloadBytes,
  }) =>
      _append(
        owner,
        [
          Gv2Create(owner.memberKey.publicKey),
          for (final p in invite)
            Gv2Invite(p.ciphertext, _newInviteKey(p).publicKey),
        ],
        owner.memberKey,
        member: memberPayload(owner),
        title: titlePayloadBytes ?? titlePayload(title),
      );

  Gv2GroupState invite(Gv2TestPerson actor, Gv2TestPerson invitee) => _append(
        actor,
        [Gv2Invite(invitee.ciphertext, _newInviteKey(invitee).publicKey)],
        actor.memberKey,
      );

  /// [payload] replaces the sealed member payload (the rules do not look
  /// inside it, so any bytes are accepted).
  Gv2GroupState accept(
    Gv2TestPerson invitee, {
    int issuedAtMs = 1794528000000,
    Uint8List? payload,
  }) =>
      _append(
        invitee,
        [
          Gv2Accept(
            invitee.memberKey.publicKey,
            gv2SignInviteAccept(
              inviteKey: inviteKeyOf(invitee),
              groupId: groupId,
              ciphertext: invitee.ciphertext,
              memberPub: invitee.memberKey.publicKey,
            ),
          ),
        ],
        invitee.memberKey,
        member: payload ?? memberPayload(invitee, issuedAtMs: issuedAtMs),
      );

  Gv2GroupState decline(Gv2TestPerson invitee) =>
      _append(invitee, const [Gv2Decline()], inviteKeyOf(invitee));

  /// Any other change by a member, signed with its member key.
  Gv2GroupState change(
    Gv2TestPerson actor,
    List<Gv2Action> actions, {
    String? newTitle,
  }) =>
      _append(
        actor,
        actions,
        actor.memberKey,
        title: newTitle == null ? null : titlePayload(newTitle),
      );
}
