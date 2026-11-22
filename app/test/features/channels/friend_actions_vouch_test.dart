/// @file        friend_actions_vouch_test.dart
/// @description FriendActions and the vouched mark: a friend request the
///              server took vouches for the account (VouchSource
///              .friendRequest), one that failed does not; accepting a
///              request vouches for its sender (friendAccepted); a request
///              without a sender's snowId vouches for nobody.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21
///
/// @functions
///  - main(): the cases above
///  - _Api: answers or fails POSTs, recording their paths
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/app/providers.dart';
import 'package:snowchat/core/crypto/verified_identity_store.dart';
import 'package:snowchat/core/network/api_client.dart';
import 'package:snowchat/features/channels/models/channel.dart';
import 'package:snowchat/features/channels/providers/channel_provider.dart';

import '../../core/crypto/identity_test_support.dart';

String _snow(int i) => 'snow${i.toRadixString(16).padLeft(32, '0')}';

class _Api implements ApiClient {
  bool fail = false;
  final List<String> posts = [];

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    posts.add(path);
    if (fail) throw DioException(requestOptions: RequestOptions(path: path));
    return Response<T>(
      data: {'status': 'pending'} as T,
      statusCode: 200,
      requestOptions: RequestOptions(path: path),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('not in this test: ${invocation.memberName}');
}

void main() {
  late _Api api;
  late VerifiedIdentityStore store;
  late ProviderContainer container;

  setUp(() {
    api = _Api();
    store = VerifiedIdentityStore(InMemorySecureStorage());
    container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      verifiedIdentityStoreProvider.overrideWithValue(store),
    ]);
  });
  tearDown(() => container.dispose());

  test('a friend request the server took vouches; a failed one does not',
      () async {
    final friends = container.read(friendActionsProvider);
    api.fail = true;
    expect(await friends.addFriend(_snow(1)), 'error');
    expect(await store.isVouched(_snow(1)), isFalse);
    api.fail = false;
    expect(await friends.addFriend(_snow(1)), 'pending');
    expect(await store.isVouched(_snow(1)), isTrue);
  });

  test('accepting a request vouches for its sender', () async {
    final friends = container.read(friendActionsProvider);
    expect(
      await friends.acceptFriendRequest(
        PendingChannel(id: 'ch-1', creatorSnowchatId: _snow(2)),
      ),
      isTrue,
    );
    expect(api.posts.single, contains('ch-1'));
    expect(await store.isVouched(_snow(2)), isTrue);

    // Failed: nobody is vouched for.
    api.fail = true;
    expect(
      await friends.acceptFriendRequest(
        PendingChannel(id: 'ch-3', creatorSnowchatId: _snow(3)),
      ),
      isFalse,
    );
    expect(await store.isVouched(_snow(3)), isFalse);
  });
}
