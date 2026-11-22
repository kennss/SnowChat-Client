/// @file        snow_avatar.dart
/// @description Deterministic colored avatar widget keyed on SnowChat ID. Derives color and initials from the public key
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-22 (imageBytes replaces avatarUrl / authHeader: the image is fetched by the
///              caller — POST /files/fetch, the file id is never in a URL — and shown from memory).
///              Earlier 2026-04-28 (an uploaded image when there is one, else the initials)
///
/// @functions
///  - SnowAvatar: deterministic colored avatar StatelessWidget

import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Generates a deterministic color avatar from a SnowChat ID,
/// similar to Session's public-key-based colored avatars.
///
/// [imageBytes] (an uploaded image the caller fetched — e.g. a community's,
/// communityAvatarBytesProvider) is shown when given; while it is missing or
/// when it does not decode, the same initials.
class SnowAvatar extends StatelessWidget {
  final String snowId;
  final double size;
  final String? displayName;
  final Uint8List? imageBytes;

  const SnowAvatar({
    super.key,
    required this.snowId,
    this.size = 48,
    this.displayName,
    this.imageBytes,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFromId(snowId);
    final initials = _initials();

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: color,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    final bytes = imageBytes;
    if (bytes == null || bytes.isEmpty) return fallback;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }

  String _initials() {
    if (displayName != null && displayName!.isNotEmpty) {
      final parts = displayName!.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return parts[0][0].toUpperCase();
    }
    // Fallback: use first 2 chars after "snow" prefix
    if (snowId.length >= 6) {
      return snowId.substring(4, 6).toUpperCase();
    }
    return '??';
  }

  static Color _colorFromId(String id) {
    if (id.length < 8) return SnowColors.primary;
    // Use the hex portion of the ID to derive a hue
    final hexPart = id.length > 4 ? id.substring(4) : id;
    int hash = 0;
    for (int i = 0; i < hexPart.length; i++) {
      hash = hexPart.codeUnitAt(i) + ((hash << 5) - hash);
    }
    final hue = (hash.abs() % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.7, 0.6).toColor();
  }
}
