/// @file        sessions_table.dart
/// @description Drift Signal session and prekey table definitions. Stores libsignal serialized session state and public prekeys.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; previous: 2026-03-29)
///
/// @functions
///  - SignalSessions: Signal session state table class
///  - SignalPreKeys: Signal prekey table class

import 'package:drift/drift.dart';

/// Signal protocol session state (serialized binary from libsignal).
class SignalSessions extends Table {
  TextColumn get recipientDeviceId =>
      text()(); // format: "recipientSnowId:deviceId"
  BlobColumn get sessionState => blob()(); // libsignal serialized session
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {recipientDeviceId};
}

/// Signal PreKeys (public portion; private keys in flutter_secure_storage).
class SignalPreKeys extends Table {
  IntColumn get keyId => integer()();
  BlobColumn get publicKey => blob()();
  BoolColumn get isUsed =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {keyId};
}
