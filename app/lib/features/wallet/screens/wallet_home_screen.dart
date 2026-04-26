/// @file        wallet_home_screen.dart
/// @description Main wallet home screen (real data wiring, shimmer loading,
///              Devnet badge, airdrop button, pull-to-refresh, Helius
///              Enhanced History Activity tab + legacy fallback).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; fix: removed ref.read in dispose — WalletLiveService cache pattern)
///
/// @functions
///  - WalletHomeScreen: main wallet-home screen widget (ConsumerStatefulWidget)

/// Phantom-style wallet home screen.
///
/// Layout: large balance -> action buttons -> tabbed content (Tokens | NFTs | Activity).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../live/wallet_live_provider.dart';
import '../live/wallet_live_service.dart' show WalletLiveService;
import '../providers/enhanced_history_provider.dart';
import '../providers/wallet_list_provider.dart';
import '../wallet_provider.dart';
import '../widgets/balance_card.dart';
import '../widgets/action_buttons.dart';
import '../widgets/token_list_tile.dart';
import '../widgets/tx_list_tile.dart';
import '../widgets/enhanced_tx_list_tile.dart';
import '../widgets/wallet_selector_chip.dart';
import '../../nft/widgets/nft_card.dart';
import '../../nft/nft_provider.dart';
import '../../settings/screens/network_settings_screen.dart';

abstract class _C {
  static const background = Color(0xFF000000);
  static const primary = Color(0xFF00F782);
  static const surface = Color(0xFF111111);
  static const textSecondary = Color(0xFF9E9E9E);
  static const textTertiary = Color(0xFF5C5C5C);
  static const shimmer = Color(0xFF1A1A1A);
  static const shimmerHighlight = Color(0xFF2A2A2A);
}

class WalletHomeScreen extends ConsumerStatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  ConsumerState<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends ConsumerState<WalletHomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _tabController;
  // ref.read at dispose time is forbidden in Riverpod 2.x (assert fail).
  // Cache the latest instance in didChangeDependencies and use it in dispose.
  WalletLiveService? _liveService;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    // Initialize wallet data from real RPC.
    Future.microtask(() {
      if (!mounted) return;
      ref.read(walletProvider.notifier).initialize();
      ref.read(walletLiveServiceProvider)?.start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _liveService = ref.read(walletLiveServiceProvider);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveService?.stop();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final svc = ref.read(walletLiveServiceProvider);
    if (svc == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      svc.pause();
    } else if (state == AppLifecycleState.resumed) {
      svc.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final network = ref.watch(solanaNetworkProvider);

    // Auto-start LiveService once the wallet address is ready.
    // If non-null on first build, start immediately and handle later changes too.
    final liveSvc = ref.watch(walletLiveServiceProvider);
    ref.listen(walletLiveServiceProvider, (prev, next) {
      if (next != null && prev != next) {
        debugPrint('[WalletHome] LiveService changed → start()');
        next.start();
      }
    });
    if (liveSvc != null) {
      Future.microtask(() => liveSvc.start());
    }
    return Scaffold(
      backgroundColor: _C.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: _C.primary,
          backgroundColor: _C.surface,
          onRefresh: () => ref.read(walletProvider.notifier).refreshBalance(),
          child: CustomScrollView(
            slivers: [
              // App bar area with network badge.
              //
              // 2026-04-25: removed the devnet "Get Test SOL" button.
              // Public devnet requestAirdrop RPC / Helius / faucet.solana.com
              // all lack bot/automation paths, so no reliable UX is possible.
              // The server keeps the `/wallet/airdrop` proxy + faucet wallet
              // (admin curl).
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => context.push('/settings/network'),
                        child:
                            NetworkBadge(network: network, compact: true),
                      ),
                      // Multi-Wallet Phase 3B — active wallet selector chip
                      const WalletSelectorChip(),
                    ],
                  ),
                ),
              ),

              // Multi-Wallet Phase 3E — E-1 banner: when active != default
              const SliverToBoxAdapter(
                child: _ActiveDefaultMismatchBanner(),
              ),

              // Balance card (real data or shimmer).
              const SliverToBoxAdapter(child: BalanceCard()),

              // Action buttons.
              SliverToBoxAdapter(
                child: ActionButtons(
                  onReceive: () => context.push('/wallet/receive'),
                  onSend: () => context.push('/wallet/send'),
                  onSwap: () {
                    // TODO: Swap screen (Phase 6.2).
                  },
                  onMarket: () => context.push('/marketplace'),
                ),
              ),

              // Tab bar.
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  tabController: _tabController,
                ),
              ),

              // Tab content.
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    _TokensTab(),
                    _NFTsTab(),
                    _ActivityTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Shimmer placeholder
// ---------------------------------------------------------------------------

