/// @file        transfer_request_screen.dart
/// @description Wallet V2 Phase 1 (Phase C + F) — sender (A) side transfer
///              request UI. Entered from a 1:1 chat via + menu → "Send Asset".
///              Pick SOL/USDC/NFT token + enter amount + pre-validate balance
///              + call TransferService.sendRequest directly.
///              Phase F: switched from Navigator.pop(req) return pattern to
///              an in-screen TransferService call + SnackBar feedback +
///              pop() (chat_screen is now a plain navigate).
///              Float/double strictly forbidden (wallet/CLAUDE.md §2.1) —
///              all amounts are BigInt.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-20
/// @lastUpdated 2026-04-26 (header + inline English translation; Phase F TransferService.sendRequest direct call — drop pop pattern)
///
/// @functions
///  - TransferRequestScreen (ConsumerStatefulWidget): sender-side request screen
///    - build(): AppBar + Network badge + Token selector + Amount input + Send button
///    - _onTokenChanged(): token toggle handler (SOL/SPL/NFT branch, NFT picker modal)
///    - _pickNft(): pick one NFT from owned list (modal bottom sheet)
///    - _validate(): amount + token + balance check (Send button enable condition)
///    - _computeAmountLamports(): UI display string → BigInt lamports raw
///    - _onSend(): compute amount + call transferServiceProvider.sendRequest + SnackBar + pop
///  - _SelectedTokenSpec (private class): UI selection state (token + mint + decimals + symbol + nft)
///  - _NftPickerSheet (private widget): owned-NFT modal bottom sheet

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/nft_models.dart';
import '../../../shared/models/wallet_models.dart';
import '../../nft/nft_provider.dart';
import '../models/transfer_request.dart';
import '../rpc/rpc_client_provider.dart';
import '../rpc/rpc_config.dart' show SolanaNetwork;
import '../services/transfer_service.dart';
import '../utils/amount_converter.dart';
import '../wallet_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Color tokens (matches the send_screen pattern — same wallet module)
// ─────────────────────────────────────────────────────────────────────────────

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
  static const warning = Color(0xFFFFA726);
}

// ─────────────────────────────────────────────────────────────────────────────
// Wire constants (no hard-coded mints in UI logic — same as token_list_service)
// ─────────────────────────────────────────────────────────────────────────────

/// USDC mint (mainnet standard). On devnet, the same mint is used as token
/// metadata but actual balance depends on the devnet-issued token. Spec
/// §6.2 V1.0 — simplification toggle.
/// Identical to the USDC entry in `token_list_service._wellKnownTokens` (single SOT).
const String _usdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const int _usdcDecimals = 6;
const int _solDecimals = 9;

/// ATA rent fee notice (P0-4, simplification V1.0). Phase E verifies via
/// RPC `getAccountInfo` — this is a display-only estimate. Solana standard
/// ~2,039,280 lamports.
const String _ataFeeNoticeSol = '0.002';

// ─────────────────────────────────────────────────────────────────────────────
// Token kind toggle UI state
// ─────────────────────────────────────────────────────────────────────────────

enum _TokenKind { sol, usdc, nft }

/// UI selection state — token wire format + mint for balance lookup + display meta.
@immutable
class _SelectedTokenSpec {
  const _SelectedTokenSpec({
    required this.kind,
    required this.tokenType,
    required this.mint,
    required this.decimals,
    required this.symbol,
    this.nft,
  });

  final _TokenKind kind;
  final TokenType tokenType;

  /// SOL → null, USDC → standard mint, NFT → selected NFT mint.
  final String? mint;
  final int decimals;
  final String symbol;

  /// Display meta when NFT is selected (image/name beyond symbol).
  final NFTAsset? nft;

  static const _SelectedTokenSpec sol = _SelectedTokenSpec(
    kind: _TokenKind.sol,
    tokenType: TokenType.sol,
    mint: null,
    decimals: _solDecimals,
    symbol: 'SOL',
  );

  static const _SelectedTokenSpec usdc = _SelectedTokenSpec(
    kind: _TokenKind.usdc,
    tokenType: TokenType.spl,
    mint: _usdcMint,
    decimals: _usdcDecimals,
    symbol: 'USDC',
  );

