/// @file        identity_binding.dart
/// @description Identity Binding v1 (B-2) — binds a device's Signal-layer
///              identity (X25519 identity key + Ed25519 signing key) to the
///              ACCOUNT key the SnowChat ID is derived from. Because the
///              snowId is a function of the account public key, anyone who
///              knows a peer's snowId can verify a key bundle offline: a
///              compromised server can no longer substitute the Signal keys
///              of a peer (SC-02 / SC-15).
///
///              Wire message (172 bytes, all fields fixed length):
///                0xFF                              1B  (never produced by
///                                                       utf8.encode → a string
///                                                       signer cannot be used
///                                                       as a binding oracle)
///                "SnowChat_IdentityBinding_v1"    27B  ASCII
///                snowId                           36B  ASCII lowercase
///                deviceId                         36B  ASCII lowercase UUID
///                epoch                             8B  u64 big-endian
///                X25519 identity public key       32B
///                Ed25519 Signal signing pubkey    32B
///              signature = Ed25519_detached(accountPrivateKey, message)
///
///              Golden vectors shared with the server live in
///              app/test/fixtures/identity_binding_v1.json.
///
///              registrationId and the signed-prekey keyId are deliberately NOT
///              covered by the binding — they must never be used for security
///              decisions (a server can only DoS by altering them).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-10
///
/// @functions
///  - IdentityBindingV1.buildMessage(): encode the 172-byte binding message
///  - IdentityBindingV1.verify(): fail-closed verification of a binding
///  - IdentityBindingV1.isAcceptableAccountKey(): 32B, canonical, not small-order
///  - IdentityBindingV1.parseAccountKeyHex(): strict lowercase 64-hex decoder
///  - IdentityBindingV1.isValidDeviceId(): lowercase canonical UUID check
///  - IdentityBindingV1.parseEpoch(): strict decimal u63 parser
///  - IdentityBindingV1.isCanonicalSignatureScalar(): S < L check (malleability)
///  - IdentityBinding: server wire form {sig(b64), epoch(string), version}
///  - EmbeddedIdentityBinding: form embedded in a type-2 (PreKey) message
///  - LocalIdentityBinding: our own minted binding (all fields + signature)
///  - constantTimeEquals(): constant-time byte comparison helper
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;

import 'key_derivation.dart';

