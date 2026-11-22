/// @file        sender_key.dart
/// @description Sender Key protocol for group protocol v2 (wire format v4): chain ratchet,
///              key distribution message, and encrypt/decrypt where the signature covers a
///              caller-supplied binding (the hash of the group id and the envelope header) and
///              the message's own header. The keys live in the database (gv2_sender_key_store.dart);
///              a manager here holds the records a caller loaded for one operation.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-30
/// @lastUpdated 2026-11-20 (v1 groups removed: only wire format v4 remains — the v3 encrypt/decrypt,
///              rotation versions, the origin-SKDM cache, the session-store (de)serialization of the
///              manager, SKDM byte (de)serialization and the legacy record formats are gone).
///              Earlier 2026-11-13 (wire format v4 for group protocol v2; reading a message changes
///              the key state only when it opens; a v4 key reads one message)
///
/// @functions
///  - senderKeyMessageLength(): Length of a Sender Key message for a plaintext length
///  - SenderKeyException / SenderKeyFailure: Why a message could not be read
///  - SenderKeyState: Sender Key state (chain key, iteration, signing key, cached message keys)
///  - SenderKeyState.deriveMessageKey() / ratchet(): the chain ratchet
///  - SenderKeyRecord: up to five chains of one sender
///  - SenderKeyDistributionMessage: a sender's key at a position of its chain
///  - SenderKeyManager.createSenderKey(): Create our own Sender Key for a group
///  - SenderKeyManager.processSenderKey(): Install a received Sender Key
///  - SenderKeyManager.encryptBoundGroupMessage(): Encrypt a message bound to its envelope header
///  - SenderKeyManager.decryptBoundGroupMessage(): Decrypt a message, failing with a SenderKeyFailure
///  - SenderKeyManager.hasSenderKey(): Whether a key of a sender is held
///  - SenderKeyManager.toJson(): The records, by "groupId:senderId"
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pinenacl/x25519.dart' as nacl_api;
import 'package:pinenacl/ed25519.dart' as ed;

import 'ed25519_strict.dart';
import 'hkdf.dart' show hmacSha256;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum number of forward-ratchet steps allowed when decrypting
/// out-of-order messages (prevents DoS via huge iteration gaps).
/// Signal uses 25,000 to support large groups with out-of-order delivery.
const int maxForwardRatchetSteps = 25000;

/// Maximum number of chains (SenderKeyState) kept per sender: a new own chain
/// after a member left still lets messages of the earlier one be read.
const int maxSenderKeyStates = 5;

/// Maximum number of cached message keys per SenderKeyState.
/// Prevents unbounded memory growth from out-of-order message gaps.
const int maxCachedMessageKeys = 2000;

/// Wire format of group protocol v2 (the only one): the signature covers a 32-byte binding
/// supplied by the caller (the hash of the group id and the envelope header),
/// the message's own version, chain id and iteration, and the ciphertext.
///
/// The envelope of a v2 group is sealed with a key every member — and every
/// former member — knows. Without the binding such a person could wrap
/// someone else's message in a new header (a new message id, a false group
/// revision) and have it accepted; without the chain id and the iteration
/// under the signature they could push a receiver's copy of the chain
/// forward past messages still in flight.
const int senderKeyWireV4 = 4;

/// Length of the binding a v4 signature covers.
const int senderKeyBindingLength = 32;

/// version(1) + chainId(4) + iteration(4) + signature(64).
const int _messageHeaderLength = 73;

/// Bytes a Sender Key message adds to its plaintext: the header above, the
/// 24-byte nonce and the 16-byte authentication tag.
const int senderKeyMessageOverhead = _messageHeaderLength + 24 + 16;

/// Length of the Sender Key message for a plaintext of [plaintextLength]
/// bytes. A sender needs it before encrypting: the
/// envelope header it signs carries the length of the message.
int senderKeyMessageLength(int plaintextLength) =>
    senderKeyMessageOverhead + plaintextLength;

