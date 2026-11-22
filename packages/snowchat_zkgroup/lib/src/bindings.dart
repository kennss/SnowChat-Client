/// @file        bindings.dart
/// @description Raw dart:ffi declarations for the C ABI of the zkgroup Rust
///              crate (`ffi` module of native/snowchat_zkgroup/src/lib.rs).
///              The symbols resolve against the code asset the build hook
///              registers under this library's URI — no DynamicLibrary.open,
///              no per-isolate initialization.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-12
/// @lastUpdated 2026-11-22 (snowzkArgon2id — the app passcode's key derivation). Earlier
///              2026-11-12 (product ABI: group params with group id, member
///              decrypt, endorsements split into receive + send token)
///
/// @functions
///  - snowzkFree(buffer): zero and release a result buffer (exactly once).
///  - snowzkGroupParams / snowzkEncryptMember / snowzkDecryptMember /
///    snowzkReceiveAuthCredential / snowzkPresentAuthCredential /
///    snowzkReceiveEndorsements / snowzkSendToken / snowzkArgon2id: see the
///    Rust `api` module for semantics.
///
/// @notes
///  - Every call returns a [ZkBuffer] by value. `status == 0`: `ptr/len` is a
///    heap buffer owned by the caller until [snowzkFree]. Otherwise `ptr` is
///    null and `status` is a ZkError code (1 invalid input, 2 verification
///    failed, 3 internal).
///  - Inputs are (pointer, length) pairs the callee only reads.
///  - None of these are leaf calls: the larger ones run for milliseconds and
///    must not hold the isolate group at a safepoint.
library;

import 'dart:ffi';

/// Result of every `snowzk_*` call (`#[repr(C)] struct ZkBuffer`).
final class ZkBuffer extends Struct {
  external Pointer<Uint8> ptr;

  @Size()
  external int len;

  @Int32()
  external int status;
}

@Native<Void Function(ZkBuffer)>(symbol: 'snowzk_free')
external void snowzkFree(ZkBuffer buffer);

@Native<ZkBuffer Function(Pointer<Uint8>, Size)>(symbol: 'snowzk_group_params')
external ZkBuffer snowzkGroupParams(Pointer<Uint8> masterKey, int masterKeyLen);

@Native<ZkBuffer Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size)>(
  symbol: 'snowzk_encrypt_member',
)
external ZkBuffer snowzkEncryptMember(
  Pointer<Uint8> masterKey,
  int masterKeyLen,
  Pointer<Uint8> accountId,
  int accountIdLen,
);

@Native<ZkBuffer Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size)>(
  symbol: 'snowzk_decrypt_member',
)
external ZkBuffer snowzkDecryptMember(
  Pointer<Uint8> masterKey,
  int masterKeyLen,
  Pointer<Uint8> ciphertext,
  int ciphertextLen,
);

@Native<
  ZkBuffer Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Uint64,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'snowzk_receive_auth_credential')
external ZkBuffer snowzkReceiveAuthCredential(
  Pointer<Uint8> serverPublicParams,
  int serverPublicParamsLen,
  Pointer<Uint8> accountId,
  int accountIdLen,
  Pointer<Uint8> salt,
  int saltLen,
  int redemptionTime,
  Pointer<Uint8> response,
  int responseLen,
);

@Native<
  ZkBuffer Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
  )
>(symbol: 'snowzk_present_auth_credential')
external ZkBuffer snowzkPresentAuthCredential(
  Pointer<Uint8> serverPublicParams,
  int serverPublicParamsLen,
  Pointer<Uint8> masterKey,
  int masterKeyLen,
  Pointer<Uint8> credential,
  int credentialLen,
);

@Native<
  ZkBuffer Function(
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Pointer<Uint8>,
    Size,
    Uint64,
  )
>(symbol: 'snowzk_receive_endorsements')
external ZkBuffer snowzkReceiveEndorsements(
  Pointer<Uint8> serverPublicParams,
  int serverPublicParamsLen,
  Pointer<Uint8> masterKey,
  int masterKeyLen,
  Pointer<Uint8> response,
  int responseLen,
  Pointer<Uint8> members,
  int membersLen,
  int now,
);

@Native<ZkBuffer Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Uint64)>(
  symbol: 'snowzk_send_token',
)
external ZkBuffer snowzkSendToken(
  Pointer<Uint8> masterKey,
  int masterKeyLen,
  Pointer<Uint8> endorsements,
  int endorsementsLen,
  int expiration,
);

@Native<
  ZkBuffer Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size, Uint32, Uint32, Uint32)
>(symbol: 'snowzk_argon2id')
external ZkBuffer snowzkArgon2id(
  Pointer<Uint8> password,
  int passwordLen,
  Pointer<Uint8> salt,
  int saltLen,
  int memoryKiB,
  int iterations,
  int parallelism,
);
