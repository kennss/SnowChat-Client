/// @file        identity_manager.dart
/// @description User Ed25519 ID keypair management. Creation, restore, signing, and integrated Signal Protocol key management
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-10 (B-2 Identity Binding v1: account-key signing is purpose-bound — signAuthChallenge() with a strict nonce regex and signIdentityBinding(); the generic sign()/signString() are private (signing-oracle fix §3.1). currentIdentityBinding() mints/reuses the local binding with a monotonic epoch, re-signed whenever the X25519 IK, the Signal Ed25519 key or the deviceId changes). Earlier 2026-04-26 (header English translation)
///
/// @functions
///  - IdentityManager: User ID keypair and Signal key management class
///  - IdentityManager.setSignalService(): Wire up SignalProtocolService
///  - IdentityManager.hasIdentity(): Check whether an identity exists on this device
///  - IdentityManager.createIdentity(): Create a new identity, return mnemonic
///  - IdentityManager.restoreIdentity(): Restore identity from mnemonic
///  - IdentityManager.getSnowChatId(): Get the current SnowChat ID
///  - IdentityManager.getMnemonic(): Get the stored mnemonic
///  - IdentityManager.getPublicKey(): Get public key bytes
///  - IdentityManager.getPublicKeyHex(): Get public key as hex string
///  - IdentityManager.getPrivateKey(): Get private key bytes
///  - IdentityManager.signAuthChallenge(): Sign a server login nonce (strict format check)
///  - IdentityManager.signIdentityBinding(): Sign an Identity Binding v1 message
///  - IdentityManager.currentIdentityBinding(): Reuse or mint the local binding (monotonic epoch)
///  - IdentityManager.invalidateIdentityBinding(): Force a re-sign on next use
///  - IdentityManager.recordAccountMaxBindingEpoch(): Persist the server's account-wide max epoch (H1)
///  - IdentityManager.accountMaxBindingEpoch(): Read it back
///  - IdentityManager._sign(): Private Ed25519 detached signing with the account key
///  - IdentityManager.generateSignalIdentityKey(): Generate and store Signal Curve25519 keypair
///  - IdentityManager.getSignalPublicKey(): Get Signal public key
///  - IdentityManager.hasSignalIdentity(): Check whether Signal keypair exists
///  - IdentityManager.deleteIdentity(): Delete all identity data

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pinenacl/ed25519.dart';

import '../storage/secure_storage.dart';
import 'identity_binding.dart';
import 'key_derivation.dart';
import 'signal_protocol_service.dart';

/// Manages the user's Ed25519 identity keypair.
/// Private keys are stored in flutter_secure_storage (Keychain / Android Keystore).
///
/// Also coordinates with [SignalProtocolService] to generate and store the
/// Curve25519 identity key pair used by the Signal Protocol (separate from the
/// Ed25519 key used for SnowChat ID derivation).
class IdentityManager {
  final SecureStorageService _secureStorage;
  SignalProtocolService? _signalService;

  static const _mnemonicKey = 'identity_mnemonic';
  static const _privateKeyKey = 'identity_private_key';
  static const _publicKeyKey = 'identity_public_key';
  static const _snowIdKey = 'snow_chat_id';
  static const _signalIdentityPublicKey = 'signal_identity_public_key';
  static const _signalIdentityPrivateKey = 'signal_identity_private_key';
  static const _signalSigningSeedKey = 'signal_signing_seed';
  static const _signalVerifyKeyKey = 'signal_verify_key';
  static const _signalRegistrationIdKey = 'signal_registration_id';

  /// B-2: our current Identity Binding (JSON, see LocalIdentityBinding).
  static const _localBindingKey = 'identity_binding_v1_local';

  /// B-2: highest binding epoch ever minted on this install. Survives
  /// invalidation so a re-minted binding always has a strictly larger epoch.
  static const _lastBindingEpochKey = 'identity_binding_v1_last_epoch';

  /// B-2 H1: highest binding epoch the SERVER has seen for this account
  /// (`accountMaxIdentityBindingEpoch` from /auth/verify and
  /// /keys/prekey-count). A fresh install / restore has no local high-water
  /// mark, so without this it could mint below an epoch the account already
  /// used and be rejected as a regression.
  static const _accountMaxBindingEpochKey = 'identity_binding_v1_account_max';

  /// Largest epoch representable on the wire (u64 field, but kept <= 2^63-1
  /// to match the server and Dart's native int).
  static const int _maxEpoch = 0x7fffffffffffffff;

  /// Login nonce format issued by the server: UUIDv4 + '-' + base36(ms).
  /// Anything else is refused BEFORE touching the account key, so a hostile
  /// server cannot turn the login challenge into a general signing oracle.
  static final RegExp _authNonceRe = RegExp(r'^[0-9a-f-]{36}-[0-9a-z]{1,12}$');
  static const int _authNonceMaxLength = 49;

