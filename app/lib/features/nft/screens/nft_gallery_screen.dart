/// @file        nft_gallery_screen.dart
/// @description NFT gallery screen (server API integration, 2-column grid grouped by collection, error retry).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - NFTGalleryScreen: screen widget displaying NFT gallery grouped by collection

/// Phantom-style NFT gallery with 2-column grid grouped by collection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../shared/models/nft_models.dart';
import '../nft_provider.dart';
import '../widgets/collection_header.dart';
import '../widgets/nft_card.dart';

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
}

class NFTGalleryScreen extends ConsumerWidget {
  const NFTGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(nftCollectionsProvider);
    final nftCountAsync = ref.watch(nftCountProvider);

    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        elevation: 0,
        title: Row(
          children: [
            const Text(
              'My NFTs',
              style: TextStyle(
                color: _C.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
            const SizedBox(width: 8),
            nftCountAsync.when(
              data: (count) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _C.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: _C.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      body: collectionsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: _C.primary),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Error: $e', style: const TextStyle(color: _C.textSecondary)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => ref.invalidate(nftCollectionsProvider),
                child: const Text('Retry', style: TextStyle(color: _C.primary)),
              ),
            ],
          ),
        ),
        data: (collections) {
          if (collections.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_not_supported_outlined, color: _C.textSecondary, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'No NFTs yet',
                    style: TextStyle(color: _C.textSecondary, fontSize: 16),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: collections.length,
            itemBuilder: (context, index) {
              return _CollectionSection(collection: collections[index]);
            },
          );
        },
      ),
    );
  }
}

/// A single collection section: header + 2-col grid of NFTs.
class _CollectionSection extends StatelessWidget {
  const _CollectionSection({required this.collection});

  final NFTCollection collection;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CollectionHeader(collection: collection),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.82,
            ),
            itemCount: collection.nfts.length,
            itemBuilder: (context, i) {
              final nft = collection.nfts[i];
              return NFTCard(
                nft: nft,
                onTap: () => context.push('/nft/detail', extra: nft),
              );
            },
          ),
        ),
      ],
    );
  }
}
