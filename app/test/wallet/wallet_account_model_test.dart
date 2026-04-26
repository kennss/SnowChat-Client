/// @file        wallet_account_model_test.dart
/// @description Multi-Wallet 데이터 모델 unit tests — WalletEntry,
///              WalletKind, WalletRole, WalletLabels 의 직렬화 + invariant.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-25

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/wallet/models/wallet_account_model.dart';

void main() {
  group('WalletEntry serialization', () {
    test('derived primary roundtrip', () {
      final original = WalletEntry(
        id: 'wal_abc123def456',
        address: 'GjT7Aa1bC2d3E4f5G6h7I8j9K0l1M2n3O4p5Q6r7RyKp',
        kind: WalletKind.derived,
        role: WalletRole.primary,
        label: WalletLabels.primary,
        createdAtMs: 1729870234567,
        derivationAccountIndex: 0,
      );
      final json = original.toJson();
      final restored = WalletEntry.fromJson(json);
      expect(restored, original);
    });

    test('derived sub roundtrip', () {
      final original = WalletEntry(
        id: 'wal_subAcc789xyz',
        address: '9zyGkPtmiN8iB5yixooqJdtLoQXVHRCrYk5Uch5ewP82',
        kind: WalletKind.derived,
        role: WalletRole.sub,
        label: WalletLabels.derivedAccount(2),
        createdAtMs: 1729870300000,
        derivationAccountIndex: 2,
        hidden: false,
      );
      final restored = WalletEntry.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.label, 'Account 3'); // 2 + 1
    });

    test('imported sub roundtrip — no derivation index', () {
      final original = WalletEntry(
        id: 'wal_imported001',
        address: 'hLtQ8WP9LgiAGAbXGVrZC4ZzF4aavhcafQryh5n8D5Y',
        kind: WalletKind.imported,
        role: WalletRole.sub,
        label: 'Phantom',
        createdAtMs: 1729870400000,
      );
      final restored = WalletEntry.fromJson(original.toJson());
      expect(restored, original);
      expect(restored.derivationAccountIndex, isNull);
    });

    test('hidden=false 는 JSON 에서 omit 됨 (size optimization)', () {
      final original = WalletEntry(
        id: 'wal_x',
        address: 'addr',
        kind: WalletKind.derived,
        role: WalletRole.sub,
        label: 'L',
        createdAtMs: 0,
        derivationAccountIndex: 1,
      );
      expect(original.toJson().containsKey('hidden'), isFalse);
    });

    test('hidden=true 는 JSON 에 포함', () {
      final original = WalletEntry(
        id: 'wal_x',
        address: 'addr',
        kind: WalletKind.derived,
        role: WalletRole.sub,
        label: 'L',
        createdAtMs: 0,
        derivationAccountIndex: 1,
        hidden: true,
      );
      expect(original.toJson()['hidden'], true);
    });

    test('unknown kind throws FormatException', () {
      expect(
        () => WalletEntry.fromJson({
          'id': 'x',
          'address': 'a',
          'kind': 'unknown_kind',
          'role': 'sub',
          'label': 'L',
          'createdAtMs': 0,
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('WalletEntry invariants', () {
    test('derived 는 derivationAccountIndex 필수', () {
      expect(
        () => WalletEntry(
          id: 'x',
          address: 'a',
          kind: WalletKind.derived,
          role: WalletRole.sub,
          label: 'L',
          createdAtMs: 0,
          // derivationAccountIndex 누락
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('imported 는 derivationAccountIndex null', () {
      expect(
        () => WalletEntry(
          id: 'x',
          address: 'a',
          kind: WalletKind.imported,
          role: WalletRole.sub,
          label: 'L',
          createdAtMs: 0,
          derivationAccountIndex: 1, // imported 인데 index 줌 → assert
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('primary 는 derivationAccountIndex==0 필수', () {
      expect(
        () => WalletEntry(
          id: 'x',
          address: 'a',
          kind: WalletKind.derived,
          role: WalletRole.primary,
          label: 'L',
          createdAtMs: 0,
          derivationAccountIndex: 1, // primary 인데 0 아님
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('WalletEntry copyWith', () {
    test('label 만 변경', () {
      final original = WalletEntry(
        id: 'x',
        address: 'a',
        kind: WalletKind.derived,
        role: WalletRole.sub,
        label: 'L',
        createdAtMs: 0,
        derivationAccountIndex: 1,
      );
      final renamed = original.copyWith(label: 'New Label');
      expect(renamed.label, 'New Label');
      expect(renamed.id, original.id);
      expect(renamed.address, original.address);
    });

    test('hidden=true 토글', () {
      final original = WalletEntry(
        id: 'x',
        address: 'a',
        kind: WalletKind.derived,
        role: WalletRole.sub,
        label: 'L',
        createdAtMs: 0,
        derivationAccountIndex: 1,
      );
      expect(original.hidden, false);
      final hidden = original.copyWith(hidden: true);
      expect(hidden.hidden, true);
      expect(hidden.id, original.id);
    });
  });

  group('WalletLabels', () {
    test('Phantom 호환 라벨링 — 0-based index → 1-based 표시', () {
      expect(WalletLabels.derivedAccount(0), 'Account 1');
      expect(WalletLabels.derivedAccount(1), 'Account 2');
      expect(WalletLabels.derivedAccount(4), 'Account 5');
    });

    test('legacy primary 라벨은 일반 imported 와 차별화', () {
      expect(WalletLabels.legacyPrimary, isNot(WalletLabels.importedDefault));
      expect(WalletLabels.legacyPrimary.contains('Legacy'), isTrue);
    });
  });
}