  /// Serializes binding minting so two concurrent callers never mint two
  /// different epochs for the same keys.
  Future<LocalIdentityBinding>? _bindingInFlight;

  /// Attach a [SignalProtocolService] instance for Signal key management.
  /// This is optional -- if not set, Signal-related operations are skipped.
  void setSignalService(SignalProtocolService service) {
    _signalService = service;
  }

  IdentityManager(this._secureStorage);

  /// Check if identity already exists on this device.
  Future<bool> hasIdentity() async {
    final id = await _secureStorage.read(_snowIdKey);
    return id != null && id.isNotEmpty;
  }

  /// Create a new identity. Returns the mnemonic for backup.
  Future<List<String>> createIdentity() async {
    final mnemonic = KeyDerivation.generateMnemonic();
    final keyPair = await KeyDerivation.deriveKeyPair(mnemonic);

    await _secureStorage.write(_mnemonicKey, mnemonic.join(' '));
    await _secureStorage.write(
        _privateKeyKey, _bytesToHex(keyPair.privateKey));
    await _secureStorage.write(
        _publicKeyKey, _bytesToHex(keyPair.publicKey));
    await _secureStorage.write(_snowIdKey, keyPair.snowChatId);

    return mnemonic;
  }

  /// Restore identity from mnemonic.
  Future<String> restoreIdentity(List<String> mnemonic) async {
    if (!KeyDerivation.isValidMnemonic(mnemonic)) {
      throw ArgumentError('Invalid mnemonic: must be 12 or 24 valid BIP39 words');
    }

    final _sw = Stopwatch()..start();
    final keyPair = await KeyDerivation.deriveKeyPair(mnemonic);
    debugPrint('[Perf]   BIP39 + SLIP-0010 deriveKeyPair: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(_mnemonicKey, mnemonic.join(' '));
    debugPrint('[Perf]   write mnemonic: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(
        _privateKeyKey, _bytesToHex(keyPair.privateKey));
    debugPrint('[Perf]   write privateKey: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(
        _publicKeyKey, _bytesToHex(keyPair.publicKey));
    debugPrint('[Perf]   write publicKey: ${_sw.elapsedMilliseconds}ms');

    _sw.reset();
    await _secureStorage.write(_snowIdKey, keyPair.snowChatId);
    debugPrint('[Perf]   write snowId: ${_sw.elapsedMilliseconds}ms');

    return keyPair.snowChatId;
  }

  /// Get the current SnowChat ID.
  Future<String?> getSnowChatId() async {
    return _secureStorage.read(_snowIdKey);
  }

  /// Get the stored mnemonic (for backup display).
  Future<List<String>?> getMnemonic() async {
    final stored = await _secureStorage.read(_mnemonicKey);
    if (stored == null) return null;
    return stored.split(' ');
  }

  /// Get the public key bytes.
  Future<Uint8List?> getPublicKey() async {
    final hex = await _secureStorage.read(_publicKeyKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the public key as hex string (for server registration).
  Future<String?> getPublicKeyHex() async {
    return _secureStorage.read(_publicKeyKey);
  }

  /// Get the private key bytes (use with caution).
  Future<Uint8List?> getPrivateKey() async {
    final hex = await _secureStorage.read(_privateKeyKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Sign [data] with the ACCOUNT key (Ed25519 detached, 64 bytes).
  /// Private on purpose (§3.1): the account key now vouches for the Signal
  /// identity, so only purpose-bound wrappers may reach it.
  Future<Uint8List> _sign(Uint8List data) async {
    final privateKeySeed = await getPrivateKey();
    if (privateKeySeed == null) {
      throw StateError('No identity key available');
    }

    // pinenacl SigningKey from 32-byte seed produces tweetnacl-compatible signatures
    final signingKey = SigningKey(seed: privateKeySeed);
    final signedMessage = signingKey.sign(data);
    // signedMessage.signature is the 64-byte detached signature
    return Uint8List.fromList(signedMessage.signature.toList());
  }

  /// Sign the server's login challenge [nonce] and return the hex signature.
  /// Throws [FormatException] — aborting the login — when the nonce is not
  /// exactly the server's `uuidv4-base36(ms)` shape.
  Future<String> signAuthChallenge(String nonce) async {
    if (nonce.length > _authNonceMaxLength || !_authNonceRe.hasMatch(nonce)) {
      throw const FormatException(
          'Login challenge nonce has an unexpected format — refusing to sign');
    }
    final signature = await _sign(Uint8List.fromList(utf8.encode(nonce)));
    return _bytesToHex(signature);
  }

  /// Sign an Identity Binding v1 message for this account. The message starts
  /// with 0xFF, which utf8.encode never emits, so it can never collide with a
  /// login-challenge signature.
  Future<Uint8List> signIdentityBinding({
    required String deviceId,
    required int epoch,
    required Uint8List identityKey,
    required Uint8List ed25519,
  }) async {
    final snowId = await getSnowChatId();
    final accountPub = await getPublicKey();
    if (snowId == null || accountPub == null) {
      throw StateError('No identity available for binding');
    }
    if (KeyDerivation.deriveSnowChatId(accountPub) != snowId) {
      throw StateError('Stored account key does not derive the stored snowId');
    }
    final msg = IdentityBindingV1.buildMessage(
      snowId: snowId,
      deviceId: deviceId,
      epoch: epoch,
      identityKey: identityKey,
      ed25519: ed25519,
    );
    return _sign(msg);
  }

  /// Return the local Identity Binding covering exactly ([deviceId],
  /// [identityKey], [ed25519]). Reuses the stored binding when it already
  /// covers these values (and its epoch is above [minEpochExclusive]);
  /// otherwise mints a new one with epoch = max(now ms, last+1, min+1), so the
  /// epoch is strictly monotonic per install even within one millisecond or
  /// after a clock step backwards.
  Future<LocalIdentityBinding> currentIdentityBinding({
    required String deviceId,
    required Uint8List identityKey,
    required Uint8List ed25519,
    int? minEpochExclusive,
  }) async {
    while (_bindingInFlight != null) {
      try {
        await _bindingInFlight;
      } catch (_) {}
    }
    final future = _currentIdentityBindingLocked(
      deviceId: deviceId,
      identityKey: identityKey,
      ed25519: ed25519,
      minEpochExclusive: minEpochExclusive,
    );
    _bindingInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_bindingInFlight, future)) _bindingInFlight = null;
    }
  }

  Future<LocalIdentityBinding> _currentIdentityBindingLocked({
    required String deviceId,
    required Uint8List identityKey,
    required Uint8List ed25519,
    int? minEpochExclusive,
  }) async {
    final snowId = await getSnowChatId();
    final accountPub = await getPublicKey();
    if (snowId == null || accountPub == null) {
      throw StateError('No identity available for binding');
    }
    final accountMax = await accountMaxBindingEpoch();
    final storedRaw = await _secureStorage.read(_localBindingKey);
    if (storedRaw != null) {
      LocalIdentityBinding? stored;
      try {
        stored = LocalIdentityBinding.tryParseStorage(jsonDecode(storedRaw));
      } catch (_) {
        stored = null;
      }
      if (stored != null &&
          stored.snowId == snowId &&
          constantTimeEquals(stored.accountPublicKey, accountPub) &&
          stored.covers(deviceId: deviceId, ik: identityKey, edKey: ed25519) &&
          (minEpochExclusive == null || stored.epoch > minEpochExclusive) &&
          (accountMax == null || stored.epoch >= accountMax)) {
        return stored;
      }
    }

    final last = IdentityBindingV1.parseEpoch(
            await _secureStorage.read(_lastBindingEpochKey)) ??
        -1;
    // epoch = max(now ms, localLast+1, accountMax+1, minExclusive+1)
    var epoch = DateTime.now().millisecondsSinceEpoch;
    for (final floor in [last, accountMax, minEpochExclusive]) {
      if (floor == null) continue;
      if (floor >= _maxEpoch) {
        throw StateError('Identity binding epoch space exhausted');
      }
      if (epoch <= floor) epoch = floor + 1;
    }
    // Persist the epoch high-water mark BEFORE signing so a crash can never
    // lead to re-using an epoch for different keys.
    await _secureStorage.write(_lastBindingEpochKey, epoch.toString());
    final sig = await signIdentityBinding(
      deviceId: deviceId,
      epoch: epoch,
      identityKey: identityKey,
      ed25519: ed25519,
    );
    final binding = LocalIdentityBinding(
      snowId: snowId,
      accountPublicKey: accountPub,
      deviceId: deviceId,
      epoch: epoch,
      identityKey: Uint8List.fromList(identityKey),
      ed25519: Uint8List.fromList(ed25519),
      signature: sig,
    );
    await _secureStorage.write(
        _localBindingKey, jsonEncode(binding.toStorageJson()));
    debugPrint('[IdentityManager] minted identity binding (new epoch)');
    return binding;
  }

  /// B-2 H1: remember the account-wide max binding epoch reported by the
  /// server (monotonic — a lower value never overwrites a higher one).
  /// Accepts the raw wire value (decimal string or null).
  Future<void> recordAccountMaxBindingEpoch(Object? raw) async {
    if (raw is! String) return;
    final epoch = IdentityBindingV1.parseEpoch(raw);
    if (epoch == null) return;
    final current = await accountMaxBindingEpoch();
    if (current != null && current >= epoch) return;
    await _secureStorage.write(_accountMaxBindingEpochKey, epoch.toString());
  }

  /// Account-wide max binding epoch last reported by the server, or null.
  Future<int?> accountMaxBindingEpoch() async =>
      IdentityBindingV1.parseEpoch(
          await _secureStorage.read(_accountMaxBindingEpochKey));

  /// Drop the stored local binding so the next [currentIdentityBinding] call
  /// re-signs with a fresh epoch. Called whenever the IK or Ed is regenerated.
  Future<void> invalidateIdentityBinding() async {
    await _secureStorage.delete(_localBindingKey);
  }

  // ---------------------------------------------------------------------------
  // Signal Protocol Identity Key (Curve25519)
  // ---------------------------------------------------------------------------

  /// Generate and store the Signal Protocol identity key pair (Curve25519).
  /// This is separate from the Ed25519 key used for SnowChat ID.
  /// Called once during initial setup or identity creation.
  Future<Map<String, dynamic>> generateSignalIdentityKey() async {
    final signal = _signalService;
    if (signal == null) {
      throw StateError('SignalProtocolService not attached to IdentityManager');
    }

    final keyPair = await signal.generateIdentityKeyPair();
    // B-2: new IK (and possibly new Ed) → the old binding no longer covers
    // our keys; force a re-sign with a new epoch on next use.
    await invalidateIdentityBinding();
    final publicKey = keyPair['publicKey'] as Uint8List;
    final privateKey = keyPair['privateKey'] as Uint8List;

    // Store X25519 identity key pair
    await _secureStorage.write(
        _signalIdentityPublicKey, _bytesToHex(publicKey));
    await _secureStorage.write(
        _signalIdentityPrivateKey, _bytesToHex(privateKey));

    // Store Ed25519 signing seed + verify key + registration ID
    // (generated inside generateIdentityKeyPair)
    if (signal.signingKeySeed != null) {
      await _secureStorage.write(
          _signalSigningSeedKey, _bytesToHex(signal.signingKeySeed!));
    }
    if (signal.verifyKey != null) {
      await _secureStorage.write(
          _signalVerifyKeyKey, _bytesToHex(signal.verifyKey!));
    }
    if (signal.registrationId != null) {
      await _secureStorage.write(
          _signalRegistrationIdKey, signal.registrationId.toString());
    }

    return keyPair;
  }

  /// Get the stored Signal identity public key.
  Future<Uint8List?> getSignalPublicKey() async {
    final hex = await _secureStorage.read(_signalIdentityPublicKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Signal identity private key.
  Future<Uint8List?> getSignalPrivateKey() async {
    final hex = await _secureStorage.read(_signalIdentityPrivateKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Ed25519 signing seed.
  Future<Uint8List?> getSignalSigningSeed() async {
    final hex = await _secureStorage.read(_signalSigningSeedKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Ed25519 verify key.
  Future<Uint8List?> getSignalVerifyKey() async {
    final hex = await _secureStorage.read(_signalVerifyKeyKey);
    if (hex == null) return null;
    return _hexToBytes(hex);
  }

  /// Get the stored Signal registration ID.
  Future<int?> getSignalRegistrationId() async {
    final str = await _secureStorage.read(_signalRegistrationIdKey);
    if (str == null) return null;
    return int.tryParse(str);
  }

  /// Save Ed25519 signing seed + verify key to secure storage.
  /// B-2: a regenerated Ed invalidates the binding (re-signed on next use).
  Future<void> saveSigningSeed(Uint8List seed, Uint8List verifyKey) async {
    await _secureStorage.write(_signalSigningSeedKey, _bytesToHex(seed));
    await _secureStorage.write(_signalVerifyKeyKey, _bytesToHex(verifyKey));
    await invalidateIdentityBinding();
  }

  /// Check if a Signal identity key pair exists.
  Future<bool> hasSignalIdentity() async {
    final key = await _secureStorage.read(_signalIdentityPublicKey);
    return key != null && key.isNotEmpty;
  }

  /// Delete all identity data (dangerous!).
  Future<void> deleteIdentity() async {
    await _secureStorage.delete(_mnemonicKey);
    await _secureStorage.delete(_privateKeyKey);
    await _secureStorage.delete(_publicKeyKey);
    await _secureStorage.delete(_snowIdKey);
    await _secureStorage.delete(_signalIdentityPublicKey);
    await _secureStorage.delete(_signalIdentityPrivateKey);
    await _secureStorage.delete(_localBindingKey);
  }

  // --- Hex helpers ---

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final bytes = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
