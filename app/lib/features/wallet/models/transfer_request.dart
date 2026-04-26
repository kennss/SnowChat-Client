/// @file        transfer_request.dart
/// @description Wallet V2 Phase 1 — in-chat transfer message payloads
///              (4 types, BigInt-safe wire format).
///              **amount wire unit = lamports raw integer string** (Solana standard).
///              UI conversion goes through solToLamports() /
///              lamportsToSolString() in one place only.
///              Float/double are strictly forbidden (wallet/CLAUDE.md §2.1).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-20
/// @lastUpdated 2026-04-26 (header + inline English translation; D1+D2 review fix: TransferCompletedStatus enum + amount in lamports made explicit)
///
/// @functions
///  - TokenType (enum): SOL / SPL / NFT — toJson/fromJson (uppercase)
///  - NetworkType (enum): devnet / mainnet — toJson/fromJson (lowercase)
///  - FailureReason (enum): 7 failure reasons — toJson/fromJson (snake_case)
///  - TransferCompletedStatus (enum): confirmed / failed — toJson/fromJson
///  - TransferMessageType (const): 4 wire 'type' values
///  - TransferRequest (class): A → B request (amount lamports raw, token, network, ...)
///    - toJson() / fromJson() / == / hashCode / toString()
///  - TransferResponse (class): B → A response (walletAddress + Ed25519 sig + ATA info)
///    - toJson() / fromJson() / == / hashCode / toString() (only sig length exposed)
///  - TransferCompleted (class): A → B completion (B-side RPC verification required)
///    - toJson() / fromJson() / == / hashCode / toString()
///  - TransferFailed (class): A → B explicit failure (no timeout dependency)
///    - toJson() / fromJson() / == / hashCode / toString()

import 'package:meta/meta.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────

/// Transfer token kind.
/// JSON serialization uses uppercase (`'SOL'`, `'SPL'`, `'NFT'`).
enum TokenType {
  sol,
  spl,
  nft;

  /// JSON wire format (uppercase).
  String toJson() {
    switch (this) {
      case TokenType.sol:
        return 'SOL';
      case TokenType.spl:
        return 'SPL';
      case TokenType.nft:
        return 'NFT';
    }
  }

  /// JSON wire format → enum.
  /// Throws [ArgumentError] for unknown values.
  static TokenType fromJson(String value) {
    switch (value) {
      case 'SOL':
        return TokenType.sol;
      case 'SPL':
        return TokenType.spl;
      case 'NFT':
        return TokenType.nft;
      default:
        throw ArgumentError('Unknown TokenType: $value');
    }
  }
}

/// Solana network.
/// JSON serialization uses lowercase (`'devnet'`, `'mainnet'`).
enum NetworkType {
  devnet,
  mainnet;

  String toJson() {
    switch (this) {
      case NetworkType.devnet:
        return 'devnet';
      case NetworkType.mainnet:
        return 'mainnet';
    }
  }

  static NetworkType fromJson(String value) {
    switch (value) {
      case 'devnet':
        return NetworkType.devnet;
      case 'mainnet':
        return NetworkType.mainnet;
      default:
        throw ArgumentError('Unknown NetworkType: $value');
    }
  }
}

/// Transfer completion status.
/// JSON serialization uses lowercase (`'confirmed'` | `'failed'`).
/// V1.0.1 (D2-3 fix): free-form String → enum (throw if peer sends arbitrary status).
enum TransferCompletedStatus {
  confirmed,
  failed;

  String toJson() {
    switch (this) {
      case TransferCompletedStatus.confirmed:
        return 'confirmed';
      case TransferCompletedStatus.failed:
        return 'failed';
    }
  }

  static TransferCompletedStatus fromJson(String value) {
    switch (value) {
      case 'confirmed':
        return TransferCompletedStatus.confirmed;
      case 'failed':
        return TransferCompletedStatus.failed;
      default:
        throw ArgumentError('Unknown TransferCompletedStatus: $value');
    }
  }
}

/// Transfer failure reason.
/// JSON serialization uses snake_case (e.g. `'insufficient_balance'`).
enum FailureReason {
  insufficientBalance,
  rpcError,
  userCancel,
  networkMismatch,
  signatureInvalid,
  ataCreateFailed,
  timeout;

  String toJson() {
    switch (this) {
      case FailureReason.insufficientBalance:
        return 'insufficient_balance';
      case FailureReason.rpcError:
        return 'rpc_error';
      case FailureReason.userCancel:
        return 'user_cancel';
      case FailureReason.networkMismatch:
        return 'network_mismatch';
      case FailureReason.signatureInvalid:
        return 'signature_invalid';
      case FailureReason.ataCreateFailed:
        return 'ata_create_failed';
      case FailureReason.timeout:
        return 'timeout';
    }
  }

