/// @file        account_deletion.dart
/// @description Deleting this account on the server the way group protocol
///              v2 needs it (design document §9.7): first leave every v2
///              group — an owner hands its group on — then send the deletion
///              request with the proof the account key signs. The server
///              stores the proof in the moment it deletes the account and
///              hands it to group members that still address the account;
///              they drop it on its own signature, never on the server's
///              word.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-19
/// @lastUpdated 2026-11-20
///
/// @functions
///  - deleteAccountWithProof(): leave the groups, then delete the account
///  - accountDeletionClockLimit: how far the server's clock may be from
///    this device's for a second proof to be signed
///
/// Notes:
///  - The proof states a time. The server takes it only within ten minutes
///    of its own clock and, when it refuses, says what its clock shows. A
///    device whose clock is off signs once more for the server's time — but
///    only when that time is within [accountDeletionClockLimit] of its own
///    clock: members read a proof as "every certificate of this account
///    issued before that time belongs to the deleted account", so a proof
///    for a time far ahead would also condemn a later registration of the
///    same recovery phrase. A server cannot talk this device into signing
///    one.
///  - Leaving the groups is best effort and never keeps the deletion from
///    happening: what could not be left is settled by the proof.
library;

import 'package:dio/dio.dart';

import '../crypto/account_deletion_proof.dart';
import '../crypto/identity_binding.dart';
import 'api_client.dart';
import 'api_endpoints.dart';

/// A second proof is signed for the server's time only when it is at most
/// this far from this device's clock.
const Duration accountDeletionClockLimit = Duration(hours: 24);

/// Delete this account on the server. [sign] returns the account key's
/// deletion proof for a time (IdentityManager.signAccountDeleted);
/// [leaveGroups] leaves the v2 groups first and must not throw for what a
/// server can cause (Gv2Runtime.leaveAllGroups). Throws what the API client
/// throws when the server did not delete the account.
Future<void> deleteAccountWithProof({
  required ApiClient api,
  required Future<AccountDeletionProof> Function(int deletedAtMs) sign,
  Future<void> Function()? leaveGroups,
  int Function()? nowMs,
}) async {
  final clock = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);
  try {
    await leaveGroups?.call();
  } catch (_) {
    // The proof settles what was not left.
  }

  Future<void> request(int deletedAtMs) async {
    final proof = await sign(deletedAtMs);
    await api.post<Object?>(
      ApiEndpoints.deleteAccountWithProof,
      data: {'deletionProof': proof.toWireJson()},
    );
  }

  try {
    await request(clock());
  } on DioException catch (e) {
    final serverTime = _refusedClock(e);
    if (serverTime == null ||
        (serverTime - clock()).abs() >
            accountDeletionClockLimit.inMilliseconds) {
      rethrow;
    }
    await request(serverTime);
  }
}

/// The server's clock when it refused a proof for its time, else null.
int? _refusedClock(DioException e) {
  if (e.response?.statusCode != 400) return null;
  final body = e.response?.data;
  final error = body is Map ? body['error'] : null;
  if (error is! Map || error['reason'] != 'time') return null;
  final time = error['serverTimeMs'];
  return time is String ? IdentityBindingV1.parseEpoch(time) : null;
}
