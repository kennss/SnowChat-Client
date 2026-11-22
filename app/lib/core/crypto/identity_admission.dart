/// @file        identity_admission.dart
/// @description B-2 Identity Binding v1 — admission policy for remote Signal
///              identities. Decides, for a (snowId, deviceId, IK, Ed) tuple
///              presented by the server (send side) or by a PreKey message
///              (receive side), whether we may run X3DH with it:
///
///              Bound (binding present):
///                verifyBinding → epoch latch (>= highest accepted; equal only
///                for byte-identical keys) → account-key pin match → record
///                bound=true + latch. A key change of a bound peer (same
///                account) → non-blocking "device keys changed" notice.
///              Unbound (no binding): always refused — bindings are
///                mandatory. A latched snowId is refused as a downgrade, any
///                other as bindingRequired.
///
///              Pure policy over VerifiedIdentityStore — no network, no
///              session state — so it is unit-testable in isolation. Session
///              purging (§5.6) is done by SignalProtocolService using
///              [AdmittedIdentity.identityKey].
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-10
/// @lastUpdated 2026-11-21 (AdmittedIdentity is always a bound identity: {identityKey, ed25519}; promotionNotice → keyChangeNotice: only a bound → bound change gives a notice (no record carries unproven keys any more, so the legacy → bound promotion rules and interceptionSuspected are gone); admitBound reads the record without the legacy device hint). Earlier 2026-11-20 (admitUnbound → refuseUnbound(): an unbound peer is always refused — downgrade when latched, else bindingRequired; AppConfig.allowUnboundIdentity, the allowUnbound field and its test override are gone, and with them the legacy TOFU admission body). Earlier 2026-11-11 (admitUnbound refuses every unbound peer with bindingRequired unless AppConfig.allowUnboundIdentity — mandatory bindings for beta / self-hosted). Earlier 2026-11-10 (review fixes: M1 promotion compares only the IK against migrated Eds and treats a different legacy deviceId as reinstall evidence; M2 the blocked notice fires only on the transition; M4 admitDirectory() admits a device from the non-consuming directory BEFORE any one-time prekey is consumed)
///
/// @functions
///  - AdmittedIdentity: result of a successful admission
///  - RemoteDeviceIdentity / RemoteIdentityDirectory: server identity views
///  - IdentityAdmission.admitBound(): verify + record a bound identity
///  - IdentityAdmission.refuseUnbound(): the refusal for a peer without a binding
///  - IdentityAdmission.selectDevice(): pick the highest-epoch valid device
///  - IdentityAdmission.reject(): emit a rejection event and build the exception
///  - IdentityAdmission.keyChangeNotice(): notice for a bound peer's key change
///  - IdentityAdmission.admitDirectory(): non-consuming pre-admission from GET /keys/identity (M4)
library;

import 'dart:typed_data';

import 'identity_binding.dart';
import 'identity_binding_exception.dart';
import 'verified_identity_store.dart';

/// Outcome of a successful admission: the peer's account-signed identity.
/// Every session (active or archived) whose remote IK differs from
/// [identityKey] must be purged / refused (§5.6).
class AdmittedIdentity {
  final Uint8List identityKey;
  final Uint8List ed25519;

  const AdmittedIdentity({
    required this.identityKey,
    required this.ed25519,
  });
}

/// One device as returned by `GET /keys/identity/:snowId` or the prekey
/// bundle endpoints.
class RemoteDeviceIdentity {
  final String deviceId;
  final Uint8List identityKey;
  final Uint8List? ed25519;

  /// Parsed binding, or null when absent / unparseable.
  final IdentityBinding? binding;

  /// True when the server sent a binding object that failed to parse.
  final bool bindingUnparseable;

  /// Index into the server's original device list (bundle selection).
  final int index;

  const RemoteDeviceIdentity({
    required this.deviceId,
    required this.identityKey,
    required this.ed25519,
    required this.binding,
    required this.bindingUnparseable,
    required this.index,
  });
}

/// Non-consuming identity directory of one user.
class RemoteIdentityDirectory {
  final Uint8List? accountPublicKey;
  final List<RemoteDeviceIdentity> devices;

