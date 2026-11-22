/// @file        identity_manager_create_test.dart
/// @description IdentityManager.createIdentity() never overwrites an identity (design 2026-11-22
///              §2.5 / §7): on a device that holds one it throws IdentityExistsException and the
///              stored account seed, phrase and snowId stay as they were; on an empty device it
///              makes one. Also the contact backup key: derived from the account seed (the same
///              phrase gives the same key), different from the group backup key.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases above
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/crypto/identity_manager.dart';

import 'identity_test_support.dart';

void main() {
  test('an empty device makes an identity; a second create is refused and '
      'changes nothing', () async {
    final storage = InMemorySecureStorage();
    final identity = IdentityManager(storage);
    expect(await identity.hasIdentity(), isFalse);
    final phrase = await identity.createIdentity();
    final snowId = await identity.getSnowChatId();
    final seed = await identity.getPrivateKey();
    final before = Map.of(storage.data);

    await expectLater(identity.createIdentity(),
        throwsA(isA<IdentityExistsException>()));
    expect(storage.data, before);
    expect(await identity.getSnowChatId(), snowId);
    expect(await identity.getMnemonic(), phrase);
    expect(await identity.getPrivateKey(), seed);
  });

  test('the contact backup key follows the account seed and is not the group '
      'backup key', () async {
    final storage = InMemorySecureStorage();
    final identity = IdentityManager(storage);
    final phrase = await identity.createIdentity();
    final key = await identity.deriveContactBackupKey();
    expect(key, hasLength(32));
    expect(key, isNot(await identity.deriveGroupBackupKey()));

    final again = IdentityManager(InMemorySecureStorage());
    await again.restoreIdentity(phrase);
    expect(await again.deriveContactBackupKey(), key);
  });
}
