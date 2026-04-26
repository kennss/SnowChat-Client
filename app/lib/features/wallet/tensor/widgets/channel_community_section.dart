/// @file        channel_community_section.dart
/// @description Community Fee Share section for `ChannelAdminScreen`.
///              Channel owner enters their collection mint; the widget
///              fetches the on-chain CommunityRegistration PDA and shows
///              status + stats + Seal/Register/Revoke actions. Gated on
///              `communityFeaturesEnabledProvider` — renders a locked
///              banner on mainnet.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-24
/// @lastUpdated 2026-04-24

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana/solana.dart';

import '../../../../shared/constants/colors.dart';
import '../../../../shared/constants/sizes.dart';
import '../../../../shared/widgets/toast.dart';
import '../community_registration.dart';
import '../tensor_providers.dart';

class ChannelCommunitySection extends ConsumerStatefulWidget {
  const ChannelCommunitySection({
    super.key,
    required this.channelId,
  });

  final String channelId;

  @override
  ConsumerState<ChannelCommunitySection> createState() =>
      _ChannelCommunitySectionState();
}

class _ChannelCommunitySectionState
    extends ConsumerState<ChannelCommunitySection> {
  final _collectionMintCtl = TextEditingController();
  final _snowchatIdCtl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _collectionMintCtl.dispose();
    _snowchatIdCtl.dispose();
    super.dispose();
  }

  Future<void> _sealAndRegister() async {
    final mintText = _collectionMintCtl.text.trim();
    final snowchatId = _snowchatIdCtl.text.trim();
    if (mintText.isEmpty) {
      SnowToast.show(context, message: 'Enter collection mint');
      return;
    }
    if (snowchatId.length != 36) {
      SnowToast.show(context, message: 'SnowChat ID must be 36 chars ("snow" + 32 hex)');
      return;
    }
    Ed25519HDPublicKey mint;
    try {
      mint = Ed25519HDPublicKey.fromBase58(mintText);
    } catch (_) {
      SnowToast.show(context, message: 'Invalid mint pubkey');
      return;
    }

    final channelId = widget.channelId.padRight(32, '_').substring(0, 32);
    setState(() => _busy = true);
    final service = ref.read(tensorTxServiceProvider);
    try {
      // Single tx = single biometric prompt. Two back-to-back prompts
      // triggered the Galaxy fingerprint-hang (user report 2026-04-24).
      final result = await service.sealAndRegister(
        collectionMint: mint,
        snowchatId: snowchatId,
        channelId: channelId,
      );
      if (!mounted) return;
      ref.invalidate(communityRegistrationFetchProvider(mintText));
      SnowToast.show(
        context,
        message: 'Sealed + registered: ${result.signature.substring(0, 10)}…',
      );
    } catch (e) {
      if (mounted) SnowToast.show(context, message: 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Ed25519HDPublicKey mint) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Revoke registration?'),
        content: const Text(
          '30-day cooldown from register time is enforced on-chain. '
          'Early revocation will fail with CommunityCooldownActive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke',
                style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(tensorTxServiceProvider)
          .revoke(collectionMint: mint);
      if (!mounted) return;
      ref.invalidate(
          communityRegistrationFetchProvider(mint.toBase58()));
      SnowToast.show(context, message: 'Revoked: ${result.signature.substring(0, 10)}…');
    } catch (e) {
      if (mounted) SnowToast.show(context, message: 'Revoke failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(communityFeaturesEnabledProvider);
    if (!enabled) {
      return Container(
        padding: const EdgeInsets.all(SnowSizes.md),
        decoration: BoxDecoration(
          color: SnowColors.surface,
          borderRadius: BorderRadius.circular(SnowSizes.radiusMd),
          border: Border.all(color: SnowColors.divider),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline, color: SnowColors.textTertiary),
            SizedBox(width: SnowSizes.sm),
            Expanded(
              child: Text(
                'Community Fee Share is devnet-only. Switch network in Settings.',
                style: TextStyle(
                  color: SnowColors.textTertiary,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final mintText = _collectionMintCtl.text.trim();
    final asyncReg = mintText.isEmpty
        ? const AsyncData<CommunityRegistration?>(null)
        : ref.watch(communityRegistrationFetchProvider(mintText));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _input(_collectionMintCtl, 'Collection NFT mint (Base58)',
            onChanged: (_) => setState(() {})),
        _input(_snowchatIdCtl, 'Leader SnowChat ID ("snow" + 32 hex)'),
        const SizedBox(height: SnowSizes.sm),
        asyncReg.when(
          data: (reg) {
            if (reg == null) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (mintText.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: SnowSizes.xs),
                      child: Text(
                        'Not registered yet',
                        style: TextStyle(
                            color: SnowColors.textTertiary, fontSize: 12),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sealAndRegister,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock),
                    label: const Text('Seal metadata + Register'),
                  ),
                ],
              );
            }
            return _RegisteredCard(
              registration: reg,
              busy: _busy,
              onRevoke: () => _revoke(reg.collectionMint),
            );
          },
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: LinearProgressIndicator(),
          ),
          error: (e, _) => Text(
            'Fetch error: $e',
            style: const TextStyle(color: SnowColors.error, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _RegisteredCard extends StatelessWidget {
  const _RegisteredCard({
    required this.registration,
    required this.busy,
    required this.onRevoke,
  });

  final CommunityRegistration registration;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final cumSol = registration.cumulativeShareLamports.toDouble() / 1e9;
    final registeredDate = DateTime.fromMillisecondsSinceEpoch(
      registration.registeredAt * 1000,
    );
    return Container(
      padding: const EdgeInsets.all(SnowSizes.md),
      decoration: BoxDecoration(
        color: SnowColors.surface,
        borderRadius: BorderRadius.circular(SnowSizes.radiusMd),
        border: Border.all(color: SnowColors.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: SnowColors.primary, size: 18),
              const SizedBox(width: SnowSizes.xs),
              Text(
                registration.isActive ? 'Active' : 'Revoked',
                style: TextStyle(
                  color: registration.isActive
                      ? SnowColors.primary
                      : SnowColors.textTertiary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: SnowSizes.sm),
          _kv('Collection', _shorten(registration.collectionMint.toBase58())),
          _kv('Leader', _shorten(registration.leaderWallet.toBase58())),
          _kv('Registered', _formatDate(registeredDate)),
          _kv('Cumulative share',
              '${cumSol.toStringAsFixed(6)} SOL (${registration.cumulativeShareLamports} lamports)'),
          _kv('Trade count (SOL)', registration.tradeCount.toString()),
          if (registration.isActive) ...[
            const SizedBox(height: SnowSizes.sm),
            OutlinedButton.icon(
              onPressed: busy ? null : onRevoke,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Revoke'),
              style: OutlinedButton.styleFrom(
                foregroundColor: SnowColors.error,
                side: const BorderSide(color: SnowColors.error),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _shorten(String address) {
    if (address.length < 12) return address;
    return '${address.substring(0, 6)}…${address.substring(address.length - 6)}';
  }

  static String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                k,
                style: const TextStyle(
                    color: SnowColors.textTertiary, fontSize: 12),
              ),
            ),
            Expanded(
              child: SelectableText(
                v,
                style: const TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      );
}

Widget _input(
  TextEditingController ctl,
  String label, {
  ValueChanged<String>? onChanged,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: SnowSizes.sm),
      child: TextField(
        controller: ctl,
        onChanged: onChanged,
        style: const TextStyle(
          color: SnowColors.textPrimary,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          labelStyle: const TextStyle(color: SnowColors.textSecondary),
          border: const OutlineInputBorder(),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: SnowColors.divider),
          ),
        ),
      ),
    );
