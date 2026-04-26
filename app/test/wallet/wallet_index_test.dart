/// @file        wallet_index_test.dart
/// @description Multi-Wallet 의 단일 source of truth 컬렉션 테스트.
///              직렬화 + invariants + mutators + nextDerivationAccountIndex
///              monotonic + Open Decision 한도 강제.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-25

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/wallet/models/wallet_account_model.dart';
import 'package:snowchat/features/wallet/models/wallet_index.dart';
import 'package:snowchat/features/wallet/models/wallet_index_exceptions.dart';

WalletEntry _primary({String id = 'wal_primary'}) => WalletEntry(
      id: id,
      address: 'PrimaryAddress11111111111111111111111111111',
      kind: WalletKind.derived,
      role: WalletRole.primary,
      label: WalletLabels.primary,
      createdAtMs: 1729870000000,
      derivationAccountIndex: 0,
    );

WalletEntry _derivedSub({
  required String id,
  required int index,
  required String address,
  bool hidden = false,
}) =>
    WalletEntry(
      id: id,
      address: address,
      kind: WalletKind.derived,
      role: WalletRole.sub,
      label: WalletLabels.derivedAccount(index),
      createdAtMs: 1729870000000 + index,
      derivationAccountIndex: index,
      hidden: hidden,
    );

WalletEntry _imported({
  required String id,
  required String address,
  String label = 'Phantom',
}) =>
    WalletEntry(
      id: id,
      address: address,
      kind: WalletKind.imported,
      role: WalletRole.sub,
      label: label,
      createdAtMs: 1729870000000,
    );

