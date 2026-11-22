/// @file        name_cert_service.dart
/// @description Names from name certificates (design 2026-11-22-friend-graph-off-server §5.6,
///              contract §12.3, §12.4). Sending: this account's own certificate is fetched from
///              the server (POST /users/name-cert, renewed when older than seven days) and
///              attached to the first message to a peer, to every contact_added, and to the next
///              message after the certificate became newer than the last one announced to that
///              peer. Receiving: a certificate in a sealed message is checked offline against the
///              pinned server keys and, when newer than the stored one, renames the peer — its
///              contact row, its 1:1 conversation title. Nothing asks the server who a sender is.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22 (review fixes: the own certificate is renewed by this device's own clock —
///              seven days after it was fetched here, not after the server's issue time — and checked
///              for signature and subject only (a phone whose clock is off still sends it); a fetch
///              that failed is not tried again before a growing wait (30 s doubling to an hour), so
///              a server that refuses (429) or cannot be reached is not asked on every send;
///              invalidateOwn() — the account was renamed: the next send fetches a new certificate
///              and carries it to every peer; forgetAnnounced() — a peer started a new session and
///              may have lost this account's name). Earlier 2026-11-22 (the own certificate is stored with a write of its two columns only —
///              ContactDao.patchSyncState — so it never puts back a sync state column the contact
///              backup changed meanwhile, e.g. the restore's)
///
/// @functions
///  - NameCertService.ownCertificate(): this account's certificate (cached, renewed 7 days after it
///    was fetched; a failed fetch waits before the next)
///  - NameCertService.invalidateOwn(): the account was renamed — the cached certificate goes
///  - NameCertService.forgetAnnounced(): a peer may have lost this account's name — sent again
///  - NameCertService.certToAttach(): the certificate to put in the next message to a peer, or null
///  - NameCertService.markAnnounced(): the server took a message carrying the certificate
///  - NameCertService.receive(): a certificate a peer sent — verified, newer only
///  - NameCertService.nameOf(): the name this device knows for a peer (contact → certificate)
///  - NameCertService.warmUp() / cachedName(): the known names in memory, for a synchronous read
///    (an incoming call must be named before its signaling event returns)
///  - NameCertService.resolveName(): nameOf, else the 1:1 conversation's title (the name order of §5.6
///    for a 1:1 peer — never a server lookup)
///
/// Notes:
///  - A peer's name is the server's word, as before (§6) — what changes is that the server
///    does not see who asks.
///  - Never throws for what the server or a peer can cause; nothing of a certificate is logged.
library;


import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../storage/daos/contact_dao.dart';
import '../storage/daos/conversation_dao.dart';
import '../storage/database.dart';
import 'contact_backup.dart' show drawContactWritePeriodMs;
import 'name_certificate.dart';

class NameCertService {
  final ContactDao _dao;
  final ConversationDao _conversations;
  final Future<Uint8List> Function() _fetchOwn;
  final List<Uint8List>? _trustedKeys;
  final String Function() _me;
  final int Function() _nowMs;

  /// [fetchOwn] asks the server for this account's certificate
  /// (POST /users/name-cert); [trustedKeys] are the Sealed Sender server keys
  /// pinned in the build (null: no certificate is ever believed); [mySnowId]
  /// is this account.
  NameCertService({
    required ContactDao dao,
    required ConversationDao conversations,
    required Future<Uint8List> Function() fetchOwn,
    required List<Uint8List>? trustedKeys,
    required String Function() mySnowId,
    int Function()? nowMs,
  })  : _dao = dao,
        _conversations = conversations,
        _fetchOwn = fetchOwn,
        _trustedKeys = trustedKeys,
        _me = mySnowId,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  Future<NameCertificate?>? _fetching;

  /// Bumped by [invalidateOwn]: a fetch that started before it does not
  /// store what it got (the name it carries may be the old one).
  int _generation = 0;

  /// Failed fetches in a row, and when the next fetch may go (local clock).
  int _failures = 0;
  int _retryAtMs = 0;

  /// The first wait after a failed fetch; doubled per failure up to
  /// [fetchBackoffMax].
  static const Duration fetchBackoffBase = Duration(seconds: 30);
  static const Duration fetchBackoffMax = Duration(hours: 1);

  /// The names known on this device (contact rows first, then
  /// certificates), by account — [cachedName]. Filled by [warmUp] and kept
  /// in step by [receive] and [nameOf].
  final Map<String, String> _cache = {};

  /// Called when a peer's name changed on this device (the conversation
  /// list and the contact list re-read it).
  void Function(String peer)? onNameChanged;

