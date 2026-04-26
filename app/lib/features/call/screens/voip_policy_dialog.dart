/// @file        voip_policy_dialog.dart
/// @description Zero-Trace policy dialog shown once on the first call (Phase 8.2 §23.6).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation; UI: English)
///
/// @functions
///  - VoipPolicyDialog.showIfNeeded(): show once after checking flutter_secure_storage flag

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storageKey = 'voip_policy_acknowledged';

class VoipPolicyDialog extends StatelessWidget {
  const VoipPolicyDialog({super.key});

  /// Call this on the first call attempt/receive in the app. Returns immediately if already acknowledged.
  static Future<void> showIfNeeded(BuildContext context) async {
    const storage = FlutterSecureStorage();
    final acknowledged = await storage.read(key: _storageKey);
    if (acknowledged == 'true') return;
    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const VoipPolicyDialog(),
    );
    await storage.write(key: _storageKey, value: 'true');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('SnowChat Call Policy'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Bullet('Call content is end-to-end encrypted (DTLS-SRTP)'),
          SizedBox(height: 8),
          _Bullet('Voice data never traverses the server'),
          SizedBox(height: 8),
          _Bullet('Call history is never stored anywhere'),
          SizedBox(height: 8),
          _Bullet('Missed calls are not recorded'),
          SizedBox(height: 8),
          _Bullet('Call recording is not provided'),
          SizedBox(height: 16),
          Text(
            '※ If you need to follow up after a call,\nplease message the contact directly.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('✓ ', style: TextStyle(color: Colors.green)),
        Expanded(child: Text(text)),
      ],
    );
  }
}
