/// @file        snowchat_zkgroup.dart
/// @description Typed Dart API over the zkgroup Rust crate: the client role of
///              group protocol v2's anonymous credentials. Bytes in, bytes
///              out, failures as [ZkGroupException]. Stateless — callable from
///              any isolate with no setup call.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-12
/// @lastUpdated 2026-11-22 (Argon2id.derive — the app passcode's key derivation, the one
///              native primitive outside zkgroup). Earlier 2026-11-12 (product API: groupParams returns the group id,
///              decryptMember, receiveEndorsements + sendToken replace the
///              one-shot token call)
///
/// @functions
///  - ZkGroup.groupParams(masterKey): group id + public params.
///  - ZkGroup.encryptMember(masterKey, accountId): 65-byte member ciphertext.
///  - ZkGroup.decryptMember(masterKey, ciphertext): 16-byte account id.
///  - ZkGroup.receiveAuthCredential(...): verify + keep the daily credential.
///  - ZkGroup.presentAuthCredential(...): presentation for one group.
///  - ZkGroup.receiveEndorsements(...): verify the server's endorsements
///    against the caller's roster; one endorsement per member + expiration.
///  - ZkGroup.sendToken(...): send token for any subset of those members.
///  - Argon2id.derive(...): 32-byte Argon2id v1.3 key of a passcode.
///
/// @notes
///  - accountId: the 16 bytes behind a snowId ("snow" + 32 hex).
///  - masterKey: 32 bytes. Times are epoch SECONDS.
///  - The group id comes from the master key. Never take it from a value the
///    server supplied.
///  - Inputs are copied into native memory for the call and that memory is
///    zeroed before it is released (it holds the group master key and the
///    credential). Result buffers are zeroed by the native side when freed.
///    Nothing here logs.
///  - receiveEndorsements costs about 0.1 ms per member on a phone; call it
///    off the main isolate for rosters of a few hundred members.
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.dart';

/// Why a call failed. Mirrors the Rust `ZkError` codes.
enum ZkGroupError {
  /// An argument has the wrong length or cannot be parsed.
  invalidInput,

  /// A proof, credential, endorsement or ciphertext did not verify.
  verificationFailed,

  /// libsignal rejected the call with a panic (caught at the boundary).
  internal,
}

/// Thrown by every [ZkGroup] function on failure. Carries no input bytes.
final class ZkGroupException implements Exception {
  const ZkGroupException(this.error);

  final ZkGroupError error;

  @override
  String toString() => 'ZkGroupException(${error.name})';
}

/// Length in bytes of an account id.
const int zkAccountIdLength = 16;

/// Length in bytes of a group master key.
const int zkGroupMasterKeyLength = 32;

/// Length in bytes of a group id.
const int zkGroupIdLength = 32;

/// Length in bytes of a member ciphertext.
const int zkMemberCiphertextLength = 65;

/// Length in bytes of one endorsement.
const int zkEndorsementLength = 33;

/// What a group master key determines publicly.
final class ZkGroupParams {
  const ZkGroupParams({required this.groupId, required this.publicParams});

  /// 32-byte group id.
  final Uint8List groupId;

  /// Serialized public params — what the server stores for the group.
  final Uint8List publicParams;
}

/// Verified endorsements of one roster.
final class ZkEndorsements {
  const ZkEndorsements({required this.expiration, required this.endorsements});

  /// Epoch seconds, day-aligned. Tokens built from [endorsements] stop
  /// verifying after this time.
  final int expiration;

  /// One 33-byte endorsement per member, in the order the members were given.
  final List<Uint8List> endorsements;
}

/// Client-side zkgroup operations.
abstract final class ZkGroup {
  /// Group id and public params of the group behind [masterKey].
  static ZkGroupParams groupParams(Uint8List masterKey) {
    final out = _invoke([
      masterKey,
    ], (p) => snowzkGroupParams(p[0].ptr, p[0].len));
    return ZkGroupParams(
      groupId: Uint8List.sublistView(out, 0, zkGroupIdLength),
      publicParams: Uint8List.sublistView(out, zkGroupIdLength),
    );
  }

  /// Deterministic per-group ciphertext of [accountId].
  static Uint8List encryptMember({
    required Uint8List masterKey,
    required Uint8List accountId,
  }) => _invoke([
    masterKey,
    accountId,
  ], (p) => snowzkEncryptMember(p[0].ptr, p[0].len, p[1].ptr, p[1].len));

  /// The account id inside a member [ciphertext] of this group. Throws
  /// [ZkGroupError.verificationFailed] when the ciphertext is not a member
  /// entry of this group.
  static Uint8List decryptMember({
    required Uint8List masterKey,
    required Uint8List ciphertext,
  }) => _invoke([
    masterKey,
    ciphertext,
  ], (p) => snowzkDecryptMember(p[0].ptr, p[0].len, p[1].ptr, p[1].len));

  /// Verifies the server's auth-credential [response] for [accountId] (issued
  /// without a PNI, bound to [salt] and [redemptionTime]) and returns the
  /// credential.
  static Uint8List receiveAuthCredential({
    required Uint8List serverPublicParams,
    required Uint8List accountId,
    required Uint8List salt,
    required int redemptionTime,
    required Uint8List response,
  }) => _invoke(
    [serverPublicParams, accountId, salt, response],
    (p) => snowzkReceiveAuthCredential(
      p[0].ptr,
      p[0].len,
      p[1].ptr,
      p[1].len,
      p[2].ptr,
      p[2].len,
      redemptionTime,
      p[3].ptr,
      p[3].len,
    ),
  );

