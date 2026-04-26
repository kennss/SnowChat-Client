/// @file        desktop_link_screen.dart
/// @description Desktop Link — E2EE pairing with the Mac desktop via QR scan.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-16
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - _scanQR(): scan QR code -> obtain desktop public key
///  - _performPairing(): X25519 DH -> shared_key -> server register -> deliver JWT

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/x25519.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../ai/service/desktop_relay_service.dart';

/// Desktop Link state
enum DesktopLinkState { idle, scanning, connecting, paired, error }

/// Security mode
enum SecurityMode { paranoid, smart, cloud }

class DesktopLinkScreen extends ConsumerStatefulWidget {
  const DesktopLinkScreen({super.key});

  @override
  ConsumerState<DesktopLinkScreen> createState() => _DesktopLinkScreenState();
}

class _DesktopLinkScreenState extends ConsumerState<DesktopLinkScreen> {
  DesktopLinkState _state = DesktopLinkState.idle;
  String _statusMessage = '';
  String? _pairedDeviceId;
  SecurityMode _securityMode = SecurityMode.paranoid;
  String _activeModel = 'Local';
  final _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _checkExistingPairing();
  }

  Future<void> _checkExistingPairing() async {
    final deviceId = await _secureStorage.read(key: 'desktop_device_id');
    if (deviceId != null) {
      setState(() {
        _state = DesktopLinkState.paired;
        _pairedDeviceId = deviceId;
        _statusMessage = 'Connected to desktop';
      });
    }
  }

  Future<void> _startPairing() async {
    // Handle QR data via manual input (mobile_scanner currently disabled)
    // TODO: replace with camera scan once mobile_scanner is enabled
    final controller = TextEditingController();

    final qrData = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desktop QR Data'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Paste QR code data from desktop',
          ),
          maxLines: 5,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );

    if (qrData == null || qrData.isEmpty) return;

    await _performPairing(qrData);
  }

  Future<void> _performPairing(String qrData) async {
    setState(() {
      _state = DesktopLinkState.connecting;
      _statusMessage = 'Connecting to desktop...';
    });

    try {
      // 1. Parse QR data
      final data = jsonDecode(qrData) as Map<String, dynamic>;
      if (data['type'] != 'snowclaw_pair') {
        throw Exception('Invalid QR code');
      }

      final desktopPubKeyHex = data['publicKey'] as String;
      final ip = data['ip'] as String;
      final port = data['port'] as int;

      // 2. Generate mobile X25519 keypair
      final mobileKeyPair = PrivateKey.generate();
      final mobilePubKeyHex = _bytesToHex(
        Uint8List.fromList(mobileKeyPair.publicKey.toList()),
      );

      // 3. Connect directly to desktop (P2P WebSocket)
      setState(() => _statusMessage = 'Key exchange...');

      final uri = Uri.parse('ws://$ip:$port');
      final channel = WebSocketChannel.connect(uri);

      // Send mobile public key + deviceId
      final deviceId = await _getDeviceId();
      channel.sink.add(jsonEncode({
        'type': 'snowclaw_pair_response',
        'publicKey': mobilePubKeyHex,
        'deviceId': deviceId,
      }));

      // Wait for confirmation response
      final response = await channel.stream.first
          .timeout(const Duration(seconds: 30));
      final confirm = jsonDecode(response as String) as Map<String, dynamic>;

      if (confirm['success'] != true) {
        throw Exception('Pairing rejected by desktop');
      }

      final desktopDeviceId = confirm['desktopDeviceId'] as String;

      // 4. Derive shared key (X25519 DH)
      final desktopPubKey = PublicKey(
        Uint8List.fromList(_hexToBytes(desktopPubKeyHex)),
      );
      final sharedSecret = Box(
        myPrivateKey: mobileKeyPair,
        theirPublicKey: desktopPubKey,
      );
      // Box.sharedKey → SHA256 hash (same scheme as desktop)
      final sharedKeyBytes = sharedSecret.sharedKey;
      // Note: PyNaCl's Box.shared_key() applies HSalsa20.
      // Use pinenacl's Box here for the same compatibility.
      final sharedKeyHex = _bytesToHex(
        Uint8List.fromList(sharedKeyBytes.toList()),
      );

      // 5. Save to SecureStorage
      await _secureStorage.write(
        key: 'desktop_shared_key',
        value: sharedKeyHex,
      );
      await _secureStorage.write(
        key: 'desktop_device_id',
        value: desktopDeviceId,
      );

      channel.sink.close();

      setState(() {
        _state = DesktopLinkState.paired;
        _pairedDeviceId = desktopDeviceId;
        _statusMessage = 'Paired successfully!';
      });
    } catch (e) {
      setState(() {
        _state = DesktopLinkState.error;
        _statusMessage = 'Pairing failed: $e';
      });
    }
  }

  Future<void> _unpair() async {
    await _secureStorage.delete(key: 'desktop_shared_key');
    await _secureStorage.delete(key: 'desktop_device_id');
    setState(() {
      _state = DesktopLinkState.idle;
      _pairedDeviceId = null;
      _statusMessage = '';
    });
  }

  Future<String> _getDeviceId() async {
    // Reuse existing device ID
    final stored = await _secureStorage.read(key: 'deviceId');
    return stored ?? 'unknown';
  }

  Future<void> _sendConfigChange(String key, String value) async {
    // TODO: send config change to desktop over E2EE relay
    // For now only local state changes (real send once relay is connected)
    debugPrint('[DesktopLink] Config change: $key = $value');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Desktop Link')),
      body: _state == DesktopLinkState.paired
          ? _buildControlPanel(theme)
          : _buildPairingView(theme),
    );
  }

  /// Connected state — desktop control panel
  Widget _buildControlPanel(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurface.withOpacity(0.5);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // Connection status
        _buildSection(
          'CONNECTION',
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green, shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text('Online', style: TextStyle(color: dim, fontSize: 14)),
              const Spacer(),
              Text(
                _pairedDeviceId?.substring(0, 8) ?? '',
                style: TextStyle(color: dim, fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Security Mode — 3-tier segment
        _buildSection(
          'SECURITY',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    _segmentButton('Paranoid', SecurityMode.paranoid, theme),
                    _segmentButton('Smart', SecurityMode.smart, theme),
                    _segmentButton('Cloud', SecurityMode.cloud, theme),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _securityModeDesc(),
                style: TextStyle(color: dim, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // AI Model
        _buildSection(
          'AI MODEL',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  children: [
                    _modelButton('Local', 'Local', theme),
                    _modelButton('Gemini', 'Gemini', theme),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _activeModel == 'Local'
                    ? 'Ollama local inference. Free, private, offline capable.'
                    : 'Google Gemini API. Requires API key, higher quality.',
                style: TextStyle(color: dim, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // E2EE indicator
        _buildSection(
          'ENCRYPTION',
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: dim),
              const SizedBox(width: 8),
              Text(
                'NaCl XSalsa20-Poly1305 (E2EE)',
                style: TextStyle(color: dim, fontSize: 13),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        // Disconnect
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _unpair,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            child: const Text('Disconnect Desktop'),
          ),
        ),
      ],
    );
  }

  Widget _segmentButton(String label, SecurityMode mode, ThemeData theme) {
    final selected = _securityMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _securityMode = mode);
          _sendConfigChange('security_mode', mode.name);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modelButton(String label, String value, ThemeData theme) {
    final selected = _activeModel == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeModel = value);
          _sendConfigChange('model', value == 'Local' ? 'gemma4:26b' : 'gemini-2.5-flash');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }

  String _securityModeDesc() {
    switch (_securityMode) {
      case SecurityMode.paranoid:
        return 'Fully offline. No network access. Local data only.';
      case SecurityMode.smart:
        return 'Local first + anonymous web search via SearXNG. PII removed.';
      case SecurityMode.cloud:
        return 'Gemini API enabled + web search. API key required.';
    }
  }

  Widget _buildSection(String title, {required Widget child}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  /// Unconnected state — pairing UI
  Widget _buildPairingView(ThemeData theme) {
    final dim = theme.colorScheme.onSurface.withOpacity(0.5);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.desktop_access_disabled, size: 56, color: dim),
          const SizedBox(height: 16),
          Text('No desktop connected', style: theme.textTheme.titleMedium),
          if (_statusMessage.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 13,
                color: _state == DesktopLinkState.error ? Colors.red : dim,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Connect your Mac to use it as an AI server.\n\n'
              '1. Open SnowClaw on your Mac\n'
              '2. Run with --pair flag\n'
              '3. Scan the QR code below',
              style: TextStyle(fontSize: 14, height: 1.6),
            ),
          ),
          const Spacer(),
          if (_state == DesktopLinkState.connecting)
            const CircularProgressIndicator()
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _startPairing,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan QR Code'),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Helpers ──

  static Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
