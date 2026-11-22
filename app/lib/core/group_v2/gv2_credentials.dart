/// @file        gv2_credentials.dart
/// @description Group protocol v2 — what lets this device act in a group
///              without logging in. Once every few days it fetches, WITH its
///              login, a week of auth credentials ("some account the server
///              knows"); from then on a group request carries a presentation
///              made from the day's credential and the group's master key,
///              which shows the server one member ciphertext of that group
///              and nothing else. Sending is authorized by a send token built
///              from the server's per-member endorsements, which this device
///              accepts only when they verify against ITS OWN view of the
///              members (design document §6).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (the server keys are the ones this build trusts — gv2_trusted_keys.dart; what the server publishes is only compared with them, serverKeysDiffer. A clock behind the server presents tomorrow's credential when today's is not held). Earlier 2026-11-13
///
/// @functions
///  - Gv2Credentials.serverKeys(): the server keys this build trusts, stored
///    with the credentials issued under them
///  - Gv2Credentials.comparePublishedKeys() / serverKeysDiffer /
///    serverKeysDifferChanges: whether the server publishes other keys
///  - Gv2Credentials.dispose()
///  - Gv2Credentials.presentation(masterKey): presentation for one group
///  - Gv2Credentials.renew(): fetch credentials again now (after the server
///    refused a presentation)
///  - Gv2Credentials.refreshEndorsements(groupId): fetch, verify and store
///    the endorsements of a group's members — Gv2EndorsementOutcome
///  - Gv2Credentials.sendToken(groupId, recipients): token for a subset of
///    the members, or null when endorsements are missing or about to expire
///  - gv2AccountIdOfSnowId(): the 16 bytes behind a snowId
///  - Gv2CredentialException: the server issued nothing usable
///
/// Notes:
///  - Times are epoch SECONDS here (zkgroup's unit). A credential is for one
///    UTC day; the server accepts a presentation from one day before to two
///    days after it, so a device clock that is off by hours still works.
///  - The credential fetch is the only request with a login and it names no
///    group: the server learns "this account uses groups on these days".
///  - The server keys are the build's (gv2_trusted_keys.dart), never the
///    server's word: a server that issues or signs under other keys gets
///    nothing verified, so groups stop rather than run under keys only this
///    account was given. What GET /zk/params publishes is compared with them
///    once per run (and on credentials that do not verify) only to tell the
///    user why ([serverKeysDiffer]). A build that trusts other keys than the
///    stored ones (a release that changed them) stores its own, and the
///    store erases every credential and endorsement issued under the old
///    ones. A group's title still commits to the keys it was created under
///    (Gv2Sync.titleMatchesServerKeys).
///  - Endorsement verification costs about 0.1 ms per member and decrypting a
///    member ciphertext about 0.3 ms on a phone; for 256 members or more both
///    run in a worker isolate.
///  - Nothing here logs. Credentials, presentations, endorsements and tokens
///    never appear in an exception.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:snowchat_zkgroup/snowchat_zkgroup.dart';

import '../crypto/identity_binding.dart';
import '../storage/database.dart';
import 'gv2_codec.dart';
import 'gv2_store.dart';
import 'gv2_transport.dart';
import 'gv2_trusted_keys.dart';

const int _daySeconds = 86400;

/// Members from which the zkgroup work moves to a worker isolate.
const int gv2EndorsementIsolateThreshold = 256;

/// A token is not built from endorsements that expire within this margin:
/// the request must still verify when it reaches the server.
const int _tokenMarginSeconds = 600;

/// Stored credentials are topped up when fewer than this many days remain.
const int _refillDays = 2;

/// A failed top-up is not repeated more often than this.
const int _refillRetrySeconds = 3600;

/// A look at the server's published keys that got no answer is repeated no
/// sooner than this.
const int _publishedRetrySeconds = 60;

/// The server did not issue a credential this device can use.
class Gv2CredentialException implements Exception {
  final String reason;
  const Gv2CredentialException(this.reason);

  @override
  String toString() => 'Gv2CredentialException: $reason';
}