  factory _SelectedTokenSpec.nft(NFTAsset asset) {
    return _SelectedTokenSpec(
      kind: _TokenKind.nft,
      tokenType: TokenType.nft,
      mint: asset.mint,
      decimals: 0,
      symbol: asset.name.isNotEmpty ? asset.name : 'NFT',
      nft: asset,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// 1:1 chat transfer-request screen (sender A side).
///
/// Call pattern (Phase F — plain navigate, no result handling):
/// ```dart
/// await Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => TransferRequestScreen(
///       recipientSnowchatId: peer.snowchatId,
///       recipientDisplayName: peer.displayName,
///     ),
///   ),
/// );
/// // TransferService.sendRequest is called directly inside this screen.
/// ```
class TransferRequestScreen extends ConsumerStatefulWidget {
  const TransferRequestScreen({
    super.key,
    required this.recipientSnowchatId,
    required this.recipientDisplayName,
  });

  /// Recipient (B) SnowChat ID — used in Phase E by EncryptedMessageHandler.send.
  final String recipientSnowchatId;

  /// For header display — nickname or truncated SnowChat ID.
  final String recipientDisplayName;

  @override
  ConsumerState<TransferRequestScreen> createState() =>
      _TransferRequestScreenState();
}

class _TransferRequestScreenState extends ConsumerState<TransferRequestScreen> {
  final TextEditingController _amountController = TextEditingController();

  _SelectedTokenSpec _selected = _SelectedTokenSpec.sol;
  String? _formError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    // Re-render Send button enabled state.
    setState(() {
      _formError = null;
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helpers — balance / amount / validation
  // ───────────────────────────────────────────────────────────────────────────

  /// Balance of the selected token (raw lamports / smallest units).
  /// SOL: from walletProvider.balance.tokens with mint='SOL' or isNativeSOL.
  /// SPL/NFT: match by mint in the same tokens list (NFT balance is 1).
  BigInt? _balanceForSelected(WalletState walletState) {
    final tokens = walletState.balance?.tokens ?? const <TokenInfo>[];
    if (tokens.isEmpty) return null;

    if (_selected.kind == _TokenKind.sol) {
      for (final t in tokens) {
        if (t.isNativeSOL) return t.balanceLamports;
      }
      return BigInt.zero;
    }

    // SPL / NFT — match by mint. Don't distinguish null (unknown) from zero — treat as 0.
    final mint = _selected.mint;
    if (mint == null) return BigInt.zero;
    for (final t in tokens) {
      if (t.mint == mint) return t.balanceLamports;
    }
    return BigInt.zero;
  }

  /// UI display string ("1.5") → raw lamports (BigInt).
  /// null on invalid input.
  BigInt? _computeAmountLamports() {
    final raw = _amountController.text.trim();
    if (raw.isEmpty) return null;
    try {
      if (_selected.kind == _TokenKind.sol) {
        return solToLamports(raw);
      }
      if (_selected.kind == _TokenKind.nft) {
        // NFT is always 1 — ignore input.
        return BigInt.one;
      }
      // SPL (USDC) — convert with decimals.
      return tokenToSmallestUnit(raw, _selected.decimals);
    } on FormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Conditions for enabling the Send button.
  /// - amount > 0
  /// - amount <= balance
  /// - For NFT: an NFT must be selected
  bool _canSend(WalletState walletState) {
    if (_submitting) return false;
    if (walletState.publicKey == null) return false;

    if (_selected.kind == _TokenKind.nft && _selected.nft == null) {
      return false;
    }

    final amount = _computeAmountLamports();
    if (amount == null) return false;
    if (amount <= BigInt.zero) return false;

    final balance = _balanceForSelected(walletState);
    if (balance == null) return false; // balance loading
    if (amount > balance) return false;

    return true;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // UI handlers
  // ───────────────────────────────────────────────────────────────────────────

  void _onTokenChanged(_TokenKind kind) async {
    if (kind == _TokenKind.nft) {
      // NFT pick — owned-NFT modal.
      final picked = await _pickNft();
      if (picked == null) return; // user cancelled
      setState(() {
        _selected = _SelectedTokenSpec.nft(picked);
        _amountController.text = '1';
        _formError = null;
      });
      return;
    }

    setState(() {
      _selected = kind == _TokenKind.sol
          ? _SelectedTokenSpec.sol
          : _SelectedTokenSpec.usdc;
      _amountController.clear();
      _formError = null;
    });
  }

  Future<NFTAsset?> _pickNft() async {
    return showModalBottomSheet<NFTAsset>(
      context: context,
      backgroundColor: _C.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _NftPickerSheet(),
    );
  }

  /// Phase F: call TransferService.sendRequest directly.
  /// On success: SnackBar + pop. TransferLockException → notice SnackBar
  /// (per-peer pending lock). Other errors → error SnackBar + keep screen
  /// (retry allowed).
  Future<void> _onSend() async {
    final walletState = ref.read(walletProvider);

    if (!_canSend(walletState)) {
      setState(() => _formError = 'Cannot send — check amount and balance');
      return;
    }

    final amountLamports = _computeAmountLamports();
    if (amountLamports == null || amountLamports <= BigInt.zero) {
      setState(() => _formError = 'Invalid amount');
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });

    final transferService = ref.read(transferServiceProvider);

    try {
      await transferService.sendRequest(
        recipientSnowchatId: widget.recipientSnowchatId,
        amount: amountLamports,
        token: _selected.tokenType,
        mint: _selected.mint,
        decimals: _selected.decimals,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transfer request sent'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pop();
    } on TransferLockException catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = 'A transfer to this contact is already pending';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Previous transfer pending'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('[TransferRequestScreen] sendRequest failed: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = 'Failed to send transfer request';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send transfer request: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final network = ref.watch(solanaNetworkProvider);
    final balance = _balanceForSelected(walletState);
    final canSend = _canSend(walletState);

    return Scaffold(
      backgroundColor: _C.background,
      appBar: AppBar(
        backgroundColor: _C.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _C.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Send Asset to ${widget.recipientDisplayName}',
          style: const TextStyle(
            color: _C.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Network badge.
              _NetworkBadge(network: network),
              const SizedBox(height: 16),

              // Token selector.
              const Text(
                'Token',
                style: TextStyle(color: _C.textTertiary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _TokenSelectorRow(
                selected: _selected.kind,
                onChanged: _onTokenChanged,
              ),
              const SizedBox(height: 8),
              if (_selected.kind == _TokenKind.nft && _selected.nft != null)
                _SelectedNftCard(asset: _selected.nft!),
              const SizedBox(height: 20),

              // Amount input.
              const Text(
                'Amount',
                style: TextStyle(color: _C.textTertiary, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _AmountField(
                controller: _amountController,
                enabled: _selected.kind != _TokenKind.nft,
                symbol: _selected.symbol,
                decimals: _selected.decimals,
              ),
              const SizedBox(height: 8),
              _BalanceRow(
                walletInitialised: walletState.publicKey != null,
                balance: balance,
                decimals: _selected.decimals,
                symbol: _selected.symbol,
                kind: _selected.kind,
              ),

              // ATA fee notice (SPL/NFT only).
              if (_selected.kind != _TokenKind.sol) ...[
                const SizedBox(height: 16),
                _AtaFeeNotice(),
              ],

              // Form error.
              if (_formError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _formError!,
                  style: const TextStyle(color: _C.error, fontSize: 13),
                ),
              ],

              const SizedBox(height: 28),

              // Send button.
              _SendRequestButton(
                enabled: canSend,
                submitting: _submitting,
                onPressed: _onSend,
              ),
              const SizedBox(height: 12),

              // Phase E wire-up notice (dev stage — UI label English, for user clarity).
              const Text(
                'Recipient must accept this request before any asset moves.',
                style: TextStyle(color: _C.textTertiary, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NetworkBadge extends StatelessWidget {
  const _NetworkBadge({required this.network});

  final SolanaNetwork network;

  @override
  Widget build(BuildContext context) {
    final isDevnet = network == SolanaNetwork.devnet;
    final label = isDevnet ? 'Devnet' : 'Mainnet';
    final color = isDevnet ? _C.primary : _C.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TokenSelectorRow extends StatelessWidget {
  const _TokenSelectorRow({
    required this.selected,
    required this.onChanged,
  });

  final _TokenKind selected;
  final ValueChanged<_TokenKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TokenChip(
            label: 'SOL',
            isSelected: selected == _TokenKind.sol,
            onTap: () => onChanged(_TokenKind.sol),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TokenChip(
            label: 'USDC',
            isSelected: selected == _TokenKind.usdc,
            onTap: () => onChanged(_TokenKind.usdc),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _TokenChip(
            label: 'NFT',
            isSelected: selected == _TokenKind.nft,
            onTap: () => onChanged(_TokenKind.nft),
          ),
        ),
      ],
    );
  }
}

class _TokenChip extends StatelessWidget {
  const _TokenChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: isSelected ? _C.primaryBg : _C.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _C.primary : Colors.transparent,
            width: 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _C.primary : _C.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SelectedNftCard extends StatelessWidget {
  const _SelectedNftCard({required this.asset});

  final NFTAsset asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _C.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 40,
              height: 40,
              color: _C.surface,
              child: asset.imageUrl.isNotEmpty
                  ? Image.network(
                      asset.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.image_not_supported,
                        color: _C.textTertiary,
                        size: 20,
                      ),
                    )
                  : const Icon(
                      Icons.image,
                      color: _C.textTertiary,
                      size: 20,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.name.isEmpty ? 'Unnamed NFT' : asset.name,
                  style: const TextStyle(
                    color: _C.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  asset.mint,
                  style: const TextStyle(
                    color: _C.textTertiary,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    required this.enabled,
    required this.symbol,
    required this.decimals,
  });

  final TextEditingController controller;
  final bool enabled;
  final String symbol;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    // For NFT, amount is fixed to 1 — disabled + placeholder.
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        // One decimal point + digits only. Exact decimal-place validation
        // is capped at the BigInt conversion in _computeAmountLamports
        // (digits beyond decimals are truncated).
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: const TextStyle(
        color: _C.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: enabled ? '0' : '1 (NFT)',
        hintStyle: const TextStyle(color: _C.textTertiary),
        filled: true,
        fillColor: _C.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixText: symbol,
        suffixStyle: const TextStyle(
          color: _C.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.walletInitialised,
    required this.balance,
    required this.decimals,
    required this.symbol,
    required this.kind,
  });

  final bool walletInitialised;
  final BigInt? balance;
  final int decimals;
  final String symbol;
  final _TokenKind kind;

  @override
  Widget build(BuildContext context) {
    if (!walletInitialised) {
      return const Text(
        'Balance: wallet not initialised',
        style: TextStyle(color: _C.textTertiary, fontSize: 12),
      );
    }
    if (balance == null) {
      return const Text(
        'Balance: loading…',
        style: TextStyle(color: _C.textTertiary, fontSize: 12),
      );
    }

    final String display;
    if (kind == _TokenKind.sol) {
      display = '${lamportsToSol(balance!)} $symbol';
    } else if (kind == _TokenKind.nft) {
      // NFT balance is 1 (owned) or 0 (not owned). No separate display unit.
      display = balance == BigInt.one ? '1 owned' : '${balance!} owned';
    } else {
      display = '${smallestUnitToDisplay(balance!, decimals)} $symbol';
    }

    return Text(
      'Balance: $display',
      style: const TextStyle(color: _C.textSecondary, fontSize: 12),
    );
  }
}

class _AtaFeeNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _C.warning.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _C.warning.withOpacity(0.5), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: _C.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Recipient may need ATA: +$_ataFeeNoticeSol SOL fee',
              style: const TextStyle(color: _C.warning, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _SendRequestButton extends StatelessWidget {
  const _SendRequestButton({
    required this.enabled,
    required this.submitting,
    required this.onPressed,
  });

  final bool enabled;
  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _C.primary,
          disabledBackgroundColor: _C.surfaceVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: submitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Color(0xFF000000),
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                'Send Request',
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFF000000)
                      : _C.textTertiary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NFT picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _NftPickerSheet extends ConsumerWidget {
  const _NftPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncNfts = ref.watch(allNFTsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _C.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Select NFT',
              style: TextStyle(
                color: _C.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: asyncNfts.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: _C.primary),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'Failed to load NFTs: $e',
                      style: const TextStyle(color: _C.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                data: (nfts) {
                  if (nfts.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No NFTs found in this wallet.',
                          style: TextStyle(
                            color: _C.textSecondary,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: nfts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final nft = nfts[i];
                      return _NftListTile(
                        asset: nft,
                        onTap: () => Navigator.of(context).pop(nft),
                      );
                    },
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

class _NftListTile extends StatelessWidget {
  const _NftListTile({required this.asset, required this.onTap});

  final NFTAsset asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _C.surfaceVariant,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 44,
                height: 44,
                color: _C.surface,
                child: asset.imageUrl.isNotEmpty
                    ? Image.network(
                        asset.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported,
                          color: _C.textTertiary,
                          size: 20,
                        ),
                      )
                    : const Icon(
                        Icons.image,
                        color: _C.textTertiary,
                        size: 20,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name.isEmpty ? 'Unnamed NFT' : asset.name,
                    style: const TextStyle(
                      color: _C.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (asset.collectionName != null &&
                      asset.collectionName!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      asset.collectionName!,
                      style: const TextStyle(
                        color: _C.textTertiary,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: _C.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
