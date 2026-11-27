/// @file        schema_migration_test.dart
/// @description The drift schema against its recorded versions
///              (drift_schemas/drift_schema_vN.json, test/generated_migrations):
///              a database upgraded from an older version must end with
///              exactly the tables a fresh install creates, and the rows that
///              were there before must survive. Also the guard that the
///              current schema has been recorded at all — a table change
///              without a new schemaVersion and a new dump fails here.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-27 (v18 → v19: the four wallet tables and their indexes go, the other rows
///              stay; the fresh install makes seven hand-made indexes, not ten). Earlier 2026-11-22 (v17 → v18 marks the contact restore done with the block replace due — an
///              install upgraded in place has no backup). Earlier 2026-11-22 (v17 → v18: the contacts table goes; contact_list, peer_names and
///              contact_sync_state come; blocked_accounts.nickname). Earlier 2026-11-21 (v16 → v17: direct_outbox and local_messages.peer_client_id with its
///              unique index). Earlier 2026-11-21 (v15 → v16: blocked_accounts; v14 → v15: gv2_backup_state.write_due_at_ms). Earlier 2026-11-20 (v13 → v14: only conversations keyed by a snowId or a v2 group id stay,
///              with their messages and attachment rows; the v10 case keeps a 1:1 room keyed by
///              its peer). Earlier same day (v12 → v13: gv2_groups.change_sent_at_ms)
///
/// @functions
///  - main(): the test cases.
///
/// Notes:
///  - After changing a table: bump SnowDatabase.schemaVersion, add the
///    migration step, then record the new version:
///      dart run drift_dev schema dump lib/core/storage/database.dart drift_schemas/
///      dart run drift_dev schema generate drift_schemas/ test/generated_migrations/
///  - Versions before 10 were never recorded (recording started with v11), so
///    upgrades are verified from v10 on.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_common.dart' show ValidationOptions;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/storage/database.dart';

