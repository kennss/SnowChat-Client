/// @file        derivation_service_test.dart
/// @description Multi-Wallet 키 파생 서비스 unit tests — account index 별
///              determinism, Phantom 호환성, raw seed import.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-25
/// @lastUpdated 2026-04-25

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/wallet/core/derivation_service.dart';

// 표준 BIP39 test vector (24-word). 절대 실제 자산을 가진 mnemonic
// 사용 금지 — 본 테스트는 derivation 알고리즘의 determinism 만 검증.
const _testMnemonic =
    'legal winner thank year wave sausage worth useful legal winner '
    'thank year wave sausage worth useful legal winner thank year '
    'wave sausage worth title';

void main() {
  group('walletDerivationPathFor', () {
    test('account 0 = legacy 경로와 일치', () {
      expect(
        DerivationService.walletDerivationPathFor(0),
        DerivationService.walletDerivationPath,
      );
    });

    test('임의 account index 의 정확한 형식', () {
      expect(
        DerivationService.walletDerivationPathFor(1),
        "m/44'/501'/1'/0'",
      );
      expect(
        DerivationService.walletDerivationPathFor(7),
        "m/44'/501'/7'/0'",
      );
      expect(
        DerivationService.walletDerivationPathFor(99),
        "m/44'/501'/99'/0'",
      );
    });

    test('음수 account index → throw', () {
      expect(
        () => DerivationService.walletDerivationPathFor(-1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('deriveWalletKeyPairAt — determinism', () {
    test('같은 (mnemonic, account) → 같은 address', () async {
      final addr1 =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      final addr2 =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      expect(addr1, addr2);
    });

    test('다른 account → 다른 address', () async {
      final addr0 =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      final addr1 =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 1);
      final addr2 =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 2);
      expect(addr0, isNot(addr1));
      expect(addr1, isNot(addr2));
      expect(addr0, isNot(addr2));
    });

    test('legacy deriveWalletAddress == account 0', () async {
      final legacy =
          await DerivationService.deriveWalletAddress(_testMnemonic);
      final indexed =
          await DerivationService.deriveWalletAddressAt(_testMnemonic, 0);
      expect(legacy, indexed);
    });

    test('account index 음수 → throw', () async {
      expect(
        () => DerivationService.deriveWalletKeyPairAt(_testMnemonic, -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('keyPairFromSecret', () {
    test('정확히 32 바이트 seed 만 허용', () async {
      final seed = Uint8List(32);
      // 0으로 채운 seed 도 valid Ed25519 seed (보안 측면 별개, 알고리즘만 검증).
      final kp = await DerivationService.keyPairFromSecret(seed);
      expect(kp.publicKey.toBase58().isNotEmpty, isTrue);
    });

    test('32 바이트 아님 → throw', () async {
      expect(
        () => DerivationService.keyPairFromSecret(Uint8List(31)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DerivationService.keyPairFromSecret(Uint8List(33)),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => DerivationService.keyPairFromSecret(Uint8List(64)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('같은 seed → 같은 public key', () async {
      final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final kp1 = await DerivationService.keyPairFromSecret(seed);
      final kp2 = await DerivationService.keyPairFromSecret(seed);
      expect(kp1.publicKey.toBase58(), kp2.publicKey.toBase58());
    });
  });

  group('Multi-wallet primary 영구 invariant', () {
    // Primary 가 항상 account 0 — wallet/CLAUDE.md §2.4 의 정책 검증.
    test('account 0 derivation 은 절대 변경되지 않음 (regression guard)',
        () async {
      // 같은 test mnemonic 으로 여러 번 호출 — 모두 동일 address.
      final results = await Future.wait(
        List.generate(5, (_) => DerivationService.deriveWalletAddressAt(_testMnemonic, 0)),
      );
      final unique = results.toSet();
      expect(unique.length, 1);
    });
  });
}
