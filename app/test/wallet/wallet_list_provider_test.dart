/// @file        wallet_list_provider_test.dart
/// @description WalletIndexNotifier + ActiveWalletController 통합 unit
///              테스트. ProviderContainer + FakeFlutterSecureStorage 로
///              storage 격리. Phase 2A 의 single source 동작 검증.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-25

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/wallet/core/secure_wallet_storage.dart';
import 'package:snowchat/features/wallet/models/wallet_account_model.dart';
import 'package:snowchat/features/wallet/models/wallet_index.dart';
import 'package:snowchat/features/wallet/models/wallet_index_exceptions.dart';
import 'package:snowchat/features/wallet/providers/wallet_list_provider.dart';
import 'package:snowchat/features/wallet/wallet_provider.dart'
    show secureWalletStorageProvider;

class _FakeStoragePlatform extends FlutterSecureStoragePlatform {
  final Map<String, String> data = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    data[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async =>
      data[key];

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    data.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async =>
      data.containsKey(key);

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async =>
      Map.of(data);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    data.clear();
  }
}

WalletEntry _makeEntry({
  required String id,
  required String address,
  required WalletKind kind,
  required WalletRole role,
  int? derivationAccountIndex,
  bool hidden = false,
  String? label,
}) {
  return WalletEntry(
    id: id,
    address: address,
    kind: kind,
    role: role,
    label: label ?? 'Test',
    createdAtMs: 1700000000000,
    derivationAccountIndex: derivationAccountIndex,
    hidden: hidden,
  );
}

