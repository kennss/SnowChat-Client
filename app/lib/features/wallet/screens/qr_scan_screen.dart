/// @file        qr_scan_screen.dart
/// @description QR code scan screen — validates scan result and returns a
///              String to the caller. Accepts Solana Pay URI / Solana Base58
///              address / .sol domain. Phase 6.1 §3.3 (mobile_scanner ^7.2.0).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - QrScanScreen: camera preview + barcode detect → Navigator.pop(result)
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../naming/sns_resolver.dart';
import '../utils/solana_pay_parser.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF00F782);
  static const _text = Color(0xFFFFFFFF);

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
      if (_isAcceptable(raw)) {
        _consumed = true;
        Navigator.pop(context, raw);
        return;
      }
    }
  }

  /// Check whether the input is a form the send screen can handle.
  static bool _isAcceptable(String input) {
    if (SolanaPayParser.tryParse(input) != null) return true;
    if (SnsResolver.isSnsDomain(input)) return true;
    // Solana Base58 address (32-44 chars, base58 charset)
    if (input.length >= 32 && input.length <= 44) {
      return RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(input);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Scan QR',
          style: TextStyle(color: _text, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: _text),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle flash',
            icon: const Icon(Icons.flash_on, color: _text),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch, color: _text),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _text),
                  ),
                ),
              );
            },
          ),
          // Guide frame
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: _accent, width: 2),
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
                'Solana address, name.sol, or Solana Pay',
                style: TextStyle(color: _text, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