  /// This account's certificate: the cached one while it was fetched less
  /// than [nameCertRefreshAfter] ago (this device's clock — the server's
  /// issue time is not compared with it), else a new one from the server.
  /// When the server cannot give one (or a failed fetch is still waited
  /// out), the cached one while it was fetched less than [nameCertMaxAge]
  /// ago — a receiver may still take it; otherwise null. Concurrent calls
  /// share one fetch.
  Future<NameCertificate?> ownCertificate() async {
    final state = await _dao.syncState();
    final cached = _parse(state?.ownNameCert);
    final fetchedAt = state?.ownNameCertAtMs;
    final now = _nowMs();
    // A fetch time ahead of the clock (the clock was set back) says
    // nothing about the age: renewed, and kept meanwhile.
    final age = (cached == null || fetchedAt == null) ? null : now - fetchedAt;
    if (age != null && age >= 0 && age < nameCertRefreshAfter.inMilliseconds) {
      return cached;
    }
    if (now >= _retryAtMs) {
      final fresh = await (_fetching ??=
          _fetchAndStore().whenComplete(() => _fetching = null));
      if (fresh != null) return fresh;
    }
    if (age != null && age < nameCertMaxAge.inMilliseconds) return cached;
    return null;
  }

  static NameCertificate? _parse(Uint8List? bytes) {
    if (bytes == null) return null;
    try {
      return NameCertificate.parse(bytes);
    } on FormatException {
      return null;
    }
  }

  Future<NameCertificate?> _fetchAndStore() async {
    final keys = _trustedKeys;
    if (keys == null) return null;
    final generation = _generation;
    try {
      final cert = NameCertificate.parse(await _fetchOwn());
      // The server's certificate must be signed by a pinned key and name
      // this account — else it is not carried at all. Its age is not
      // judged by this device's clock (the receivers judge it by theirs).
      cert.verifyOrigin(trustedKeys: keys, expectedSnowId: _me());
      if (generation != _generation) return null; // renamed meanwhile
      await _dao.ensureSyncState(
        periodMs: drawContactWritePeriodMs(),
        nowMs: _nowMs(),
      );
      // Only these two columns: the backup writes the same row on its own
      // queue (a whole-row write here could undo its restore).
      await _dao.patchSyncState(ContactSyncStatesCompanion(
        ownNameCert: Value(cert.bytes),
        ownNameCertAtMs: Value(_nowMs()),
      ));
      _failures = 0;
      _retryAtMs = 0;
      return cert;
    } catch (e) {
      _failures++;
      final shift = _failures - 1 > 16 ? 16 : _failures - 1;
      var wait = fetchBackoffBase.inMilliseconds * (1 << shift);
      if (wait > fetchBackoffMax.inMilliseconds) {
        wait = fetchBackoffMax.inMilliseconds;
      }
      _retryAtMs = _nowMs() + wait;
      debugPrint('[NameCert] own certificate not renewed: ${e.runtimeType}');
      return null;
    }
  }

  /// This account's name changed on the server (a profile update it took):
  /// the cached certificate names the old one. It goes; the next send
  /// fetches a new one at once (no waiting out an earlier failure), and —
  /// newer than what each peer was sent — it goes to every peer with the
  /// next message. Never throws.
  Future<void> invalidateOwn() async {
    _generation++;
    _fetching = null;
    _failures = 0;
    _retryAtMs = 0;
    try {
      await _dao.patchSyncState(const ContactSyncStatesCompanion(
        ownNameCert: Value(null),
        ownNameCertAtMs: Value(null),
      ));
    } catch (e) {
      debugPrint('[NameCert] own certificate not dropped: ${e.runtimeType}');
    }
  }

  /// [peer] started a new session with this device (it reinstalled, or
  /// reset the session): it may have lost the name it had for this account.
  /// The next message to it carries the certificate again. Never throws.
  Future<void> forgetAnnounced(String peer) async {
    try {
      await _dao.transaction(() async {
        final row = await _dao.peerName(peer);
        if (row == null || row.announcedIssuedAtMs == null) return;
        await _dao.putPeerName(PeerNameRow(
          peer: peer,
          name: row.name,
          issuedAtMs: row.issuedAtMs,
          announcedIssuedAtMs: null,
        ));
      });
    } catch (e) {
      debugPrint('[NameCert] announced name not reset: ${e.runtimeType}');
    }
  }

  /// The certificate to put in the next message to [peer]: this
  /// account's certificate when the peer was never sent one, or was sent an
  /// older one; null otherwise (or when there is none). [always] (a
  /// contact_added) returns it whenever there is one.
  Future<NameCertificate?> certToAttach(String peer, {bool always = false}) async {
    final own = await ownCertificate();
    if (own == null) return null;
    if (always) return own;
    final announced = (await _dao.peerName(peer))?.announcedIssuedAtMs;
    if (announced != null && announced >= own.issuedAtMs) return null;
    return own;
  }