/// Constant-time equality for byte arrays (length leak only).
bool constantTimeEquals(List<int>? a, List<int>? b) {
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Lowercase hex encoding.
String bytesToHexLower(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class IdentityBindingV1 {
  IdentityBindingV1._();

  /// Binding format version carried on the wire.
  static const int version = 1;

  /// First byte of every binding message. 0xFF is not a valid UTF-8 byte, so
  /// no `utf8.encode(string)` (old or new client) can ever produce it.
  static const int domainPrefix = 0xFF;

  /// ASCII domain label (27 bytes).
  static const String label = 'SnowChat_IdentityBinding_v1';

  /// Total message length: 1 + 27 + 36 + 36 + 8 + 32 + 32.
  static const int messageLength = 172;

  static final RegExp _deviceIdRe = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
  static final RegExp _snowIdRe = RegExp(r'^snow[0-9a-f]{32}$');
  static final RegExp _hex64Re = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _epochRe = RegExp(r'^(0|[1-9][0-9]{0,18})$');

  /// Largest epoch accepted. Epochs are millisecond timestamps (plus a
  /// monotonic bump), so anything past 2^63-1 is never legitimate; rejecting
  /// it keeps all arithmetic inside Dart's native 64-bit int.
  static final BigInt _maxEpoch = (BigInt.one << 63) - BigInt.one;

  /// True iff [id] is a canonical lowercase UUID (36 chars).
  static bool isValidDeviceId(String id) => _deviceIdRe.hasMatch(id);

  /// True iff [id] is a canonical lowercase snowId (36 chars).
  static bool isValidSnowId(String id) => _snowIdRe.hasMatch(id);

  /// Strict decimal epoch parser. Returns null for anything that is not a
  /// canonical non-negative decimal below 2^63.
  static int? parseEpoch(String? s) {
    if (s == null || !_epochRe.hasMatch(s)) return null;
    final v = BigInt.parse(s);
    if (v > _maxEpoch) return null;
    return v.toInt();
  }

  /// Strict account-key decoder: exactly 64 LOWERCASE hex chars → 32 bytes.
  static Uint8List? parseAccountKeyHex(String? hex) {
    if (hex == null || !_hex64Re.hasMatch(hex)) return null;
    final out = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  // Ed25519 encodings of the small-order points (libsodium blocklist), with
  // the x-sign bit masked off on comparison. Includes the non-canonical
  // encodings of 0 and 1 (p and p+1).
  static final List<Uint8List> _smallOrderBlocklist = [
    _hex('0000000000000000000000000000000000000000000000000000000000000000'),
    _hex('0100000000000000000000000000000000000000000000000000000000000000'),
    _hex('26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05'),
    _hex('c7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a'),
    _hex('ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f'),
    _hex('edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f'),
    _hex('eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f'),
  ];

  static Uint8List _hex(String h) {
    final out = Uint8List(h.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  /// Account public key sanity: exactly 32 bytes, canonical y (< p), and not
  /// one of the small-order points (which would let a signature verify for
  /// many messages / keys).
  static bool isAcceptableAccountKey(Uint8List? key) {
    if (key == null || key.length != 32) return false;
    // Small-order check (sign bit masked).
    for (final bad in _smallOrderBlocklist) {
      var diff = 0;
      for (var i = 0; i < 31; i++) {
        diff |= key[i] ^ bad[i];
      }
      diff |= (key[31] & 0x7f) ^ (bad[31] & 0x7f);
      if (diff == 0) return false;
    }
    // Canonical encoding: y (little-endian, top bit masked) must be < p,
    // p = 2^255 - 19 → reject y in [p, 2^255).
    if ((key[31] & 0x7f) == 0x7f) {
      var allFF = true;
      for (var i = 1; i < 31; i++) {
        if (key[i] != 0xff) {
          allFF = false;
          break;
        }
      }
      if (allFF && key[0] >= 0xed) return false;
    }
    return true;
  }

  /// Encode the 172-byte binding message. Throws [ArgumentError] when any
  /// field violates the fixed-length format (callers verifying untrusted
  /// input should use [verify], which never throws).
  static Uint8List buildMessage({
    required String snowId,
    required String deviceId,
    required int epoch,
    required Uint8List identityKey,
    required Uint8List ed25519,
  }) {
    if (!isValidSnowId(snowId)) {
      throw ArgumentError('binding: snowId format');
    }
    if (!isValidDeviceId(deviceId)) {
      throw ArgumentError('binding: deviceId must be a lowercase UUID');
    }
    if (epoch < 0) throw ArgumentError('binding: epoch must be >= 0');
    if (identityKey.length != 32 || ed25519.length != 32) {
      throw ArgumentError('binding: keys must be 32 bytes');
    }
    final b = BytesBuilder(copy: false)
      ..addByte(domainPrefix)
      ..add(ascii.encode(label))
      ..add(ascii.encode(snowId))
      ..add(ascii.encode(deviceId));
    final epochBytes = ByteData(8)..setUint64(0, epoch, Endian.big);
    b
      ..add(epochBytes.buffer.asUint8List())
      ..add(identityKey)
      ..add(ed25519);
    final out = b.takeBytes();
    assert(out.length == messageLength);
    return out;
  }

  /// Fail-closed verification. Returns true only when ALL hold:
  ///  1. [accountPublicKey] is 32B, canonical, not small-order;
  ///  2. deriveSnowChatId(accountPublicKey) == [snowId] (constant time);
  ///  3. [deviceId] is a lowercase UUID; [identityKey]/[ed25519] are 32B;
  ///  4. Ed25519_Verify(accountPublicKey, message, signature).
  static bool verify({
    required String snowId,
    required Uint8List accountPublicKey,
    required String deviceId,
    required int epoch,
    required Uint8List identityKey,
    required Uint8List ed25519,
    required Uint8List signature,
  }) {
    try {
      if (!isAcceptableAccountKey(accountPublicKey)) return false;
      if (!isValidSnowId(snowId)) return false;
      final derived = KeyDerivation.deriveSnowChatId(accountPublicKey);
      if (!constantTimeEquals(ascii.encode(derived), ascii.encode(snowId))) {
        return false;
      }
      if (!isValidDeviceId(deviceId)) return false;
      if (epoch < 0) return false;
      if (identityKey.length != 32 || ed25519.length != 32) return false;
      if (signature.length != 64) return false;
      // Reject non-canonical / malleable signatures (S >= L), matching the
      // server verifier. TweetNaCl alone does not enforce this.
      if (!isCanonicalSignatureScalar(signature)) return false;
      final msg = buildMessage(
        snowId: snowId,
        deviceId: deviceId,
        epoch: epoch,
        identityKey: identityKey,
        ed25519: ed25519,
      );
      // pinenacl throws on a bad signature; any exception → false.
      return ed.VerifyKey(Uint8List.fromList(accountPublicKey)).verify(
            signature: ed.Signature(Uint8List.fromList(signature)),
            message: msg,
          );
    } catch (_) {
      return false;
    }
  }

  /// Ed25519 group order L = 2^252 + 27742317777372353535851937790883648493.
  static final BigInt _groupOrder = (BigInt.one << 252) +
      BigInt.parse('27742317777372353535851937790883648493');

  /// True iff the S half (bytes 32..63, little-endian) of [signature] is
  /// strictly below L (RFC 8032 §5.1.7 canonical check).
  static bool isCanonicalSignatureScalar(Uint8List signature) {
    if (signature.length != 64) return false;
    var s = BigInt.zero;
    for (var i = 63; i >= 32; i--) {
      s = (s << 8) | BigInt.from(signature[i]);
    }
    return s < _groupOrder;
  }

  /// True iff [accountPublicKey] is acceptable AND derives [snowId]. Used when
  /// the server hands us an account key without a binding (legacy peer) so we
  /// can still compute the account-key Safety Number.
  static bool accountKeyMatchesSnowId(
      Uint8List? accountPublicKey, String snowId) {
    if (!isAcceptableAccountKey(accountPublicKey)) return false;
    final derived = KeyDerivation.deriveSnowChatId(accountPublicKey!);
    return constantTimeEquals(ascii.encode(derived), ascii.encode(snowId));
  }
}

/// Server wire form of a binding: `{sig: base64(64B), epoch: "<u64>", version: 1}`.
class IdentityBinding {
  final Uint8List signature;
  final int epoch;
  final int version;

  const IdentityBinding({
    required this.signature,
    required this.epoch,
    this.version = IdentityBindingV1.version,
  });

  Map<String, dynamic> toWireJson() => {
        'sig': base64Encode(signature),
        'epoch': epoch.toString(),
        'version': version,
      };

  /// Strict parser. Returns null when [raw] is not a well-formed v1 binding
  /// (callers must distinguish "absent" — raw == null — from "present but
  /// unparseable", which is treated as an invalid binding).
  static IdentityBinding? tryParseWire(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    if (version != IdentityBindingV1.version) return null;
    final epochRaw = raw['epoch'];
    if (epochRaw is! String) return null;
    final epoch = IdentityBindingV1.parseEpoch(epochRaw);
    if (epoch == null) return null;
    final sigRaw = raw['sig'];
    if (sigRaw is! String) return null;
    final Uint8List sig;
    try {
      sig = base64Decode(sigRaw);
    } catch (_) {
      return null;
    }
    if (sig.length != 64) return null;
    return IdentityBinding(signature: sig, epoch: epoch);
  }
}

/// Binding carried INSIDE a type-2 (PreKey) Signal message so the receiver can
/// verify the initiator's identity offline (no server round-trip, no OPK
/// consumption). The X25519 identity key is NOT duplicated here: the
/// receiver binds the signature to the X3DH header's identityKey, so a header
/// whose key differs from the signed one simply fails verification.
///
/// JSON fields: accountPublicKey (hex64), deviceId, epoch (decimal u64
/// string), ed25519 (hex64), sig (base64, 64 bytes), version (1).
class EmbeddedIdentityBinding {
  final Uint8List accountPublicKey;
  final String deviceId;
  final int epoch;
  final Uint8List ed25519;
  final Uint8List signature;

  const EmbeddedIdentityBinding({
    required this.accountPublicKey,
    required this.deviceId,
    required this.epoch,
    required this.ed25519,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'accountPublicKey': bytesToHexLower(accountPublicKey),
        'deviceId': deviceId,
        'epoch': epoch.toString(),
        'ed25519': bytesToHexLower(ed25519),
        'sig': base64Encode(signature),
        'version': IdentityBindingV1.version,
      };

  /// Strict parser — null when malformed (see [IdentityBinding.tryParseWire]).
  static EmbeddedIdentityBinding? tryParse(Object? raw) {
    if (raw is! Map) return null;
    if (raw['version'] != IdentityBindingV1.version) return null;
    // Type checks first: a non-string field must yield null (→ typed
    // badFormat rejection by the caller), never a TypeError.
    final accountRaw = raw['accountPublicKey'];
    final edRaw = raw['ed25519'];
    final epochRaw = raw['epoch'];
    final deviceId = raw['deviceId'];
    final sigRaw = raw['sig'];
    if (accountRaw is! String || edRaw is! String || epochRaw is! String) {
      return null;
    }
    final account = IdentityBindingV1.parseAccountKeyHex(accountRaw);
    final edKey = IdentityBindingV1.parseAccountKeyHex(edRaw);
    final epoch = IdentityBindingV1.parseEpoch(epochRaw);
    if (account == null ||
        edKey == null ||
        epoch == null ||
        deviceId is! String ||
        sigRaw is! String) {
      return null;
    }
    final Uint8List sig;
    try {
      sig = base64Decode(sigRaw);
    } catch (_) {
      return null;
    }
    if (sig.length != 64) return null;
    return EmbeddedIdentityBinding(
      accountPublicKey: account,
      deviceId: deviceId,
      epoch: epoch,
      ed25519: edKey,
      signature: sig,
    );
  }
}

/// Our own binding, minted by IdentityManager. Holds every signed field so it
/// can be emitted both in the server wire form and embedded in PreKey messages.
class LocalIdentityBinding {
  final String snowId;
  final Uint8List accountPublicKey;
  final String deviceId;
  final int epoch;
  final Uint8List identityKey;
  final Uint8List ed25519;
  final Uint8List signature;

  const LocalIdentityBinding({
    required this.snowId,
    required this.accountPublicKey,
    required this.deviceId,
    required this.epoch,
    required this.identityKey,
    required this.ed25519,
    required this.signature,
  });

  /// True iff this binding signs exactly ([deviceId], [ik], [edKey]).
  bool covers({
    required String deviceId,
    required Uint8List ik,
    required Uint8List edKey,
  }) =>
      this.deviceId == deviceId &&
      constantTimeEquals(identityKey, ik) &&
      constantTimeEquals(ed25519, edKey);

  IdentityBinding get wire =>
      IdentityBinding(signature: signature, epoch: epoch);

  EmbeddedIdentityBinding get embedded => EmbeddedIdentityBinding(
        accountPublicKey: accountPublicKey,
        deviceId: deviceId,
        epoch: epoch,
        ed25519: ed25519,
        signature: signature,
      );

  Map<String, dynamic> toStorageJson() => {
        'snowId': snowId,
        'accountPublicKey': bytesToHexLower(accountPublicKey),
        'deviceId': deviceId,
        'epoch': epoch.toString(),
        'identityKey': bytesToHexLower(identityKey),
        'ed25519': bytesToHexLower(ed25519),
        'sig': base64Encode(signature),
      };

  static LocalIdentityBinding? tryParseStorage(Object? raw) {
    if (raw is! Map) return null;
    try {
      final account = IdentityBindingV1.parseAccountKeyHex(
          raw['accountPublicKey'] as String?);
      final ik =
          IdentityBindingV1.parseAccountKeyHex(raw['identityKey'] as String?);
      final edKey =
          IdentityBindingV1.parseAccountKeyHex(raw['ed25519'] as String?);
      final epoch = IdentityBindingV1.parseEpoch(raw['epoch'] as String?);
      final sig = base64Decode(raw['sig'] as String);
      final snowId = raw['snowId'] as String;
      final deviceId = raw['deviceId'] as String;
      if (account == null || ik == null || edKey == null || epoch == null) {
        return null;
      }
      return LocalIdentityBinding(
        snowId: snowId,
        accountPublicKey: account,
        deviceId: deviceId,
        epoch: epoch,
        identityKey: ik,
        ed25519: edKey,
        signature: sig,
      );
    } catch (_) {
      return null;
    }
  }
}