  static FailureReason fromJson(String value) {
    switch (value) {
      case 'insufficient_balance':
        return FailureReason.insufficientBalance;
      case 'rpc_error':
        return FailureReason.rpcError;
      case 'user_cancel':
        return FailureReason.userCancel;
      case 'network_mismatch':
        return FailureReason.networkMismatch;
      case 'signature_invalid':
        return FailureReason.signatureInvalid;
      case 'ata_create_failed':
        return FailureReason.ataCreateFailed;
      case 'timeout':
        return FailureReason.timeout;
      default:
        throw ArgumentError('Unknown FailureReason: $value');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message type constants (wire format)
// ─────────────────────────────────────────────────────────────────────────────

/// `type` field values in E2EE payload.
/// Used for dispatch branching in EncryptedMessageHandler.
class TransferMessageType {
  TransferMessageType._();

  static const String request = 'transfer_request';
  static const String response = 'transfer_response';
  static const String completed = 'transfer_completed';
  static const String failed = 'transfer_failed';
}

// ─────────────────────────────────────────────────────────────────────────────
// TransferRequest (A → B)
// ─────────────────────────────────────────────────────────────────────────────

/// Sender(A) → recipient(B) transfer request.
///
/// **`amount` unit = lamports / raw smallest units (BigInt-safe String, mandatory)**:
/// - SOL: 1 SOL = `"1000000000"` (1e9 lamports)
/// - USDC: 1 USDC = `"1000000"` (decimals=6)
/// - NFT: 1 NFT = `"1"` (decimals=0)
///
/// UI input (user types "1.5") is converted via `solToLamports('1.5')` before wire.
/// UI display ("1.5 SOL") goes through `lamportsToSolString(BigInt)`.
/// Float/double never used (`wallet/CLAUDE.md §2.1`).
@immutable
class TransferRequest {
  final String requestId;
  /// lamports / raw smallest units (BigInt-safe). Use as `BigInt.parse(amount)`.
  final String amount;
  final TokenType token;
  final String? mint;
  final int decimals;
  final NetworkType network;
  final int sentAt;

  const TransferRequest({
    required this.requestId,
    required this.amount,
    required this.token,
    required this.mint,
    required this.decimals,
    required this.network,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': TransferMessageType.request,
      'requestId': requestId,
      'amount': amount,
      'token': token.toJson(),
      'mint': mint,
      'decimals': decimals,
      'network': network.toJson(),
      'sentAt': sentAt,
    };
  }

  factory TransferRequest.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != TransferMessageType.request) {
      throw ArgumentError(
        'TransferRequest.fromJson: invalid type "$type" '
        '(expected "${TransferMessageType.request}")',
      );
    }

    return TransferRequest(
      requestId: json['requestId'] as String,
      amount: json['amount'] as String,
      token: TokenType.fromJson(json['token'] as String),
      mint: json['mint'] as String?,
      decimals: json['decimals'] as int,
      network: NetworkType.fromJson(json['network'] as String),
      sentAt: json['sentAt'] as int,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransferRequest &&
        other.requestId == requestId &&
        other.amount == amount &&
        other.token == token &&
        other.mint == mint &&
        other.decimals == decimals &&
        other.network == network &&
        other.sentAt == sentAt;
  }

  @override
  int get hashCode => Object.hash(
        requestId,
        amount,
        token,
        mint,
        decimals,
        network,
        sentAt,
      );

  @override
  String toString() =>
      'TransferRequest(requestId: $requestId, amount: $amount, '
      'token: ${token.toJson()}, mint: $mint, decimals: $decimals, '
      'network: ${network.toJson()}, sentAt: $sentAt)';
}

// ─────────────────────────────────────────────────────────────────────────────
// TransferResponse (B → A)
// ─────────────────────────────────────────────────────────────────────────────

/// Recipient(B) → sender(A) response.
///
/// `walletAddress` + `walletAddressSig` are attached only when `accepted=true`.
/// SPL/NFT transfers use `ataExists` + `ataRentLamports` (P0-4).
@immutable
class TransferResponse {
  final String requestId;
  final bool accepted;
  final String? walletAddress;

  /// Ed25519 signature over `walletAddress` (signed with B's Signal identity key).
  /// base64 encoded. A only proceeds with broadcast after verification (P1-5).
  final String? walletAddressSig;

  /// Whether the recipient's ATA (Associated Token Account) exists.
  /// For SPL/NFT, attached after RPC lookup right when the dialog is shown.
  /// Irrelevant for SOL transfer (null allowed).
  final bool? ataExists;

  /// Extra rent (lamports) the sender must cover when ATA is missing.
  /// Solana standard ~2,039,280 lamports (~0.002 SOL).
  final int? ataRentLamports;

  const TransferResponse({
    required this.requestId,
    required this.accepted,
    required this.walletAddress,
    required this.walletAddressSig,
    required this.ataExists,
    required this.ataRentLamports,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': TransferMessageType.response,
      'requestId': requestId,
      'accepted': accepted,
      'walletAddress': walletAddress,
      'walletAddressSig': walletAddressSig,
      'ataExists': ataExists,
      'ataRentLamports': ataRentLamports,
    };
  }

  factory TransferResponse.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != TransferMessageType.response) {
      throw ArgumentError(
        'TransferResponse.fromJson: invalid type "$type" '
        '(expected "${TransferMessageType.response}")',
      );
    }

    return TransferResponse(
      requestId: json['requestId'] as String,
      accepted: json['accepted'] as bool,
      walletAddress: json['walletAddress'] as String?,
      walletAddressSig: json['walletAddressSig'] as String?,
      ataExists: json['ataExists'] as bool?,
      ataRentLamports: json['ataRentLamports'] as int?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransferResponse &&
        other.requestId == requestId &&
        other.accepted == accepted &&
        other.walletAddress == walletAddress &&
        other.walletAddressSig == walletAddressSig &&
        other.ataExists == ataExists &&
        other.ataRentLamports == ataRentLamports;
  }

  @override
  int get hashCode => Object.hash(
        requestId,
        accepted,
        walletAddress,
        walletAddressSig,
        ataExists,
        ataRentLamports,
      );

  @override
  String toString() =>
      'TransferResponse(requestId: $requestId, accepted: $accepted, '
      'walletAddress: $walletAddress, walletAddressSig: '
      '${walletAddressSig == null ? 'null' : '<base64:${walletAddressSig!.length}b>'}, '
      'ataExists: $ataExists, ataRentLamports: $ataRentLamports)';
}

// ─────────────────────────────────────────────────────────────────────────────
// TransferCompleted (A → B)
// ─────────────────────────────────────────────────────────────────────────────

/// Sender(A) → recipient(B) transfer completion notification.
///
/// Recipient does not blindly trust `txHash` — it must verify (recipient,
/// amount, mint, status) via RPC `getTransaction` before committing the
/// system message (P0-3).
@immutable
class TransferCompleted {
  final String requestId;
  final String txHash;
  /// V1.0.1 (D2-3 fix): promoted String → enum. Rejects arbitrary status.
  final TransferCompletedStatus status;

