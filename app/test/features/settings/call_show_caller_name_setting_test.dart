/// @file        call_show_caller_name_setting_test.dart
/// @description "Show caller name on calls" setting: on by default, persisted under
///              `call_show_caller_name`, read back by a new SettingsNotifier; the value call code
///              reads (callShowCallerNameForCall) waits for the stored one, and is false while the
///              store cannot be read (device locked since boot), true again once it can.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-23
/// @lastUpdated 2026-11-23
///
/// @functions
///  - _MemoryStorage: SecureStorageService over a map (the real typed getters / setters)
///  - main(): the cases

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/storage/secure_storage.dart';
import 'package:snowchat/features/settings/settings_provider.dart';

/// The real SecureStorageService with its key-value layer in memory, so the
/// typed getters and setters (and their keys) are the ones under test.
class _MemoryStorage extends SecureStorageService {
  final Map<String, String> data = {};

  /// Keys whose reads throw (iOS Keychain before first unlock).
  final Set<String> locked = {};

  @override
  Future<String?> read(String key) async {
    if (locked.contains(key)) throw StateError('keychain locked');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}

const _key = 'call_show_caller_name';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default on: nothing stored', () async {
    final notifier = SettingsNotifier(_MemoryStorage());
    expect(notifier.state.callShowCallerName, isTrue);
    expect(await notifier.callShowCallerNameForCall(), isTrue);
    notifier.dispose();
  });

  test('off is persisted and read back by a new notifier', () async {
    final storage = _MemoryStorage();
    final first = SettingsNotifier(storage);
    await first.setCallShowCallerName(false);
    expect(storage.data[_key], 'false');
    expect(await first.callShowCallerNameForCall(), isFalse);
    first.dispose();

    final second = SettingsNotifier(storage);
    // Asked before the startup load can have finished: still the stored off.
    expect(await second.callShowCallerNameForCall(), isFalse);
    expect(second.state.callShowCallerName, isFalse);
    second.dispose();
  });

  test('on again is persisted', () async {
    final storage = _MemoryStorage()..data[_key] = 'false';
    final notifier = SettingsNotifier(storage);
    await notifier.setCallShowCallerName(true);
    expect(storage.data[_key], 'true');
    expect(await notifier.callShowCallerNameForCall(), isTrue);
    notifier.dispose();
  });

  test('unreadable store: false for calls, read again once readable', () async {
    final storage = _MemoryStorage()..locked.add(_key);
    final notifier = SettingsNotifier(storage);
    expect(await notifier.callShowCallerNameForCall(), isFalse);
    storage.locked.clear();
    expect(await notifier.callShowCallerNameForCall(), isTrue);
    notifier.dispose();
  });
}