/// How [Gv2Credentials.refreshEndorsements] ended.
enum Gv2EndorsementOutcome {
  /// Verified against this device's members and stored.
  stored,

  /// The server is at another revision than this device, or the group moved
  /// while the request was under way: sync the log first, then ask again.
  revisionDiffers,

  /// Same revision, but the endorsements do not verify for the members this
  /// device holds: the server's list of members differs from the verified
  /// one. Never a reason to accept the server's list.
  rosterMismatch,

  /// A member's ciphertext does not decrypt to an account id, so this
  /// device cannot name the members the way zkgroup needs.
  rosterUnusable,
}

/// A send token and the time it stops verifying.
class Gv2SendToken {
  final Uint8List token;
  final int expiration;
  const Gv2SendToken(this.token, this.expiration);
}

/// The 16-byte account id behind [snowId] ("snow" + 32 hex).
Uint8List gv2AccountIdOfSnowId(String snowId) {
  if (!IdentityBindingV1.isValidSnowId(snowId)) {
    throw ArgumentError('gv2 credentials: snowId format');
  }
  return gv2Unhex(snowId.substring(4));
}

class Gv2Credentials {
  final Gv2Store _store;
  final Gv2Transport _transport;
  final Future<String?> Function() _snowId;
  final int Function() _now;
  final int _isolateThreshold;
  final Gv2TrustedServerKeys _trusted;

  Future<void>? _publishedInFlight;
  Future<void>? _fetchInFlight;

  /// Local seconds of the last look at the published keys, and of the last
  /// one that got an answer (null before the first).
  int _publishedTriedAt = -_publishedRetrySeconds;
  int? _publishedSeenAt;
  bool _serverKeysDiffer = false;
  final StreamController<bool> _differChanges = StreamController.broadcast();
  int _lastRefillAttempt = 0;

  /// When today's credential was last fetched because it was missing (a
  /// clock behind the server's keeps missing it), local seconds.
  int _lastTodayFetch = -_refillRetrySeconds;

