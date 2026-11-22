/// @file        account_deletion_test.dart
/// @description Deleting the account with its deletion proof: the groups
///              are left first, the request carries a proof the account key
///              signed for this account and the stated time, and a second
///              proof is signed for the server's clock only when that clock
///              is near this device's.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20
///
/// @functions
///  - main(): order, the proof, a refused clock, other refusals.
///
/// Notes:
///  - The API client is a stand-in that answers like the server's route
///    (POST /users/me/delete): 200, or 400 with `error.reason` and the
///    server's time.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:snowchat/core/crypto/account_deletion_proof.dart';
import 'package:snowchat/core/crypto/key_derivation.dart';
import 'package:snowchat/core/network/account_deletion.dart';
import 'package:snowchat/core/network/api_client.dart';

class _Api extends Fake implements ApiClient {
  final List<String> order;
  _Api(this.order);

  /// The server's clock; a proof further than ten minutes from it is
  /// refused, as on the server.
  int serverNow = 0;

  /// Answers instead of the clock rule, one per request.
  final List<Response<Object?> Function(RequestOptions)> scripted = [];
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    order.add('POST $path');
    final request = RequestOptions(path: path);
    bodies.add((data as Map).cast<String, dynamic>());
    final Response<Object?> response;
    if (scripted.isNotEmpty) {
      response = scripted.removeAt(0)(request);
    } else {
      final proof = AccountDeletionProof.tryParseWire(data['deletionProof'])!;
      final near =
          (proof.deletedAtMs - serverNow).abs() <= 10 * 60 * 1000;
      response = near
          ? Response(requestOptions: request, statusCode: 200, data: const {})
          : Response(
              requestOptions: request,
              statusCode: 400,
              data: {
                'error': {
                  'code': 'INVALID_REQUEST',
                  'reason': 'time',
                  'serverTimeMs': '$serverNow',
                },
              },
            );
    }
    if (response.statusCode != 200) {
      throw DioException(requestOptions: request, response: response);
    }
    return Response<T>(
      requestOptions: request,
      statusCode: 200,
      data: response.data as T?,
    );
  }
}

void main() {
  final seed = Uint8List.fromList(List.generate(32, (i) => i + 1));
  final key = ed.SigningKey(seed: seed);
  final accountPub = Uint8List.fromList(key.verifyKey.asTypedList);
  final snowId = KeyDerivation.deriveSnowChatId(accountPub);
  const hour = 60 * 60 * 1000;
  const t0 = 1795000000000;

  late List<String> order;
  late _Api api;
  late List<int> signedFor;

  Future<AccountDeletionProof> sign(int deletedAtMs) async {
    signedFor.add(deletedAtMs);
    return AccountDeletionProof(
      deletedAtMs: deletedAtMs,
      signature: Uint8List.fromList(
        key
            .sign(
              AccountDeletionProofV1.buildMessage(
                snowId: snowId,
                deletedAtMs: deletedAtMs,
              ),
            )
            .signature
            .asTypedList,
      ),
    );
  }

  Response<Object?> refuse(RequestOptions r, Map<String, Object?> error) =>
      Response(requestOptions: r, statusCode: 400, data: {'error': error});

  setUp(() {
    order = [];
    api = _Api(order)..serverNow = t0;
    signedFor = [];
  });

  test('the groups are left first; the request carries the account key\'s '
      'proof for this moment', () async {
    await deleteAccountWithProof(
      api: api,
      sign: sign,
      leaveGroups: () async => order.add('leave'),
      nowMs: () => t0 + 1234,
    );
    expect(order, ['leave', 'POST /users/me/delete']);
    expect(signedFor, [t0 + 1234]);
    expect(api.bodies.single.keys, ['deletionProof']);
    final proof = AccountDeletionProof.tryParseWire(
      api.bodies.single['deletionProof'],
    )!;
    expect(proof.deletedAtMs, t0 + 1234);
    expect(
      AccountDeletionProofV1.verify(
        snowId: snowId,
        accountPublicKey: accountPub,
        proof: proof,
      ),
      isTrue,
    );
  });

  test('leaving the groups fails, or there is nothing to leave: the account '
      'is deleted all the same', () async {
    await deleteAccountWithProof(
      api: api,
      sign: sign,
      leaveGroups: () async => throw StateError('database'),
      nowMs: () => t0,
    );
    await deleteAccountWithProof(api: api, sign: sign, nowMs: () => t0);
    expect(order, ['POST /users/me/delete', 'POST /users/me/delete']);
  });

  test('a device whose clock is off signs once more, for the server\'s time',
      () async {
    await deleteAccountWithProof(
      api: api,
      sign: sign,
      nowMs: () => t0 - 3 * hour,
    );
    expect(signedFor, [t0 - 3 * hour, t0]);
    expect(order, hasLength(2));
    final second = AccountDeletionProof.tryParseWire(
      api.bodies.last['deletionProof'],
    )!;
    expect(second.deletedAtMs, t0);
  });

  test('a server whose clock is far from this device\'s gets no second proof',
      () async {
    for (final (device, server) in [
      (t0, t0 + 24 * hour + 1),
      (t0, t0 - 24 * hour - 1),
      (t0, t0 + 365 * 24 * hour),
    ]) {
      signedFor.clear();
      api.serverNow = server;
      await expectLater(
        deleteAccountWithProof(api: api, sign: sign, nowMs: () => device),
        throwsA(isA<DioException>()),
      );
      expect(signedFor, [device], reason: '$server');
    }
    // Exactly at the limit it still does.
    signedFor.clear();
    api.serverNow = t0 + 24 * hour;
    await deleteAccountWithProof(api: api, sign: sign, nowMs: () => t0);
    expect(signedFor, [t0, t0 + 24 * hour]);
  });

  test('the second proof is the last: a server that refuses it again is not '
      'answered a third time', () async {
    api.scripted.addAll([
      (r) => refuse(r, {'reason': 'time', 'serverTimeMs': '${t0 + hour}'}),
      (r) => refuse(r, {'reason': 'time', 'serverTimeMs': '${t0 + 2 * hour}'}),
    ]);
    await expectLater(
      deleteAccountWithProof(api: api, sign: sign, nowMs: () => t0),
      throwsA(isA<DioException>()),
    );
    expect(signedFor, [t0, t0 + hour]);
  });

  test('any other refusal, and a refusal without a usable time, is thrown '
      'as it is', () async {
    final refusals = <Response<Object?> Function(RequestOptions)>[
      (r) => refuse(r, {'reason': 'signature', 'serverTimeMs': '$t0'}),
      (r) => refuse(r, {'reason': 'time'}),
      (r) => refuse(r, {'reason': 'time', 'serverTimeMs': t0}), // a number
      (r) => refuse(r, {'reason': 'time', 'serverTimeMs': '-5'}),
      (r) => Response(requestOptions: r, statusCode: 400, data: 'nope'),
      (r) => Response(
        requestOptions: r,
        statusCode: 500,
        data: {
          'error': {'reason': 'time', 'serverTimeMs': '$t0'},
        },
      ),
    ];
    for (final refusal in refusals) {
      signedFor.clear();
      api.scripted.add(refusal);
      await expectLater(
        deleteAccountWithProof(api: api, sign: sign, nowMs: () => t0 + hour),
        throwsA(isA<DioException>()),
      );
      expect(signedFor, [t0 + hour]);
    }
    // No answer at all.
    api.scripted.add(
      (r) => throw DioException(
        requestOptions: r,
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      deleteAccountWithProof(api: api, sign: sign, nowMs: () => t0),
      throwsA(isA<DioException>()),
    );
  });
}
