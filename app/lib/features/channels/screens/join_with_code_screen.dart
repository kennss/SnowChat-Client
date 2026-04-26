/// @file        join_with_code_screen.dart
/// @description Phase 1 fallback for invite links — manual code entry +
///              in-app QR scan (mobile_scanner). Used when:
///                1. The recipient is already in the app and was given the
///                   raw code (snowchat://invite/<code> link broken in
///                   their environment, or a friend pasted just the code).
///                2. The system camera app cannot route a custom-scheme QR
///                   to SnowChat (most stock cameras only handle https://).
///              Phase 2 (Universal Link / App Link) will let the system
///              camera open SnowChat directly, but this screen still serves
///              as the manual fallback for shared codes.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-26
/// @lastUpdated 2026-04-26
///
/// @functions
///  - JoinWithCodeScreen: paste/scan invite code → validate → /invite/<code>
///  - _extractCode(): accepts raw code OR full snowchat://... URL paste

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';

class JoinWithCodeScreen extends StatefulWidget {
  const JoinWithCodeScreen({super.key});

  @override
  State<JoinWithCodeScreen> createState() => _JoinWithCodeScreenState();
}

class _JoinWithCodeScreenState extends State<JoinWithCodeScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  /// ChannelInvite.code is 12 hex chars (server: ChannelService.ts:839 uses
  /// crypto.randomBytes(6).toString('hex')). Validate before navigating to
  /// avoid hitting the API with garbage.
  static final _codeRegex = RegExp(r'^[a-f0-9]{12}$', caseSensitive: false);

  /// Accepts:
  ///  - bare code:                    "b8b18145f3f4"
  ///  - custom-scheme URL:            "snowchat://invite/b8b18145f3f4"
  ///  - Phase 2 Universal Link URL:   "https://snowchat.calidalab.ai/invite/b8b18145f3f4"
  String? _extractCode(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // If it parses as a URI with the invite path, pull the last segment.
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      final isInviteUri =
          (uri.scheme == 'snowchat' && uri.host == 'invite') ||
              (uri.scheme == 'https' &&
                  uri.host == 'snowchat.calidalab.ai' &&
                  uri.pathSegments.isNotEmpty &&
                  uri.pathSegments.first == 'invite');
      if (isInviteUri && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last.toLowerCase();
      }
    }

    // Otherwise treat as a raw code.
    return trimmed.toLowerCase();
  }

  void _submit() {
    final code = _extractCode(_controller.text);
    if (code == null || !_codeRegex.hasMatch(code)) {
      setState(() {
        _error = 'Invalid invite code. Expected 12 hex characters.';
      });
      return;
    }
    setState(() => _error = null);
    context.push('/invite/$code');
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const _InviteQrScanScreen(),
      ),
    );
    if (scanned == null || !mounted) return;
    _controller.text = scanned;
    _submit();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    setState(() => _error = null);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        title: const Text('Join with Code'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(SnowSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste an invite link or 12-character code from a friend.',
              style: TextStyle(color: SnowColors.textTertiary, fontSize: 14),
            ),
            const SizedBox(height: SnowSizes.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'snowchat://invite/... or b8b18145f3f4',
                errorText: _error,
                suffixIcon: IconButton(
                  tooltip: 'Paste',
                  icon: const Icon(Icons.content_paste_rounded,
                      color: SnowColors.primary),
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
            const SizedBox(height: SnowSizes.md),
            ElevatedButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Continue'),
            ),
            const SizedBox(height: SnowSizes.md),
            const Row(
              children: [
                Expanded(child: Divider(color: SnowColors.divider)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR',
                      style: TextStyle(color: SnowColors.textTertiary)),
                ),
                Expanded(child: Divider(color: SnowColors.divider)),
              ],
            ),
            const SizedBox(height: SnowSizes.md),
            OutlinedButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Scan QR Code'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lightweight QR scanner specialised for invite codes. Returns the raw
/// scanned string to the caller — the parent screen extracts/validates the
/// code (so the same regex lives in one place).
class _InviteQrScanScreen extends StatefulWidget {
  const _InviteQrScanScreen();

  @override
  State<_InviteQrScanScreen> createState() => _InviteQrScanScreenState();
}

class _InviteQrScanScreenState extends State<_InviteQrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _consumed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_consumed) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;
      _consumed = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Scan Invite QR',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle flash',
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: SnowColors.primary, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 32,
            child: Center(
              child: Text(
                'Point at a SnowChat invite QR',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
