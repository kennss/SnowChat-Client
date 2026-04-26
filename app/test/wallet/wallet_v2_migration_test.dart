/// @file        wallet_v2_migration_test.dart
/// @description Multi-Wallet v1→v2 migration unit tests.
///              FakeFlutterSecureStorage 로 in-memory 시뮬레이션,
///              IdentityMnemonicReader 주입으로 외부 의존성 격리.
///              모든 audit P0/P1 fix 회귀 테스트.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-25

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/wallet/core/derivation_service.dart';
import 'package:snowchat/features/wallet/core/secure_wallet_storage.dart';
import 'package:snowchat/features/wallet/core/wallet_v2_migration.dart';
import 'package:snowchat/features/wallet/models/wallet_account_model.dart';
import 'package:snowchat/features/wallet/models/wallet_index.dart';

// 표준 BIP39 test vector. 실제 자산 보유한 mnemonic 절대 사용 금지.
const _testMnemonic =
    'legal winner thank year wave sausage worth useful legal winner '
    'thank year wave sausage worth useful legal winner thank year '
    'wave sausage worth title';

const _otherMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

/// In-memory FlutterSecureStorage replacement.
/// `flutter_secure_storage_platform_interface` 의 인터페이스 구현 — 모든
/// 호출이 Map 으로 라우팅된다.
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

