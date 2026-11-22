/// @file        gv2_retention_provider.dart
/// @description How long the server keeps group messages for this account
///              while it is offline (group protocol v2, design §12): read
///              from and written to the server — the server is the one that
///              deletes them.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-20
///
/// @functions
///  - gv2RetentionChoices: the periods the server accepts, in DAYS
///  - gv2RetentionLabel(): a period in words
///  - gv2RetentionProvider: the account's period (Gv2RetentionNotifier)
///  - Gv2RetentionNotifier.choose(): set another period
///
/// Notes:
///  - The value is DAYS and one of 1, 7, 30; anything else from the server
///    is an error, not a value to show.
///  - A message that waited on the server longer than this is gone when the
///    device comes back; nothing on the device changes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_endpoints.dart';

/// The periods the server accepts, in DAYS.
const List<int> gv2RetentionChoices = [1, 7, 30];

/// [days] in words.
String gv2RetentionLabel(int days) => switch (days) {
  1 => '1 day',
  7 => '1 week',
  30 => '1 month',
  _ => '$days days',
};

class Gv2RetentionNotifier extends AutoDisposeAsyncNotifier<int> {
  @override
  Future<int> build() async {
    final response = await ref
        .read(apiClientProvider)
        .get<Object?>(ApiEndpoints.gv2Retention);
    return _days(response.data);
  }

  /// Set the period to [days] (one of [gv2RetentionChoices]). The shown
  /// value changes only once the server took it; throws when it did not.
  Future<void> choose(int days) async {
    if (!gv2RetentionChoices.contains(days)) {
      throw ArgumentError('retention: not a period the server keeps');
    }
    final response = await ref
        .read(apiClientProvider)
        .put<Object?>(ApiEndpoints.gv2Retention, data: {'days': days});
    state = AsyncData(_days(response.data));
  }

  static int _days(Object? data) {
    final days = data is Map ? data['days'] : null;
    if (days is! int || !gv2RetentionChoices.contains(days)) {
      throw const FormatException('retention: unexpected answer');
    }
    return days;
  }
}

final gv2RetentionProvider =
    AsyncNotifierProvider.autoDispose<Gv2RetentionNotifier, int>(
      Gv2RetentionNotifier.new,
    );