  const TransferCompleted({
    required this.requestId,
    required this.txHash,
    required this.status,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': TransferMessageType.completed,
      'requestId': requestId,
      'txHash': txHash,
      'status': status.toJson(),
    };
  }

  factory TransferCompleted.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != TransferMessageType.completed) {
      throw ArgumentError(
        'TransferCompleted.fromJson: invalid type "$type" '
        '(expected "${TransferMessageType.completed}")',
      );
    }

    return TransferCompleted(
      requestId: json['requestId'] as String,
      txHash: json['txHash'] as String,
      status: TransferCompletedStatus.fromJson(json['status'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransferCompleted &&
        other.requestId == requestId &&
        other.txHash == txHash &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(requestId, txHash, status);

  @override
  String toString() =>
      'TransferCompleted(requestId: $requestId, txHash: $txHash, '
      'status: ${status.toJson()})';
}

// ─────────────────────────────────────────────────────────────────────────────
// TransferFailed (A → B) — V1 required
// ─────────────────────────────────────────────────────────────────────────────

/// Sender(A) → recipient(B) explicit transfer failure.
///
/// Promoted from V2 deferred to V1 required — B-side dialog reflects exact
/// state immediately without depending on a timer (insufficient_balance,
/// network_mismatch, etc.).
@immutable
class TransferFailed {
  final String requestId;
  final FailureReason reason;

  const TransferFailed({
    required this.requestId,
    required this.reason,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': TransferMessageType.failed,
      'requestId': requestId,
      'reason': reason.toJson(),
    };
  }

  factory TransferFailed.fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type != TransferMessageType.failed) {
      throw ArgumentError(
        'TransferFailed.fromJson: invalid type "$type" '
        '(expected "${TransferMessageType.failed}")',
      );
    }

    return TransferFailed(
      requestId: json['requestId'] as String,
      reason: FailureReason.fromJson(json['reason'] as String),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TransferFailed &&
        other.requestId == requestId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(requestId, reason);

  @override
  String toString() =>
      'TransferFailed(requestId: $requestId, reason: ${reason.toJson()})';
}