  /// The server took a message to [peer] carrying the certificate issued at
  /// [issuedAtMs]. The announced time only moves forward.
  Future<void> markAnnounced(String peer, int issuedAtMs) =>
      _dao.transaction(() async {
        final row = await _dao.peerName(peer);
        final current = row?.announcedIssuedAtMs;
        if (current != null && current >= issuedAtMs) return;
        await _dao.putPeerName(PeerNameRow(
          peer: peer,
          name: row?.name,
          issuedAtMs: row?.issuedAtMs,
          announcedIssuedAtMs: issuedAtMs,
        ));
      });

  /// A certificate ([encoded], base64) that [sender] — the authenticated
  /// sender of a sealed message — carried. Believed only when a pinned key
  /// signed it, it names [sender], it is within its age window, and it is
  /// newer than the one stored for [sender]; then the peer's contact row and
  /// 1:1 conversation title take the name. Returns whether the name changed
  /// (or was learned). Never throws.
  Future<bool> receive(String sender, Object? encoded) async {
    final keys = _trustedKeys;
    final cert = NameCertificate.tryParseBase64(encoded);
    if (keys == null || cert == null) return false;
    try {
      cert.verify(trustedKeys: keys, expectedSnowId: sender, nowMs: _nowMs());
    } on NameCertException catch (e) {
      debugPrint('[NameCert] certificate refused (${e.reason.name})');
      return false;
    }
    final changed = await _dao.transaction(() async {
      final row = await _dao.peerName(sender);
      final stored = row?.issuedAtMs;
      if (stored != null && stored >= cert.issuedAtMs) return false;
      await _dao.putPeerName(PeerNameRow(
        peer: sender,
        name: cert.name,
        issuedAtMs: cert.issuedAtMs,
        announcedIssuedAtMs: row?.announcedIssuedAtMs,
      ));
      final contact = await _dao.row(sender);
      if (contact != null) {
        await _dao.putRow(contact.copyWith(
          nickname: Value(cert.name),
          nameIssuedAtMs: Value(cert.issuedAtMs),
          updatedAtMs: _nowMs(),
        ));
      }
      return true;
    });
    if (!changed) return false;
    final name = cert.name;
    await nameOf(sender);
    if (name != null && name.isNotEmpty) {
      try {
        // A 1:1 room is keyed by the peer's snowId.
        if (await _conversations.getConversation(sender) != null) {
          await _conversations.updateTitle(sender, name);
        }
      } catch (e) {
        debugPrint('[NameCert] conversation title not updated: ${e.runtimeType}');
      }
    }
    onNameChanged?.call(sender);
    return true;
  }

  /// The name this device knows for [peer]: its contact row's, else the
  /// newest certificate's; null when none.
  Future<String?> nameOf(String peer) async {
    final contact = await _dao.row(peer);
    final fromContact = contact?.nickname;
    final fromCert = (fromContact != null && fromContact.isNotEmpty)
        ? null
        : (await _dao.peerName(peer))?.name;
    final name = (fromContact != null && fromContact.isNotEmpty)
        ? fromContact
        : (fromCert != null && fromCert.isNotEmpty ? fromCert : null);
    if (name != null) _cache[peer] = name;
    return name;
  }

  /// Read every known name into memory (certificates first, contact rows
  /// over them — the order of [nameOf]). Never throws.
  Future<void> warmUp() async {
    try {
      for (final row in await _dao.allPeerNames()) {
        final name = row.name;
        if (name != null && name.isNotEmpty) _cache[row.peer] = name;
      }
      for (final row in await _dao.allRows()) {
        final name = row.nickname;
        if (name != null && name.isNotEmpty) _cache[row.snowId] = name;
      }
    } catch (e) {
      debugPrint('[NameCert] names not read: ${e.runtimeType}');
    }
  }

  /// The name of [peer] as last read on this device ([warmUp], [nameOf],
  /// [receive]), or null. Synchronous.
  String? cachedName(String peer) => _cache[peer];

  /// The name of [peer] for display: [nameOf], else its 1:1 conversation's
  /// title when that is not the snowId itself; null when none (the caller
  /// shows the short snowId). Never asks the server.
  Future<String?> resolveName(String peer) async {
    final known = await nameOf(peer);
    if (known != null) return known;
    final title = (await _conversations.getConversation(peer))?.title;
    if (title != null && title.isNotEmpty && title != peer) return title;
    return null;
  }
}
