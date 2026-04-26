/// @file        nft_send_screen.dart
/// @description NFT send screen — uses NftTransferService branched by tokenStandard.
///              Phase 7: shows unsupported notice for pNFT.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - NFTSendScreen: screen widget for sending an NFT to another wallet

/// NFT send screen with slide-to-confirm.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:local_auth/local_auth.dart';

import '../../../shared/models/nft_models.dart';
import '../../wallet/utils/transfer_error_formatter.dart';
import '../nft_provider.dart' show nftTransferServiceProvider;

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const primaryBg = Color(0xFF0A2A1A);
  static const surface = Color(0xFF111111);
  static const surfaceVariant = Color(0xFF1A1A1A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const error = Color(0xFFFF4444);
}

class NFTSendScreen extends ConsumerStatefulWidget {
  const NFTSendScreen({super.key, required this.nft});

  final NFTAsset nft;

  @override
  ConsumerState<NFTSendScreen> createState() => _NFTSendScreenState();
}

class _NFTSendScreenState extends ConsumerState<NFTSendScreen> {
  final _addressController = TextEditingController();
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _C.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Send NFT',
          style: TextStyle(color: _C.textPrimary, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // NFT preview.
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: CachedNetworkImage(
                  imageUrl: widget.nft.imageUrl,
                  width: 140,
                  height: 140,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 140,
                    height: 140,
                    color: _C.surface,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 140,
                    height: 140,
                    color: _C.surface,
                    child: const Icon(Icons.image, color: _C.textSecondary),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.nft.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _C.textPrimary,
                ),
              ),
              if (widget.nft.collectionName != null) ...[
                const SizedBox(height: 4),
                Text(
                  widget.nft.collectionName!,
                  style: const TextStyle(fontSize: 13, color: _C.textSecondary),
                ),
              ],
              const SizedBox(height: 32),

              // Recipient address.
              TextField(
                controller: _addressController,
                style: const TextStyle(color: _C.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Recipient wallet address',
                  hintStyle: const TextStyle(color: _C.textTertiary),
                  filled: true,
                  fillColor: _C.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste, color: _C.textTertiary, size: 20),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _addressController.text = data!.text!;
                      }
                    },
                  ),
                ),
              ),
              const Spacer(),

              // Fee info.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Network fee',
                      style: TextStyle(color: _C.textTertiary, fontSize: 13),
                    ),
                    Text(
                      '~0.002 SOL',
                      style: TextStyle(color: _C.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Error.
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: SingleChildScrollView(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: _C.error, fontSize: 13),
                      ),
                    ),
                  ),
                ),

              // Slide to confirm.
              _SlideToConfirm(
                isLoading: _isSending,
                onConfirm: _handleSend,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleSend() async {
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() => _error = 'Enter a recipient address');
      return;
    }

    // Biometric gate (CLAUDE.md: every transfer action must pass local_auth)
    final localAuth = LocalAuthentication();
    final canAuth = await localAuth.canCheckBiometrics ||
        await localAuth.isDeviceSupported();
    if (canAuth) {
      final didAuth = await localAuth.authenticate(
        localizedReason: 'Authenticate to send NFT',
        options: const AuthenticationOptions(biometricOnly: false),
      );
      if (!didAuth) return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final transferService = ref.read(nftTransferServiceProvider);
      final result = await transferService.transfer(
        recipientAddress: address,
        mintAddress: widget.nft.mint,
        tokenStandard: widget.nft.tokenStandard,
        isCompressed: widget.nft.isCompressed,
      );

      if (mounted) {
        Navigator.pop(context, result.signature);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _error = TransferErrorFormatter.format(e.toString());
        });
      }
    }
  }
}

// Reusable slide-to-confirm (same as in send_screen).
class _SlideToConfirm extends StatefulWidget {
  const _SlideToConfirm({
    required this.onConfirm,
    this.isLoading = false,
  });

  final VoidCallback onConfirm;
  final bool isLoading;

  @override
  State<_SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<_SlideToConfirm> {
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: _C.primaryBg,
        borderRadius: BorderRadius.circular(28),
      ),
      child: widget.isLoading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: _C.primary, strokeWidth: 2.5),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxSlide = constraints.maxWidth - 56;
                return Stack(
                  children: [
                    Center(
                      child: Text(
                        'Slide to send',
                        style: TextStyle(
                          color: _C.primary.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Positioned(
                      left: _progress * maxSlide,
                      top: 4,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) {
                          setState(() {
                            _progress += d.delta.dx / maxSlide;
                            _progress = _progress.clamp(0.0, 1.0);
                          });
                        },
                        onHorizontalDragEnd: (_) {
                          if (_progress > 0.85) widget.onConfirm();
                          setState(() => _progress = 0);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: _C.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: Color(0xFF000000),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
