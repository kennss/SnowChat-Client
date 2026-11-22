/// @file        name_cert_support.dart
/// @description Test support: name certificates signed the way the server signs them (contract
///              §12.3) — version 0x01, issue time, snowId, name, Ed25519 signature over
///              "SnowChat-NameCert-v1" ‖ 0x00 ‖ the body — with a key a test holds, so the tests
///              can sign with the pinned key, another key, or another domain label.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - nameCertBody(): the bytes the signature covers (after the label)
///  - signNameCert(): a whole certificate
///  - testServerKey(): a fixed server signing key for the tests
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pinenacl/ed25519.dart' as ed;

/// The certificate without its signature.
Uint8List nameCertBody({
  required String snowId,
  required String? name,
  required int issuedAtMs,
}) {
  final b = BytesBuilder();
  b.addByte(0x01);
  final t = ByteData(8)..setInt64(0, issuedAtMs, Endian.big);
  b.add(t.buffer.asUint8List());
  final id = ascii.encode(snowId);
  b.addByte(id.length);
  b.add(id);
  final n = name == null ? Uint8List(0) : utf8.encode(name);
  final len = ByteData(2)..setUint16(0, n.length, Endian.big);
  b.add(len.buffer.asUint8List());
  b.add(n);
  return b.takeBytes();
}

/// A certificate for [snowId] / [name] issued at [issuedAtMs], signed by
/// [key] over [label] ‖ 0x00 ‖ body.
Uint8List signNameCert({
  required ed.SigningKey key,
  required String snowId,
  required String? name,
  required int issuedAtMs,
  String label = 'SnowChat-NameCert-v1',
}) {
  final body = nameCertBody(snowId: snowId, name: name, issuedAtMs: issuedAtMs);
  final message = Uint8List.fromList([...utf8.encode(label), 0x00, ...body]);
  final signature = key.sign(message).signature.asTypedList;
  return Uint8List.fromList([...body, ...signature]);
}

/// A fixed server key (seed 0x42…).
ed.SigningKey testServerKey([int seed = 0x42]) =>
    ed.SigningKey(seed: Uint8List.fromList(List.filled(32, seed)));
