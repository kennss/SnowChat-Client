/// @file        snow_avatar.dart
/// @description Deterministic colored avatar widget keyed on SnowChat ID. Derives color and initials from the public key
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-28 (avatarUrl 옵션 — 채널/사용자가 업로드한 이미지가 있으면 표시, 없으면 이니셜 fallback)
///
/// @functions
///  - SnowAvatar: deterministic colored avatar StatelessWidget

import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../../core/network/api_endpoints.dart';

/// Generates a deterministic color avatar from a SnowChat ID,
/// similar to Session's public-key-based colored avatars.
///
/// 만약 [avatarUrl] (서버 fileId) 가 주어지면 network image 로 표시 +
/// 로딩/에러 시 동일 이니셜 fallback 으로 자연스럽게 degradation.
/// 인증 헤더 [authHeader] (Bearer token) 가 필요한 경우 widget 호출
/// 측에서 전달 (raw HTTP 가 dio interceptor 우회하므로).
class SnowAvatar extends StatelessWidget {
  final String snowId;
  final double size;
  final String? displayName;
  final String? avatarUrl;
  final String? authHeader;

  const SnowAvatar({
    super.key,
    required this.snowId,
    this.size = 48,
    this.displayName,
    this.avatarUrl,
    this.authHeader,
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

    if (avatarUrl == null || avatarUrl!.isEmpty) return fallback;

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
          '${ApiEndpoints.getBaseUrl()}/files/$avatarUrl',
          width: size,
          height: size,
          fit: BoxFit.cover,
          headers: authHeader != null ? {'Authorization': authHeader!} : null,
          errorBuilder: (_, __, ___) => fallback,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback,
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
