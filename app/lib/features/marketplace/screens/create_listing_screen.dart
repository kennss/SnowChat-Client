/// @file        create_listing_screen.dart
/// @description NFT listing creation screen — Step 1: select NFT, Step 2: price input + fee preview,
///              Step 3: slide-to-confirm -> biometric -> escrow transfer -> server register.
///              BigInt only (price). Display-only double via lamportsToSol() only.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-11
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - CreateListingScreen: 3-step NFT listing creation screen (ConsumerStatefulWidget)
///  - _NFTSelectionStep: pick from my NFT gallery
///  - _PriceInputStep: price input + fee preview
///  - _SlideToConfirm: slide-to-confirm widget

/// Create NFT listing screen — select NFT, set price, confirm.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:solana/solana.dart';

import '../../../shared/models/nft_models.dart';
import '../../nft/nft_provider.dart';
import '../../wallet/tensor/tensor_providers.dart';
import '../../wallet/utils/amount_converter.dart';

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const primaryBg = Color(0xFF0A2A1A);
  static const surface = Color(0xFF111111);
  static const surfaceLight = Color(0xFF1A1A1A);
  static const surfaceVariant = Color(0xFF242424);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const error = Color(0xFFFF4444);
}

class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key});

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  int _currentStep = 0; // 0: select NFT, 1: set price
  NFTAsset? _selectedNFT;
  final TextEditingController _priceController = TextEditingController();
  String? _error;
  bool _isSubmitting = false;

  static const int _feeBps = 200; // 2% — loaded from server in production

  @override
  void dispose() {
    _priceController.dispose();
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
          onPressed: () {
            if (_currentStep > 0) {
              setState(() {
                _currentStep--;
                _error = null;
              });
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          _currentStep == 0 ? 'Select NFT' : 'Set Price',
          style: const TextStyle(
            color: _C.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          // Step indicator.
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Step ${_currentStep + 1} of 2',
                style:
                    const TextStyle(color: _C.textSecondary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _currentStep == 0
            ? _NFTSelectionStep(
                key: const ValueKey('step0'),
                onSelected: (nft) {
                  setState(() {
                    _selectedNFT = nft;
                    _currentStep = 1;
                    _error = null;
                  });
                },
              )
            : _PriceInputStep(
                key: const ValueKey('step1'),
                nft: _selectedNFT!,
                priceController: _priceController,
                feeBps: _feeBps,
                error: _error,
                isSubmitting: _isSubmitting,
                onConfirm: _handleConfirm,
              ),
      ),
    );
  }

  Future<void> _handleConfirm() async {
    final priceText = _priceController.text.trim();
    if (priceText.isEmpty) {
      setState(() => _error = 'Enter a price');
      return;
    }

    // Parse price to BigInt lamports.
    BigInt priceLamports;
    try {
      priceLamports = solToLamports(priceText);
    } catch (e) {
      setState(() => _error = 'Invalid price format');
      return;
    }

    if (priceLamports <= BigInt.zero) {
      setState(() => _error = 'Price must be greater than 0');
      return;
    }

    // Biometric auth moved into TensorTxService.listNft — single prompt
    // per tx. Double prompts caused fingerprint hangs on Samsung devices.
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Phase 2: on-chain list_legacy (Tensor fork PDA). Replaces the
      // server escrow flow — removes custody / VASP risk and the
      // community fee share attaches automatically when buyers include
      // the registered collection on buy. TensorTxService enforces its
      // own biometric gate + v0 send + confirm.
      final service = ref.read(tensorTxServiceProvider);
      await service.listNft(
        mint: Ed25519HDPublicKey.fromBase58(_selectedNFT!.mint),
        priceLamports: priceLamports,
      );
      if (mounted) _showSuccessDialog();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = e.toString();
        });
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: _C.primary, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Listed!',
              style: TextStyle(
                color: _C.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_selectedNFT!.name} is now listed for sale',
              style: const TextStyle(color: _C.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // dismiss dialog
              // Schedule navigation after dialog fully dismissed
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.go('/marketplace');
              });
            },
            child: const Text(
              'Back to Marketplace',
              style: TextStyle(color: _C.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: NFT Selection
// ---------------------------------------------------------------------------

class _NFTSelectionStep extends ConsumerWidget {
  const _NFTSelectionStep({super.key, required this.onSelected});

  final ValueChanged<NFTAsset> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(nftCollectionsProvider);

    return collectionsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: _C.primary),
      ),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $e',
                style: const TextStyle(color: _C.textSecondary)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(nftCollectionsProvider),
              child: const Text('Retry',
                  style: TextStyle(color: _C.primary)),
            ),
          ],
        ),
      ),
      data: (collections) {
        final allNFTs = collections.expand((c) => c.nfts).toList();

        if (allNFTs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.collections_outlined,
                    color: _C.textSecondary, size: 48),
                SizedBox(height: 12),
                Text(
                  'No NFTs in your wallet',
                  style: TextStyle(
                      color: _C.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text(
                  'You need at least one NFT to create a listing',
                  style: TextStyle(color: _C.textSecondary, fontSize: 14),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Choose an NFT to list for sale',
                style: TextStyle(color: _C.textSecondary, fontSize: 14),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemCount: allNFTs.length,
                itemBuilder: (context, index) {
                  final nft = allNFTs[index];
                  return _SelectableNFTCard(
                    nft: nft,
                    onTap: () => onSelected(nft),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SelectableNFTCard extends StatelessWidget {
  const _SelectableNFTCard({required this.nft, required this.onTap});

  final NFTAsset nft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _C.surfaceLight,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image.
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: nft.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: nft.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: _C.surfaceVariant,
                          child: const Center(
                            child: Icon(Icons.image_outlined,
                                color: _C.primary, size: 32),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: _C.surfaceVariant,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: _C.textSecondary, size: 32),
                          ),
                        ),
                      )
                    : Container(
                        color: _C.surfaceVariant,
                        child: const Center(
                          child: Icon(Icons.image_outlined,
                              color: _C.textTertiary, size: 40),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nft.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _C.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (nft.collectionName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      nft.collectionName!,
                      style: const TextStyle(
                          fontSize: 11, color: _C.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Price Input
// ---------------------------------------------------------------------------

class _PriceInputStep extends StatelessWidget {
  const _PriceInputStep({
    super.key,
    required this.nft,
    required this.priceController,
    required this.feeBps,
    required this.onConfirm,
    this.error,
    this.isSubmitting = false,
  });

  final NFTAsset nft;
  final TextEditingController priceController;
  final int feeBps;
  final VoidCallback onConfirm;
  final String? error;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected NFT preview.
          _SelectedNFTPreview(nft: nft),

          const SizedBox(height: 24),

          // Price input.
          const Text(
            'Listing Price',
            style: TextStyle(
              color: _C.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              color: _C.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              hintText: '0.00',
              hintStyle: TextStyle(
                  color: _C.textTertiary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700),
              suffixText: 'SOL',
              suffixStyle: const TextStyle(
                color: _C.primary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: _C.surfaceLight,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: _C.primary.withValues(alpha: 0.5)),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Fee preview.
          _FeePreview(
            priceController: priceController,
            feeBps: feeBps,
          ),

          // Error message.
          if (error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _C.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: _C.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style:
                          const TextStyle(color: _C.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Slide to confirm.
          _SlideToConfirm(
            onConfirm: onConfirm,
            isLoading: isSubmitting,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SelectedNFTPreview extends StatelessWidget {
  const _SelectedNFTPreview({required this.nft});

  final NFTAsset nft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Thumbnail.
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 64,
              child: nft.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: nft.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: _C.surfaceVariant,
                        child: const Icon(Icons.image_outlined,
                            color: _C.primary, size: 24),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: _C.surfaceVariant,
                        child: const Icon(Icons.broken_image_outlined,
                            color: _C.textSecondary, size: 24),
                      ),
                    )
                  : Container(
                      color: _C.surfaceVariant,
                      child: const Icon(Icons.image_outlined,
                          color: _C.textTertiary, size: 24),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          // Info.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nft.name,
                  style: const TextStyle(
                    color: _C.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (nft.collectionName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    nft.collectionName!,
                    style: const TextStyle(
                        color: _C.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  nft.mint.length > 12
                      ? '${nft.mint.substring(0, 6)}...${nft.mint.substring(nft.mint.length - 6)}'
                      : nft.mint,
                  style:
                      const TextStyle(color: _C.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          const Icon(Icons.check_circle, color: _C.primary, size: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fee preview (updates as user types price)
// ---------------------------------------------------------------------------

class _FeePreview extends StatelessWidget {
  const _FeePreview({
    required this.priceController,
    required this.feeBps,
  });

  final TextEditingController priceController;
  final int feeBps;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: priceController,
      builder: (_, __) {
        final priceText = priceController.text.trim();
        String feeDisplay = '0 SOL';
        String feePercent = '${feeBps ~/ 100}%';

        if (priceText.isNotEmpty) {
          try {
            final priceLamports = solToLamports(priceText);
            if (priceLamports > BigInt.zero) {
              final feeLamports =
                  priceLamports * BigInt.from(feeBps) ~/ BigInt.from(10000);
              feeDisplay = '${lamportsToSol(feeLamports)} SOL';
            }
          } catch (_) {
            // Invalid input, show default.
          }
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _C.surfaceLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$feePercent marketplace fee',
                style: const TextStyle(
                    color: _C.textSecondary, fontSize: 13),
              ),
              Text(
                feeDisplay,
                style: const TextStyle(
                  color: _C.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Slide-to-confirm widget (consistent with wallet send_screen pattern)
// ---------------------------------------------------------------------------

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
                child: CircularProgressIndicator(
                    color: _C.primary, strokeWidth: 2.5),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxSlide = constraints.maxWidth - 56;
                return Stack(
                  children: [
                    Center(
                      child: Text(
                        'Slide to list for sale',
                        style: TextStyle(
                          color: _C.primary.withValues(alpha: 0.6),
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
