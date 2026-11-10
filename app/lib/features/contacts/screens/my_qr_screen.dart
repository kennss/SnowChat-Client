/// @file        my_qr_screen.dart
/// @description "My code" first-contact hub. Shows my SnowChat first-contact link
///              as a QR (encodes https://snowchat.calidalab.ai/u/<id> — the
///              permanent Universal-Link form our in-app scanner + deeplink
///              handler already parse), with Copy / Share, plus a "Scan a code"
///              action that reads a friend's QR and opens the add-friend confirm
///              pre-filled with their id. A first-contact link is A sharing their
///              OWN id (opt-in self-disclosure) — categorically different from the
///              nick lookup, so embedding the raw id here is fine.
///
///              LAYOUT NOTE: the action buttons are full-width DIRECT children of
///              the scrolling Column — NOT wrapped in a Row. A horizontal Row that
///              directly contains Material buttons inside a SingleChildScrollView
///              triggers an intrinsic-dimension/paint stall (the whole body lays
///              out but never paints, with no thrown exception) — verified live on
///              device. Full-width stacked buttons sidestep it entirely.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-10 (B-2: the link/QR carries the account public
///              key as ?k=<64 hex> so a first contact made through it is
///              pinned + latched (no unbound downgrade). Earlier 2026-08-05 (Part C: QR/link now carries the /u/<id> first-contact
///              deeplink + in-app scan-to-add; scrollable body with full-width
///              stacked actions. Previously: 2026-05-11 share_plus 13.x migration.)
///
/// @functions
///  - MyQrScreen: display my first-contact QR + Copy/Share + Scan
///  - MyQrScreen.firstContactLink(): build the https /u/[id]?k=[accountKey] deeplink
///  - MyQrScreen.extractUserId(): parse an id out of a scanned QR string
///  - MyQrScreen.extractAccountKeyHex(): parse the inviter account key (?k=) (B-2)
///  - _shareLink()/_copyLink(): share/copy the first-contact link
///  - _scanCode(): open the scanner, route the scanned id to /add-friend
///  - _UserQrScanScreen: mobile_scanner camera sheet returning the raw QR string

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app/deeplink_handler.dart' show addFriendDeeplinkPath;
import '../../../core/crypto/identity_binding.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_id_display.dart';
import '../../../shared/widgets/toast.dart';
import '../../../app/providers.dart';

class MyQrScreen extends ConsumerWidget {
  const MyQrScreen({super.key});

  // Fallback when provider has no value yet
  static const _fallbackId = '';

  /// The permanent first-contact deeplink for [snowId]. https (not snowchat://)
  /// so it is clickable in any chat app; once AASA/assetlinks + the /u/<id> web
  /// page ship it opens the app for not-yet-installed users too (until then our
  /// in-app scanner still resolves it directly).
  /// B-2: [accountKeyHex] (my ACCOUNT public key, 64 lowercase hex) is
  /// appended as `?k=` so the scanner can pin it; older apps ignore it.
  static String firstContactLink(String snowId, {String? accountKeyHex}) {
    final base = 'https://snowchat.calidalab.ai/u/$snowId';
    return (accountKeyHex == null || accountKeyHex.isEmpty)
        ? base
        : '$base?k=$accountKeyHex';
  }

  /// B-2: the inviter account key (`?k=`) from a scanned payload, or null.
  /// Validation (lowercase 64-hex, derives the id) happens in AddFriendScreen.
  static String? extractAccountKeyHex(String raw) {
    final k = Uri.tryParse(raw.trim())?.queryParameters['k'];
    return (k == null || k.isEmpty) ? null : k;
  }

