/// @file        session_manager_archive_test.dart
/// @description SignalSessionManager.archivePeerSessions(): the sessions with
///              a peer that stated that its own are gone are archived — and
///              the archive is never lost: it is recorded first, written to
///              the session store on disk, and the record cleared only then.
///              Asked for before the manager is initialized (the store not
///              loaded yet), it is applied when the store is loaded.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (SignalSessionManager takes no socket). Earlier 2026-11-20 (the first run writes its store through dispose — saveGroupState is gone with v1 groups)
///
/// @functions
///  - main(): the cases above
///  - _Device: a local account with a real Signal identity and a real
///    session manager over a session store file in a temporary directory;
///    a second _Device on the same storage is the same install after a
///    restart
///
/// Notes:
///  - The server is not reachable here (every call fails): initialize()
///    goes on without it, as it does on a device that is offline.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/identity_binding.dart' show bytesToHexLower;
import 'package:snowchat/core/crypto/identity_manager.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/crypto/session_store.dart';
import 'package:snowchat/core/crypto/signal_protocol_service.dart';
import 'package:snowchat/core/crypto/signal_session_manager.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';
import 'package:snowchat/core/network/api_client.dart';

import 'identity_test_support.dart';

const _pendingKey = 'signal_pending_peer_archives';
const _epoch = 1000;

/// Every call fails as when the server cannot be reached.
class _OfflineApi extends Fake implements ApiClient {
  Never _fail(String path) => throw DioException.connectionError(
    requestOptions: RequestOptions(path: path),
    reason: 'offline',
  );

  @override
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async =>
      _fail(path);

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async => _fail(path);

  @override
  Future<Response<T>> put<T>(String path, {dynamic data}) async => _fail(path);
}


class _SessionStore extends Fake implements SessionStore {
  @override
  Future<void> initialize() async {}
}

/// Secure storage whose writes of [failing] keys fail.
class _Storage extends InMemorySecureStorage {
  final Set<String> failing = {};

  @override
  Future<void> write(String key, String value) async {
    if (failing.contains(key)) throw StateError('keychain locked');
    return super.write(key, value);
  }
}

class _Device {
  final _Storage storage;
  final SignalSessionManager manager;
  _Device._(this.storage, this.manager);

  SignalProtocolService get signal => manager.signal;

  /// The account of [storage] (made the first time) as one run of the app.
  /// [storePath] is read at each use (a test may move the store).
  static Future<_Device> start(
    _Storage storage,
    String Function() storePath,
  ) async {
    if (!storage.data.containsKey('identity_private_key')) {
      final seed = Uint8List.fromList(List.filled(32, 21));
      final pub = Uint8List.fromList(ed.SigningKey(seed: seed).verifyKey);
      storage.data['identity_private_key'] = bytesToHexLower(seed);
      storage.data['identity_public_key'] = bytesToHexLower(pub);
      storage.data['snow_chat_id'] = KeyDerivation.deriveSnowChatId(pub);
      storage.data['device_id'] = 'aaaaaaaa-1111-4111-8111-111111111111';
    }
    final signal = SignalProtocolService(
      identityStore: VerifiedIdentityStore(storage),
    );
    final identity = IdentityManager(storage)..setSignalService(signal);
    if (!storage.data.keys.any((k) => k.startsWith('signal_identity'))) {
      await identity.generateSignalIdentityKey();
    }
    final manager = SignalSessionManager(
      signalService: signal,
      apiClient: _OfflineApi(),
      secureStorage: storage,
      identityManager: identity,
      sessionStore: _SessionStore(),
      sessionStorePath: () async => storePath(),
    );
    return _Device._(storage, manager);
  }

  Future<void> connect(TestParty to) => signal.createSession(
    recipientId: to.snowId,
    deviceId: to.deviceId,
    preKeyBundle: to.bundle(
      binding: to.bindingFor(epoch: _epoch),
      accountPublicKey: to.accountPub,
    ),
  );

  Future<bool> hasSessionWith(TestParty peer) =>
      signal.hasSession(peer.snowId, peer.deviceId);
}