void main() {
  group('WalletIndex invariants', () {
    test('I1: primaryId 가 entry 와 매치돼야 함', () {
      expect(
        () => WalletIndex(
          entries: [_primary()],
          primaryId: 'wal_orphan_id', // entries 에 없음
          defaultId: 'wal_primary',
        ),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('I1: primaryId 의 entry 는 role==primary 여야', () {
      final entry = _derivedSub(
        id: 'wal_x',
        index: 1,
        address: 'a',
      );
      expect(
        () => WalletIndex(
          entries: [_primary(), entry],
          primaryId: 'wal_x', // sub entry 를 primaryId 로 → I1 위반
          defaultId: 'wal_x',
        ),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('I2: defaultId 가 entries 에 없으면 throw', () {
      expect(
        () => WalletIndex(
          entries: [_primary()],
          primaryId: 'wal_primary',
          defaultId: 'wal_missing',
        ),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('I3: primary 가 정확히 1개 — 0개', () {
      expect(
        () => WalletIndex(
          entries: [
            _derivedSub(id: 'wal_only_sub', index: 1, address: 'a'),
          ],
          primaryId: 'wal_only_sub',
          defaultId: 'wal_only_sub',
        ),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('I3: primary 가 정확히 1개 — 2개', () {
      final p1 = _primary(id: 'wal_p1');
      final p2 = _primary(id: 'wal_p2').copyWith(
        // address 다르게 (I4 충돌 회피)
        address: 'AnotherPrimary',
      );
      expect(
        () => WalletIndex(
          entries: [p1, p2],
          primaryId: 'wal_p1',
          defaultId: 'wal_p1',
        ),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('I4: 중복 id throw', () {
      final p = _primary();
      final dup = _derivedSub(id: 'wal_primary', index: 1, address: 'a');
      expect(
        () => WalletIndex(
          entries: [p, dup],
          primaryId: 'wal_primary',
          defaultId: 'wal_primary',
        ),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('I4: 중복 address throw', () {
      final p = _primary();
      final dupAddr = _derivedSub(
        id: 'wal_x',
        index: 1,
        address: p.address, // 같은 주소
      );
      expect(
        () => WalletIndex(
          entries: [p, dupAddr],
          primaryId: 'wal_primary',
          defaultId: 'wal_primary',
        ),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('정상 케이스: primary + 2 sub + 1 imported', () {
      final p = _primary();
      final s1 = _derivedSub(id: 'wal_s1', index: 1, address: 'addr1');
      final s2 = _derivedSub(id: 'wal_s2', index: 2, address: 'addr2');
      final imp = _imported(id: 'wal_imp', address: 'addr3');
      final idx = WalletIndex(
        entries: [p, s1, s2, imp],
        primaryId: p.id,
        defaultId: imp.id,
      );
      expect(idx.entries.length, 4);
      expect(idx.primaryEntry.id, p.id);
      expect(idx.defaultEntry.id, imp.id);
    });
  });

  group('Lookups + queries', () {
    final p = _primary();
    final s1 = _derivedSub(id: 'wal_s1', index: 1, address: 'addr1');
    final s2 = _derivedSub(
      id: 'wal_s2',
      index: 2,
      address: 'addr2',
      hidden: true,
    );
    final imp = _imported(id: 'wal_imp', address: 'addr3');
    final idx = WalletIndex(
      entries: [p, s1, s2, imp],
      primaryId: p.id,
      defaultId: p.id,
    );

    test('visibleEntries excludes hidden', () {
      expect(idx.visibleEntries.length, 3);
      expect(idx.visibleEntries.contains(s2), isFalse);
    });

    test('derivedEntries includes hidden', () {
      expect(idx.derivedEntries.length, 3);
      expect(idx.derivedEntries.contains(s2), isTrue);
    });

    test('importedEntries 만 imported', () {
      expect(idx.importedEntries.length, 1);
      expect(idx.importedEntries.single, imp);
    });

    test('findByAddress / findById', () {
      expect(idx.findByAddress('addr3'), imp);
      expect(idx.findByAddress('xxx'), isNull);
      expect(idx.findById('wal_s1'), s1);
      expect(idx.findById('xxx'), isNull);
    });
  });

  group('nextDerivationAccountIndex (C-2 monotonic)', () {
    test('primary 만 있으면 next = 1', () {
      final idx = WalletIndex(
        entries: [_primary()],
        primaryId: 'wal_primary',
        defaultId: 'wal_primary',
      );
      expect(idx.nextDerivationAccountIndex(), 1);
    });

    test('hidden 도 카운트 — gap 재사용 금지', () {
      final p = _primary();
      final s1 = _derivedSub(id: 'wal_s1', index: 1, address: 'a1');
      final s2Hidden = _derivedSub(
        id: 'wal_s2',
        index: 2,
        address: 'a2',
        hidden: true,
      );
      final idx = WalletIndex(
        entries: [p, s1, s2Hidden],
        primaryId: p.id,
        defaultId: p.id,
      );
      // hidden index=2 도 max 에 포함 → next = 3 (gap 재사용 금지)
      expect(idx.nextDerivationAccountIndex(), 3);
    });

    test('large gap 정상 처리', () {
      final p = _primary();
      final s = _derivedSub(id: 'wal_big', index: 7, address: 'a');
      final idx = WalletIndex(
        entries: [p, s],
        primaryId: p.id,
        defaultId: p.id,
      );
      expect(idx.nextDerivationAccountIndex(), 8);
    });
  });

  group('mutators', () {
    test('withEntry — 신규 sub 추가', () {
      final p = _primary();
      final idx = WalletIndex(
        entries: [p],
        primaryId: p.id,
        defaultId: p.id,
      );
      final sub = _derivedSub(id: 'wal_s1', index: 1, address: 'a1');
      final next = idx.withEntry(sub);
      expect(next.entries.length, 2);
      expect(next.findById('wal_s1'), sub);
    });

    test('withEntry — primary 추가 시도 throw', () {
      final p = _primary();
      final idx = WalletIndex(
        entries: [p],
        primaryId: p.id,
        defaultId: p.id,
      );
      final p2 = _primary(id: 'wal_p2').copyWith(address: 'OtherAddr');
      expect(
        () => idx.withEntry(p2),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('withEntry — duplicate address throw', () {
      final p = _primary();
      final s = _derivedSub(id: 'wal_s', index: 1, address: 'a1');
      final idx = WalletIndex(
        entries: [p, s],
        primaryId: p.id,
        defaultId: p.id,
      );
      final dup = _imported(id: 'wal_imp', address: 'a1');
      expect(
        () => idx.withEntry(dup),
        throwsA(isA<DuplicateWalletException>()),
      );
    });

    test('withoutEntry — Primary 제거 시도 throw (P0 C-3)', () {
      final p = _primary();
      final idx = WalletIndex(
        entries: [p],
        primaryId: p.id,
        defaultId: p.id,
      );
      expect(
        () => idx.withoutEntry(p.id),
        throwsA(isA<CannotRemovePrimaryException>()),
      );
    });

    test('withoutEntry — Default 제거 시 Primary 로 fallback', () {
      final p = _primary();
      final imp = _imported(id: 'wal_imp', address: 'a1');
      final idx = WalletIndex(
        entries: [p, imp],
        primaryId: p.id,
        defaultId: imp.id, // imported 가 default
      );
      final next = idx.withoutEntry(imp.id);
      expect(next.defaultId, p.id); // fallback
    });

    test('withDefault — 정상 변경', () {
      final p = _primary();
      final imp = _imported(id: 'wal_imp', address: 'a1');
      final idx = WalletIndex(
        entries: [p, imp],
        primaryId: p.id,
        defaultId: p.id,
      );
      final next = idx.withDefault(imp.id);
      expect(next.defaultId, imp.id);
    });

    test('withDefault — 존재 안 하는 id 에 throw', () {
      final p = _primary();
      final idx = WalletIndex(
        entries: [p],
        primaryId: p.id,
        defaultId: p.id,
      );
      expect(
        () => idx.withDefault('wal_missing'),
        throwsA(isA<WalletNotFoundException>()),
      );
    });

    test('updateEntry — 라벨 변경', () {
      final p = _primary();
      final s = _derivedSub(id: 'wal_s', index: 1, address: 'a');
      final idx = WalletIndex(
        entries: [p, s],
        primaryId: p.id,
        defaultId: p.id,
      );
      final next =
          idx.updateEntry(s.id, (e) => e.copyWith(label: 'Trading'));
      expect(next.findById(s.id)!.label, 'Trading');
    });
  });

  group('Open Decision 한도', () {
    test('canAddDerived — 5 미만일 때 true', () {
      final p = _primary();
      final idx = WalletIndex(
        entries: [p],
        primaryId: p.id,
        defaultId: p.id,
      );
      expect(idx.canAddDerived, isTrue); // 1 derived (primary)
    });

    test('canAddDerived — 5 도달 시 false (hidden 포함)', () {
      final p = _primary(); // index 0
      final entries = <WalletEntry>[p];
      for (int i = 1; i <= 4; i++) {
        entries.add(_derivedSub(
          id: 'wal_d$i',
          index: i,
          address: 'addr_d$i',
          hidden: i == 2 || i == 3, // 일부 hidden
        ));
      }
      final idx = WalletIndex(
        entries: entries,
        primaryId: p.id,
        defaultId: p.id,
      );
      // primary + 4 derived sub = 5 derived total
      expect(idx.derivedEntries.length, 5);
      expect(idx.canAddDerived, isFalse);
    });

    test('canAddImported — 10 미만일 때 true', () {
      final p = _primary();
      final entries = <WalletEntry>[p];
      for (int i = 0; i < 9; i++) {
        entries.add(_imported(id: 'wal_imp$i', address: 'imp_addr_$i'));
      }
      final idx = WalletIndex(
        entries: entries,
        primaryId: p.id,
        defaultId: p.id,
      );
      expect(idx.importedEntries.length, 9);
      expect(idx.canAddImported, isTrue);
    });

    test('canAddImported — 10 도달 시 false', () {
      final p = _primary();
      final entries = <WalletEntry>[p];
      for (int i = 0; i < 10; i++) {
        entries.add(_imported(id: 'wal_imp$i', address: 'imp_addr_$i'));
      }
      final idx = WalletIndex(
        entries: entries,
        primaryId: p.id,
        defaultId: p.id,
      );
      expect(idx.canAddImported, isFalse);
    });
  });

  group('serialization', () {
    test('전체 roundtrip — primary + sub + imported + metadata', () {
      final p = _primary();
      final s = _derivedSub(id: 'wal_s', index: 1, address: 'a');
      final imp = _imported(id: 'wal_imp', address: 'b');
      final original = WalletIndex(
        entries: [p, s, imp],
        primaryId: p.id,
        defaultId: imp.id,
        metadata: const WalletIndexMetadata(
          legacyKeysPendingCleanup: true,
          migratedAtMs: 1729870500000,
        ),
      );
      final json = original.toJson();
      final restored = WalletIndex.fromJson(json);
      expect(restored.entries.length, original.entries.length);
      expect(restored.primaryId, original.primaryId);
      expect(restored.defaultId, original.defaultId);
      expect(restored.metadata.legacyKeysPendingCleanup, isTrue);
      expect(restored.metadata.migratedAtMs, 1729870500000);
    });

    test('version mismatch → throw', () {
      expect(
        () => WalletIndex.fromJson({
          'version': 99,
          'entries': [],
          'primaryId': 'x',
          'defaultId': 'x',
        }),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('markLegacyKeysCleaned — flag false 로', () {
      final p = _primary();
      final idx = WalletIndex(
        entries: [p],
        primaryId: p.id,
        defaultId: p.id,
        metadata: const WalletIndexMetadata(legacyKeysPendingCleanup: true),
      );
      expect(idx.metadata.legacyKeysPendingCleanup, isTrue);
      final cleaned = idx.markLegacyKeysCleaned();
      expect(cleaned.metadata.legacyKeysPendingCleanup, isFalse);
    });
  });
}
