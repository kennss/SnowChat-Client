/// @file        send_screen.dart
/// @description Token send screen — Phase 6.1: added priority-fee tier
///              toggle + simulation preview sheet. Preserves the existing
///              slide-to-confirm UI.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SendScreen: main send-screen widget (ConsumerStatefulWidget)

/// Phantom-style send screen with custom keypad and slide-to-confirm.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../address_book/address_book_sheet.dart';
import '../core/keypair_manager.dart';
import '../providers/balance_provider.dart';
import '../providers/wallet_list_provider.dart';
import '../../../shared/models/wallet_models.dart';
import '../naming/sns_resolver.dart';
import '../transaction/compute_budget_helper.dart';
import '../utils/solana_pay_parser.dart';
import '../utils/transfer_error_formatter.dart';
import '../wallet_provider.dart';
import '../widgets/amount_input.dart';
import '../widgets/fee_tier_selector.dart';
import '../widgets/send_preview_sheet.dart';
import '../widgets/wallet_picker_sheet.dart';
import 'qr_scan_screen.dart';

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

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key, this.preselectedToken, this.initialAddress});

  /// Optionally preselect a token (e.g. navigating from token detail).
  final TokenInfo? preselectedToken;

  /// Optionally prefill recipient address (e.g. "Send Again" from tx detail).
  final String? initialAddress;

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  final _addressController = TextEditingController();
  final _amountKey = GlobalKey<AmountInputState>();
  TokenInfo? _selectedToken;
  bool _isSending = false;
  String? _error;
  PriorityLevel _priorityLevel = PriorityLevel.normal;

  /// `.sol` resolution result (shown explicitly to user — anti-spoofing).
  String? _resolvedAddress;
  String? _resolvedDomain;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _selectedToken = widget.preselectedToken;
    if (widget.initialAddress != null) {
      _addressController.text = widget.initialAddress!;
    }
    _addressController.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _addressController.removeListener(_onAddressChanged);
    _addressController.dispose();
    super.dispose();
  }

  /// Detect address-input changes — for `.sol` domains, resolve in the background.
  /// Called on every change, so simple debounce.
  void _onAddressChanged() {
    final text = _addressController.text.trim();
    if (text.isEmpty) {
      if (_resolvedAddress != null || _resolvedDomain != null) {
        setState(() {
          _resolvedAddress = null;
          _resolvedDomain = null;
        });
      }
      return;
    }
    if (SnsResolver.isSnsDomain(text)) {
      _resolveSnsDomain(text);
    } else if (_resolvedAddress != null || _resolvedDomain != null) {
      setState(() {
        _resolvedAddress = null;
        _resolvedDomain = null;
      });
    }
  }

  Future<void> _resolveSnsDomain(String domain) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      final resolver = ref.read(snsResolverProvider);
      final result = await resolver.resolveDomain(domain);
      if (!mounted) return;
      // Ignore if the input changed in the meantime
      if (_addressController.text.trim().toLowerCase() !=
          result.domain.toLowerCase()) {
        return;
      }
      setState(() {
        _resolving = false;
        _resolvedDomain = result.domain;
        _resolvedAddress = result.address;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolvedDomain = null;
        _resolvedAddress = null;
        _error = 'Domain resolve failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final walletState = ref.watch(walletProvider);
    final tokens = walletState.balance?.tokens ?? [];

    // Default to first token if none selected.
    _selectedToken ??= tokens.isNotEmpty ? tokens.first : null;

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
          'Send',
          style: TextStyle(color: _C.textPrimary, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          if (tokens.isNotEmpty)
            PopupMenuButton<TokenInfo>(
              icon: Text(
                _selectedToken?.symbol ?? 'SOL',
                style: const TextStyle(
                  color: _C.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              color: _C.surface,
              onSelected: (token) => setState(() => _selectedToken = token),
              itemBuilder: (_) => tokens
                  .map((t) => PopupMenuItem(
                        value: t,
                        child: Text(
                          t.symbol,
                          style: const TextStyle(color: _C.textPrimary),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Phase 4B — From wallet selector chip.
            // On change, switch active via walletProvider.switchActive() →
            // balance / tokens / signer auto-refresh against that wallet.
            Builder(builder: (_) {
              final activeId = ref.watch(activeWalletIdProvider);
              if (activeId == null) return const SizedBox.shrink();
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: WalletPickerChip(
                    selectedId: activeId,
                    label: 'From',
                    title: 'Send from',
                    onChanged: (id) async {
                      try {
                        await ref
                            .read(walletProvider.notifier)
                            .switchActive(id);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Switch failed: $e'),
                              backgroundColor: const Color(0xFF111111),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              );
            }),

            // Recipient address.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _addressController,
                style: const TextStyle(color: _C.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Address, SnowChat ID, or name.sol',
                  hintStyle: const TextStyle(color: _C.textTertiary),
                  filled: true,
                  fillColor: _C.surfaceVariant,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Scan QR',
                        icon: const Icon(Icons.qr_code_scanner,
                            color: _C.textTertiary, size: 20),
                        onPressed: _scanQrCode,
                      ),
                      IconButton(
                        tooltip: 'Address book',
                        icon: const Icon(Icons.book_outlined,
                            color: _C.textTertiary, size: 20),
                        onPressed: _openAddressBook,
                      ),
                      IconButton(
                        tooltip: 'Paste',
                        icon: const Icon(Icons.content_paste,
                            color: _C.textTertiary, size: 20),
                        onPressed: _pasteAddress,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // SNS resolution banner (Phase 6.1 §3.6 — anti-spoofing).
            if (_resolving || _resolvedAddress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _C.primaryBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.primary, width: 1),
                  ),
                  child: _resolving
                      ? const Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _C.primary,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Resolving .sol domain…',
                              style: TextStyle(
                                color: _C.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resolves to (verify before sending):',
                              style: TextStyle(
                                color: _C.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _resolvedAddress!,
                              style: const TextStyle(
                                color: _C.primary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

            // Amount input with keypad.
            Expanded(
              child: AmountInput(
                key: _amountKey,
                symbol: _selectedToken?.symbol ?? 'SOL',
                usdRate: _selectedToken != null && _selectedToken!.usdValueCents > BigInt.zero
                    ? _selectedToken!.usdValueCents.toDouble() /
                        100.0 /
                        (double.tryParse(_selectedToken!.shortBalance) ?? 1.0)
                    : null,
                maxDecimals: _selectedToken?.decimals ?? 9,
              ),
            ),

            // Network speed (priority fee tier).
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Network speed',
                    style: TextStyle(color: _C.textTertiary, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  FeeTierSelector(
                    value: _priorityLevel,
                    onChanged: (l) => setState(() => _priorityLevel = l),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Error message.
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 100),
                  child: SingleChildScrollView(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: _C.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

            // Slide to confirm.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: _SlideToConfirm(
                isLoading: _isSending,
                onConfirm: _handleSend,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Handle QR-scan result. Solana Pay URI prefills; otherwise fill the input
  /// with raw text (subsequent .sol auto-resolution / validation is handled
  /// by _onAddressChanged).
  Future<void> _scanQrCode() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (scanned == null || !mounted) return;

    final pay = SolanaPayParser.tryParse(scanned);
    if (pay != null) {
      _applySolanaPayRequest(pay);
    } else {
      _addressController.text = scanned;
    }
  }

  Future<void> _openAddressBook() async {
    final owner = ref.read(walletProvider).publicKey;
    if (owner == null) return;
    final picked = await showAddressBookPickerSheet(
      context: context,
      ref: ref,
      ownerAddress: owner,
    );
    if (picked != null && mounted) {
      _addressController.text = picked.address;
    }
  }

  Future<void> _pasteAddress() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;

    // Auto-recover iOS Simulator host→guest pasteboard UTF-16 LE corruption:
    // when macOS clipboard sends UTF-16 LE and the simulator reads it as
    // UTF-8, each ASCII char becomes a CJK ideograph. Split each codepoint
    // into 2 bytes to recover the original ASCII.
    final isAscii = text.codeUnits.every((c) => c < 128);
    if (!isAscii) {
      final recovered = _tryRecoverUtf16Le(text);
      if (recovered != null) {
        // Recovery succeeded — verify Solana Pay / address before using
        final pay = SolanaPayParser.tryParse(recovered);
        if (pay != null) {
          _applySolanaPayRequest(pay);
          return;
        }
        _addressController.text = recovered;
        return;
      }
      // Recovery failed — surface the error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: _C.surface,
            content: Text(
              'Clipboard data corrupted. Use Simulator menu → Edit → '
              'Send Clipboard to Device, or test on a real device.',
              style: TextStyle(color: _C.textPrimary),
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    // Auto-detect Solana Pay URI (Phase 6.1 §3.4)
    final pay = SolanaPayParser.tryParse(text);
    if (pay != null) {
      _applySolanaPayRequest(pay);
      return;
    }
    _addressController.text = text;
  }

  void _applySolanaPayRequest(SolanaPayRequest req) {
    _addressController.text = req.recipient;
    // amount prefill (SOL only — for SPL, token decimals unknown so not applied)
    if (req.amountLamports != null) {
      final amountStr = _lamportsToDisplay(req.amountLamports!, 9);
      _amountKey.currentState?.setAmount(amountStr);
    }
    final label = req.label ?? req.message;
    if (mounted && label != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _C.surface,
          content: Text(
            'Solana Pay: $label',
            style: const TextStyle(color: _C.textPrimary),
          ),
        ),
      );
    }
  }

  static String _lamportsToDisplay(BigInt lamports, int decimals) {
    final divisor = BigInt.from(10).pow(decimals);
    final whole = lamports ~/ divisor;
    final frac = lamports % divisor;
    if (frac == BigInt.zero) return whole.toString();
    final fracStr = frac.toString().padLeft(decimals, '0').replaceAll(
          RegExp(r'0+$'),
          '',
        );
    return fracStr.isEmpty ? whole.toString() : '$whole.$fracStr';
  }

  Future<void> _handleSend() async {
    final input = _addressController.text.trim();
    final amountStr = _amountKey.currentState?.amount ?? '0';

    if (input.isEmpty) {
      setState(() => _error = 'Enter a recipient address');
      return;
    }
    if (amountStr == '0' || amountStr.isEmpty) {
      setState(() => _error = 'Enter an amount');
      return;
    }

    // For .sol domains use the resolved address. Block when unresolved.
    final String address;
    if (SnsResolver.isSnsDomain(input)) {
      if (_resolvedAddress == null) {
        setState(() => _error = 'Domain not resolved yet — please wait');
        return;
      }
      address = _resolvedAddress!;
    } else {
      address = input;
    }

    final token = _selectedToken;
    final lamports = (token != null && !token.isNativeSOL)
        ? _parseTokenAmount(amountStr, token.decimals)
        : KeypairManager.solToLamports(amountStr);

    // Phase A-4: extra defense against amount 0 ('0.0' / '0.00' etc. that
    // pass the line 514 check). Block before self-send dialog to avoid
    // wasting only the fee.
    if (lamports <= BigInt.zero) {
      setState(() => _error = 'Enter a positive amount');
      return;
    }

    // Phase 6-D: self-send detection. When recipient is one of the user's
    // own wallets, get explicit confirmation. Prevents user mistakes
    // (e.g. wrong clipboard paste). Intentional self-send is allowed —
    // proceed after confirm.
    final ownEntry = ref
        .read(walletIndexProvider)
        .valueOrNull
        ?.findByAddress(address);
    if (ownEntry != null) {
      final activeAddr = ref.read(walletProvider).publicKey;
      final isSameWallet = ownEntry.address == activeAddr;
      final selfConfirmed = await _showSelfSendWarning(
        context,
        ownEntry.label,
        address,
        isSameWallet: isSameWallet,
      );
      if (!selfConfirmed) return;
    }

    // Step 1: preview sheet (Phase 6.1 §2.3 — simulate + tier choice)
    final notifier = ref.read(walletProvider.notifier);
    final previewResult = await showSendPreviewSheet(
      context: context,
      recipient: address,
      amountLamports: lamports,
      tokenSymbol: token?.symbol ?? 'SOL',
      tokenDecimals: token?.decimals ?? 9,
      initialLevel: _priorityLevel,
      loadEstimate: (level) => notifier.previewSolFee(
        toAddress: address,
        lamports: lamports,
        level: level,
      ),
    );

    if (previewResult == null || !previewResult.confirmed) {
      return; // user cancelled
    }
    setState(() => _priorityLevel = previewResult.level);

    setState(() {
      _isSending = true;
      _error = null;
    });

    // Phase 4C — SendLock acquire. Snapshot the walletId at send-start so
    // finally releases the same id exactly. Even if active changes
    // mid-flight, the current in-flight tx remains tied to the original
    // wallet.
    final sendingWalletId = ref.read(activeWalletIdProvider);
    final sendLock = ref.read(walletSendLockProvider);
    if (sendingWalletId != null) sendLock.acquire(sendingWalletId);

    try {
      String sig;
      if (token != null && !token.isNativeSOL) {
        sig = await notifier.sendSPLToken(
          toAddress: address,
          tokenMint: token.mint,
          amount: lamports,
          decimals: token.decimals,
          level: previewResult.level,
        );
      } else {
        sig = await notifier.sendSOL(
          toAddress: address,
          lamports: lamports,
          level: previewResult.level,
        );
      }

      if (mounted) {
        final network = ref.read(solanaNetworkProvider);
        final explorerUrl = getSolanaExplorerUrl(sig, network);

        // Phase 6.1 §3.5 — offer to save to address book right after sending
        // (skipping when input is a .sol domain or address is already saved
        // is a future improvement)
        final owner = ref.read(walletProvider).publicKey;
        if (owner != null) {
          await showSaveAddressDialog(
            context: context,
            ref: ref,
            ownerAddress: owner,
            address: address,
            network: network.name,
          );
        }
        if (!mounted) return;
        _showSuccessDialog(sig, explorerUrl);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _error = TransferErrorFormatter.format(e.toString());
        });
      }
    } finally {
      if (sendingWalletId != null) sendLock.release(sendingWalletId);
    }
  }

  /// Recover iOS Simulator UTF-16 LE corruption.
  /// When macOS clipboard sends ASCII as UTF-16 LE, each character corrupts
  /// into a CJK ideograph. Recoverable when each codepoint's low byte is ASCII.
  static String? _tryRecoverUtf16Le(String text) {
    final buf = StringBuffer();
    for (final cu in text.codeUnits) {
      final lo = cu & 0xFF;
      final hi = (cu >> 8) & 0xFF;
      // Low byte must be printable ASCII (0x20~0x7E)
      if (lo < 0x20 || lo > 0x7E) return null;
      buf.writeCharCode(lo);
      // If high byte is non-zero, it must also be ASCII
      if (hi != 0) {
        if (hi < 0x20 || hi > 0x7E) return null;
        buf.writeCharCode(hi);
      }
    }
    final recovered = buf.toString();
    // Final check that the recovered result is all ASCII
    if (recovered.codeUnits.every((c) => c < 128) && recovered.length >= 32) {
      return recovered;
    }
    return null;
  }

  static BigInt _parseTokenAmount(String input, int decimals) {
    final parts = input.split('.');
    final integerPart =
        BigInt.parse(parts[0].isEmpty ? '0' : parts[0]) *
            BigInt.from(10).pow(decimals);
    if (parts.length == 1) return integerPart;
    final frac = parts[1].padRight(decimals, '0').substring(0, decimals);
    return integerPart + BigInt.parse(frac);
  }

  // Phase 6-D: self-send confirm dialog. Called when recipient is one of
  // the user's own wallets. Returns true if the user confirms it's intentional, false otherwise.
  Future<bool> _showSelfSendWarning(
    BuildContext context,
    String walletLabel,
    String address, {
    required bool isSameWallet,
  }) async {
    final shortAddr = address.length > 12
        ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
        : address;
    final result = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: _C.surface,
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: _C.primary, size: 22),
            SizedBox(width: 8),
            Text(
              'Sending to your own wallet',
              style: TextStyle(color: _C.textPrimary, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSameWallet
                  ? 'The recipient is the SAME wallet you are sending '
                      'from ($walletLabel). The transfer will only cost '
                      'the network fee (~0.000005 SOL); the amount will '
                      'just move to itself.'
                  : 'The recipient is your own wallet "$walletLabel" '
                      '($shortAddr). This is fine if you intend to move '
                      'funds between your own wallets.',
              style: const TextStyle(
                color: _C.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('Send anyway'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _showSuccessDialog(String signature, String explorerUrl) {
    // Send succeeded → auto-refresh balance/history
    ref.invalidate(solBalanceProvider);
    ref.invalidate(tokenBalancesProvider);
    ref.invalidate(transactionHistoryProvider);
    // Also refresh walletProvider that BalanceCard watches (for immediate sender-side reflection)
    ref.read(walletProvider.notifier).refreshBalance(force: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: _C.surface,
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: _C.primary, size: 24),
            SizedBox(width: 8),
            Text(
              'Transaction Sent',
              style: TextStyle(color: _C.textPrimary, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Signature:',
              style: TextStyle(color: _C.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            SelectableText(
              signature,
              style: const TextStyle(
                color: _C.textPrimary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              explorerUrl,
              style: TextStyle(
                color: _C.primary.withValues(alpha: 0.7),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, signature);
            },
            child: const Text('Done', style: TextStyle(color: _C.primary)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide-to-confirm widget
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
                  color: _C.primary,
                  strokeWidth: 2.5,
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final maxSlide = constraints.maxWidth - 56;
                return Stack(
                  children: [
                    // Label.
                    Center(
                      child: Text(
                        'Slide to confirm',
                        style: TextStyle(
                          color: _C.primary.withOpacity(0.6),
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    // Thumb.
                    Positioned(
                      left: _progress * maxSlide,
                      top: 4,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (details) {
                          setState(() {
                            _progress += details.delta.dx / maxSlide;
                            _progress = _progress.clamp(0.0, 1.0);
                          });
                        },
                        onHorizontalDragEnd: (details) {
                          if (_progress > 0.85) {
                            widget.onConfirm();
                          }
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