void main() {
  late Directory dir;
  late String storePath;
  late _Storage storage;
  late TestParty bob;
  late TestParty carol;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('session_manager_archive');
    storePath = '${dir.path}/signal_session_store.bin';
    storage = _Storage();
    bob = await TestParty.create(
      seedByte: 2,
      deviceId: '22222222-2222-4222-8222-222222222222',
    );
    carol = await TestParty.create(
      seedByte: 3,
      deviceId: '33333333-3333-4333-8333-333333333333',
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  /// A run of the app that sets up sessions with bob and carol and ends —
  /// its shutdown (dispose) writes the session store to disk.
  Future<void> withSessions() async {
    final first = await _Device.start(storage, () => storePath);
    await first.manager.initialize();
    expect(first.manager.isInitialized, isTrue);
    await first.connect(bob);
    await first.connect(carol);
    await first.manager.dispose();
  }

  test('an initialized manager archives at once, writes the store and keeps '
      'no record', () async {
    await withSessions();
    final device = await _Device.start(storage, () => storePath);
    await device.manager.initialize();
    expect(await device.hasSessionWith(bob), isTrue);

    await device.manager.archivePeerSessions(bob.snowId);
    expect(await device.hasSessionWith(bob), isFalse);
    expect(await device.hasSessionWith(carol), isTrue);
    expect(storage.data.containsKey(_pendingKey), isFalse);

    // The next run of the app reads the archived state from disk.
    final restarted = await _Device.start(storage, () => storePath);
    await restarted.manager.initialize();
    expect(await restarted.hasSessionWith(bob), isFalse);
    expect(await restarted.hasSessionWith(carol), isTrue);
  });

  test('asked for before the store is loaded, the archive is recorded and '
      'applied when it is', () async {
    await withSessions();
    final device = await _Device.start(storage, () => storePath);
    expect(device.manager.isInitialized, isFalse);

    await device.manager.archivePeerSessions(bob.snowId);
    expect(storage.data[_pendingKey], contains(bob.snowId));

    await device.manager.initialize();
    expect(await device.hasSessionWith(bob), isFalse);
    expect(await device.hasSessionWith(carol), isTrue);
    expect(storage.data.containsKey(_pendingKey), isFalse);

    final restarted = await _Device.start(storage, () => storePath);
    await restarted.manager.initialize();
    expect(await restarted.hasSessionWith(bob), isFalse);
  });

  test('a record that cannot be made throws — the caller tries again — and '
      'archives nothing', () async {
    await withSessions();
    final device = await _Device.start(storage, () => storePath);
    await device.manager.initialize();
    storage.failing.add(_pendingKey);
    await expectLater(
      device.manager.archivePeerSessions(bob.snowId),
      throwsStateError,
    );
    expect(await device.hasSessionWith(bob), isTrue);

    storage.failing.clear();
    await device.manager.archivePeerSessions(bob.snowId);
    expect(await device.hasSessionWith(bob), isFalse);
  });

  test('an archive whose store could not be written keeps its record, and '
      'the next start applies it', () async {
    await withSessions();
    final device = await _Device.start(storage, () => storePath);
    await device.manager.initialize();
    final good = storePath;
    // A place no file can be written to: its "directory" is a file.
    File('${dir.path}/blocked').writeAsStringSync('');
    storePath = '${dir.path}/blocked/signal_session_store.bin';
    await device.manager.archivePeerSessions(bob.snowId);
    expect(storage.data[_pendingKey], contains(bob.snowId));

    // On disk bob's session is still there; the next start puts it aside.
    storePath = good;
    final restarted = await _Device.start(storage, () => storePath);
    await restarted.manager.initialize();
    expect(await restarted.hasSessionWith(bob), isFalse);
    expect(storage.data.containsKey(_pendingKey), isFalse);
  });

  test('archives of several peers asked for at once are all kept', () async {
    await withSessions();
    final device = await _Device.start(storage, () => storePath);
    await Future.wait([
      device.manager.archivePeerSessions(bob.snowId),
      device.manager.archivePeerSessions(carol.snowId),
    ]);
    expect(storage.data[_pendingKey], allOf(contains(bob.snowId), contains(carol.snowId)));
    await device.manager.initialize();
    expect(await device.hasSessionWith(bob), isFalse);
    expect(await device.hasSessionWith(carol), isFalse);
    expect(storage.data.containsKey(_pendingKey), isFalse);
  });

  test('a new session with the peer can be set up after the archive', () async {
    await withSessions();
    final device = await _Device.start(storage, () => storePath);
    await device.manager.initialize();
    await device.manager.archivePeerSessions(bob.snowId);
    await device.connect(bob);
    expect(await device.hasSessionWith(bob), isTrue);
  });
}