WalletIndex _seedIndex() {
  final primary = _makeEntry(
    id: 'wal_primary',
    address: 'PrimAddr',
    kind: WalletKind.derived,
    role: WalletRole.primary,
    derivationAccountIndex: 0,
    label: 'Main Wallet',
  );
  final sub = _makeEntry(
    id: 'wal_sub_1',
    address: 'SubAddr1',
    kind: WalletKind.derived,
    role: WalletRole.sub,
    derivationAccountIndex: 1,
    label: 'Account 2',
  );
  return WalletIndex(
    entries: [primary, sub],
    primaryId: 'wal_primary',
    defaultId: 'wal_primary',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeStoragePlatform fakePlatform;
  late SecureWalletStorage storage;
  late ProviderContainer container;

  setUp(() async {
    fakePlatform = _FakeStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakePlatform;
    storage = SecureWalletStorage(storage: const FlutterSecureStorage());
    container = ProviderContainer(
      overrides: [
        secureWalletStorageProvider.overrideWithValue(storage),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  Future<void> _seedStorage(WalletIndex idx) async {
    await storage.writeWalletIndexJson(jsonEncode(idx.toJson()));
  }

  group('WalletIndexNotifier — build', () {
    test('storage 비어있음 → WalletIndexCorruptedException', () async {
      await expectLater(
        container.read(walletIndexProvider.future),
        throwsA(isA<WalletIndexCorruptedException>()),
      );
    });

    test('정상 storage → fromJson 결과 반환', () async {
      final seed = _seedIndex();
      await _seedStorage(seed);

      final loaded = await container.read(walletIndexProvider.future);
      expect(loaded.primaryId, 'wal_primary');
      expect(loaded.entries.length, 2);
      expect(loaded.defaultId, 'wal_primary');
    });
  });

  group('WalletIndexNotifier — setDefault', () {
    test('정상 변경 + storage persist', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      await container
          .read(walletIndexProvider.notifier)
          .setDefault('wal_sub_1');

      final loaded = container.read(walletIndexProvider).valueOrNull!;
      expect(loaded.defaultId, 'wal_sub_1');

      // 새 container 로 재로드 — 영속 검증
      final container2 = ProviderContainer(
        overrides: [secureWalletStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container2.dispose);
      final reloaded = await container2.read(walletIndexProvider.future);
      expect(reloaded.defaultId, 'wal_sub_1');
    });

    test('존재하지 않는 walletId → WalletNotFoundException', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      expect(
        () => container
            .read(walletIndexProvider.notifier)
            .setDefault('wal_unknown'),
        throwsA(isA<WalletNotFoundException>()),
      );
    });
  });

  group('WalletIndexNotifier — addEntry', () {
    test('정상 추가 + persist', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      final newSub = _makeEntry(
        id: 'wal_sub_2',
        address: 'SubAddr2',
        kind: WalletKind.derived,
        role: WalletRole.sub,
        derivationAccountIndex: 2,
      );
      await container.read(walletIndexProvider.notifier).addEntry(newSub);

      final loaded = container.read(walletIndexProvider).valueOrNull!;
      expect(loaded.entries.length, 3);
      expect(loaded.findById('wal_sub_2'), isNotNull);
    });

    test('중복 address → DuplicateWalletException', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      final dup = _makeEntry(
        id: 'wal_dup',
        address: 'SubAddr1', // 이미 존재
        kind: WalletKind.imported,
        role: WalletRole.sub,
      );
      expect(
        () => container.read(walletIndexProvider.notifier).addEntry(dup),
        throwsA(isA<DuplicateWalletException>()),
      );
    });
  });

  group('WalletIndexNotifier — removeEntry', () {
    test('imported sub 제거 → entry + secret 둘 다 삭제', () async {
      // seed: primary + imported sub
      final imported = _makeEntry(
        id: 'wal_imp',
        address: 'ImpAddr',
        kind: WalletKind.imported,
        role: WalletRole.sub,
      );
      final idx = WalletIndex(
        entries: [
          _seedIndex().primaryEntry,
          imported,
        ],
        primaryId: 'wal_primary',
        defaultId: 'wal_primary',
      );
      await _seedStorage(idx);
      await storage.writeImportedSecret(
        'wal_imp',
        Uint8List.fromList(List.filled(32, 0x42)),
      );
      await container.read(walletIndexProvider.future);

      await container
          .read(walletIndexProvider.notifier)
          .removeEntry('wal_imp');

      final loaded = container.read(walletIndexProvider).valueOrNull!;
      expect(loaded.findById('wal_imp'), isNull);
      expect(await storage.readImportedSecret('wal_imp'), isNull);
    });

    test('primary 제거 시도 → CannotRemovePrimaryException', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      expect(
        () => container
            .read(walletIndexProvider.notifier)
            .removeEntry('wal_primary'),
        throwsA(isA<CannotRemovePrimaryException>()),
      );
    });

    test('default 였던 sub 제거 → primary 로 fallback', () async {
      await _seedStorage(_seedIndex().withDefault('wal_sub_1'));
      await container.read(walletIndexProvider.future);

      await container
          .read(walletIndexProvider.notifier)
          .removeEntry('wal_sub_1');

      final loaded = container.read(walletIndexProvider).valueOrNull!;
      expect(loaded.defaultId, 'wal_primary');
    });
  });

  group('WalletIndexNotifier — hideDerived / unhideDerived', () {
    test('hide → visibleEntries 에서 사라짐, derivedEntries 에는 남음', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      await container
          .read(walletIndexProvider.notifier)
          .hideDerived('wal_sub_1');

      final loaded = container.read(walletIndexProvider).valueOrNull!;
      expect(loaded.visibleEntries.length, 1);
      expect(loaded.derivedEntries.length, 2);
      expect(loaded.findById('wal_sub_1')!.hidden, isTrue);
    });

    test('hide primary → CannotRemovePrimaryException', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      expect(
        () => container
            .read(walletIndexProvider.notifier)
            .hideDerived('wal_primary'),
        throwsA(isA<CannotRemovePrimaryException>()),
      );
    });

    test('unhide(index) → hidden=false 복원', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);
      await container
          .read(walletIndexProvider.notifier)
          .hideDerived('wal_sub_1');

      await container
          .read(walletIndexProvider.notifier)
          .unhideDerived(1);

      final loaded = container.read(walletIndexProvider).valueOrNull!;
      expect(loaded.findById('wal_sub_1')!.hidden, isFalse);
      expect(loaded.visibleEntries.length, 2);
    });
  });

  group('WalletIndexNotifier — rename', () {
    test('정상 라벨 변경', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      await container
          .read(walletIndexProvider.notifier)
          .rename('wal_sub_1', 'Trading');

      final loaded = container.read(walletIndexProvider).valueOrNull!;
      expect(loaded.findById('wal_sub_1')!.label, 'Trading');
    });

    test('빈 문자열 → noop', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);
      final before = container.read(walletIndexProvider).valueOrNull!;

      await container
          .read(walletIndexProvider.notifier)
          .rename('wal_sub_1', '   ');

      final after = container.read(walletIndexProvider).valueOrNull!;
      expect(after.findById('wal_sub_1')!.label,
          before.findById('wal_sub_1')!.label);
    });
  });

  group('ActiveWalletController', () {
    test('hydrate — storage 미존재 → primary 로 fallback + persist', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      await container.read(activeWalletControllerProvider).hydrate();

      expect(container.read(activeWalletIdProvider), 'wal_primary');
      expect(await storage.readActiveWalletId(), 'wal_primary');
    });

    test('hydrate — storage 에 last-seen 존재 → 그대로 사용', () async {
      await _seedStorage(_seedIndex());
      await storage.writeActiveWalletId('wal_sub_1');
      await container.read(walletIndexProvider.future);

      await container.read(activeWalletControllerProvider).hydrate();

      expect(container.read(activeWalletIdProvider), 'wal_sub_1');
    });

    test('set — 메모리 + storage 동시 갱신', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      await container.read(activeWalletControllerProvider).set('wal_sub_1');

      expect(container.read(activeWalletIdProvider), 'wal_sub_1');
      expect(await storage.readActiveWalletId(), 'wal_sub_1');
    });
  });

  group('Derived providers', () {
    test('defaultWalletAddressProvider — index.defaultEntry 따라감', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);

      expect(container.read(defaultWalletAddressProvider), 'PrimAddr');

      await container
          .read(walletIndexProvider.notifier)
          .setDefault('wal_sub_1');
      expect(container.read(defaultWalletAddressProvider), 'SubAddr1');
    });

    test('activeWalletAddressProvider — activeId 변경 반영', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);
      await container.read(activeWalletControllerProvider).set('wal_sub_1');

      expect(container.read(activeWalletAddressProvider), 'SubAddr1');
    });

    test('visibleWalletEntriesProvider — hidden 제외', () async {
      await _seedStorage(_seedIndex());
      await container.read(walletIndexProvider.future);
      await container
          .read(walletIndexProvider.notifier)
          .hideDerived('wal_sub_1');

      final visible = container.read(visibleWalletEntriesProvider);
      expect(visible.length, 1);
      expect(visible.first.id, 'wal_primary');
    });
  });
}
