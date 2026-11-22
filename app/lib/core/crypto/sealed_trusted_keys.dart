/// @file        sealed_trusted_keys.dart
/// @description The Sealed Sender server verification keys this build trusts, per SERVER_ENV.
///              A sender certificate is accepted only when one of them signed it; a key the
///              server hands out at run time is never used (2026-11-10 report, SC-06 / A-3) —
///              a compromised server could otherwise sign certificates for any account.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - sealedTrustedServerKeysFor(env): the keys of a SERVER_ENV, or null when this build trusts none there
///  - sealedTrustedServerKeys: the keys of the environment this build talks to
///
/// Notes:
///  - dev: the development server derives its key from a fixed public label
///    (server/src/services/SenderCertificateService.ts DEV_SEALED_KEY_LABEL),
///    so it is the same on every machine and survives a restart; the server
///    refuses it in production. A server test pins the same value.
///  - prod: the production key, rotated 2026-11-22 (GET /api/v2/auth/server-key
///    of snowchat.calidalab.ai returns it).
///  - Rotation, with no change to the certificate format: (1) release an app
///    whose list holds the current AND the next key; (2) give users time to
///    update; (3) switch the server to the next key; (4) drop the old key in a
///    later release. A certificate signed by any key of the list is accepted.
///  - Pure Dart (no Flutter, no packages): tool/require_server_keys.dart
///    imports it with no package config.
library;

import 'dart:convert';
import 'dart:typed_data';

const String _devSealedKey = 'TdSsrbaIDU7iCrzvcA49YeYXX9wHRJLt7mNMuy3yJHc=';

/// Production, rotated 2026-11-22 (the beta reset).
const String _prodSealedKey = 'lVL6dGJpm2qkQ1+Pxi1CgzuNH6HQFjn3mN4Oxe5xx5o=';

/// The Ed25519 public keys this build trusts to sign sender certificates on
/// the server of [env] (`dev` or `prod`, as in SERVER_ENV), or null when it
/// trusts none there (Sealed Sender — and with it 1:1 messaging — cannot run).
List<Uint8List>? sealedTrustedServerKeysFor(String env) {
  switch (env) {
    case 'dev':
      return [base64Decode(_devSealedKey)];
    case 'prod':
      return [base64Decode(_prodSealedKey)];
    default:
      return null;
  }
}

/// The keys of the server this build talks to (SERVER_ENV), or null.
final List<Uint8List>? sealedTrustedServerKeys = sealedTrustedServerKeysFor(
  const String.fromEnvironment('SERVER_ENV', defaultValue: 'dev'),
);
