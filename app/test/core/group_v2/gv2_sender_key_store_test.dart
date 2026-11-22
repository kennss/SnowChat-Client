/// @file        gv2_sender_key_store_test.dart
/// @description Gv2SenderKeyStore on a real (in-memory) database: v4 Sender
///              Keys installed from a member never replace a chain already
///              held (not by an earlier position of it either), two lanes
///              installing at once both land, what a read or an own message
///              changes is stored only when saved, and the key given to a
///              member stays the one first given.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-13
/// @lastUpdated 2026-11-20 (the Sender Key manager is v4 only)
///
/// @functions
///  - main(): the test groups below.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/sender_key.dart';
import 'package:snowchat/core/group_v2/gv2_codec.dart';
import 'package:snowchat/core/group_v2/gv2_pairwise.dart';
import 'package:snowchat/core/group_v2/gv2_sender_key_store.dart';
import 'package:snowchat/core/storage/database.dart';

import 'gv2_test_support.dart';

const _alice = 'snow00000000000000000000000000a11ce0';
const _bob = 'snow000000000000000000000000000000b0';

final String _group = gv2Hex(gv2TestSha('sender key store — group'));
final Uint8List _binding = gv2TestSha('sender key store — binding');

Uint8List _text(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late SnowDatabase db;
  late Gv2SenderKeyStore keys;

  // Alice's own keys live in a database of their own (her device).
  late SnowDatabase aliceDb;
  late Gv2SenderKeyStore aliceKeys;

  setUp(() {
    db = SnowDatabase(NativeDatabase.memory());
    keys = db.gv2SenderKeyStore;
    aliceDb = SnowDatabase(NativeDatabase.memory());
    aliceKeys = aliceDb.gv2SenderKeyStore;
  });
  tearDown(() async {
    await db.close();
    await aliceDb.close();
  });

  /// Alice encrypts [text] with her current key and stores the moved chain.
  Future<Uint8List> aliceSends(String text) async {
    final m = await aliceKeys.manager(_group, _alice);
    final out = m.encryptBoundGroupMessage(
      _group,
      _alice,
      _text(text),
      _binding,
    );
    await aliceKeys.save(_group, _alice, m);
    return out;
  }

  Future<String> read(Uint8List message) async {
    final m = await keys.manager(_group, _alice);
    final plain = m.decryptBoundGroupMessage(_group, _alice, message, _binding);
    await keys.save(_group, _alice, m);
    return utf8.decode(plain);
  }

  group('installing', () {
    test('a key from a member reads that member\'s messages', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      expect(await keys.install(_group, _alice, key), isTrue);
      expect(await read(await aliceSends('one')), 'one');
      expect(await read(await aliceSends('two')), 'two');
    });

    test('a chain already held is not replaced, not by an earlier position '
        'either', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      expect(await keys.install(_group, _alice, key), isTrue);
      final first = await aliceSends('one');
      final second = await aliceSends('two');
      expect(await read(second), 'two');
      final later = (await aliceKeys.ownCurrent(_group, _alice))!;
      expect(later.iteration, 2);

      // The same chain again (from position 0, and from position 2): held,
      // nothing changes — the cached key of the skipped 'one' survives, and
      // the used key of 'two' does not come back.
      expect(await keys.install(_group, _alice, key), isTrue);
      expect(await keys.install(_group, _alice, later), isTrue);
      expect(await read(first), 'one');
      await expectLater(
        read(second),
        throwsA(
          isA<SenderKeyException>().having(
            (e) => e.reason,
            'reason',
            SenderKeyFailure.expired,
          ),
        ),
      );
      final record = await keys.manager(_group, _alice);
      expect(
        (record.toJson()['$_group:$_alice'] as Map)['states'] as List,
        hasLength(1),
      );
    });

    test('new chains are added, at most five kept', () async {
      for (var i = 0; i < 6; i++) {
        await keys.install(
          _group,
          _alice,
          Gv2SenderKeyBody(
            chainId: 100 + i,
            iteration: 0,
            chainKey: gv2TestSha('chain $i'),
            signingKey: gv2TestSha('signing $i'),
          ),
        );
      }
      final json = (await keys.manager(_group, _alice)).toJson();
      final chains = [
        for (final s in (json['$_group:$_alice'] as Map)['states'] as List)
          (s as Map)['chainId'],
      ];
      expect(chains, [105, 104, 103, 102, 101]);
    });

    test('two installs at once both land', () async {
      await Future.wait([
        for (var i = 0; i < 2; i++)
          keys.install(
            _group,
            _alice,
            Gv2SenderKeyBody(
              chainId: 200 + i,
              iteration: 0,
              chainKey: gv2TestSha('parallel $i'),
              signingKey: gv2TestSha('parallel signing $i'),
            ),
          ),
      ]);
      final json = (await keys.manager(_group, _alice)).toJson();
      final chains = {
        for (final s in (json['$_group:$_alice'] as Map)['states'] as List)
          (s as Map)['chainId'],
      };
      expect(chains, {200, 201});
    });

    test('a manager\'s change is stored only when saved', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      await keys.install(_group, _alice, key);
      final message = await aliceSends('once');
      final m = await keys.manager(_group, _alice);
      m.decryptBoundGroupMessage(_group, _alice, message, _binding);
      // Not saved: the stored chain has not moved.
      final stored = (await keys.manager(_group, _alice)).toJson();
      expect(
        (((stored['$_group:$_alice'] as Map)['states'] as List).single
            as Map)['iteration'],
        0,
      );
      await keys.save(_group, _alice, m);
      final saved = (await keys.manager(_group, _alice)).toJson();
      expect(
        (((saved['$_group:$_alice'] as Map)['states'] as List).single
            as Map)['iteration'],
        1,
      );
      // Saving a record the manager does not hold is a bug, not a no-op.
      expect(() => keys.save(_group, _bob, m), throwsStateError);
    });

    test('keys of one sender, or of one group, are separate', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      await keys.install(_group, _alice, key);
      final other = gv2Hex(gv2TestSha('another group'));
      expect(
        (await keys.manager(other, _alice)).hasSenderKey(other, _alice),
        isFalse,
      );
      expect(
        (await keys.manager(_group, _bob)).hasSenderKey(_group, _bob),
        isFalse,
      );
      await keys.forget(_group, _alice);
      expect(
        (await keys.manager(_group, _alice)).hasSenderKey(_group, _alice),
        isFalse,
      );
    });
  });

  group('own key', () {
    test(
      'a new own key keeps the earlier chains; the current one is the new',
      () async {
        final first = await aliceKeys.createOwn(_group, _alice);
        await aliceSends('x');
        final second = await aliceKeys.createOwn(_group, _alice);
        expect(second.chainId, isNot(first.chainId));
        final current = (await aliceKeys.ownCurrent(_group, _alice))!;
        expect(current.chainId, second.chainId);
        expect(current.iteration, 0);
        final json = (await aliceKeys.manager(_group, _alice)).toJson();
        expect(
          ((json['$_group:$_alice'] as Map)['states'] as List),
          hasLength(2),
        );
      },
    );

    test('a received key is not an own key', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      await keys.install(_group, _alice, key);
      expect(await keys.ownCurrent(_group, _alice), isNull);
      expect(await keys.ownCurrent(_group, _bob), isNull);
    });

    test('the current position moves with what is sent', () async {
      await aliceKeys.createOwn(_group, _alice);
      await aliceSends('a');
      await aliceSends('b');
      expect((await aliceKeys.ownCurrent(_group, _alice))!.iteration, 2);
    });
  });

  group('deliveries', () {
    test('the key first given to a member stays the one given', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      await aliceKeys.recordDelivery(_group, _bob, key, nowMs: 1);
      await aliceSends('moves the chain');
      final later = (await aliceKeys.ownCurrent(_group, _alice))!;
      await aliceKeys.recordDelivery(_group, _bob, later, nowMs: 2);
      final given = (await aliceKeys.delivered(_group, _bob, key.chainId))!;
      expect(given.encode(), key.encode());
      expect(await aliceKeys.delivered(_group, _bob, key.chainId + 1), isNull);
      expect(await aliceKeys.delivered(_group, _alice, key.chainId), isNull);
    });

    test('what was given can be forgotten for one member or for all', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      await aliceKeys.recordDelivery(_group, _bob, key, nowMs: 1);
      await aliceKeys.recordDelivery(_group, _alice, key, nowMs: 1);
      await aliceKeys.forgetDeliveries(_group, member: _bob);
      expect(await aliceKeys.delivered(_group, _bob, key.chainId), isNull);
      expect(await aliceKeys.delivered(_group, _alice, key.chainId), isNotNull);
      await aliceKeys.forgetDeliveries(_group);
      expect(await aliceKeys.delivered(_group, _alice, key.chainId), isNull);
    });
  });

  group('reading and erasing', () {
    test(
      'a read stores the moved chain; a failed read stores nothing',
      () async {
        final key = await aliceKeys.createOwn(_group, _alice);
        await keys.install(_group, _alice, key);
        final message = await aliceSends('once');
        Uint8List open(SenderKeyManager m) =>
            m.decryptBoundGroupMessage(_group, _alice, message, _binding);

        final other = gv2TestSha('another binding');
        await expectLater(
          keys.read(
            _group,
            _alice,
            (m) => m.decryptBoundGroupMessage(_group, _alice, message, other),
          ),
          throwsA(isA<SenderKeyException>()),
        );
        expect(utf8.decode(await keys.read(_group, _alice, open)), 'once');
        // Its key is spent.
        await expectLater(
          keys.read(_group, _alice, open),
          throwsA(
            isA<SenderKeyException>().having(
              (e) => e.reason,
              'reason',
              SenderKeyFailure.expired,
            ),
          ),
        );
      },
    );

    test('a key installed while a message is being read is not lost', () async {
      final key = await aliceKeys.createOwn(_group, _alice);
      await keys.install(_group, _alice, key);
      final message = await aliceSends('one');
      final rotated = await aliceKeys.createOwn(_group, _alice);
      await Future.wait([
        keys.read(
          _group,
          _alice,
          (m) => m.decryptBoundGroupMessage(_group, _alice, message, _binding),
        ),
        keys.install(_group, _alice, rotated),
      ]);
      final json = (await keys.manager(_group, _alice)).toJson();
      final states = (json['$_group:$_alice'] as Map)['states'] as List;
      expect(
        {for (final s in states) (s as Map)['chainId']},
        {key.chainId, rotated.chainId},
      );
      expect(
        states.firstWhere(
          (s) => (s as Map)['chainId'] == key.chainId,
        )['iteration'],
        1,
      );
    });

    test(
      'keepOnly erases the keys and delivery records of everyone else',
      () async {
        const c = 'snow00000000000000000000000000000ca7';
        expect(c.length, 36);
        final own = await keys.createOwn(_group, _bob);
        for (final sender in [_alice, c]) {
          await keys.install(
            _group,
            sender,
            Gv2SenderKeyBody(
              chainId: 7,
              iteration: 0,
              chainKey: gv2TestSha('chain of $sender'),
              signingKey: gv2TestSha('signing of $sender'),
            ),
          );
          await keys.recordDelivery(_group, sender, own, nowMs: 1);
        }
        expect(await keys.deliveredTo(_group, own.chainId), {_alice, c});
        expect(await keys.deliveredTo(_group, own.chainId + 1), isEmpty);

        await keys.keepOnly(_group, {_alice}, me: _bob);
        expect(await keys.deliveredTo(_group, own.chainId), {_alice});
        expect(
          (await keys.manager(_group, c)).hasSenderKey(_group, c),
          isFalse,
        );
        expect(
          (await keys.manager(_group, _alice)).hasSenderKey(_group, _alice),
          isTrue,
        );
        expect(await keys.ownCurrent(_group, _bob), isNotNull);

        // Nobody left: everything but this device's own key goes.
        await keys.keepOnly(_group, {}, me: _bob);
        expect(await keys.deliveredTo(_group, own.chainId), isEmpty);
        expect(
          (await keys.manager(_group, _alice)).hasSenderKey(_group, _alice),
          isFalse,
        );
        expect(await keys.ownCurrent(_group, _bob), isNotNull);
      },
    );
  });

  test('the stored keys read v4 messages only: a message of another format '
      'under the same key is refused', () async {
    final key = await aliceKeys.createOwn(_group, _alice);
    await keys.install(_group, _alice, key);
    final m = await keys.manager(_group, _alice);
    // A message that does not start with 0x04 is malformed (0x03 was the
    // wire format of the removed v1 groups).
    final v3Message = Uint8List.fromList([0x03, ...Uint8List(200)]);
    expect(
      () => m.decryptBoundGroupMessage(_group, _alice, v3Message, _binding),
      throwsA(
        isA<SenderKeyException>().having(
          (e) => e.reason,
          'reason',
          SenderKeyFailure.malformed,
        ),
      ),
    );
  });
}