  /// Presentation of [credential] for the group behind [masterKey].
  static Uint8List presentAuthCredential({
    required Uint8List serverPublicParams,
    required Uint8List masterKey,
    required Uint8List credential,
  }) => _invoke(
    [serverPublicParams, masterKey, credential],
    (p) => snowzkPresentAuthCredential(
      p[0].ptr,
      p[0].len,
      p[1].ptr,
      p[1].len,
      p[2].ptr,
      p[2].len,
    ),
  );

  /// Verifies the server's endorsements [response] against the caller's own
  /// view of the roster ([members], account ids). It only verifies when the
  /// server issued it for exactly these members, so a roster that differs
  /// from the server's shows up here as [ZkGroupError.verificationFailed].
  /// [now] is the current time in epoch seconds.
  static ZkEndorsements receiveEndorsements({
    required Uint8List serverPublicParams,
    required Uint8List masterKey,
    required Uint8List response,
    required List<Uint8List> members,
    required int now,
  }) {
    final out = _invoke(
      [
        serverPublicParams,
        masterKey,
        response,
        _pack(members, zkAccountIdLength),
      ],
      (p) => snowzkReceiveEndorsements(
        p[0].ptr,
        p[0].len,
        p[1].ptr,
        p[1].len,
        p[2].ptr,
        p[2].len,
        p[3].ptr,
        p[3].len,
        now,
      ),
    );
    final expected = 8 + members.length * zkEndorsementLength;
    if (out.length != expected) {
      throw const ZkGroupException(ZkGroupError.internal);
    }
    return ZkEndorsements(
      expiration: ByteData.sublistView(out, 0, 8).getUint64(0),
      endorsements: [
        for (var i = 0; i < members.length; i++)
          Uint8List.sublistView(
            out,
            8 + i * zkEndorsementLength,
            8 + (i + 1) * zkEndorsementLength,
          ),
      ],
    );
  }

  /// Send token for exactly the members whose [endorsements] are given (any
  /// non-empty subset of one [receiveEndorsements] result; order does not
  /// matter). [expiration] is the value returned with them.
  static Uint8List sendToken({
    required Uint8List masterKey,
    required List<Uint8List> endorsements,
    required int expiration,
  }) => _invoke(
    [masterKey, _pack(endorsements, zkEndorsementLength)],
    (p) => snowzkSendToken(p[0].ptr, p[0].len, p[1].ptr, p[1].len, expiration),
  );
}

/// Argon2id (v1.3, RFC 9106) — the app passcode's key derivation, run in the
/// same native library (RustCrypto `argon2`). Failures are [ZkGroupException]
/// with [ZkGroupError.invalidInput] (a salt shorter than 8 bytes, zero
/// iterations or lanes, memory below 8 KiB per lane).
abstract final class Argon2id {
  /// Length in bytes of the derived key.
  static const int outputLength = 32;

  /// The 32-byte key of [password] with [salt]: [memoryKiB] KiB of memory,
  /// [iterations] passes, [parallelism] lanes. Blocks for as long as the
  /// parameters make it (hundreds of milliseconds at passcode settings) —
  /// call it off the UI isolate. The result is key material: the native copy
  /// is zeroed when released; the caller owns (and should clear) the
  /// returned list.
  static Uint8List derive({
    required Uint8List password,
    required Uint8List salt,
    required int memoryKiB,
    required int iterations,
    required int parallelism,
  }) {
    final out = _invoke(
      [password, salt],
      (p) => snowzkArgon2id(
        p[0].ptr,
        p[0].len,
        p[1].ptr,
        p[1].len,
        memoryKiB,
        iterations,
        parallelism,
      ),
    );
    if (out.length != outputLength) {
      throw const ZkGroupException(ZkGroupError.internal);
    }
    return out;
  }
}

/// Concatenates [items], each of exactly [itemLength] bytes.
Uint8List _pack(List<Uint8List> items, int itemLength) {
  final packed = Uint8List(items.length * itemLength);
  for (var i = 0; i < items.length; i++) {
    if (items[i].length != itemLength) {
      throw const ZkGroupException(ZkGroupError.invalidInput);
    }
    packed.setRange(i * itemLength, (i + 1) * itemLength, items[i]);
  }
  return packed;
}

/// One input copied into native memory.
typedef _Native = ({Pointer<Uint8> ptr, int len});

/// Copies [inputs] into native memory, runs [call], and returns the result
/// bytes as a Dart-owned list. The native input copies are zeroed and freed,
/// and the result buffer is returned to Rust (which zeroes it), on every path.
Uint8List _invoke(
  List<Uint8List> inputs,
  ZkBuffer Function(List<_Native> pointers) call,
) {
  final pointers = <_Native>[];
  try {
    for (final input in inputs) {
      if (input.isEmpty) {
        pointers.add((ptr: nullptr, len: 0));
        continue;
      }
      final ptr = malloc<Uint8>(input.length);
      ptr.asTypedList(input.length).setAll(0, input);
      pointers.add((ptr: ptr, len: input.length));
    }

    final buffer = call(pointers);
    if (buffer.status != 0) {
      throw ZkGroupException(switch (buffer.status) {
        1 => ZkGroupError.invalidInput,
        2 => ZkGroupError.verificationFailed,
        _ => ZkGroupError.internal,
      });
    }
    try {
      return Uint8List.fromList(buffer.ptr.asTypedList(buffer.len));
    } finally {
      snowzkFree(buffer);
    }
  } finally {
    for (final pointer in pointers) {
      if (pointer.ptr == nullptr) continue;
      pointer.ptr.asTypedList(pointer.len).fillRange(0, pointer.len, 0);
      malloc.free(pointer.ptr);
    }
  }
}
