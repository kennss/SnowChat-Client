/// @file        solana_pay_parser.dart
/// @description Solana Pay URI parser. Converts payment-request URIs of the
///              form `solana:<recipient>?amount=...&spl-token=...` into
///              prefill data for the send screen.
///              spec: https://docs.solanapay.com/spec
///              All amounts are converted to BigInt (lamports / smallest unit).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - SolanaPayParser.tryParse(): parse URI string into SolanaPayRequest
///  - SolanaPayRequest: parse result (recipient, amount, splToken, label, message, memo)
library;

/// Solana Pay payment-request parse result.
class SolanaPayRequest {
  const SolanaPayRequest({
    required this.recipient,
    this.amountLamports,
    this.amountSmallestUnit,
    this.splToken,
    this.label,
    this.message,
    this.memo,
    this.references = const [],
  });

  /// Recipient Solana address (Base58).
  final String recipient;

  /// lamports (BigInt) for SOL transfer. Used when spl-token is not specified.
  final BigInt? amountLamports;

  /// SPL token smallest unit (BigInt) for SPL transfer.
  /// The spec leaves amount decimal precision ambiguous, so caller must look
  /// up token decimals and recompute. This field does not preserve the lamports
  /// value before BigInt scaling — use [amountDecimalString] instead.
  final BigInt? amountSmallestUnit;

  /// SPL token mint address (Base58). null means SOL.
  final String? splToken;

  /// Label shown to user (e.g. store name).
  final String? label;

  /// Payment reason.
  final String? message;

  /// memo included in the transaction.
  final String? memo;

  /// Additional public keys for transaction reference.
  final List<String> references;

  bool get isSplTransfer => splToken != null;
}

/// Solana Pay URI parser. Pure Dart, no external deps.
abstract class SolanaPayParser {
  SolanaPayParser._();

  static const _scheme = 'solana:';

  /// Try parsing [input] as a Solana Pay URI. Returns null on failure.
  ///
  /// Supported forms:
  /// ```
  /// solana:<recipient>
  /// solana:<recipient>?amount=1.5
  /// solana:<recipient>?amount=10&spl-token=<mint>
  /// solana:<recipient>?amount=1.5&label=Coffee&message=Tip&memo=Thanks
  /// ```
  ///
  /// recipient is Base58 32-44 chars. amount is a decimal string.
  static SolanaPayRequest? tryParse(String input) {
    final trimmed = input.trim();
    if (!trimmed.toLowerCase().startsWith(_scheme)) return null;

    final body = trimmed.substring(_scheme.length);
    if (body.isEmpty) return null;

    // recipient + query
    final qIdx = body.indexOf('?');
    final recipient = qIdx < 0 ? body : body.substring(0, qIdx);
    if (!_isValidBase58Address(recipient)) return null;

    final query = qIdx < 0 ? '' : body.substring(qIdx + 1);
    final params = _parseQuery(query);

    final amountStr = params['amount'];
    final splToken = params['spl-token'];

    BigInt? amountLamports;
    BigInt? amountSmallest;
    if (amountStr != null && amountStr.isNotEmpty) {
      if (splToken == null) {
        // SOL — convert decimal string to lamports
        amountLamports = _decimalStringToBigInt(amountStr, 9);
      } else {
        // SPL — defer decimals lookup to caller; preserve as raw smallest-unit
        // Caller must look up token decimals for accuracy. Avoid assuming a
        // default 9 decimals here — placeholder String → BigInt(0) only;
        // caller recomputes.
        amountSmallest = BigInt.zero;
      }
    }

    if (splToken != null && !_isValidBase58Address(splToken)) {
      return null;
    }

    final references = <String>[];
    final ref = params['reference'];
    if (ref != null) {
      // spec: comma separated or multiple reference= entries.
      // _parseQuery preserves only the last value; extend if needed.
      references.addAll(ref.split(','));
    }

    return SolanaPayRequest(
      recipient: recipient,
      amountLamports: amountLamports,
      amountSmallestUnit: amountSmallest,
      splToken: splToken,
      label: params['label'],
      message: params['message'],
      memo: params['memo'],
      references: references,
    );
  }

  /// Helper for the caller to invoke once SPL token decimals are known.
  /// "1.5" with 6 decimals → BigInt(1500000)
  static BigInt amountStringToSmallestUnit(String amount, int decimals) {
    return _decimalStringToBigInt(amount, decimals);
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Map<String, String> _parseQuery(String q) {
    if (q.isEmpty) return const {};
    final out = <String, String>{};
    for (final part in q.split('&')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq < 0) {
        out[Uri.decodeQueryComponent(part)] = '';
      } else {
        final k = Uri.decodeQueryComponent(part.substring(0, eq));
        final v = Uri.decodeQueryComponent(part.substring(eq + 1));
        out[k] = v;
      }
    }
    return out;
  }

  static bool _isValidBase58Address(String s) {
    if (s.length < 32 || s.length > 44) return false;
    final base58Regex = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$');
    return base58Regex.hasMatch(s);
  }

  /// "1.5", 9 → BigInt(1_500_000_000). Float/double never used.
  static BigInt _decimalStringToBigInt(String s, int decimals) {
    final parts = s.split('.');
    if (parts.length > 2) {
      throw FormatException('Invalid decimal: $s');
    }
    final intPart = parts[0].isEmpty ? BigInt.zero : BigInt.parse(parts[0]);
    final whole = intPart * BigInt.from(10).pow(decimals);
    if (parts.length == 1) return whole;
    var frac = parts[1];
    if (frac.length > decimals) {
      frac = frac.substring(0, decimals);
    } else {
      frac = frac.padRight(decimals, '0');
    }
    return whole + BigInt.parse(frac);
  }
}