import '../../generated_migrations/schema.dart';

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the current schema version has been recorded', () {
    final db = SnowDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(GeneratedHelper.versions, contains(db.schemaVersion),
        reason: 'run the two drift_dev schema commands (see the file header)');
    expect(GeneratedHelper.versions.last, db.schemaVersion);
  });

  // validateDropped: anything the recorded schema does not have is an error
  // too (used where the database starts from a recorded version).
  const strict = ValidationOptions(validateDropped: true);

  const listNames =
      "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'";

  /// One column as `name type notnull default pk`. The recorded schema and
  /// the code write a default as `(0)` and `0`: the brackets are dropped.
  String column(Object? name, Object? type, Object? notNull, Object? dflt, Object? pk) {
    var value = '$dflt';
    while (value.startsWith('(') && value.endsWith(')')) {
      value = value.substring(1, value.length - 1);
    }
    return '$name $type notnull=$notNull default=$value pk=$pk';
  }

  /// table → its columns, for the recorded [version].
  Future<Map<String, List<String>>> recordedTables(int version) async {
    final schema = await verifier.schemaAt(version);
    addTearDown(schema.rawDatabase.dispose);
    final raw = schema.rawDatabase;
    return {
      for (final t in raw.select(listNames, ['table']))
        t['name'] as String: [
          for (final c in raw.select('PRAGMA table_info("${t['name']}")'))
            column(c['name'], c['type'], c['notnull'], c['dflt_value'], c['pk']),
        ],
    };
  }

  Future<Set<String>> recordedIndexes(int version) async {
    final schema = await verifier.schemaAt(version);
    addTearDown(schema.rawDatabase.dispose);
    return {
      for (final r in schema.rawDatabase.select(listNames, ['index']))
        r['name'] as String,
    };
  }

  /// The same for a database created by the code (onCreate).
  Future<Map<String, List<String>>> createdTables(SnowDatabase db) async {
    final tables = await db.customSelect(listNames,
        variables: [Variable.withString('table')]).get();
    final out = <String, List<String>>{};
    for (final t in tables) {
      final name = t.read<String>('name');
      final columns = await db.customSelect('PRAGMA table_info("$name")').get();
      out[name] = [
        for (final c in columns)
          column(c.data['name'], c.data['type'], c.data['notnull'],
              c.data['dflt_value'], c.data['pk']),
      ];
    }
    return out;
  }

  Future<Set<String>> createdIndexes(SnowDatabase db) async => {
        for (final r in await db.customSelect(listNames,
            variables: [Variable.withString('index')]).get())
          r.read<String>('name'),
      };

  test('a fresh install creates exactly the recorded current schema', () async {
    final current = GeneratedHelper.versions.last;
    // A new empty database: onCreate runs the code's own table definitions.
    final db = SnowDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Tables: the same set, each with the same columns.
    expect(await createdTables(db), await recordedTables(current));

    // Indexes: every recorded one, plus exactly the seven older indexes that
    // onCreate makes by hand (they predate the recording and are not part of
    // the drift schema). Anything else is an index nobody recorded.
    final indexes = await createdIndexes(db);
    final recorded = await recordedIndexes(current);
    expect(indexes.containsAll(recorded), isTrue);
    expect(indexes.difference(recorded), {
      'idx_messages_unread_per_conversation',
      'idx_messages_unnotified',
      'idx_messages_sender_timestamp',
      'idx_messages_conversation_time',
      'idx_conversations_active_time',
      'idx_attachments_message',
      'idx_attachments_pending',
    });

    // Constraints and index definitions, as drift's own verifier compares them.
    await verifier.migrateAndValidate(db, current);
  });

  test('the comparison above can fail: v10 is not what the code creates',
      () async {
    final db = SnowDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = await createdTables(db);
    final before = await recordedTables(10);
    expect(now, isNot(before));
    expect(now.keys.toSet().difference(before.keys.toSet()), {
      'gv2_groups',
      'gv2_members',
      'gv2_pending',
      'gv2_server_keys',
      'gv2_auth_credentials',
      'gv2_endorsements',
      'gv2_inbox',
      'gv2_seen',
      'gv2_heads',
      'gv2_sender_keys',
      'gv2_key_deliveries',
      'gv2_outbox',
      'gv2_message_ids',
      'gv2_backup_state',
      'blocked_accounts',
      'direct_outbox',
      'contact_list',
      'peer_names',
      'contact_sync_state',
    });
    // v18 dropped the never-written contacts table, v19 the wallet tables.
    const dropped = {
      'contacts',
      'wallet_balances',
      'wallet_tx_cache',
      'wallet_address_book',
      'pending_transfers',
    };
    expect(before.keys.toSet().difference(now.keys.toSet()), dropped);
    // Everything else v10 had is unchanged, but for the one column v17
    // added to local_messages (the receiver's duplicate guard).
    for (final e in before.entries) {
      if (dropped.contains(e.key)) continue;
      if (e.key == 'local_messages') {
        expect(now[e.key]!.where((c) => !c.startsWith('peer_client_id ')),
            e.value);
        continue;
      }
      expect(now[e.key], e.value, reason: e.key);
    }
  });

  for (final from in GeneratedHelper.versions) {
    if (from == GeneratedHelper.versions.last) continue;
    test('upgrade from v$from ends with exactly the current schema', () async {
      final connection = await verifier.startAt(from);
      final db = SnowDatabase(connection);
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, GeneratedHelper.versions.last,
          options: strict);
    });
  }

  test('v10 → current keeps existing rows and adds usable group tables',
      () async {
    final schema = await verifier.schemaAt(10);
    final raw = schema.rawDatabase;
    final peer = 'snow${'0' * 31}1';
    raw.execute(
      'INSERT INTO conversations (id, type, participant_ids, created_at, updated_at) '
      "VALUES ('$peer', 'direct', '[]', 1, 2)",
    );
    raw.execute(
      'INSERT INTO identity_verifications '
      '(peer_snowchat_id, pinned_ed25519, safety_number, algorithm_version, created_at, updated_at) '
      "VALUES ('snow00000000000000000000000000000001', 'a2V5', '${'1' * 60}', 2, 1, 2)",
    );

    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);

    final conversation = await db.select(db.conversations).getSingle();
    expect(conversation.id, peer);
    expect(conversation.type, 'direct');
    final pinned = await db.select(db.identityVerifications).getSingle();
    expect(pinned.pinnedEd25519, 'a2V5');
    expect(pinned.algorithmVersion, 2);

    // The new tables exist, are empty and the store can read them.
    expect(await db.gv2Store.groups(), isEmpty);
    expect(await db.gv2Store.memberRows('ab' * 32), isEmpty);
    expect(await db.gv2Store.pendingInvites('ab' * 32), isEmpty);
    final index = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_gv2_members_snow'")
        .get();
    expect(index, hasLength(1));
  });

  test('v11 → current keeps the groups, adds the reset flag and the backup '
      'state', () async {
    final schema = await verifier.schemaAt(11);
    final raw = schema.rawDatabase;
    raw.execute(
      'INSERT INTO gv2_groups (group_id, master_key, my_ciphertext, '
      'protocol_version, membership, revision, chain, state_hash, '
      'state_loaded, title_payload) '
      "VALUES ('${'ab' * 32}', x'${'11' * 32}', '${'cd' * 65}', 1, 'active', "
      "7, x'${'22' * 32}', x'${'33' * 32}', 1, x'')",
    );

    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);

    final group = (await db.gv2Store.groups()).single;
    expect(group.groupId, 'ab' * 32);
    expect(group.revision, 7);
    expect(group.resetPending, isFalse);
    expect(group.changeSentAtMs, isNull);
    expect(await db.select(db.gv2BackupStates).get(), isEmpty);
  });

  test('v12 → v13 keeps the groups and adds the unanswered-change mark',
      () async {
    final schema = await verifier.schemaAt(12);
    final raw = schema.rawDatabase;
    raw.execute(
      'INSERT INTO gv2_groups (group_id, master_key, my_ciphertext, '
      'protocol_version, membership, revision, chain, state_hash, '
      'state_loaded, title_payload, reset_pending, last_sync_at_ms) '
      "VALUES ('${'ab' * 32}', x'${'11' * 32}', '${'cd' * 65}', 1, 'active', "
      "7, x'${'22' * 32}', x'${'33' * 32}', 1, x'', 1, 1234)",
    );

    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 13);

    final group = (await db.gv2Store.groups()).single;
    expect(group.revision, 7);
    expect(group.resetPending, isTrue);
    expect(group.lastSyncAtMs, 1234);
    expect(group.changeSentAtMs, isNull);
  });

  test('v13 → v14 keeps only the conversations of a peer or a v2 group, '
      'with their messages and attachment rows', () async {
    final schema = await verifier.schemaAt(13);
    final raw = schema.rawDatabase;
    final peer = 'snow${'0123456789abcdef' * 2}';
    final group = 'ab' * 32;
    // What goes: a v1 group / community room and a legacy 1:1 room (server
    // CUIDs), an old group row mis-typed as 'direct', and ids that only
    // look valid (upper-case hex, a snow prefix with a wrong length).
    final gone = <String, String>{
      'clx0v1group000000000000001': 'group',
      'clx0legacy1to1000000000001': 'direct',
      'clx0mistyped0000000000001': 'direct',
      'AB' * 32: 'group',
      'snow${'0123456789ABCDEF' * 2}': 'direct',
      'snow${'0' * 31}': 'direct',
    };
    final kept = <String, String>{peer: 'direct', group: 'group'};
    var n = 0;
    for (final e in {...kept, ...gone}.entries) {
      n++;
      raw.execute(
        'INSERT INTO conversations (id, type, participant_ids, created_at, updated_at) '
        "VALUES ('${e.key}', '${e.value}', '', 1, 2)",
      );
      raw.execute(
        'INSERT INTO local_messages (id, conversation_id, sender_snowchat_id, '
        'date_sent, date_received, plaintext) '
        "VALUES ('m$n', '${e.key}', '$peer', 1, 2, 'text $n')",
      );
      raw.execute(
        'INSERT INTO local_attachments (id, message_id, content_type) '
        "VALUES ('a$n', 'm$n', 'image/png')",
      );
    }

    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 14);

    final conversations = await db.select(db.conversations).get();
    expect({for (final c in conversations) c.id}, kept.keys.toSet());
    final messages = await db.select(db.localMessages).get();
    expect({for (final m in messages) m.conversationId}, kept.keys.toSet());
    final attachments = await db.select(db.localAttachments).get();
    expect({for (final a in attachments) a.messageId},
        {for (final m in messages) m.id});
    // The rows that stay are untouched.
    final peerRow = conversations.singleWhere((c) => c.id == peer);
    expect(peerRow.type, 'direct');
    expect(messages.singleWhere((m) => m.conversationId == peer).plaintext,
        'text 1');
  });

  test('v14 → v15 keeps the backup state and adds no pending write',
      () async {
    final schema = await verifier.schemaAt(14);
    schema.rawDatabase.execute(
      'INSERT INTO gv2_backup_state (slot, restored, etag, fingerprint) '
      "VALUES (0, 1, 'tag', x'${'44' * 32}')",
    );
    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 15);

    final state = (await db.gv2Store.backupState())!;
    expect(state.restored, isTrue);
    expect(state.etag, 'tag');
    expect(state.fingerprint, hasLength(32));
    expect(state.writeDueAtMs, isNull);
  });

  test('v14 → v15 keeps the groups and their log points; the points get no '
      'time (old: pruned first) and the own key none (replaced before the '
      'next message)', () async {
    final schema = await verifier.schemaAt(14);
    final raw = schema.rawDatabase;
    raw.execute(
      'INSERT INTO gv2_groups (group_id, master_key, my_ciphertext, '
      'protocol_version, membership, revision, chain, state_hash, '
      'state_loaded, title_payload, reset_pending, last_sync_at_ms, '
      'my_key_revision) '
      "VALUES ('${'ab' * 32}', x'${'11' * 32}', '${'cd' * 65}', 1, 'active', "
      "7, x'${'22' * 32}', x'${'33' * 32}', 1, x'', 0, 1234, 5)",
    );
    raw.execute(
      'INSERT INTO gv2_heads (group_id, revision, chain) '
      "VALUES ('${'ab' * 32}', 7, x'${'22' * 32}')",
    );
    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 15);

    final group = (await db.gv2Store.groups()).single;
    expect(group.myKeyRevision, 5);
    expect(group.myKeyAtMs, isNull);
    final head = (await db.gv2Store.head('ab' * 32, 7))!;
    expect(head.storedAtMs, 0);
  });

  // (Validated at the current version: the table is created with its
  // current columns — v18 added nickname — so it does not match v16's.)
  test('v15 → current adds the blocked accounts, empty', () async {
    final schema = await verifier.schemaAt(15);
    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, GeneratedHelper.versions.last);
    expect(await db.blockListDao.allRows(), isEmpty);
  });

  test('v16 → v17 keeps the messages, adds an empty 1:1 outbox and the '
      'duplicate guard (a sender\'s own id is unique, absent ones are not)',
      () async {
    final schema = await verifier.schemaAt(16);
    final raw = schema.rawDatabase;
    const peer = 'snow0123456789abcdef0123456789abcdef';
    for (final (id, sent) in [('m1', 1), ('m2', 2)]) {
      raw.execute(
          'INSERT INTO local_messages (id, conversation_id, sender_snowchat_id, '
          "date_sent, date_received, plaintext) VALUES (?, ?, ?, ?, ?, 'x')",
          [id, peer, peer, sent, sent]);
    }
    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 17);

    expect(await db.directOutboxDao.allJobs(), isEmpty);
    final m1 = await db.messageDao.getMessageById('m1');
    expect(m1!.peerClientId, isNull);
    expect(await db.messageDao.getMessageById('m2'), isNotNull);

    // Two old rows with no cid live side by side; a cid is unique per sender.
    await db.customStatement(
        "UPDATE local_messages SET peer_client_id = 'msg_1' WHERE id = 'm1'");
    expect(await db.messageDao.hasMessageFromPeer(peer, 'msg_1'), isTrue);
    expect(
      () => db.customStatement(
          "UPDATE local_messages SET peer_client_id = 'msg_1' WHERE id = 'm2'"),
      throwsA(anything),
    );
  });

  test('v17 → v18 drops the contacts table, adds the contact list tables '
      'empty, keeps the blocks (with no name) and marks the restore done',
      () async {
    final schema = await verifier.schemaAt(17);
    final raw = schema.rawDatabase;
    const peer = 'snow0123456789abcdef0123456789abcdef';
    raw.execute(
        'INSERT INTO blocked_accounts (snow_id, blocked, synced, updated_at_ms) '
        'VALUES (?, 1, 1, 5)',
        [peer]);
    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 18);

    final tables = {
      for (final r in await db.customSelect(listNames,
          variables: [Variable.withString('table')]).get())
        r.read<String>('name'),
    };
    expect(tables, isNot(contains('contacts')));
    expect(await db.contactDao.allRows(), isEmpty);
    expect(await db.contactDao.allPeerNames(), isEmpty);
    final block = (await db.blockListDao.allRows()).single;
    expect(block.snowId, peer);
    expect(block.blocked, isTrue);
    expect(block.nickname, isNull);

    // An install upgraded in place never restores (it has no backup) and
    // puts its whole block list on the server at the first sync (§5.10).
    final state = (await db.contactDao.syncState())!;
    expect(state.restored, isTrue);
    expect(state.blocksReplacePending, isTrue);
    expect(state.restoreNoticeDue, isFalse);
    expect(state.periodMs,
        inInclusiveRange(const Duration(hours: 6).inMilliseconds,
            const Duration(hours: 24).inMilliseconds));
    // ensureSyncState keeps it as it is.
    final again = await db.contactDao.ensureSyncState(periodMs: 7, nowMs: 100);
    expect(again.restored, isTrue);
    expect(again.periodMs, state.periodMs);
  });

  test('v18 → v19 drops the wallet tables and their indexes, keeps the rest',
      () async {
    final schema = await verifier.schemaAt(18);
    final raw = schema.rawDatabase;
    const peer = 'snow0123456789abcdef0123456789abcdef';
    raw.execute(
        'INSERT INTO conversations (id, type, participant_ids, created_at, updated_at) '
        "VALUES (?, 'direct', '[]', 1, 2)",
        [peer]);
    raw.execute(
        'INSERT INTO local_messages (id, conversation_id, sender_snowchat_id, '
        "date_sent, date_received, plaintext) VALUES ('m1', ?, ?, 1, 2, 'kept')",
        [peer, peer]);
    raw.execute(
        'INSERT INTO blocked_accounts (snow_id, blocked, synced, updated_at_ms) '
        'VALUES (?, 1, 1, 5)',
        [peer]);
    // The hand-made wallet indexes an older onCreate / v4 step made.
    raw.execute('CREATE INDEX idx_wallet_balances_owner '
        'ON wallet_balances (owner_address, last_updated_ms DESC)');
    raw.execute('CREATE INDEX idx_wallet_tx_cache_owner_time '
        'ON wallet_tx_cache (owner_address, block_time DESC)');
    raw.execute('CREATE INDEX idx_wallet_address_book_owner '
        'ON wallet_address_book (owner_address, last_used_ms DESC)');

    final db = SnowDatabase(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 19, options: strict);

    final tables = {
      for (final r in await db.customSelect(listNames,
          variables: [Variable.withString('table')]).get())
        r.read<String>('name'),
    };
    expect(
        tables.intersection({
          'wallet_balances',
          'wallet_tx_cache',
          'wallet_address_book',
          'pending_transfers',
        }),
        isEmpty);
    final indexes = await createdIndexes(db);
    expect(indexes.where((i) => i.startsWith('idx_wallet_')), isEmpty);

    expect((await db.select(db.conversations).getSingle()).id, peer);
    expect((await db.messageDao.getMessageById('m1'))!.plaintext, 'kept');
    expect((await db.blockListDao.allRows()).single.snowId, peer);
  });

  test('a new install (no upgrade) makes the sync state on first use: not '
      'restored, replace pending', () async {
    final db = SnowDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.contactDao.syncState(), isNull);
    final state = await db.contactDao.ensureSyncState(periodMs: 7, nowMs: 100);
    expect(state.restored, isFalse);
    expect(state.blocksReplacePending, isTrue);
    expect(state.nextWriteAtMs, 107);
  });
}
