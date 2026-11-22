/// @file        require_server_keys.dart
/// @description Release gate: exits 1 when this build pins no server keys for a SERVER_ENV
///              (default `prod`) — neither the group protocol v2 keys (gv2_trusted_keys.dart)
///              nor the Sealed Sender verify key (sealed_trusted_keys.dart) may be missing. Run
///              by scripts/build_release.sh and scripts/build_release_ios.sh before they build,
///              so a release can never ship with groups or 1:1 messaging that cannot run.
///              Pure Dart (no Flutter, no packages) — run with the empty package config next
///              to it, so that no dependency's build hook runs:
///                dart --packages=tool/no_packages.json \
///                  tool/require_server_keys.dart prod
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-20
/// @lastUpdated 2026-11-22 (was require_gv2_keys.dart: also requires the pinned Sealed Sender
///              key — SC-06). Earlier 2026-11-20
///
/// @functions
///  - main(args): check both key sets of args[0] ?? 'prod', exit 1 if either is missing
library;

import 'dart:io';

// Relative imports of pure Dart files: run with no package config, so no
// dependency build hook runs (see the header).
import '../lib/core/crypto/sealed_trusted_keys.dart';
import '../lib/core/group_v2/gv2_trusted_keys.dart';

void main(List<String> args) {
  final env = args.isEmpty ? 'prod' : args.first;
  var ok = true;
  if (gv2TrustedServerKeysFor(env) == null) {
    stderr.writeln('[require_server_keys] this build trusts no group server keys '
        'for SERVER_ENV=$env (lib/core/group_v2/gv2_trusted_keys.dart). '
        'Generate the server keys of that environment and pin them first.');
    ok = false;
  }
  final sealed = sealedTrustedServerKeysFor(env);
  if (sealed == null || sealed.isEmpty || sealed.any((k) => k.length != 32)) {
    stderr.writeln('[require_server_keys] this build pins no Sealed Sender server '
        'key for SERVER_ENV=$env (lib/core/crypto/sealed_trusted_keys.dart). '
        'Pin the public key the server of that environment signs with first.');
    ok = false;
  }
  if (!ok) exit(1);
  stdout.writeln('[require_server_keys] group and Sealed Sender server keys pinned '
      'for SERVER_ENV=$env');
}
