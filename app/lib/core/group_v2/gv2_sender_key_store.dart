/// @file        gv2_sender_key_store.dart
/// @description Group protocol v2 — the only writer of the Sender Key tables
///              (gv2_sender_keys, gv2_key_deliveries). The v4 Sender Keys
///              live in the encrypted database, one record per (group,
///              sender), so that installing a key or moving a chain commits
///              in the same transaction as the inbox row that caused it
///              (design §8).
///              Also records the exact key given to each member, per chain
///              of this device's own key.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (comment: no v1 rooms; the Sender Key manager has one wire format now — no wireVersion argument). Earlier 2026-11-13
///
/// @functions
///  - Gv2SenderKeyStore.manager(): a v4 manager holding one record
///  - Gv2SenderKeyStore.save(): store a record a manager changed
///  - Gv2SenderKeyStore.install(): install a key a member sent
///  - Gv2SenderKeyStore.createOwn() / ownCurrent(): this device's own key
///  - Gv2SenderKeyStore.forget(): drop the keys of a sender
///  - Gv2SenderKeyStore.read() / sealOwn(): decrypt or encrypt a message and
///    store the moved chain, in one transaction
///  - Gv2SenderKeyStore.delivered() / deliveredTo() / recordDelivery() /
///    forgetDeliveries(): the key given to a member
///  - Gv2SenderKeyStore.keepOnly(): erase what belongs to former members
///
/// Notes:
///  - install() reads and writes the record inside one transaction: two
///    lanes of the inbox (a key arriving pairwise, a message read in its
///    group) never overwrite each other's change.
///  - A key is installed only from the sender itself (a pairwise message on
///    its own 1:1 session); this file does not judge who may install what.
///  - Records hold key material: nothing here logs.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../crypto/sender_key.dart';
import '../storage/database.dart';
import '../storage/tables/gv2_tables.dart';
import 'gv2_pairwise.dart';

part 'gv2_sender_key_store.g.dart';