  /// Parse a SnowChat id out of a scanned QR payload. Accepts the Universal-Link
  /// form, the custom-scheme form, and a bare id — returns null if none matches.
  static String? extractUserId(String raw) {
    final s = raw.trim();
    const httpsPrefix = 'https://snowchat.calidalab.ai/u/';
    const customPrefix = 'snowchat://user/';
    String? candidate;
    if (s.startsWith(httpsPrefix)) {
      candidate = s.substring(httpsPrefix.length);
    } else if (s.startsWith(customPrefix)) {
      candidate = s.substring(customPrefix.length);
    } else {
      candidate = s; // maybe a legacy bare-id QR
    }
    candidate = candidate.split(RegExp(r'[/?#]')).first.trim();
    return KeyDerivation.isValidSnowChatId(candidate) ? candidate : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentSnowIdProvider) ?? _fallbackId;
    final myKey = ref.watch(_myAccountKeyHexProvider);
    // Wait for the key so the first QR shown already carries it; if it
    // cannot be produced, fall back to the id-only link.
    final link = (myId.isEmpty || myKey.isLoading)
        ? ''
        : firstContactLink(myId, accountKeyHex: myKey.value);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('My QR Code'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(SnowSizes.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // QR encodes the first-contact deeplink (not the bare id) so a
            // scan lands the other person straight on the add-friend confirm.
            Center(
              child: Container(
                width: 260,
                height: 260,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: link.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: SnowColors.primary))
                    : QrImageView(
                        data: link,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.circle,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.circle,
                          color: Colors.black,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: SnowSizes.md),

            const Text(
              'Let a friend scan this to add you',
              textAlign: TextAlign.center,
              style: TextStyle(color: SnowColors.textSecondary, fontSize: 14),
            ),

            const SizedBox(height: SnowSizes.lg),

            const Text(
              'Your SnowChat ID',
              textAlign: TextAlign.center,
              style: TextStyle(color: SnowColors.textSecondary, fontSize: 13),
            ),

            const SizedBox(height: SnowSizes.sm),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: SnowColors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SnowIdDisplay(snowId: myId, compact: false, fontSize: 13),
            ),

            const SizedBox(height: SnowSizes.xl),

            // Copy / Share the first-contact link. Full-width stacked buttons —
            // see the LAYOUT NOTE in the header (a Row of Material buttons inside
            // this scroll view fails to paint).
            OutlinedButton.icon(
              onPressed: link.isEmpty ? null : () => _copyLink(context, link),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy link'),
            ),

            const SizedBox(height: SnowSizes.sm),

            Builder(
              builder: (btnContext) => OutlinedButton.icon(
                onPressed:
                    link.isEmpty ? null : () => _shareLink(btnContext, link),
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share'),
              ),
            ),

            const SizedBox(height: SnowSizes.lg),
            const Divider(color: SnowColors.divider),
            const SizedBox(height: SnowSizes.lg),

            // Scan a friend's code → add them.
            ElevatedButton.icon(
              onPressed: () => _scanCode(context),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text("Scan a friend's code"),
            ),
          ],
        ),
      ),
    );
  }

  /// Copy the first-contact link to clipboard.
  void _copyLink(BuildContext context, String link) {
    Clipboard.setData(ClipboardData(text: link));
    SnowToast.show(
      context,
      message: 'Invite link copied to clipboard',
      type: ToastType.success,
    );
  }

  /// Share the first-contact link as text via share_plus.
  /// sharePositionOrigin required on iPad and iOS 26 iPhone (share_plus ≥12.0.1).
  void _shareLink(BuildContext context, String link) {
    final box = context.findRenderObject() as RenderBox?;
    SharePlus.instance.share(ShareParams(
      text: 'Add me on SnowChat: $link',
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    ));
  }

  /// Open the camera, and route a valid scanned id to the add-friend confirm.
  Future<void> _scanCode(BuildContext context) async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _UserQrScanScreen()),
    );
    if (raw == null || !context.mounted) return;
    final id = extractUserId(raw);
    if (id == null) {
      SnowToast.show(
        context,
        message: 'That QR code is not a SnowChat contact code',
        type: ToastType.error,
      );
      return;
    }
    context.push(addFriendDeeplinkPath(id, extractAccountKeyHex(raw)));
  }
}

/// B-2: my ACCOUNT public key (lowercase hex) for the first-contact link.
/// Only emitted when it derives my snowId (never advertise a broken key).
final _myAccountKeyHexProvider = FutureProvider<String?>((ref) async {
  final im = ref.read(identityManagerProvider);
  final key = await im.getPublicKey();
  final id = await im.getSnowChatId();
  if (key == null || id == null) return null;
  if (!IdentityBindingV1.accountKeyMatchesSnowId(key, id)) return null;
  return bytesToHexLower(key);
});

/// Full-screen camera that returns the first scanned QR string to the caller
/// (the caller extracts/validates the id, keeping that logic in one place).
class _UserQrScanScreen extends StatefulWidget {
  const _UserQrScanScreen();

  @override
  State<_UserQrScanScreen> createState() => _UserQrScanScreenState();
}

class _UserQrScanScreenState extends State<_UserQrScanScreen> {
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
      _consumed = true;
      Navigator.of(context).pop(raw);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Scan Contact QR',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle flash',
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: SnowColors.primary, width: 2),
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
                "Point at a friend's SnowChat QR",
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
