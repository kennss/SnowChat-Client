/// @file        gv2_transport.dart
/// @description Group protocol v2 — the HTTP calls of the group protocol.
///              Group requests carry NO login: the caller is known to the
///              server only as "a member ciphertext of this group" (a zkgroup
///              presentation in the Authorization header) or as "someone
///              holding a send token for these recipients". So this is a
///              separate client from ApiClient, which attaches the account's
///              bearer token to every request: a bearer on a group request
///              would tell the server which account acts in which group
///              (design document §6.2, §10.2, §11.1).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-22 (SC-18: send() takes no noPush — it named the sender of every group message). Earlier 2026-11-21 (P5.6: integers that are hashed or signed are range-checked — revisions u32, a snapshot's joined / pending revisions no later than the snapshot, the version a u8). Earlier 2026-11-13
///
/// @functions
///  - Gv2Transport.fetchServerKeys(): GET /zk/params (no login)
///  - Gv2Transport.fetchCredentials(): POST /zk/credentials (the ONE call with
///    a login; it names no group)
///  - Gv2Transport.create() / change(): submit a change-log entry
///  - Gv2Transport.log() / snapshot(): read the change log and a state
///  - Gv2Transport.endorsements(): the server's send endorsements
///  - Gv2Transport.send() / names(): authorized by a send token alone
///  - Gv2ApiException / Gv2NetworkException / Gv2ProtocolException
///  - Gv2ServerKeysResponse, Gv2IssuedCredentials, Gv2Head, Gv2LogPage,
///    Gv2Snapshot, Gv2EndorsementsResponse, Gv2SendEntry, Gv2SendResult,
///    Gv2DeletedRecipient: request and response values (bytes, not base64)
///
/// Notes:
///  - Nothing here logs: not a path, not a status, not a body. The
///    Authorization header of a group request is a credential that stays
///    valid for about three days.
///  - Every group request is a POST with the group id in the BODY, so that no
///    proxy access log pairs a client address with a group id.
///  - The anonymous calls use their own Dio instance, hence their own
///    connections: a group request never travels on a connection that also
///    carried this account's bearer token. (The server still sees the same
///    network address; hiding that is out of scope — design §13.)
///  - The server is not trusted. Every response field is checked for type and
///    length before it is used; anything else is a Gv2ProtocolException. The
///    group id of a result is the one the caller asked for, never one the
///    server returned.
///  - Times: redemptionTime and expiration are epoch SECONDS; a deletion
///    proof's deletedAtMs is epoch milliseconds.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../crypto/account_deletion_proof.dart';
import '../network/api_endpoints.dart';
import 'gv2_codec.dart';

/// The server answered with an error. [code] is its machine-readable reason
/// (for example `revision_conflict`, `entry_rejected`, `not_a_member`,
/// `presentation_invalid`, `rate_limited`).
class Gv2ApiException implements Exception {
  final int status;
  final String code;

  /// With `revision_conflict`: the head the server is at.
  final Gv2Head? head;

  /// With `entry_rejected`: the state machine's reject code on the server.
  final String? reason;

  const Gv2ApiException(this.status, this.code, {this.head, this.reason});

  @override
  String toString() => 'Gv2ApiException($status, $code)';
}

/// The request did not get an answer (no connection, timeout).
class Gv2NetworkException implements Exception {
  const Gv2NetworkException();

  @override
  String toString() => 'Gv2NetworkException';
}

/// The server answered with something that is not a well-formed response.
class Gv2ProtocolException implements Exception {
  final String what;
  const Gv2ProtocolException(this.what);

  @override
  String toString() => 'Gv2ProtocolException: $what';
}

class Gv2ServerKeysResponse {
  final Uint8List serverPublicParams;
  final Uint8List headPublicKey;
  const Gv2ServerKeysResponse({
    required this.serverPublicParams,
    required this.headPublicKey,
  });
}

class Gv2IssuedCredentials {
  /// The account's salt; needed to verify the responses.
  final Uint8List salt;

  /// redemptionTime (epoch seconds) → the server's response for that day.
  final Map<int, Uint8List> responses;
  const Gv2IssuedCredentials({required this.salt, required this.responses});
}

/// A point of a group's log as the server signed it.
class Gv2Head {
  final int revision;
  final Uint8List chain;
  final Uint8List headSig;
  const Gv2Head({
    required this.revision,
    required this.chain,
    required this.headSig,
  });
}

class Gv2LogEntry {
  final int revision;

  /// The encoded entry (gv2DecodeEntry).
  final Uint8List entry;