  /// [snowId] returns this device's account; [trustedKeys] are the server
  /// keys this build trusts; [nowSeconds] is the clock (epoch seconds),
  /// replaceable in tests. [isolateThreshold] is the number of members from
  /// which endorsements are verified in a worker isolate.
  Gv2Credentials({
    required Gv2Store store,
    required Gv2Transport transport,
    required Future<String?> Function() snowId,
    required Gv2TrustedServerKeys trustedKeys,
    int Function()? nowSeconds,
    int isolateThreshold = gv2EndorsementIsolateThreshold,
  })  : _store = store,
        _transport = transport,
        _snowId = snowId,
        _trusted = trustedKeys,
        _isolateThreshold = isolateThreshold,
        _now = nowSeconds ??
            (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  // ---------------------------------------------------------------------------
  // Server keys
  // ---------------------------------------------------------------------------

  /// The server keys this build trusts, as stored with the credentials
  /// issued under them. On first use — or when this build trusts other keys
  /// than the stored ones — the build's keys are stored, and the store erases
  /// the credentials and endorsements issued under the old ones. Also starts
  /// the look at what the server publishes when one is due (not awaited).
  Future<Gv2ServerKeysRow> serverKeys() async {
    _lookAtPublishedWhenDue();
    final stored = await _store.serverKeys();
    if (stored != null &&
        _sameBytes(stored.serverPublicParams, _trusted.serverPublicParams) &&
        _sameBytes(stored.headPublicKey, _trusted.headPublicKey)) {
      return stored;
    }
    await _store.saveServerKeys(
      serverPublicParams: _trusted.serverPublicParams,
      headPublicKey: _trusted.headPublicKey,
    );
    return (await _store.serverKeys())!;
  }

  /// Whether the server, when last asked, published other keys than the
  /// ones this build trusts.
  bool get serverKeysDiffer => _serverKeysDiffer;

  /// [serverKeysDiffer] each time it changes.
  Stream<bool> get serverKeysDifferChanges => _differChanges.stream;

  /// Once per run after an answer; again a minute after a look that got
  /// none; hourly while the keys differ (to see the server fixed).
  void _lookAtPublishedWhenDue() {
    final now = _now();
    final seen = _publishedSeenAt;
    final due = seen == null
        ? now - _publishedTriedAt >= _publishedRetrySeconds
        : _serverKeysDiffer && now - seen >= _refillRetrySeconds;
    if (due) unawaited(comparePublishedKeys());
  }

  /// Compare what the server publishes (GET /zk/params) with the keys this
  /// build trusts and record it in [serverKeysDiffer]. Concurrent callers
  /// share one request. Never throws: without an answer nothing is learned,
  /// and the trusted keys are used all the same.
  Future<void> comparePublishedKeys() {
    final running = _publishedInFlight;
    if (running != null) return running;
    final future = () async {
      _publishedTriedAt = _now();
      final Gv2ServerKeysResponse published;
      try {
        published = await _transport.fetchServerKeys();
      } on Gv2NetworkException {
        return;
      } on Gv2ApiException {
        return;
      } on Gv2ProtocolException {
        return;
      }
      _publishedSeenAt = _now();
      final differ =
          !_sameBytes(published.serverPublicParams, _trusted.serverPublicParams) ||
          !_sameBytes(published.headPublicKey, _trusted.headPublicKey);
      if (differ != _serverKeysDiffer) {
        _serverKeysDiffer = differ;
        if (!_differChanges.isClosed) _differChanges.add(differ);
      }
    }();
    _publishedInFlight = future;
    return future.whenComplete(() => _publishedInFlight = null);
  }

  void dispose() {
    unawaited(_differChanges.close());
  }

  // ---------------------------------------------------------------------------
  // Credentials and presentations
  // ---------------------------------------------------------------------------

  /// A presentation for the group behind [masterKey]: the value of the
  /// `Authorization: SnowZk` header of a group request. Fetches credentials
  /// first when today's is missing.
  Future<Uint8List> presentation(Uint8List masterKey) async {
    final credential = await _credentialForToday();
    final keys = await serverKeys();
    try {
      return ZkGroup.presentAuthCredential(
        serverPublicParams: keys.serverPublicParams,
        masterKey: masterKey,
        credential: credential,
      );
    } on ZkGroupException {
      throw const Gv2CredentialException('presentation could not be made');
    }
  }

  /// Fetch credentials again now. For the caller that got
  /// `presentation_invalid` from the server: the stored credential may be
  /// one the server no longer takes.
  Future<void> renew() async {
    final snowId = await _account();
    final now = _now();
    await _fetchCredentials(snowId, now - now % _daySeconds);
  }

  Future<String> _account() async {
    final snowId = await _snowId();
    if (snowId == null) {
      throw StateError('gv2 credentials: no identity on this device');
    }
    return snowId;
  }

  /// Today's credential by this device's clock. When today's is missing it
  /// is fetched; when the server still issues none for today, tomorrow's is
  /// used: the server issues credentials from ITS today on and accepts a
  /// presentation from one day before its redemption time (libsignal), so a
  /// clock that runs behind the server's — by minutes around midnight, or by
  /// up to a day — presents tomorrow's, which the server takes. Such a clock
  /// does not fetch again for every request ([_refillRetrySeconds]). A clock
  /// further behind has nothing the server would take.
  Future<Uint8List> _credentialForToday() async {
    final snowId = await _account();
    final now = _now();
    final today = now - now % _daySeconds;
    Future<Gv2AuthCredentialRow?> tomorrow() =>
        _store.authCredential(snowId, today + _daySeconds);

    var row = await _store.authCredential(snowId, today);
    if (row == null) {
      final ahead = await tomorrow();
      if (ahead != null && now - _lastTodayFetch < _refillRetrySeconds) {
        return ahead.credential;
      }
      _lastTodayFetch = now;
      await _fetchCredentials(snowId, today);
      row = await _store.authCredential(snowId, today) ?? await tomorrow();
      if (row == null) {
        throw const Gv2CredentialException('no credential for today');
      }
      return row.credential;
    }

    // Top up before the stock runs out. Today's credential is in hand, so a
    // failure here is not an error; it is tried again later.
    final last = await _store.lastAuthCredentialTime(snowId) ?? today;
    if (last < today + _refillDays * _daySeconds &&
        now - _lastRefillAttempt >= _refillRetrySeconds) {
      _lastRefillAttempt = now;
      try {
        await _fetchCredentials(snowId, today);
      } on Gv2NetworkException {
        // Offline: keep going with what is stored.
      } on Gv2ApiException {
        // Rate limited or server trouble: likewise.
      } on Gv2CredentialException {
        // Nothing usable came back: likewise.
      }
    }
    return row.credential;
  }

  /// Fetch credentials and store the ones that verify (concurrent callers
  /// share one request).
  Future<void> _fetchCredentials(String snowId, int today) {
    final running = _fetchInFlight;
    if (running != null) return running;
    final future = _fetchCredentialsOnce(snowId, today);
    _fetchInFlight = future;
    return future.whenComplete(() => _fetchInFlight = null);
  }

  Future<void> _fetchCredentialsOnce(String snowId, int today) async {
    final issued = await _transport.fetchCredentials();
    final accountId = gv2AccountIdOfSnowId(snowId);

    Map<int, Uint8List>? receive(Uint8List serverPublicParams) {
      final out = <int, Uint8List>{};
      for (final e in issued.responses.entries) {
        // Only whole days from today on are of any use.
        if (e.key % _daySeconds != 0 || e.key < today) continue;
        try {
          out[e.key] = ZkGroup.receiveAuthCredential(
            serverPublicParams: serverPublicParams,
            accountId: accountId,
            salt: issued.salt,
            redemptionTime: e.key,
            response: e.value,
          );
        } on ZkGroupException {
          return null;
        }
      }
      return out;
    }

    // serverKeys() first: the stored keys must be the trusted ones before
    // credentials issued under them are stored (replacing the keys erases
    // the credentials).
    final received = receive((await serverKeys()).serverPublicParams);
    if (received == null) {
      // Not issued under the keys this build trusts. Whatever the server now
      // publishes, they are not taken; the look only tells the user why —
      // the one under way, or one if this run has had no answer yet.
      final running = _publishedInFlight;
      if (running != null) {
        await running;
      } else if (_publishedSeenAt == null) {
        await comparePublishedKeys();
      }
      throw const Gv2CredentialException('credentials do not verify');
    }
    if (received.isEmpty) {
      throw const Gv2CredentialException('no credential for today or later');
    }
    await _store.saveAuthCredentials(snowId, received, pruneBefore: today);
  }

  // ---------------------------------------------------------------------------
  // Endorsements and send tokens
  // ---------------------------------------------------------------------------

  /// Fetch the server's endorsements for [groupId] (lowercase hex), verify
  /// them against the members this device holds and store them.
  Future<Gv2EndorsementOutcome> refreshEndorsements(String groupId) async {
    final group = await _store.group(groupId);
    if (group == null || !group.stateLoaded) {
      throw StateError('gv2 credentials: group state not loaded');
    }
    final members = await _store.memberRows(groupId);
    final keys = await serverKeys();

    final response = await _transport.endorsements(
      groupId: gv2Unhex(groupId),
      presentation: await presentation(group.masterKey),
    );
    if (response.revision != group.revision) {
      return Gv2EndorsementOutcome.revisionDiffers;
    }

    final request = _ReceiveRequest(
      serverPublicParams: keys.serverPublicParams,
      masterKey: group.masterKey,
      response: response.response,
      now: _now(),
      ciphertexts: [for (final m in members) gv2Unhex(m.ciphertext)],
      knownAccountIds: [
        for (final m in members)
          m.snowId == null ? null : gv2AccountIdOfSnowId(m.snowId!),
      ],
    );
    final result = members.length >= _isolateThreshold
        ? await _receiveInIsolate(request)
        : _receive(request);
    if (result.outcome != Gv2EndorsementOutcome.stored) return result.outcome;

    try {
      await _store.replaceEndorsements(
        groupId: groupId,
        revision: group.revision,
        expiration: result.expiration,
        byCiphertext: {
          for (var i = 0; i < members.length; i++)
            members[i].ciphertext: result.endorsements[i],
        },
      );
    } on Gv2StoreConflict {
      // The group advanced while the request was under way.
      return Gv2EndorsementOutcome.revisionDiffers;
    }
    return Gv2EndorsementOutcome.stored;
  }

  /// A send token for exactly [recipients] (member ciphertexts, lowercase
  /// hex; the sender includes its own). Null when an endorsement is missing
  /// or about to expire — call [refreshEndorsements] and ask again.
  Future<Gv2SendToken?> sendToken(String groupId, List<String> recipients) async {
    if (recipients.isEmpty || recipients.toSet().length != recipients.length) {
      throw ArgumentError('gv2 credentials: recipients must be distinct and not empty');
    }
    final group = await _store.group(groupId);
    if (group == null) throw StateError('gv2 credentials: unknown group');

    final stored = {
      for (final e in await _store.endorsements(groupId)) e.ciphertext: e,
    };
    final chosen = <Uint8List>[];
    int? expiration;
    for (final ciphertext in recipients) {
      final row = stored[ciphertext];
      if (row == null) return null;
      // All endorsements of one response share one expiration.
      if (expiration != null && row.expiration != expiration) return null;
      expiration = row.expiration;
      chosen.add(row.endorsement);
    }
    if (expiration! - _now() < _tokenMarginSeconds) return null;
    try {
      return Gv2SendToken(
        ZkGroup.sendToken(
          masterKey: group.masterKey,
          endorsements: chosen,
          expiration: expiration,
        ),
        expiration,
      );
    } on ZkGroupException {
      // Stored endorsements that no longer combine: fetch new ones.
      return null;
    }
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Everything [_receive] needs, sendable to a worker isolate.
class _ReceiveRequest {
  final Uint8List serverPublicParams;
  final Uint8List masterKey;
  final Uint8List response;
  final int now;

  /// Member ciphertexts, and for each the account id when it is already
  /// known (null = decrypt it).
  final List<Uint8List> ciphertexts;
  final List<Uint8List?> knownAccountIds;

  const _ReceiveRequest({
    required this.serverPublicParams,
    required this.masterKey,
    required this.response,
    required this.now,
    required this.ciphertexts,
    required this.knownAccountIds,
  });
}

class _ReceiveResult {
  final Gv2EndorsementOutcome outcome;
  final int expiration;

  /// One per ciphertext of the request, in the same order.
  final List<Uint8List> endorsements;

  const _ReceiveResult(this.outcome, [this.expiration = 0, this.endorsements = const []]);
}

/// A top-level function on purpose: the closure sent to the isolate then
/// holds the request and nothing else of the caller (no store, no client).
Future<_ReceiveResult> _receiveInIsolate(_ReceiveRequest request) =>
    Isolate.run(() => _receive(request));

/// Name the members by account id and verify the server's response for
/// exactly them. Pure: safe to run in any isolate.
_ReceiveResult _receive(_ReceiveRequest request) {
  final accountIds = <Uint8List>[];
  for (var i = 0; i < request.ciphertexts.length; i++) {
    final known = request.knownAccountIds[i];
    if (known != null) {
      accountIds.add(known);
      continue;
    }
    try {
      accountIds.add(ZkGroup.decryptMember(
        masterKey: request.masterKey,
        ciphertext: request.ciphertexts[i],
      ));
    } on ZkGroupException {
      return const _ReceiveResult(Gv2EndorsementOutcome.rosterUnusable);
    }
  }
  try {
    final verified = ZkGroup.receiveEndorsements(
      serverPublicParams: request.serverPublicParams,
      masterKey: request.masterKey,
      response: request.response,
      members: accountIds,
      now: request.now,
    );
    return _ReceiveResult(
      Gv2EndorsementOutcome.stored,
      verified.expiration,
      [for (final e in verified.endorsements) Uint8List.fromList(e)],
    );
  } on ZkGroupException {
    return const _ReceiveResult(Gv2EndorsementOutcome.rosterMismatch);
  }
}