  const RemoteIdentityDirectory({
    required this.accountPublicKey,
    required this.devices,
  });

  RemoteDeviceIdentity? deviceById(String deviceId) {
    for (final d in devices) {
      if (d.deviceId == deviceId) return d;
    }
    return null;
  }
}

class IdentityAdmission {
  final VerifiedIdentityStore store;

  IdentityAdmission(this.store);

  /// Emit a rejection event and return the exception for the caller to throw.
  IdentityBindingInvalidException reject(
      String snowId, IdentityBindingFailure reason) {
    store.emit(IdentityStoreEvent(
      kind: IdentityEventKind.bindingRejected,
      peerSnowchatId: snowId,
      reason: reason,
    ));
    return IdentityBindingInvalidException(
        peerSnowchatId: snowId, reason: reason);
  }

  /// Pick the device to talk to. Among devices with a VALID binding, the
  /// highest epoch wins; others are ignored. When no device carries a
  /// binding, the first device is returned and the caller refuses it
  /// ([refuseUnbound]). When bindings are present but none verifies, the
  /// bundle is rejected — an honest server drops invalid bindings at upload,
  /// so this is tampering.
  RemoteDeviceIdentity? selectDevice({
    required String snowId,
    required Uint8List? accountPublicKey,
    required List<RemoteDeviceIdentity> devices,
  }) {
    if (devices.isEmpty) return null;
    RemoteDeviceIdentity? best;
    var anyBindingPresent = false;
    for (final d in devices) {
      if (d.binding == null && !d.bindingUnparseable) continue;
      anyBindingPresent = true;
      final b = d.binding;
      final ed = d.ed25519;
      if (b == null || ed == null || accountPublicKey == null) continue;
      final ok = IdentityBindingV1.verify(
        snowId: snowId,
        accountPublicKey: accountPublicKey,
        deviceId: d.deviceId,
        epoch: b.epoch,
        identityKey: d.identityKey,
        ed25519: ed,
        signature: b.signature,
      );
      if (!ok) continue;
      if (best == null || b.epoch > best.binding!.epoch) best = d;
    }
    if (best != null) return best;
    if (anyBindingPresent) {
      throw reject(snowId, IdentityBindingFailure.signatureInvalid);
    }
    return devices.first;
  }

  /// M4: admit a peer from the NON-consuming identity directory BEFORE any
  /// one-time prekey is fetched. Selects the device (highest valid epoch, or
  /// the first when nobody is bound), then runs [admitBound] for it — a
  /// device without a binding is refused ([refuseUnbound]). Throws the typed identity failures exactly like those; returns
  /// null when the directory lists no usable device.
  Future<({RemoteDeviceIdentity device, AdmittedIdentity admitted})?>
      admitDirectory({
    required String snowId,
    required RemoteIdentityDirectory directory,
  }) async {
    final account = directory.accountPublicKey ??
        (await store.get(snowId))?.accountPublicKey;
    final pick = selectDevice(
      snowId: snowId,
      accountPublicKey: account,
      devices: directory.devices,
    );
    if (pick == null) return null;
    final b = pick.binding;
    final ed = pick.ed25519;
    final AdmittedIdentity admitted;
    if (b != null && ed != null && account != null) {
      admitted = await admitBound(
        snowId: snowId,
        deviceId: pick.deviceId,
        identityKey: pick.identityKey,
        ed25519: ed,
        accountPublicKey: account,
        epoch: b.epoch,
        signature: b.signature,
      );
    } else {
      throw await refuseUnbound(snowId);
    }
    return (device: pick, admitted: admitted);
  }