  /// The server's signature over the head after this entry.
  final Uint8List headSig;
  const Gv2LogEntry({
    required this.revision,
    required this.entry,
    required this.headSig,
  });
}

class Gv2LogPage {
  /// The server's current head; null for a caller that was removed (it is
  /// not told what happened afterwards).
  final Gv2Head? head;

  /// The caller is no longer a member; [entries] end with its removal.
  final bool removed;
  final List<Gv2LogEntry> entries;

  /// More entries follow; ask again from the next revision.
  final bool more;
  const Gv2LogPage({
    required this.head,
    required this.removed,
    required this.entries,
    required this.more,
  });
}

class Gv2Snapshot {
  /// The state the server claims for the revision asked for. UNVERIFIED: the
  /// caller checks its hash against the anchor it trusts.
  final Gv2GroupState state;
  final Uint8List headSig;
  const Gv2Snapshot({required this.state, required this.headSig});
}

class Gv2EndorsementsResponse {
  /// The revision whose members the endorsements cover.
  final int revision;
  final int expiration;
  final Uint8List response;
  const Gv2EndorsementsResponse({
    required this.revision,
    required this.expiration,
    required this.response,
  });
}

/// One envelope for a set of recipients.
class Gv2SendEntry {
  final Uint8List token;

  /// 16-byte account ids.
  final List<Uint8List> recipients;
  final Uint8List envelope;

  /// A control message: no push, not counted in the badge.
  final bool silent;

  /// Seconds until the server drops undelivered copies; null = keep.
  final int? expiresIn;
  const Gv2SendEntry({
    required this.token,
    required this.recipients,
    required this.envelope,
    this.silent = false,
    this.expiresIn,
  });
}

/// A recipient whose account was deleted, with that account's own proof.
/// UNVERIFIED: judge it with gv2JudgeDeletion against the member's confirmed
/// account key ([accountPublicKey] here is only what the server claims).
class Gv2DeletedRecipient {
  final Uint8List accountId;
  final Uint8List accountPublicKey;
  final AccountDeletionProof proof;
  const Gv2DeletedRecipient({
    required this.accountId,
    required this.accountPublicKey,
    required this.proof,
  });
}

class Gv2SendResult {
  /// False when the server refused the whole entry ([error] says why).
  final bool ok;
  final String? error;

  /// Rows the server created.
  final int delivered;

  /// Recipients with no account behind them (16-byte account ids).
  final List<Uint8List> unknownRecipients;

  /// Recipients over their inflow budget; nothing was queued for them.
  final int throttledRecipients;
  final List<Gv2DeletedRecipient> deleted;
  const Gv2SendResult({
    required this.ok,
    required this.error,
    required this.delivered,
    required this.unknownRecipients,
    required this.throttledRecipients,
    required this.deleted,
  });
}

/// POST with the account's bearer token, returning the decoded JSON body.
/// The app passes ApiClient here; it is used for /zk/credentials only.
typedef Gv2AuthenticatedPost = Future<Object?> Function(String path);

const int _accountIdLen = 16;

class Gv2Transport {
  final Dio _anonymous;
  final Gv2AuthenticatedPost _authenticatedPost;

