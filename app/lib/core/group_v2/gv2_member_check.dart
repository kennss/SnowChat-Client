/// @file        gv2_member_check.dart
/// @description Group protocol v2 — deciding which account stands behind a
///              member of a group, and whether that account has since been
///              deleted. The change log proves that a member key was admitted
///              by the rules; it does not prove whose key it is. Only a member
///              that passes this check is a CONFIRMED member: Sender Keys and
///              group messages go to confirmed members only, so a member the
///              server slipped in (or relabelled) never receives a key
///              (design document §5.6, §9.7).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-13
///
/// @functions
///  - gv2SnowIdOfAccountId(): the snowId of a 16-byte account id
///  - gv2CheckMember(): open the member payload and confirm the account
///  - Gv2ConfirmedMember / Gv2MemberCheck / Gv2MemberCheckFailure: its result
///  - gv2JudgeDeletion(): is a deletion proof about this member, and still in
///    force — Gv2DeletionVerdict
///
/// Notes:
///  - The caller supplies the account id: the 16 bytes the member ciphertext
///    decrypts to under the group master key (zkgroup, native). This file
///    stays pure Dart.
///  - Checks, in order (the first failure is reported):
///      payload      the member payload does not open with K_state
///      accountId    the account key's first 16 bytes are not the account id
///                   the ciphertext decrypts to
///      pinnedKey    this device already confirmed a DIFFERENT account key
///                   for that snowId (Identity Binding v1)
///      certificate  the account key did not sign (groupId, memberPub,
///                   issuedAtMs)
///  - A failed check never rejects a change-log entry (the server cannot see
///    any of this). The member stays in the state, shown as unconfirmed, and
///    receives nothing.
///  - Deletion: a proof counts only when the member's OWN confirmed account
///    key signed it, and only against a certificate issued before the stated
///    time. An account registered again from the same recovery phrase has a
///    later certificate and is not affected.
library;

import 'dart:typed_data';

import '../crypto/account_deletion_proof.dart';
import '../crypto/identity_binding.dart' show constantTimeEquals;
import '../crypto/key_derivation.dart';
import 'gv2_codec.dart';
import 'gv2_keys.dart';
import 'gv2_payloads.dart';

/// Length of an account id (the first 16 bytes of the account public key).
const int gv2AccountIdLen = 16;

/// Why a member could not be confirmed.
enum Gv2MemberCheckFailure { payload, accountId, pinnedKey, certificate }

/// A member whose account is confirmed.
class Gv2ConfirmedMember {
  final String snowId;
  final Uint8List accountPublicKey;

  /// When the member certificate was made, Unix milliseconds.
  final int issuedAtMs;

  const Gv2ConfirmedMember({
    required this.snowId,
    required this.accountPublicKey,
    required this.issuedAtMs,
  });
}

/// Outcome of [gv2CheckMember]: exactly one of [member] and [failure] is set.
class Gv2MemberCheck {
  final Gv2ConfirmedMember? member;
  final Gv2MemberCheckFailure? failure;

  const Gv2MemberCheck.confirmed(Gv2ConfirmedMember this.member)
      : failure = null;
  const Gv2MemberCheck.failed(Gv2MemberCheckFailure this.failure)
      : member = null;

  bool get confirmed => member != null;
}

/// "snow" + lowercase hex of the 16-byte [accountId].
String gv2SnowIdOfAccountId(Uint8List accountId) {
  if (accountId.length != gv2AccountIdLen) {
    throw ArgumentError('gv2 member: accountId must be $gv2AccountIdLen bytes');
  }
  return 'snow${gv2Hex(accountId)}';
}

/// Confirm the account behind one member of a group.
///
/// [accountId] is what the member's ciphertext decrypts to under the master
/// key. [pinnedAccountKey] is the account key this device has already
/// confirmed for that snowId, or null when it has none. Never throws.
Gv2MemberCheck gv2CheckMember({
  required Uint8List stateKey,
  required Uint8List groupId,
  required Uint8List accountId,
  required Gv2MemberState member,
  Uint8List? pinnedAccountKey,
}) {
  final payload = gv2OpenMemberPayload(stateKey, member.memberPayload);
  if (payload == null) {
    return const Gv2MemberCheck.failed(Gv2MemberCheckFailure.payload);
  }
  final accountKey = payload.accountPublicKey;
  if (accountId.length != gv2AccountIdLen ||
      !constantTimeEquals(accountKey.sublist(0, gv2AccountIdLen), accountId)) {
    return const Gv2MemberCheck.failed(Gv2MemberCheckFailure.accountId);
  }
  if (pinnedAccountKey != null &&
      !constantTimeEquals(pinnedAccountKey, accountKey)) {
    return const Gv2MemberCheck.failed(Gv2MemberCheckFailure.pinnedKey);
  }
  final certified = gv2VerifyMemberCert(
    accountPublicKey: accountKey,
    groupId: groupId,
    memberPub: member.memberPub,
    issuedAtMs: payload.issuedAtMs,
    signature: payload.certSignature,
  );
  if (!certified) {
    return const Gv2MemberCheck.failed(Gv2MemberCheckFailure.certificate);
  }
  return Gv2MemberCheck.confirmed(Gv2ConfirmedMember(
    snowId: KeyDerivation.deriveSnowChatId(accountKey),
    accountPublicKey: accountKey,
    issuedAtMs: payload.issuedAtMs,
  ));
}

/// What a deletion proof means for one confirmed member.
enum Gv2DeletionVerdict {
  /// The member's account signed it and the membership predates it: the
  /// account is gone. Stop sending to it; an admin client removes it.
  deleted,

  /// Not signed by this member's account key. Believe nothing.
  signature,

  /// Signed, but the member's certificate is not older than the stated time:
  /// the account was registered again and joined afterwards.
  reissued,
}

/// Judge [proof] against a confirmed [member]. The key the server sends along
/// with a proof is ignored on purpose: only the key this client confirmed for
/// the member counts.
Gv2DeletionVerdict gv2JudgeDeletion({
  required Gv2ConfirmedMember member,
  required AccountDeletionProof proof,
}) {
  final signed = AccountDeletionProofV1.verify(
    snowId: member.snowId,
    accountPublicKey: member.accountPublicKey,
    proof: proof,
  );
  if (!signed) return Gv2DeletionVerdict.signature;
  return member.issuedAtMs < proof.deletedAtMs
      ? Gv2DeletionVerdict.deleted
      : Gv2DeletionVerdict.reissued;
}