void main() {
  late _FakeStoragePlatform fakePlatform;
  late SecureWalletStorage storage;

  setUp(() {
    fakePlatform = _FakeStoragePlatform();
    FlutterSecureStoragePlatform.instance = fakePlatform;
    storage = SecureWalletStorage(storage: const FlutterSecureStorage());
  });

  IdentityMnemonicReader _identityReader(String? value) =>
      () async => value;

  group('Step 1: idempotent path', () {
    test('v2 schema 이미 존재 + identity 정상 → alreadyMigrated', () async {
      // 사전 작업: v2 schema 직접 작성
      final addr =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      final entry = WalletEntry(
        id: 'wal_existing',
        address: addr,
        kind: WalletKind.derived,
        role: WalletRole.primary,
        label: WalletLabels.primary,
        createdAtMs: 1729870000000,
        derivationAccountIndex: 0,
      );
      final index = WalletIndex(
        entries: [entry],
        primaryId: 'wal_existing',
        defaultId: 'wal_existing',
      );
      await storage.writeWalletIndexJson(jsonEncode(index.toJson()));

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.alreadyMigrated);
    });

    test('v2 schema 이미 존재 + identity null → alreadyMigrated (fail-soft)',
        () async {
      final addr =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      final entry = WalletEntry(
        id: 'wal_existing',
        address: addr,
        kind: WalletKind.derived,
        role: WalletRole.primary,
        label: WalletLabels.primary,
        createdAtMs: 1729870000000,
        derivationAccountIndex: 0,
      );
      final index = WalletIndex(
        entries: [entry],
        primaryId: 'wal_existing',
        defaultId: 'wal_existing',
      );
      await storage.writeWalletIndexJson(jsonEncode(index.toJson()));

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(null),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.alreadyMigrated);
    });

    test('C-4: derived primary 의 address 가 identity 와 mismatch → '
        'primaryIntegrityViolated', () async {
      // entry 의 address 가 _testMnemonic 의 derive 결과와 다름
      final wrongAddr = await DerivationService.deriveWalletAddressAt(
        _otherMnemonic,
        0,
      );
      final entry = WalletEntry(
        id: 'wal_corrupted',
        address: wrongAddr,
        kind: WalletKind.derived,
        role: WalletRole.primary,
        label: WalletLabels.primary,
        createdAtMs: 1729870000000,
        derivationAccountIndex: 0,
      );
      final index = WalletIndex(
        entries: [entry],
        primaryId: 'wal_corrupted',
        defaultId: 'wal_corrupted',
      );
      await storage.writeWalletIndexJson(jsonEncode(index.toJson()));

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.primaryIntegrityViolated);
    });

    test('imported primary 는 integrity 검증 skip → alreadyMigrated', () async {
      final entry = WalletEntry(
        id: 'wal_imp',
        address: 'AnyImportedAddress11111111111111111111111111',
        kind: WalletKind.imported,
        role: WalletRole.primary,
        label: WalletLabels.legacyPrimary,
        createdAtMs: 1729870000000,
      );
      final index = WalletIndex(
        entries: [entry],
        primaryId: 'wal_imp',
        defaultId: 'wal_imp',
      );
      await storage.writeWalletIndexJson(jsonEncode(index.toJson()));

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      // address 가 _testMnemonic derive 결과와 달라도 imported 라 통과
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.alreadyMigrated);
    });
  });

  group('Step 2: fresh install', () {
    test('아무 키도 없음 → freshInstall', () async {
      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(null),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.freshInstall);
      // index 작성 안 됨
      expect(await storage.readWalletIndexJson(), isNull);
    });

    test('legacy mnemonic 만 있고 address 없음 → freshInstall', () async {
      await storage.saveMnemonic(_testMnemonic);
      // address 는 의도적으로 미설정
      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.freshInstall);
    });
  });

  group('Step 3-7: migration', () {
    test('Step 3a: derived match — identity == legacy mnemonic', () async {
      final addr =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      await storage.saveMnemonic(_testMnemonic);
      await storage.saveSolanaAddress(addr);
      // private key 는 derived 케이스에서 v2 secret 으로 옮겨지지 않음.

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.migratedFromV1);

      // v2 schema 검증
      final indexJson = await storage.readWalletIndexJson();
      expect(indexJson, isNotNull);
      final index = WalletIndex.fromJson(
        jsonDecode(indexJson!) as Map<String, dynamic>,
      );
      expect(index.entries.length, 1);
      final primary = index.primaryEntry;
      expect(primary.kind, WalletKind.derived);
      expect(primary.role, WalletRole.primary);
      expect(primary.label, WalletLabels.primary);
      expect(primary.derivationAccountIndex, 0);
      expect(primary.address, addr);
      expect(index.metadata.legacyKeysPendingCleanup, isTrue);

      // F-6: 레거시 키 그대로 유지
      expect(await storage.readMnemonic(), _testMnemonic);
      expect(await storage.readSolanaAddress(), addr);
    });

    test('Step 3b: mismatch — identity != legacy mnemonic → '
        'imported "Main Wallet (Legacy)"', () async {
      await storage.saveMnemonic(_otherMnemonic);
      final addr =
          await DerivationService.deriveWalletAddressAt(_otherMnemonic, 0);
      await storage.saveSolanaAddress(addr);
      final secret = Uint8List.fromList(List.generate(32, (i) => i));
      await storage.savePrivateKey(secret);

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.migratedFromV1);

      final index = WalletIndex.fromJson(jsonDecode(
        (await storage.readWalletIndexJson())!,
      ) as Map<String, dynamic>);
      final primary = index.primaryEntry;
      expect(primary.kind, WalletKind.imported);
      expect(primary.role, WalletRole.primary);
      expect(primary.label, WalletLabels.legacyPrimary);
      expect(primary.derivationAccountIndex, isNull);
      expect(primary.address, addr);

      // imported 의 secret 이 wallet_secret/<id> 에 저장됨
      final restored = await storage.readImportedSecret(primary.id);
      expect(restored, isNotNull);
      expect(restored, equals(secret));
    });

    test('Step 3b: identity null → imported "Legacy"', () async {
      await storage.saveMnemonic(_testMnemonic);
      final addr =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      await storage.saveSolanaAddress(addr);
      final secret = Uint8List.fromList(List.generate(32, (i) => i + 1));
      await storage.savePrivateKey(secret);

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(null),
      );
      final outcome = await mig.bootstrap();
      expect(outcome, BootstrapOutcome.migratedFromV1);

      final index = WalletIndex.fromJson(jsonDecode(
        (await storage.readWalletIndexJson())!,
      ) as Map<String, dynamic>);
      expect(index.primaryEntry.kind, WalletKind.imported);
      expect(index.primaryEntry.label, WalletLabels.legacyPrimary);
    });
  });

  group('F-3: bootstrap mutex (race protection)', () {
    test('동시 호출 → 단일 작업, 모두 같은 outcome', () async {
      final addr =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      await storage.saveMnemonic(_testMnemonic);
      await storage.saveSolanaAddress(addr);

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      final futures = await Future.wait([
        mig.bootstrap(),
        mig.bootstrap(),
        mig.bootstrap(),
      ]);
      expect(futures, [
        BootstrapOutcome.migratedFromV1,
        BootstrapOutcome.migratedFromV1,
        BootstrapOutcome.migratedFromV1,
      ]);
      // single primary entry — race 가 두 개 만들지 않음
      final index = WalletIndex.fromJson(jsonDecode(
        (await storage.readWalletIndexJson())!,
      ) as Map<String, dynamic>);
      expect(index.entries.length, 1);
    });
  });

  group('F-6: legacy keys deferred to v2.1.0', () {
    test('migration 직후 레거시 키 그대로 + flag true', () async {
      final addr =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      await storage.saveMnemonic(_testMnemonic);
      await storage.saveSolanaAddress(addr);

      final mig = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      await mig.bootstrap();

      // 레거시 그대로 — v1 으로 downgrade 시 read 가능 (rollback safety)
      expect(await storage.hasLegacyKeys(), isTrue);
      expect(await storage.readMnemonic(), _testMnemonic);

      // v2 metadata
      final index = WalletIndex.fromJson(jsonDecode(
        (await storage.readWalletIndexJson())!,
      ) as Map<String, dynamic>);
      expect(index.metadata.legacyKeysPendingCleanup, isTrue);
    });
  });

  group('idempotency under crash simulation', () {
    test('migration 중 step 6 후 step 7 전 crash → 다음 boot 정상', () async {
      // step 6 까지만 수동으로 시뮬: index 작성 + 레거시 keys 그대로
      final addr =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      await storage.saveMnemonic(_testMnemonic);
      await storage.saveSolanaAddress(addr);

      final mig1 = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      await mig1.bootstrap(); // 첫 마이그레이션

      // 두 번째 boot (가짜 — 새 mig 인스턴스)
      final mig2 = WalletV2Migration(
        storage: storage,
        identityReader: _identityReader(_testMnemonic),
      );
      final outcome = await mig2.bootstrap();
      expect(outcome, BootstrapOutcome.alreadyMigrated);

      // 데이터 변형 없음
      final index = WalletIndex.fromJson(jsonDecode(
        (await storage.readWalletIndexJson())!,
      ) as Map<String, dynamic>);
      expect(index.entries.length, 1);
    });
  });
}
