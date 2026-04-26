/// @file        nft_image_utils.dart
/// @description NFT image URL normalization — multiple IPFS gateway fallbacks, Arweave passthrough.
///              Adheres to no-hardcoding principle (CLAUDE.md).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-09
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - normalizeImageUrl(): convert IPFS/Arweave URL to HTTP gateway URL
///  - ipfsGateways: list of available IPFS gateways
library;

/// IPFS gateway list (priority order). On first failure, fall back to the next.
const ipfsGateways = [
  'https://ipfs.io/ipfs/',
  'https://cloudflare-ipfs.com/ipfs/',
  'https://w3s.link/ipfs/',
  'https://gateway.pinata.cloud/ipfs/',
];

/// Convert IPFS/Arweave URLs to HTTP URLs.
/// - `ipfs://QmXyz...` → `https://ipfs.io/ipfs/QmXyz...`
/// - `ar://txId` → `https://arweave.net/txId`
/// - HTTP(S) URLs are returned as-is.
/// Use [gatewayIndex] to choose a fallback gateway (default 0 = first).
String normalizeImageUrl(String url, {int gatewayIndex = 0}) {
  if (url.isEmpty) return '';

  if (url.startsWith('ipfs://')) {
    final cid = url.substring(7); // after 'ipfs://'
    final idx = gatewayIndex.clamp(0, ipfsGateways.length - 1);
    return '${ipfsGateways[idx]}$cid';
  }

  if (url.startsWith('ar://')) {
    final txId = url.substring(5); // after 'ar://'
    return 'https://arweave.net/$txId';
  }

  return url;
}

/// On image load failure, return the next IPFS gateway URL.
/// Returns null when all gateways are exhausted.
String? nextGatewayUrl(String originalUrl, int currentIndex) {
  if (!originalUrl.startsWith('ipfs://')) return null;
  final next = currentIndex + 1;
  if (next >= ipfsGateways.length) return null;
  return normalizeImageUrl(originalUrl, gatewayIndex: next);
}