/// Domain separation of the v4 signature: no other signature in the app
/// starts with this byte and label.
const int _boundSignaturePrefix = 0xfe;
final Uint8List _boundSignatureLabel =
    Uint8List.fromList(ascii.encode('SnowChat_GV2_Msg_v1'));

final Uint8List _messageKeyInput = Uint8List.fromList([0x01]);
final Uint8List _chainKeyInput = Uint8List.fromList([0x02]);

final _rng = Random.secure();

/// Why a Sender Key message could not be read.
enum SenderKeyFailure {
  /// Not a v4 Sender Key message.
  malformed,

  /// No key of this sender, or none for the chain the message names. The
  /// claim is not authenticated — there is no key to check it with.
  noKey,

  /// The signature does not verify. The key is kept: anyone who can seal an
  /// envelope can produce such a message, and must not thereby make a
  /// receiver throw away a good key.
  signature,

  /// The chain has moved past this message and its key is no longer cached.
  expired,

  /// The message is more than [maxForwardRatchetSteps] ahead of the chain.
  tooFarAhead,

  /// Signed by the sender, but the ciphertext does not open.
  decrypt,
}

/// A Sender Key message that could not be read. The key state is unchanged.
class SenderKeyException implements Exception {
  final SenderKeyFailure reason;
  final String message;

  const SenderKeyException(this.reason, this.message);

  @override
  String toString() => 'SenderKeyException(${reason.name}): $message';
}

// ---------------------------------------------------------------------------
// SenderKeyState
// ---------------------------------------------------------------------------

/// State for a single sender key (either our own or a remote member's).
///
/// Chain ratchet uses HMAC-SHA256:
/// - messageKey = HMAC(chainKey, 0x01)
/// - nextChainKey = HMAC(chainKey, 0x02)
///
/// Encryption uses XSalsa20-Poly1305 (pinenacl SecretBox).
class SenderKeyState {
  /// 31-bit random chain identifier: a message names the chain it was sent
  /// on, and the receiver finds the state by it.
  final int chainId;

  /// Current chain ratchet iteration number.
  int iteration;

  /// Current 32-byte chain key.
  Uint8List chainKey;

  /// Ed25519 signing public key (used to authenticate sender).
  Uint8List signingKeyPublic;

  /// Ed25519 signing private key seed (only present for our own sender key).
  Uint8List? signingKeyPrivate;

  /// Out-of-order message key cache: iteration → derived message key.
  /// When receiving a message with a future iteration, intermediate keys
  /// are cached here for later out-of-order messages.
  final Map<int, Uint8List> cachedMessageKeys;

  SenderKeyState({
    required this.chainId,
    required this.iteration,
    required this.chainKey,
    required this.signingKeyPublic,
    this.signingKeyPrivate,
    Map<int, Uint8List>? cachedMessageKeys,
  }) : cachedMessageKeys = cachedMessageKeys ?? {};

  /// Derive the current message key from the chain key.
  /// messageKey = HMAC-SHA256(chainKey, 0x01)
  Uint8List deriveMessageKey() {
    return hmacSha256(chainKey, Uint8List.fromList([0x01]));
  }

  /// Advance the chain key forward by one step.
  /// nextChainKey = HMAC-SHA256(chainKey, 0x02)
  void ratchet() {
    chainKey = hmacSha256(chainKey, Uint8List.fromList([0x02]));
    iteration++;
  }

  /// Serialize state to JSON.
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'chainId': chainId,
      'iteration': iteration,
      'chainKey': _bytesToHex(chainKey),
      'signingKeyPublic': _bytesToHex(signingKeyPublic),
      if (signingKeyPrivate != null)
        'signingKeyPrivate': _bytesToHex(signingKeyPrivate!),
    };
    if (cachedMessageKeys.isNotEmpty) {
      json['cachedMessageKeys'] = cachedMessageKeys.map(
        (k, v) => MapEntry(k.toString(), _bytesToHex(v)),
      );
    }
    return json;
  }

  /// Deserialize state from JSON.
  factory SenderKeyState.fromJson(Map<String, dynamic> json) {
    Map<int, Uint8List>? cached;
    final cachedJson = json['cachedMessageKeys'] as Map<String, dynamic>?;
    if (cachedJson != null) {
      cached = cachedJson.map(
        (k, v) => MapEntry(int.parse(k), _hexToBytes(v as String)),
      );
    }
    return SenderKeyState(
      chainId: json['chainId'] as int,
      iteration: json['iteration'] as int,
      chainKey: _hexToBytes(json['chainKey'] as String),
      signingKeyPublic: _hexToBytes(json['signingKeyPublic'] as String),
      signingKeyPrivate: json['signingKeyPrivate'] != null
          ? _hexToBytes(json['signingKeyPrivate'] as String)
          : null,
      cachedMessageKeys: cached,
    );
  }
}

