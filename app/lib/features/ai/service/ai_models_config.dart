/// @file        ai_models_config.dart
/// @description Central configuration for AI model profiles.
///              To swap to a new model, change only the AIModels.iosModel /
///              androidModel constants below and rebuild. Adding the previous
///              filename to legacyFilenames auto-deletes it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-17
/// @lastUpdated 2026-04-26 (header + inline English translation; central AI model profile config)
///
/// @functions
///  - ModelProfile: single-model metadata (URL, filename, engine, size, etc.)
///  - AIModels.iosModel: currently active iOS model
///  - AIModels.androidModel: currently active Android model
///  - AIModels.legacyFilenames: list of replaced previous model filenames (auto-cleaned)
///  - AIModels.currentProfile(): ModelProfile for the current platform

import 'dart:io' show Platform;

/// Metadata for a single AI model.
/// Holds everything needed for download/load/verification.
class ModelProfile {
  /// Display name for UI. e.g. "Gemma 4 E2B (Q4_K_M)"
  final String displayName;

  /// Download URL on HuggingFace or other CDN (HTTP 302 redirect allowed).
  final String url;

  /// Local saved filename. Includes extension.
  final String filename;

  /// Minimum size in bytes to consider the download complete. Files smaller
  /// than this are treated as failed downloads.
  final int expectedMinSize;

  /// Inference engine identifier. 'llama.cpp' (iOS) | 'litert-lm' (Android)
  final String engine;

  /// Context window size (llama.cpp n_ctx). Android LiteRT uses an internal fixed value.
  final int contextSize;

  /// HuggingFace commit hash — for cache busting and pinning to an exact snapshot.
  final String hfRevision;

  /// Model activation date (YYYY-MM-DD). For docs/debug.
  final String releaseDate;

  /// SHA-256 hash (optional). When provided, integrity is verified after download.
  /// If null, only size verification is performed.
  final String? sha256;

  const ModelProfile({
    required this.displayName,
    required this.url,
    required this.filename,
    required this.expectedMinSize,
    required this.engine,
    required this.contextSize,
    required this.hfRevision,
    required this.releaseDate,
    this.sha256,
  });

  /// Size for UI display. e.g. "~2.9 GB"
  String get sizeDisplay {
    final gb = expectedMinSize / 1000000000;
    return '~${gb.toStringAsFixed(1)} GB';
  }
}

/// Registry of AI models supported by SnowChat.
///
/// ## How to swap to a new model
/// 1. Change URL/filename/hfRevision etc. of `iosModel` / `androidModel` constants
/// 2. Add the previous filename to `legacyFilenames`
/// 3. Rebuild the app → existing users auto re-download
class AIModels {
  AIModels._();

  // ═══════════════════════════════════════════════════════════════════
  // 🚀 CURRENT ACTIVE MODELS — swap to a new model by editing only this section
  // ═══════════════════════════════════════════════════════════════════

  static const iosModel = ModelProfile(
    displayName: 'Gemma 4 E2B (Q4_K_M)',
    url: 'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF'
        '/resolve/f064409/gemma-4-E2B-it-Q4_K_M.gguf',
    filename: 'gemma-4-E2B-it-Q4_K_M.gguf',
    expectedMinSize: 2500000000, // ~2.89GB
    engine: 'llama.cpp',
    contextSize: 4096,
    hfRevision: 'f064409',
    releaseDate: '2026-04-17',
  );

  static const androidModel = ModelProfile(
    displayName: 'Gemma 4 E2B (LiteRT-LM)',
    url: 'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm'
        '/resolve/2a101e0/gemma-4-E2B-it.litertlm',
    filename: 'gemma-4-E2B-it.litertlm',
    expectedMinSize: 2000000000, // ~2.58GB
    engine: 'litert-lm',
    contextSize: 4096,
    hfRevision: '2a101e0',
    releaseDate: '2026-04-17',
  );

  // ═══════════════════════════════════════════════════════════════════
  // 📦 LEGACY — past model filenames after replacement. Auto-deleted on app start.
  //    The currently active model filename is auto-excluded, so just append here.
  // ═══════════════════════════════════════════════════════════════════

  static const legacyFilenames = <String>[
    'gemma-4-E2B-it-Q3_K_S.gguf', // iOS predecessor (Q3 → Q4 upgrade)
    // When a new model is released, append the previous filename here:
    // 'gemma-4-E2B-it-Q4_K_M.gguf',
  ];

  /// Active model profile for the current platform.
  static ModelProfile currentProfile() {
    return Platform.isIOS ? iosModel : androidModel;
  }

  /// List of legacy filenames to auto-delete on the current platform
  /// (the active model filename is excluded).
  static List<String> legacyForCurrentPlatform() {
    final currentFilename = currentProfile().filename;
    return legacyFilenames
        .where((f) => f != currentFilename)
        .toList(growable: false);
  }
}
