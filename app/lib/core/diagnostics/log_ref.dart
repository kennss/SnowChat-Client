/// @file        log_ref.dart
/// @description Account and conversation ids in log lines (2026-11-22 security review S11): a log
///              line never carries one. logRef() turns an id into a short tag that is the same
///              for the same id within one run of the app — so a log can still be followed — but
///              differs between runs and cannot be turned back into the id: an HMAC under a key
///              drawn at start and never stored, so even a list of every account does not match
///              a tag.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - logRef(): the run-local tag of an id for a log line ("ref:" + 8 hex characters)
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The key of this run's tags (32 random bytes, in memory only).
final Uint8List _runKey = () {
  final random = Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
}();

/// [id] (an account, a conversation, a group) as a log line may show it:
/// "ref:" and the first 4 bytes of HMAC-SHA256(run key, id) in hex. Null or
/// empty reads "ref:-".
String logRef(String? id) {
  if (id == null || id.isEmpty) return 'ref:-';
  final mac = Hmac(sha256, _runKey).convert(utf8.encode(id)).bytes;
  final hex = mac
      .take(4)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'ref:$hex';
}