// ---------------------------------------------------------------------------
// SenderKeyRecord — the chains of one sender
// ---------------------------------------------------------------------------

/// Holds up to [maxSenderKeyStates] chains ([SenderKeyState]) of one sender
/// in one group, newest first. When the sender starts a new chain, the
/// earlier ones stay so that messages still in flight can be read.
class SenderKeyRecord {
  final List<SenderKeyState> states;

  SenderKeyRecord({required this.states});

  /// Add a new state (newest first). Evicts oldest if over limit.
  void addState(SenderKeyState state) {
    states.insert(0, state);
    while (states.length > maxSenderKeyStates) {
      states.removeLast();
    }
  }

  /// Look up state by chainId. Returns null if not found.
  SenderKeyState? stateForChainId(int chainId) {
    for (final s in states) {
      if (s.chainId == chainId) return s;
    }
    return null;
  }

  /// Get the most recent (active) state.
  SenderKeyState get current => states.first;

  bool get isEmpty => states.isEmpty;

  Map<String, dynamic> toJson() => {
        'states': states.map((s) => s.toJson()).toList(),
      };

  factory SenderKeyRecord.fromJson(Map<String, dynamic> json) =>
      SenderKeyRecord(
        states: (json['states'] as List)
            .map((s) => SenderKeyState.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// SenderKeyDistributionMessage
// ---------------------------------------------------------------------------

/// A sender's key at one position of its chain: what a member is given
/// (group protocol v2 carries it in a pairwise message — gv2_pairwise.dart).
class SenderKeyDistributionMessage {
  final String groupId;
  final String senderId;

  /// The chain the key belongs to (the chain id a message names).
  final int chainId;
  final int iteration;
  final Uint8List chainKey;
  final Uint8List signingKey;

  const SenderKeyDistributionMessage({
    required this.groupId,
    required this.senderId,
    required this.chainId,
    required this.iteration,
    required this.chainKey,
    required this.signingKey,
  });
}

// ---------------------------------------------------------------------------
// SenderKeyManager
// ---------------------------------------------------------------------------

/// Holds Sender Key records for one operation and reads, writes and makes
/// keys with them. Key format of the records: "groupId:senderId".
///
/// Encryption is O(1) regardless of group size — the same ciphertext is
/// sent to all recipients.
///
/// The key of a message that was read is not kept, so the same message
/// cannot be read a second time — a replayed envelope fails as `expired`.
/// The records live in the database and a read is saved in the same
/// transaction as the message it produced, so there is nothing to retry from
/// a kept key.
class SenderKeyManager {
  final Map<String, SenderKeyRecord> _senderKeys;

  SenderKeyManager({Map<String, SenderKeyRecord>? senderKeys})
      : _senderKeys = senderKeys ?? {};

  /// Create our own sender key for a group: a new chain, at position 0.
  /// Earlier own chains stay (up to [maxSenderKeyStates]).
  SenderKeyDistributionMessage createSenderKey(
    String groupId,
    String myId,
  ) {
    if (myId.isEmpty) {
      throw ArgumentError(
          'createSenderKey: myId must not be empty (group $groupId)');
    }
    final chainKey = _randomBytes(32);
    final signingKey = ed.SigningKey.generate();
    final chainId = _rng.nextInt(0x7FFFFFFF); // 31-bit random

    final state = SenderKeyState(
      chainId: chainId,
      iteration: 0,
      chainKey: chainKey,
      signingKeyPublic: Uint8List.fromList(signingKey.verifyKey.toList()),
      signingKeyPrivate: Uint8List.fromList(signingKey.seed),
    );

    final key = '$groupId:$myId';
    final record = _senderKeys[key];
    if (record != null) {
      record.addState(state);
    } else {
      _senderKeys[key] = SenderKeyRecord(states: [state]);
    }

    return SenderKeyDistributionMessage(
      groupId: groupId,
      senderId: myId,
      chainId: chainId,
      iteration: 0,
      chainKey: Uint8List.fromList(chainKey),
      signingKey: Uint8List.fromList(signingKey.verifyKey.toList()),
    );
  }

  /// Install a received key of another member.
  ///
  /// A chain already held is never replaced — not by an earlier position of
  /// it either (a second copy would start with an empty key cache and be
  /// found first). Returns true when the key is held afterwards (installed
  /// now, or already there), false when the message was refused.
  bool processSenderKey(SenderKeyDistributionMessage message) {
    if (message.senderId.isEmpty) return false;
    // A key of the wrong length can never read a message; installed, it
    // would only sit in front of a good one.
    if (message.chainKey.length != 32 ||
        message.signingKey.length != 32 ||
        message.iteration < 0 ||
        message.chainId < 0) {
      return false;
    }
    final key = '${message.groupId}:${message.senderId}';
    final newState = SenderKeyState(
      chainId: message.chainId,
      iteration: message.iteration,
      chainKey: Uint8List.fromList(message.chainKey),
      signingKeyPublic: Uint8List.fromList(message.signingKey),
    );

    final record = _senderKeys[key];
    if (record == null) {
      _senderKeys[key] = SenderKeyRecord(states: [newState]);
    } else if (record.stateForChainId(message.chainId) == null) {
      record.addState(newState);
    }
    return true;
  }

  /// Encrypt a message with our own sender key for the group.
  ///
  /// [binding] is the 32-byte hash that ties the message to its envelope
  /// header (group protocol v2: SHA256(groupId ‖ header)). The header
  /// carries the length of this message, which the caller gets from
  /// [senderKeyMessageLength] before calling.
  ///
  /// Layout: [version(1)=4][chainId(4 BE)][iteration(4 BE)][sig(64)][ct].
  /// Signed: 0xFE ‖ "SnowChat_GV2_Msg_v1" ‖ binding ‖ version ‖ chainId ‖
  /// iteration ‖ ct.
  ///
  /// [nonce] fixes the 24-byte nonce of the ciphertext; tests only (golden
  /// vectors). Everything else draws a fresh random one.
  Uint8List encryptBoundGroupMessage(
    String groupId,
    String myId,
    Uint8List plaintext,
    Uint8List binding, {
    @visibleForTesting Uint8List? nonce,
  }) {
    if (myId.isEmpty) {
      throw ArgumentError('encryptBoundGroupMessage: myId must not be empty');
    }
    if (binding.length != senderKeyBindingLength) {
      throw ArgumentError(
          'encryptBoundGroupMessage: binding must be $senderKeyBindingLength '
          'bytes');
    }
    final record = _senderKeys['$groupId:$myId'];
    if (record == null || record.isEmpty) {
      throw StateError('No sender key. Call createSenderKey() first.');
    }
    final state = record.current;
    if (state.signingKeyPrivate == null) {
      throw StateError(
          'Cannot encrypt with a remote sender key (no private key).');
    }

    final ciphertext =
        _encrypt(state.deriveMessageKey(), plaintext, nonce: nonce);
    final header = Uint8List(9)
      ..[0] = senderKeyWireV4
      ..setAll(1, _int32ToBE(state.chainId))
      ..setAll(5, _int32ToBE(state.iteration));
    final signature = ed.SigningKey.fromSeed(state.signingKeyPrivate!)
        .sign(_boundSignedBytes(binding, header, ciphertext))
        .signature;

    final output = Uint8List(_messageHeaderLength + ciphertext.length)
      ..setAll(0, header)
      ..setAll(9, signature)
      ..setAll(_messageHeaderLength, ciphertext);

    state.ratchet();
    return output;
  }

  /// Decrypt a message from [senderId], bound to [binding] (see
  /// [encryptBoundGroupMessage]).
  ///
  /// Throws [SenderKeyException]; the reason tells the caller what to do
  /// next (ask for the key, drop the message, ...). Whatever the reason, the
  /// stored key is neither changed nor removed.
  ///
  /// The caller decides whose messages to read at all: [senderId] must
  /// already be known as a member of the group.
  Uint8List decryptBoundGroupMessage(
    String groupId,
    String senderId,
    Uint8List data,
    Uint8List binding,
  ) {
    if (binding.length != senderKeyBindingLength) {
      throw ArgumentError(
          'decryptBoundGroupMessage: binding must be $senderKeyBindingLength '
          'bytes');
    }
    if (data.length < senderKeyMessageOverhead ||
        data[0] != senderKeyWireV4) {
      throw const SenderKeyException(
          SenderKeyFailure.malformed, 'Not a v4 Sender Key message.');
    }
    final record = _senderKeys['$groupId:$senderId'];
    final state =
        record?.stateForChainId(_beToInt32(data.sublist(1, 5)));
    if (state == null) {
      throw const SenderKeyException(
          SenderKeyFailure.noKey, 'No sender key for this chain.');
    }

    final header = Uint8List.sublistView(data, 0, 9);
    final signature = Uint8List.fromList(data.sublist(9, _messageHeaderLength));
    final ciphertext = Uint8List.fromList(data.sublist(_messageHeaderLength));
    if (!verifyEd25519Strict(state.signingKeyPublic,
        _boundSignedBytes(binding, header, ciphertext), signature)) {
      throw const SenderKeyException(
          SenderKeyFailure.signature, 'The signature does not verify.');
    }
    return _open(state, _beToInt32(data.sublist(5, 9)), ciphertext);
  }

  /// Reads [ciphertext], sent at [messageIteration] of the chain of [state].
  ///
  /// The state changes only when the ciphertext opens: the keys of the
  /// iterations skipped on the way are cached, a cached key that read its
  /// message is dropped, and the chain moves one past the message. A message
  /// that does not open leaves the chain where it was.
  Uint8List _open(
    SenderKeyState state,
    int messageIteration,
    Uint8List ciphertext,
  ) {
    // Check for out-of-order (past message)
    if (messageIteration < state.iteration) {
      final cachedKey = state.cachedMessageKeys[messageIteration];
      if (cachedKey == null) {
        throw SenderKeyException(
          SenderKeyFailure.expired,
          'Message iteration $messageIteration behind ${state.iteration}, '
          'no cached key available.',
        );
      }
      final plaintext = _decryptOrFail(cachedKey, ciphertext);
      // A key reads one message. (Only once it has: a message that does not
      // open leaves the state as it was.)
      state.cachedMessageKeys.remove(messageIteration);
      return plaintext;
    }

    final steps = messageIteration - state.iteration;
    if (steps > maxForwardRatchetSteps) {
      throw SenderKeyException(
        SenderKeyFailure.tooFarAhead,
        'Too many forward ratchet steps ($steps > $maxForwardRatchetSteps)',
      );
    }

    // Walk a copy of the chain to the message.
    var chainKey = state.chainKey;
    final skipped = <int, Uint8List>{};
    for (var i = state.iteration; i < messageIteration; i++) {
      skipped[i] = hmacSha256(chainKey, _messageKeyInput);
      chainKey = hmacSha256(chainKey, _chainKeyInput);
    }
    final messageKey = hmacSha256(chainKey, _messageKeyInput);
    final plaintext = _decryptOrFail(messageKey, ciphertext);

    // Cache the keys of the skipped iterations for messages still in
    // flight (not the key of this message — it reads one message). The cap
    // bounds memory.
    state.cachedMessageKeys.addAll(skipped);
    while (state.cachedMessageKeys.length > maxCachedMessageKeys) {
      state.cachedMessageKeys.remove(state.cachedMessageKeys.keys.first);
    }

    // Advance chain past this message
    state.chainKey = hmacSha256(chainKey, _chainKeyInput);
    state.iteration = messageIteration + 1;
    return plaintext;
  }

  /// Check if we have a sender key for a specific member in a group.
  bool hasSenderKey(String groupId, String senderId) {
    final record = _senderKeys['$groupId:$senderId'];
    return record != null && !record.isEmpty;
  }

  /// The records, by "groupId:senderId" (each [SenderKeyRecord.toJson]).
  Map<String, dynamic> toJson() => {
        for (final entry in _senderKeys.entries) entry.key: entry.value.toJson(),
      };
}

// =============================================================================
// Symmetric encryption (XSalsa20-Poly1305 via pinenacl SecretBox)
// =============================================================================

/// Encrypt [plaintext] with [messageKey] using XSalsa20-Poly1305.
/// Returns nonce (24 bytes) || ciphertext+tag. Without [nonce] the nonce is
/// random.
Uint8List _encrypt(
  Uint8List messageKey,
  Uint8List plaintext, {
  Uint8List? nonce,
}) {
  final box = nacl_api.SecretBox(messageKey);
  if (nonce == null) {
    nonce = Uint8List(nacl_api.EncryptedMessage.nonceLength);
    for (var i = 0; i < nonce.length; i++) {
      nonce[i] = _rng.nextInt(256);
    }
  } else if (nonce.length != nacl_api.EncryptedMessage.nonceLength) {
    throw ArgumentError('nonce must be 24 bytes');
  }
  final encrypted = box.encrypt(plaintext, nonce: nonce);
  return Uint8List.fromList(encrypted.toList());
}

/// [_decrypt], failing with [SenderKeyFailure.decrypt].
Uint8List _decryptOrFail(Uint8List messageKey, Uint8List ciphertextWithNonce) {
  try {
    return _decrypt(messageKey, ciphertextWithNonce);
  } catch (_) {
    throw const SenderKeyException(
        SenderKeyFailure.decrypt, 'The ciphertext does not open.');
  }
}

/// What a v4 signature covers: 0xFE ‖ label ‖ binding(32) ‖ the first nine
/// bytes of the message (version, chain id, iteration) ‖ ciphertext.
Uint8List _boundSignedBytes(
  Uint8List binding,
  Uint8List header,
  Uint8List ciphertext,
) {
  final out = BytesBuilder(copy: false)
    ..addByte(_boundSignaturePrefix)
    ..add(_boundSignatureLabel)
    ..add(binding)
    ..add(header)
    ..add(ciphertext);
  return out.takeBytes();
}

/// Decrypt [ciphertextWithNonce] with [messageKey] using XSalsa20-Poly1305.
Uint8List _decrypt(Uint8List messageKey, Uint8List ciphertextWithNonce) {
  final box = nacl_api.SecretBox(messageKey);
  final decrypted = box.decrypt(
    nacl_api.EncryptedMessage(
      nonce: ciphertextWithNonce.sublist(0, nacl_api.EncryptedMessage.nonceLength),
      cipherText: ciphertextWithNonce.sublist(nacl_api.EncryptedMessage.nonceLength),
    ),
  );
  return Uint8List.fromList(decrypted.toList());
}

// =============================================================================
// Utility
// =============================================================================

Uint8List _randomBytes(int length) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _rng.nextInt(256);
  }
  return bytes;
}

String _bytesToHex(Uint8List bytes) {
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List _hexToBytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

/// Encode a 32-bit integer as 4 big-endian bytes.
Uint8List _int32ToBE(int value) {
  return Uint8List(4)
    ..[0] = (value >> 24) & 0xFF
    ..[1] = (value >> 16) & 0xFF
    ..[2] = (value >> 8) & 0xFF
    ..[3] = value & 0xFF;
}

/// Decode 4 big-endian bytes to a 32-bit integer.
int _beToInt32(Uint8List bytes) {
  return (bytes[0] << 24) |
      (bytes[1] << 16) |
      (bytes[2] << 8) |
      bytes[3];
}