@DriftAccessor(tables: [Gv2SenderKeys, Gv2KeyDeliveries])
class Gv2SenderKeyStore extends DatabaseAccessor<SnowDatabase>
    with _$Gv2SenderKeyStoreMixin {
  Gv2SenderKeyStore(super.db);

  /// A manager holding the record of [sender] in [groupId] (lowercase
  /// hex), or no record. What it changes is stored only by [save].
  Future<SenderKeyManager> manager(String groupId, String sender) async {
    final record = await _record(groupId, sender);
    return SenderKeyManager(senderKeys: {_key(groupId, sender): ?record});
  }

  /// Store the record of [sender] that [manager] holds (after a read moved
  /// the chain, or an own message was encrypted).
  Future<void> save(
    String groupId,
    String sender,
    SenderKeyManager manager,
  ) async {
    final json = manager.toJson()[_key(groupId, sender)];
    if (json is! Map<String, dynamic>) {
      throw StateError('gv2 sender keys: the manager holds no such record');
    }
    await _write(groupId, sender, json);
  }

  /// Install [key] of [sender] in [groupId]. Returns true when the key is
  /// held afterwards (installed now or held before), false when it was
  /// refused. A chain already held is never replaced — not by an earlier
  /// position of it either.
  Future<bool> install(String groupId, String sender, Gv2SenderKeyBody key) {
    return transaction(() async {
      final m = await manager(groupId, sender);
      final held = m.processSenderKey(key.toDistribution(groupId, sender));
      if (held) await save(groupId, sender, m);
      return held;
    });
  }

  /// Make a new own key for [groupId] ([me] is this account's snowId) and
  /// return it at its first position. Earlier own chains stay (up to five)
  /// for messages still in flight.
  Future<Gv2SenderKeyBody> createOwn(String groupId, String me) {
    return transaction(() async {
      final m = await manager(groupId, me);
      final created = m.createSenderKey(groupId, me);
      await save(groupId, me, m);
      return Gv2SenderKeyBody.of(created);
    });
  }

  /// This device's own key of [groupId] at its current position, or null
  /// when it has none: what a member who never had it is given (from here
  /// on, not from the start of the chain).
  Future<Gv2SenderKeyBody?> ownCurrent(String groupId, String me) async {
    final record = await _record(groupId, me);
    if (record == null || record.isEmpty) return null;
    final state = record.current;
    if (state.signingKeyPrivate == null) return null;
    return Gv2SenderKeyBody(
      chainId: state.chainId,
      iteration: state.iteration,
      chainKey: Uint8List.fromList(state.chainKey),
      signingKey: Uint8List.fromList(state.signingKeyPublic),
    );
  }

  /// Drop every key of [sender] in [groupId].
  Future<void> forget(String groupId, String sender) => (delete(
    gv2SenderKeys,
  )..where((k) => k.groupId.equals(groupId) & k.sender.equals(sender))).go();

  /// The key of own chain [chainId] given to [member], or null.
  Future<Gv2SenderKeyBody?> delivered(
    String groupId,
    String member,
    int chainId,
  ) async {
    final row =
        await (select(gv2KeyDeliveries)..where(
              (d) =>
                  d.groupId.equals(groupId) &
                  d.member.equals(member) &
                  d.chainId.equals(chainId),
            ))
            .getSingleOrNull();
    return row == null ? null : Gv2SenderKeyBody.decode(row.key);
  }

  /// [member] is given [key]. A key of that chain given before stays: a
  /// member is never given an earlier position of a chain it holds.
  Future<void> recordDelivery(
    String groupId,
    String member,
    Gv2SenderKeyBody key, {
    required int nowMs,
  }) => into(gv2KeyDeliveries).insert(
    Gv2KeyDeliveriesCompanion.insert(
      groupId: groupId,
      member: member,
      chainId: key.chainId,
      key: key.encode(),
      deliveredAtMs: nowMs,
    ),
    mode: InsertMode.insertOrIgnore,
  );

  /// The members given the key of own chain [chainId] in [groupId].
  Future<Set<String>> deliveredTo(String groupId, int chainId) async {
    final rows =
        await (selectOnly(gv2KeyDeliveries)
              ..addColumns([gv2KeyDeliveries.member])
              ..where(
                gv2KeyDeliveries.groupId.equals(groupId) &
                    gv2KeyDeliveries.chainId.equals(chainId),
              ))
            .get();
    return {for (final r in rows) r.read(gv2KeyDeliveries.member)!};
  }

  /// Read a message of [sender] inside one transaction: load the record,
  /// let [open] decrypt with it, store what the read changed. Whatever
  /// [open] throws (a [SenderKeyException], ...) leaves the record as it
  /// was. A key installed by another lane meanwhile is never overwritten.
  Future<Uint8List> read(
    String groupId,
    String sender,
    Uint8List Function(SenderKeyManager keys) open,
  ) => transaction(() async {
    final m = await manager(groupId, sender);
    final plaintext = open(m);
    await save(groupId, sender, m);
    return plaintext;
  });

  /// Encrypt an own message inside one transaction: load this device's
  /// record, let [seal] encrypt with it, store the chain it moved.
  Future<Uint8List> sealOwn(
    String groupId,
    String me,
    Uint8List Function(SenderKeyManager keys) seal,
  ) => read(groupId, me, seal);

  /// Keep only what belongs to [members] (snowIds) in [groupId]: Sender
  /// Keys received from anyone else and the records of keys given to anyone
  /// else are erased. [me]'s own record always stays. Called after the
  /// roster changed: a removed member's key is not kept, and a member who
  /// comes back is given a key again.
  Future<void> keepOnly(
    String groupId,
    Set<String> members, {
    required String me,
  }) => transaction(() async {
    final keep = {...members, me}.toList();
    await (delete(gv2SenderKeys)..where(
          (k) => k.groupId.equals(groupId) & k.sender.isNotIn(keep),
        ))
        .go();
    await (delete(gv2KeyDeliveries)..where(
          (d) => d.groupId.equals(groupId) & d.member.isNotIn(members.toList()),
        ))
        .go();
  });

  /// Forget what was given to [member] (or to everyone) in [groupId].
  Future<void> forgetDeliveries(String groupId, {String? member}) =>
      (delete(gv2KeyDeliveries)..where(
            (d) =>
                d.groupId.equals(groupId) &
                (member == null
                    ? const Constant(true)
                    : d.member.equals(member)),
          ))
          .go();

  Future<SenderKeyRecord?> _record(String groupId, String sender) async {
    final row =
        await (select(gv2SenderKeys)..where(
              (k) => k.groupId.equals(groupId) & k.sender.equals(sender),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return SenderKeyRecord.fromJson(
      jsonDecode(utf8.decode(row.record)) as Map<String, dynamic>,
    );
  }

  Future<void> _write(
    String groupId,
    String sender,
    Map<String, dynamic> json,
  ) => into(gv2SenderKeys).insertOnConflictUpdate(
    Gv2SenderKeysCompanion.insert(
      groupId: groupId,
      sender: sender,
      record: Uint8List.fromList(utf8.encode(jsonEncode(json))),
    ),
  );

  /// The manager's name of a record: gv2SenderKeyGroup(groupId) is the
  /// group id in lowercase hex.
  static String _key(String groupId, String sender) => '$groupId:$sender';
}