  Gv2Transport({
    required Gv2AuthenticatedPost authenticatedPost,
    String? baseUrl,
  })  : _authenticatedPost = authenticatedPost,
        _anonymous = Dio(BaseOptions(
          baseUrl: baseUrl ?? ApiEndpoints.getBaseUrl(),
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: const {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          // Statuses are handled here; an error status is not an exception.
          validateStatus: (_) => true,
        ));

  /// Release the connections of the anonymous client.
  void close() => _anonymous.close(force: true);

  // ---------------------------------------------------------------------------
  // Server keys and credentials
  // ---------------------------------------------------------------------------

  Future<Gv2ServerKeysResponse> fetchServerKeys() async {
    final body = await _call('GET', '/zk/params');
    return Gv2ServerKeysResponse(
      serverPublicParams: _bytes(body, 'serverPublicParams'),
      headPublicKey: _bytes(body, 'logVerifyKey', length: gv2PublicKeyLen),
    );
  }

  /// Seven days of auth credentials for this account. The only call that
  /// carries the account's login; it says nothing about any group.
  Future<Gv2IssuedCredentials> fetchCredentials() async {
    final Object? raw;
    try {
      raw = await _authenticatedPost('/zk/credentials');
    } on DioException catch (e) {
      throw _fromDio(e);
    }
    final body = _map(raw, 'credentials response');
    final list = body['credentials'];
    if (list is! List || list.isEmpty || list.length > 31) {
      throw const Gv2ProtocolException('credentials');
    }
    final responses = <int, Uint8List>{};
    for (final item in list) {
      final entry = _map(item, 'credential');
      responses[_int(entry, 'redemptionTime')] = _bytes(entry, 'response');
    }
    if (responses.length != list.length) {
      throw const Gv2ProtocolException('duplicate redemptionTime');
    }
    return Gv2IssuedCredentials(salt: _bytes(body, 'salt'), responses: responses);
  }

  // ---------------------------------------------------------------------------
  // Group state (presentation)
  // ---------------------------------------------------------------------------

  /// Create a group: its public parameters and the revision-0 entry. The
  /// group id is derived by the caller from the master key; the one the
  /// server returns must be the same.
  Future<Gv2Head> create({
    required Uint8List groupId,
    required Uint8List publicParams,
    required Uint8List presentation,
    required Uint8List entry,
  }) async {
    final body = await _call(
      'POST',
      '/gv2/create',
      presentation: presentation,
      data: {'publicParams': base64Encode(publicParams), 'entry': base64Encode(entry)},
    );
    if (!_equal(_bytes(body, 'groupId', length: gv2GroupIdLen), groupId)) {
      throw const Gv2ProtocolException('group id differs from the master key\'s');
    }
    return _head(body);
  }

  /// Submit one entry. A `revision_conflict` error carries the server's head.
  Future<Gv2Head> change({
    required Uint8List groupId,
    required Uint8List presentation,
    required Uint8List entry,
  }) async {
    final body = await _call(
      'POST',
      '/gv2/change',
      presentation: presentation,
      data: {'groupId': base64Encode(groupId), 'entry': base64Encode(entry)},
    );
    return _head(body);
  }

  /// Entries from revision [from] on, as far as the caller may read.
  Future<Gv2LogPage> log({
    required Uint8List groupId,
    required Uint8List presentation,
    required int from,
    int? limit,
  }) async {
    final body = await _call(
      'POST',
      '/gv2/log',
      presentation: presentation,
      data: {
        'groupId': base64Encode(groupId),
        'from': from,
        'limit': ?limit,
      },
    );
    final list = body['entries'];
    if (list is! List) throw const Gv2ProtocolException('entries');
    final entries = <Gv2LogEntry>[];
    for (final item in list) {
      final e = _map(item, 'entry');
      entries.add(Gv2LogEntry(
        revision: _u32(e, 'revision'),
        entry: _bytes(e, 'entry'),
        headSig: _bytes(e, 'headSig', length: gv2SignatureLen),
      ));
    }
    for (var i = 0; i < entries.length; i++) {
      // Consecutive, starting no earlier than asked.
      if (entries[i].revision < from ||
          (i > 0 && entries[i].revision != entries[i - 1].revision + 1)) {
        throw const Gv2ProtocolException('entries out of order');
      }
    }
    final head = body['head'];
    return Gv2LogPage(
      head: head == null ? null : _head(_map(head, 'head')),
      removed: _bool(body, 'removed'),
      entries: entries,
      more: _bool(body, 'more'),
    );
  }

  /// The state at revision [at], as the server claims it.
  Future<Gv2Snapshot> snapshot({
    required Uint8List groupId,
    required Uint8List presentation,
    required int at,
  }) async {
    final body = await _call(
      'POST',
      '/gv2/snapshot',
      presentation: presentation,
      data: {'groupId': base64Encode(groupId), 'at': at},
    );
    if (_int(body, 'revision') != at) {
      throw const Gv2ProtocolException('snapshot of another revision');
    }
    final membersRaw = body['members'];
    final pendingRaw = body['pending'];
    if (membersRaw is! List ||
        pendingRaw is! List ||
        membersRaw.length + pendingRaw.length > gv2MaxGroupSize) {
      throw const Gv2ProtocolException('members');
    }
    final members = SplayTreeMap<String, Gv2MemberState>();
    for (final item in membersRaw) {
      final m = _map(item, 'member');
      final role = _int(m, 'role');
      if (role > gv2RoleOwner) throw const Gv2ProtocolException('role');
      final payload = _bytes(m, 'memberPayload');
      if (payload.length > gv2MaxMemberPayload) {
        throw const Gv2ProtocolException('memberPayload');
      }
      members[gv2Hex(_bytes(m, 'ciphertext', length: gv2CiphertextLen))] =
          Gv2MemberState(
        role: role,
        memberPub: _bytes(m, 'memberPub', length: gv2PublicKeyLen),
        // Never later than the state it is part of (and so a u32: the state
        // hash holds 32 bits of it — a larger value would be cut there and
        // pass the hash check while meaning something else).
        joinedRevision: _upTo(m, 'joinedRevision', at),
        memberPayload: payload,
      );
    }
    final pending = SplayTreeMap<String, Gv2PendingState>();
    for (final item in pendingRaw) {
      final p = _map(item, 'pending');
      pending[gv2Hex(_bytes(p, 'ciphertext', length: gv2CiphertextLen))] =
          Gv2PendingState(
        invitedBy: _bytes(p, 'invitedBy', length: gv2CiphertextLen),
        invitePub: _bytes(p, 'invitePub', length: gv2PublicKeyLen),
        revision: _upTo(p, 'revision', at),
      );
    }
    if (members.length != membersRaw.length || pending.length != pendingRaw.length) {
      throw const Gv2ProtocolException('duplicate ciphertext');
    }
    final title = _bytes(body, 'titlePayload', allowEmpty: true);
    if (title.length > gv2MaxTitlePayload) {
      throw const Gv2ProtocolException('titlePayload');
    }
    return Gv2Snapshot(
      state: Gv2GroupState(
        version: _upTo(body, 'version', 0xFF), // a u8 in the state hash
        groupId: Uint8List.fromList(groupId),
        revision: at,
        chain: _bytes(body, 'chain', length: gv2HashLen),
        deleted: _bool(body, 'deleted'),
        members: members,
        pending: pending,
        titlePayload: title,
      ),
      headSig: _bytes(body, 'headSig', length: gv2SignatureLen),
    );
  }

  /// The server's endorsements for the current members (members only).
  Future<Gv2EndorsementsResponse> endorsements({
    required Uint8List groupId,
    required Uint8List presentation,
  }) async {
    final body = await _call(
      'POST',
      '/gv2/endorsements',
      presentation: presentation,
      data: {'groupId': base64Encode(groupId)},
    );
    return Gv2EndorsementsResponse(
      revision: _u32(body, 'revision'),
      expiration: _int(body, 'expiration'),
      response: _bytes(body, 'response'),
    );
  }

  // ---------------------------------------------------------------------------
  // Sending (send token only: no presentation, no group id)
  // ---------------------------------------------------------------------------

  /// Queue [entries]. One result per entry, in order. Nothing in the request
  /// says which recipient is this account: its own row is acknowledged as it
  /// arrives, and the server pushes only rows still unacknowledged (SC-18).
  Future<List<Gv2SendResult>> send(List<Gv2SendEntry> entries) async {
    final body = await _call('POST', '/gv2/send', data: {
      'entries': [
        for (final e in entries)
          {
            'token': base64Encode(e.token),
            'recipients': [for (final r in e.recipients) base64Encode(r)],
            'envelope': base64Encode(e.envelope),
            if (e.silent) 'silent': true,
            if (e.expiresIn != null) 'expiresIn': e.expiresIn,
          },
      ],
    });
    final list = body['results'];
    if (list is! List || list.length != entries.length) {
      throw const Gv2ProtocolException('results');
    }
    return [for (final item in list) _sendResult(_map(item, 'result'))];
  }

  /// Display names of [recipients] (account ids), for whoever holds a send
  /// token for exactly them. accountId hex → name (null = no such account).
  Future<Map<String, String?>> names({
    required Uint8List token,
    required List<Uint8List> recipients,
  }) async {
    final body = await _call('POST', '/gv2/names', data: {
      'token': base64Encode(token),
      'recipients': [for (final r in recipients) base64Encode(r)],
    });
    final list = body['names'];
    if (list is! List) throw const Gv2ProtocolException('names');
    final asked = {for (final r in recipients) gv2Hex(r)};
    final out = <String, String?>{};
    for (final item in list) {
      final n = _map(item, 'name');
      final id = gv2Hex(_bytes(n, 'accountId', length: _accountIdLen));
      // Only what was asked for.
      if (!asked.contains(id)) throw const Gv2ProtocolException('names');
      final name = n['displayName'];
      if (name != null && name is! String) {
        throw const Gv2ProtocolException('displayName');
      }
      out[id] = name as String?;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _call(
    String method,
    String path, {
    Uint8List? presentation,
    Object? data,
  }) async {
    final Response<Object?> response;
    try {
      response = await _anonymous.request<Object?>(
        path,
        data: data,
        options: Options(
          method: method,
          headers: presentation == null
              ? null
              : {'Authorization': 'SnowZk ${base64Encode(presentation)}'},
        ),
      );
    } on DioException {
      // Deliberately not carried along: a DioException holds the request,
      // including its Authorization header.
      throw const Gv2NetworkException();
    }
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      return _map(response.data, 'response');
    }
    throw _apiError(status, response.data);
  }

  Exception _fromDio(DioException e) {
    final response = e.response;
    if (response == null) return const Gv2NetworkException();
    return _apiError(response.statusCode ?? 0, response.data);
  }

  Gv2ApiException _apiError(int status, Object? data) {
    final error = data is Map ? data['error'] : null;
    if (error is! Map || error['code'] is! String) {
      return Gv2ApiException(status, 'unknown');
    }
    Gv2Head? head;
    try {
      final raw = error['head'];
      if (raw != null) head = _head(_map(raw, 'head'));
    } on Gv2ProtocolException {
      head = null;
    }
    final reason = error['reason'];
    return Gv2ApiException(
      status,
      error['code'] as String,
      head: head,
      reason: reason is String ? reason : null,
    );
  }

  Gv2SendResult _sendResult(Map<String, dynamic> r) {
    final unknown = r['unknownRecipients'];
    final deleted = r['deleted'];
    if (unknown is! List || deleted is! List) {
      throw const Gv2ProtocolException('send result');
    }
    final error = r['error'];
    if (error != null && error is! String) {
      throw const Gv2ProtocolException('send result');
    }
    final proofs = <Gv2DeletedRecipient>[];
    for (final item in deleted) {
      final d = _map(item, 'deleted');
      final proof = AccountDeletionProof.tryParseWire(d);
      if (proof == null) throw const Gv2ProtocolException('deletion proof');
      proofs.add(Gv2DeletedRecipient(
        accountId: _bytes(d, 'accountId', length: _accountIdLen),
        accountPublicKey: _bytes(d, 'accountPub', length: gv2PublicKeyLen),
        proof: proof,
      ));
    }
    return Gv2SendResult(
      ok: _bool(r, 'ok'),
      error: error as String?,
      delivered: _int(r, 'delivered'),
      unknownRecipients: [
        for (final item in unknown)
          _decode(item, 'unknownRecipients', length: _accountIdLen),
      ],
      throttledRecipients: _int(r, 'throttledRecipients'),
      deleted: proofs,
    );
  }

  Gv2Head _head(Map<String, dynamic> body) => Gv2Head(
        revision: _u32(body, 'revision'),
        chain: _bytes(body, 'chain', length: gv2HashLen),
        headSig: _bytes(body, 'headSig', length: gv2SignatureLen),
      );

  static Map<String, dynamic> _map(Object? raw, String what) {
    if (raw is! Map) throw Gv2ProtocolException(what);
    return Map<String, dynamic>.from(raw);
  }

  static int _int(Map<String, dynamic> body, String field) {
    final value = body[field];
    if (value is! int || value < 0) throw Gv2ProtocolException(field);
    return value;
  }

  /// [field] of [body]: an integer no greater than [atMost].
  static int _upTo(Map<String, dynamic> body, String field, int atMost) {
    final value = _int(body, field);
    if (value > atMost) throw Gv2ProtocolException(field);
    return value;
  }

  /// [field] of [body]: a revision — a u32 wherever it is hashed or signed
  /// (a larger value would be cut to 32 bits there).
  static int _u32(Map<String, dynamic> body, String field) =>
      _upTo(body, field, 0xFFFFFFFF);

  static bool _bool(Map<String, dynamic> body, String field) {
    final value = body[field];
    if (value is! bool) throw Gv2ProtocolException(field);
    return value;
  }

  static Uint8List _bytes(
    Map<String, dynamic> body,
    String field, {
    int? length,
    bool allowEmpty = false,
  }) =>
      _decode(body[field], field, length: length, allowEmpty: allowEmpty);

  static Uint8List _decode(
    Object? value,
    String field, {
    int? length,
    bool allowEmpty = false,
  }) {
    if (value is! String) throw Gv2ProtocolException(field);
    final Uint8List bytes;
    try {
      bytes = base64Decode(value);
    } on FormatException {
      throw Gv2ProtocolException(field);
    }
    if ((bytes.isEmpty && !allowEmpty) || (length != null && bytes.length != length)) {
      throw Gv2ProtocolException(field);
    }
    return bytes;
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