  /// Verify and record a bound identity. Throws
  /// [IdentityBindingInvalidException] on any failure (event emitted).
  Future<AdmittedIdentity> admitBound({
    required String snowId,
    required String deviceId,
    required Uint8List identityKey,
    required Uint8List ed25519,
    required Uint8List accountPublicKey,
    required int epoch,
    required Uint8List signature,
  }) async {
    final ok = IdentityBindingV1.verify(
      snowId: snowId,
      accountPublicKey: accountPublicKey,
      deviceId: deviceId,
      epoch: epoch,
      identityKey: identityKey,
      ed25519: ed25519,
      signature: signature,
    );
    if (!ok) throw reject(snowId, IdentityBindingFailure.signatureInvalid);

    // Fresh reads: admission decisions must not act on a record / latch that
    // another isolate (VoIP background) has since changed.
    final existing = await store.getFresh(snowId);
    final latch = await store.latchedEpoch(snowId, fresh: true);

    if (existing?.accountPublicKey != null &&
        !constantTimeEquals(existing!.accountPublicKey, accountPublicKey)) {
      throw reject(snowId, IdentityBindingFailure.accountKeyMismatch);
    }

    final sameKeysAsBound = existing != null &&
        existing.bound &&
        existing.deviceId == deviceId &&
        constantTimeEquals(existing.identityKey, identityKey) &&
        constantTimeEquals(existing.ed25519, ed25519);

    // Exactly the keys we already trust (an older or equal epoch for the same
    // device/IK/Ed — e.g. a persistent PreKey message minted before a re-sign):
    // nothing can be replayed, accept without touching the store.
    if (sameKeysAsBound && (existing.epoch ?? -1) >= epoch) {
      return AdmittedIdentity(identityKey: identityKey, ed25519: ed25519);
    }

    if (latch != null) {
      if (epoch < latch) {
        // An older binding for DIFFERENT keys: replay of a superseded identity.
        throw reject(snowId, IdentityBindingFailure.epochRegression);
      }
      if (epoch == latch && existing != null && existing.bound &&
          !sameKeysAsBound) {
        // Same epoch can only legitimately re-appear for the exact same keys.
        throw reject(snowId, IdentityBindingFailure.epochRegression);
      }
    }

    // A bound peer's key change (same account — checked above).
    if (existing != null &&
        keyChangeNotice(
          existing: existing,
          deviceId: deviceId,
          identityKey: identityKey,
          ed25519: ed25519,
        )) {
      store.emit(IdentityStoreEvent(
        kind: IdentityEventKind.deviceKeysChanged,
        peerSnowchatId: snowId,
      ));
    }

    await store.put(VerifiedIdentityRecord(
      snowId: snowId,
      accountPublicKey: accountPublicKey,
      deviceId: deviceId,
      epoch: epoch,
      identityKey: identityKey,
      ed25519: ed25519,
      bindingSignature: signature,
      bound: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await store.raiseLatch(snowId, epoch);

    return AdmittedIdentity(identityKey: identityKey, ed25519: ed25519);
  }

  /// Whether moving from [existing] to the bound (deviceId, IK, Ed) is a
  /// key change worth a non-blocking "device keys changed" notice: a BOUND
  /// record whose device or keys differ. A record that only pins the account
  /// key (invite link, verify screen) holds no keys — first keys are no
  /// change.
  static bool keyChangeNotice({
    required VerifiedIdentityRecord existing,
    required String deviceId,
    required Uint8List identityKey,
    required Uint8List ed25519,
  }) {
    if (!existing.bound) return false;
    return existing.deviceId != deviceId ||
        !constantTimeEquals(existing.identityKey, identityKey) ||
        !constantTimeEquals(existing.ed25519, ed25519);
  }

  /// The refusal for a peer that presented NO binding (send side: no binding
  /// in the bundle / directory; receive side: none embedded and none the
  /// directory holds). Bindings are mandatory: without this, a compromised
  /// server could strip the binding of a peer we have never seen bound and
  /// get its own keys accepted. A peer this device has seen bound (latched)
  /// is refused as a [IdentityBindingFailure.downgrade], any other as
  /// [IdentityBindingFailure.bindingRequired]. Returns the exception for the
  /// caller to throw (the event is emitted).
  Future<IdentityBindingInvalidException> refuseUnbound(String snowId) async {
    final latched = await store.latchedEpoch(snowId, fresh: true) != null;
    return reject(
      snowId,
      latched
          ? IdentityBindingFailure.downgrade
          : IdentityBindingFailure.bindingRequired,
    );
  }
}
