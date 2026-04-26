/// @file        marketplace_screen.dart
/// @description NFT Marketplace main screen — search, [All]/[My Listings] tabs,
///              per-collection grouping + 4-column compact grid,
///              infinite-scroll pagination, "List your NFT" FAB. Phantom-style dark theme.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-11
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - MarketplaceScreen: marketplace listing browsing screen (ConsumerStatefulWidget)
///  - _AllListingsTab: all listings tab (infinite scroll)
///  - _MyListingsTab: my listings tab
///  - _MarketplaceListingCard: listing card widget

/// NFT Marketplace main screen — browse, search, list, buy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../marketplace_models.dart';
import '../providers/marketplace_provider.dart';
import '../widgets/listing_detail_sheet.dart';
import '../../wallet/providers/wallet_list_provider.dart';
import '../../wallet/wallet_provider.dart' show walletProvider;

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const surfaceLight = Color(0xFF1A1A1A);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const shimmer = Color(0xFF1A1A1A);
}

class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
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
            if (context.canPop()) {
              context.pop();
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.go('/wallet');
              });
            }
          },
        ),
        title: const Text(
          'Marketplace',
          style: TextStyle(
            color: _C.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              // Search bar.
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: _C.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search collections...',
                    hintStyle:
                        const TextStyle(color: _C.textTertiary, fontSize: 14),
                    prefixIcon: const Icon(Icons.search,
                        color: _C.textSecondary, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                color: _C.textSecondary, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: _C.surfaceLight,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.trim());
                  },
                ),
              ),
              // Tab bar.
              TabBar(
                controller: _tabController,
                indicatorColor: _C.primary,
                labelColor: _C.primary,
                unselectedLabelColor: _C.textSecondary,
                indicatorWeight: 2,
                labelStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'My Listings'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _AllListingsTab(searchQuery: _searchQuery),
          const _MyListingsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/marketplace/create'),
        backgroundColor: _C.primary,
        foregroundColor: _C.background,
        icon: const Icon(Icons.add),
        label: const Text(
          'List your NFT',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group listings by collection name
// ---------------------------------------------------------------------------

Map<String, List<MarketplaceListing>> _groupByCollection(
    List<MarketplaceListing> listings) {
  final grouped = <String, List<MarketplaceListing>>{};
  for (final l in listings) {
    final key = (l.collectionName != null && l.collectionName!.isNotEmpty)
        ? l.collectionName!
        : 'Uncategorized';
    grouped.putIfAbsent(key, () => []).add(l);
  }
  // Sort alphabetically, "Uncategorized" last.
  final sorted = Map.fromEntries(
    grouped.entries.toList()
      ..sort((a, b) {
        if (a.key == 'Uncategorized') return 1;
        if (b.key == 'Uncategorized') return -1;
        return a.key.compareTo(b.key);
      }),
  );
  return sorted;
}

/// Build collection-grouped slivers (header + 4-col grid per collection).
List<Widget> _buildCollectionSlivers(
  Map<String, List<MarketplaceListing>> grouped, {
  bool isOwn = false,
}) {
  const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 4,
    crossAxisSpacing: 6,
    mainAxisSpacing: 6,
    childAspectRatio: 0.72,
  );

  return [
    for (final entry in grouped.entries) ...[
      SliverToBoxAdapter(
        child: _CollectionHeader(
            name: entry.key, count: entry.value.length),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        sliver: SliverGrid(
          gridDelegate: gridDelegate,
          delegate: SliverChildBuilderDelegate(
            (context, index) => _MarketplaceListingCard(
              listing: entry.value[index],
              isOwn: isOwn,
            ),
            childCount: entry.value.length,
          ),
        ),
      ),
    ],
  ];
}

// ---------------------------------------------------------------------------
// All Listings tab (with infinite scroll)
// ---------------------------------------------------------------------------

class _AllListingsTab extends ConsumerStatefulWidget {
  const _AllListingsTab({required this.searchQuery});

  final String searchQuery;

  @override
  ConsumerState<_AllListingsTab> createState() => _AllListingsTabState();
}

class _AllListingsTabState extends ConsumerState<_AllListingsTab> {
  final ScrollController _scrollController = ScrollController();
  final List<MarketplaceListing> _allListings = [];
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_AllListingsTab old) {
    super.didUpdateWidget(old);
    if (old.searchQuery != widget.searchQuery) {
      _resetAndReload();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _resetAndReload() {
    _allListings.clear();
    _currentPage = 1;
    _hasMore = true;
    _isLoadingMore = false;
    ref.invalidate(marketplaceListingsProvider);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadNextPage();
    }
  }

  void _loadNextPage() {
    setState(() => _isLoadingMore = true);
    _currentPage++;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filter = MarketplaceFilter(
      page: _currentPage,
      query: widget.searchQuery.isNotEmpty ? widget.searchQuery : null,
    );
    final listingsAsync = ref.watch(marketplaceListingsProvider(filter));

    return listingsAsync.when(
      loading: () {
        if (_allListings.isNotEmpty) {
          return _buildGrid(showLoadingMore: true);
        }
        return _buildShimmerGrid();
      },
      error: (e, _) {
        if (_allListings.isNotEmpty) {
          return _buildGrid();
        }
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  color: _C.textSecondary, size: 48),
              const SizedBox(height: 12),
              Text('Failed to load listings',
                  style: const TextStyle(
                      color: _C.textSecondary, fontSize: 16)),
              const SizedBox(height: 8),
              Text('$e',
                  style:
                      const TextStyle(color: _C.textTertiary, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _resetAndReload,
                child:
                    const Text('Retry', style: TextStyle(color: _C.primary)),
              ),
            ],
          ),
        );
      },
      data: (listings) {
        if (_currentPage == 1) _allListings.clear();
        final existingIds = _allListings.map((l) => l.id).toSet();
        for (final listing in listings) {
          if (!existingIds.contains(listing.id)) {
            _allListings.add(listing);
          }
        }
        _hasMore = listings.length >= 20;
        _isLoadingMore = false;

        if (_allListings.isEmpty) return _buildEmptyState();
        return _buildGrid();
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.storefront_outlined,
              color: _C.textSecondary, size: 64),
          const SizedBox(height: 16),
          const Text(
            'No listings yet',
            style: TextStyle(
                color: _C.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Be the first to list an NFT!',
            style: TextStyle(color: _C.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => context.push('/marketplace/create'),
            icon: const Icon(Icons.add, color: _C.primary),
            label: const Text('List your NFT',
                style: TextStyle(color: _C.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid({bool showLoadingMore = false}) {
    final grouped = _groupByCollection(_allListings);

    return RefreshIndicator(
      color: _C.primary,
      backgroundColor: _C.surface,
      onRefresh: () async => _resetAndReload(),
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          const SliverPadding(padding: EdgeInsets.only(top: 4)),
          ..._buildCollectionSlivers(grouped),
          // Loading more indicator.
          if (showLoadingMore || (_hasMore && _isLoadingMore))
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: CircularProgressIndicator(
                      color: _C.primary, strokeWidth: 2),
                ),
              ),
            ),
          // Bottom padding for FAB.
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(
          child: _CollectionHeader(name: '       ', count: 0),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
              childAspectRatio: 0.72,
            ),
            delegate: SliverChildBuilderDelegate(
              (_, __) => Container(
                decoration: BoxDecoration(
                  color: _C.shimmer,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              childCount: 8,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// My Listings tab
// ---------------------------------------------------------------------------

class _MyListingsTab extends ConsumerWidget {
  const _MyListingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myListingsAsync = ref.watch(myListingsProvider);

    return myListingsAsync.when(
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
              onPressed: () => ref.invalidate(myListingsProvider),
              child:
                  const Text('Retry', style: TextStyle(color: _C.primary)),
            ),
          ],
        ),
      ),
      data: (listings) {
        if (listings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inventory_2_outlined,
                    color: _C.textSecondary, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'No active listings',
                  style: TextStyle(
                      color: _C.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your listed NFTs will appear here',
                  style: TextStyle(color: _C.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => context.push('/marketplace/create'),
                  icon: const Icon(Icons.add, color: _C.primary),
                  label: const Text('List your NFT',
                      style: TextStyle(color: _C.primary)),
                ),
              ],
            ),
          );
        }

        final grouped = _groupByCollection(listings);

        return RefreshIndicator(
          color: _C.primary,
          backgroundColor: _C.surface,
          onRefresh: () async => ref.invalidate(myListingsProvider),
          child: CustomScrollView(
            slivers: [
              const SliverPadding(padding: EdgeInsets.only(top: 4)),
              ..._buildCollectionSlivers(grouped, isOwn: true),
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Collection section header
// ---------------------------------------------------------------------------

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({required this.name, required this.count});

  final String name;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
      child: Row(
        children: [
          const Icon(Icons.verified, size: 14, color: _C.primary),
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _C.textPrimary,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '($count)',
              style: const TextStyle(fontSize: 11, color: _C.textTertiary),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: Container(height: 1, color: _C.surfaceLight),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Compact marketplace listing card (4-column optimized)
// ---------------------------------------------------------------------------

class _MarketplaceListingCard extends ConsumerWidget {
  const _MarketplaceListingCard({
    required this.listing,
    this.isOwn = false,
  });

  final MarketplaceListing listing;
  final bool isOwn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Multi-Wallet Phase 5-2: isOwner is decided by which wallet in
    // visibleEntries matches. Comparing only the active wallet would
    // wrongly route own listings into the buy flow under multi-wallet.
    final ownerEntry = ref
        .watch(walletIndexProvider)
        .valueOrNull
        ?.findByAddress(listing.sellerAddress);
    final isOwner = ownerEntry != null;

    return GestureDetector(
      onTap: () {
        showListingDetailSheet(
          context: context,
          listing: listing,
          isOwner: isOwner,
          ref: ref,
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // NFT Image.
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: listing.nftImageUrl != null &&
                        listing.nftImageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: listing.nftImageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: _C.surfaceLight,
                          child: const Center(
                            child: Icon(Icons.image_outlined,
                                color: _C.primary, size: 20),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: _C.surfaceLight,
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: _C.textSecondary, size: 20),
                          ),
                        ),
                      )
                    : Container(
                        color: _C.surfaceLight,
                        child: const Center(
                          child: Icon(Icons.image_outlined,
                              color: _C.textTertiary, size: 24),
                        ),
                      ),
              ),
            ),

            // Compact info: name + price (+ wallet badge for own listings).
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 5, 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    listing.nftName ?? 'Unnamed',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _C.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    listing.formattedPrice,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _C.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Phase 5-2: wallet label badge only for own listings
                  if (isOwn && ownerEntry != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '· ${ownerEntry.label}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: _C.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
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