class ShimmerBlock extends StatefulWidget {
  const ShimmerBlock({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Color.lerp(
            _C.shimmer,
            _C.shimmerHighlight,
            _animation.value,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multi-Wallet Phase 3E — E-1: active != default banner
// ---------------------------------------------------------------------------

class _ActiveDefaultMismatchBanner extends ConsumerWidget {
  const _ActiveDefaultMismatchBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeWalletIdProvider);
    final defaultId = ref.watch(defaultWalletIdProvider);
    final defaultEntry = ref.watch(defaultWalletEntryProvider);

    if (activeId == null ||
        defaultId == null ||
        defaultEntry == null ||
        activeId == defaultId) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: GestureDetector(
        onTap: () async {
          try {
            await ref
                .read(walletProvider.notifier)
                .switchActive(defaultEntry.id);
          } catch (_) {/* swallow — skip toast */}
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFAA00).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFFFAA00).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFFFFAA00),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: Color(0xFFFFAA00),
                      fontSize: 12,
                      height: 1.3,
                    ),
                    children: [
                      const TextSpan(
                        text: 'Friend transfers (via SnowChat ID) arrive '
                            'at: ',
                      ),
                      TextSpan(
                        text: defaultEntry.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: '  ·  Tap to switch'),
                    ],
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFFFAA00),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab bar delegate
// ---------------------------------------------------------------------------

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate({required this.tabController});

  final TabController tabController;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: _C.background,
      child: TabBar(
        controller: tabController,
        indicatorColor: _C.primary,
        labelColor: _C.primary,
        unselectedLabelColor: _C.textSecondary,
        indicatorWeight: 2,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(text: 'Tokens'),
          Tab(text: 'NFTs'),
          Tab(text: 'Activity'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// Tokens tab
// ---------------------------------------------------------------------------

class _TokensTab extends ConsumerWidget {
  const _TokensTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletState = ref.watch(walletProvider);
    final tokens = walletState.balance?.tokens ?? [];

    // Shimmer loading state.
    if (walletState.isLoading && tokens.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: 4,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ShimmerBlock(width: 40, height: 40),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBlock(width: 100, height: 14),
                    SizedBox(height: 6),
                    ShimmerBlock(width: 60, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Error state with retry.
    if (walletState.error != null && tokens.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Failed to load tokens',
              style: const TextStyle(color: _C.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              walletState.error!,
              style: const TextStyle(color: _C.textTertiary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () =>
                  ref.read(walletProvider.notifier).refreshBalance(),
              child: const Text('Retry', style: TextStyle(color: _C.primary)),
            ),
          ],
        ),
      );
    }

    if (tokens.isEmpty) {
      return const Center(
        child: Text(
          'No tokens yet',
          style: TextStyle(color: _C.textSecondary, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: tokens.length,
      itemBuilder: (context, index) {
        final token = tokens[index];
        return TokenListTile(
          token: token,
          onTap: () => context.push('/wallet/token', extra: token),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// NFTs tab
// ---------------------------------------------------------------------------

class _NFTsTab extends ConsumerWidget {
  const _NFTsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nftState = ref.watch(nftCollectionsProvider);

    return nftState.when(
      loading: () => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.82,
        ),
        itemCount: 4,
        itemBuilder: (_, __) => const ShimmerBlock(width: double.infinity, height: 180),
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
            child: Text(
              'No NFTs yet',
              style: TextStyle(color: _C.textSecondary, fontSize: 16),
            ),
          );
        }

        final allNFTs = collections.expand((c) => c.nfts).toList();
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.82,
          ),
          itemCount: allNFTs.length,
          itemBuilder: (context, index) {
            return NFTCard(
              nft: allNFTs[index],
              onTap: () => context.push('/nft/detail', extra: allNFTs[index]),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Activity tab — Enhanced History (Helius) with legacy fallback
// ---------------------------------------------------------------------------

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enhancedAvailable = ref.watch(enhancedHistoryAvailableProvider);

    // When Helius is not configured or returns 503, fall back to the existing transactionHistoryProvider.
    if (!enhancedAvailable) {
      return _LegacyActivityList();
    }

    return _EnhancedActivityList();
  }
}

/// Activity list backed by Helius Enhanced Transactions.
class _EnhancedActivityList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enhancedHistory = ref.watch(enhancedHistoryProvider);
    final ownerAddress = ref.watch(walletProvider.select((s) => s.publicKey));

    return enhancedHistory.when(
      loading: () => _shimmerList(),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $e', style: const TextStyle(color: _C.textSecondary)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(enhancedHistoryProvider),
              child: const Text('Retry', style: TextStyle(color: _C.primary)),
            ),
          ],
        ),
      ),
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(
            child: Text(
              'No activity yet',
              style: TextStyle(color: _C.textSecondary, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index];
            return EnhancedTxListTile(
              tx: tx,
              ownerAddress: ownerAddress ?? '',
              onTap: () => context.push('/wallet/tx-detail', extra: tx.signature),
            );
          },
        );
      },
    );
  }
}

/// Activity list backed by the existing TransactionParser (fallback).
class _LegacyActivityList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txHistory = ref.watch(transactionHistoryProvider);

    return txHistory.when(
      loading: () => _shimmerList(),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Error: $e', style: const TextStyle(color: _C.textSecondary)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref.invalidate(transactionHistoryProvider),
              child: const Text('Retry', style: TextStyle(color: _C.primary)),
            ),
          ],
        ),
      ),
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(
            child: Text(
              'No activity yet',
              style: TextStyle(color: _C.textSecondary, fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index];
            return TxListTile(
              tx: tx,
              onTap: () => context.push('/wallet/tx-detail', extra: tx.signature),
            );
          },
        );
      },
    );
  }
}

Widget _shimmerList() {
  return ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: 5,
    itemBuilder: (_, __) => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          ShimmerBlock(width: 36, height: 36),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBlock(width: 120, height: 14),
                SizedBox(height: 6),
                ShimmerBlock(width: 80, height: 12),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
