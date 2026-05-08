/// @file        onboarding_provider.dart
/// @description Onboarding state-management Provider — manages identity creation, restore, server registration, authentication, prekey upload, and mnemonic backup/verification steps.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation)
///
/// @functions
///  - OnboardingStep: onboarding-step enum (welcome, setupProfile, creating, backupPhrase, verifyPhrase, complete)
///  - OnboardingState: onboarding state data class (incl. displayName, pin)
///  - OnboardingNotifier: StateNotifier managing onboarding state
///  - onboardingProvider: StateNotifierProvider exposing onboarding state
///  - setProfile(nickname, pin): set nickname and PIN, store hash in secure storage
///  - createIdentity(): create new identity, derive wallet keypair, server register, authenticate, upload prekeys
///  - restoreIdentity(): restore identity from mnemonic, restore wallet, authenticate, upload prekeys
///  - proceedToVerify(): advance to verification step
///  - completeVerification(): finish verification and complete onboarding
///  - _deriveAndRegisterWallet(): derive wallet keypair and register on server (POST /wallet)
///  - _uploadPreKeysWithRetry(): upload prekeys (up to 3 retries)

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../app/providers.dart';
import '../wallet/wallet_provider.dart' hide secureStorageProvider;

// --- Onboarding state ---

enum OnboardingStep {
  welcome,
  setupProfile,
  creating,
  backupPhrase,
  verifyPhrase,
  complete,
}

class OnboardingState {
  final OnboardingStep step;
  final List<String>? mnemonic;
  final String? snowChatId;
  final String? displayName;
  final bool isLoading;
  final String? error;

  /// True if restore created a new user on server (needs nickname setup).
  final bool isNewUserFromRestore;

  const OnboardingState({
    this.step = OnboardingStep.welcome,
    this.mnemonic,
    this.snowChatId,
    this.displayName,
    this.isLoading = false,
    this.error,
    this.isNewUserFromRestore = false,
  });

  OnboardingState copyWith({
    OnboardingStep? step,
    List<String>? mnemonic,
    String? snowChatId,
    String? displayName,
    bool? isLoading,
    String? error,
    bool? isNewUserFromRestore,
  }) {
    return OnboardingState(
      step: step ?? this.step,
      mnemonic: mnemonic ?? this.mnemonic,
      snowChatId: snowChatId ?? this.snowChatId,
      displayName: displayName ?? this.displayName,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isNewUserFromRestore:
          isNewUserFromRestore ?? this.isNewUserFromRestore,
    );
  }
}

class OnboardingNotifier extends StateNotifier<OnboardingState> {
  final Ref _ref;

  OnboardingNotifier(this._ref) : super(const OnboardingState());

  /// Store nickname and PIN (hashed) in secure storage, and keep
  /// displayName in state for use during identity creation.
  Future<void> setProfile({
    required String nickname,
    required String pin,
  }) async {
    final secureStorage = _ref.read(secureStorageProvider);

    // Store PIN hash (never raw) and display name
    await secureStorage.storePin(pin);
    await secureStorage.storeDisplayName(nickname);
    // Phase 8.7 round 5: PIN is now on disk → router can stop redirecting
    // to /setup-profile and let the user reach /chat (or /pin-login on
    // next cold start, which is the desired locked-by-PIN state).
    _ref.read(requiresPinSetupProvider.notifier).state = false;
    _ref.read(isLockedProvider.notifier).state = false;

    // Update server with displayName (for restore→new user or normal signup)
    try {
      final token = _ref.read(authTokenProvider);
      if (token != null) {
        final apiClient = _ref.read(apiClientProvider);
        await apiClient.put('/users/profile', data: {
          'displayName': nickname,
        });
      }
    } catch (e) {
      debugPrint('[Onboarding] Server profile update failed: $e');
    }

    state = state.copyWith(
      displayName: nickname,
      step: OnboardingStep.setupProfile,
    );
  }

  /// Delete orphaned session store file to prevent stale Double Ratchet
  /// sessions from surviving across server DB resets.
  Future<void> _deleteStaleSessionStore() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/signal_session_store.bin');
      if (await file.exists()) {
        await file.delete();
        debugPrint('[Onboarding] Deleted stale signal_session_store.bin');
      }
    } catch (e) {
      debugPrint('[Onboarding] Failed to delete session store: $e');
    }
  }

  /// Create a new identity, register with the server, and authenticate.
  Future<void> createIdentity({String? displayName}) async {
    debugPrint('[Onboarding] createIdentity called, displayName=$displayName, state.displayName=${state.displayName}');
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Clear any leftover session data before fresh onboarding
      await _deleteStaleSessionStore();

      final identityManager = _ref.read(identityManagerProvider);
      final authService = _ref.read(authServiceProvider);

      // Step 1: Generate identity (BIP39 mnemonic + Ed25519 keypair)
      final mnemonic = await identityManager.createIdentity();
      final snowId = await identityManager.getSnowChatId();

      debugPrint('[Onboarding] Identity created: $snowId');

      // Step 2: Register with the server (use provided displayName or state)
      final name = displayName ?? state.displayName;
      try {
        await authService.register(displayName: name);
        debugPrint('[Onboarding] Server registration successful');
      } catch (e) {
        // Extract error message from DioException response body
        String errMsg = e.toString().toLowerCase();
        if (e is DioException && e.response?.data != null) {
          errMsg = e.response!.data.toString().toLowerCase();
        }
        if (errMsg.contains('nickname') || errMsg.contains('already taken') ||
            errMsg.contains('displayname') || errMsg.contains('duplicate')) {
          state = state.copyWith(
            isLoading: false,
            error: 'This nickname is already taken. Please choose a different one.',
          );
          return;
        }
        debugPrint('[Onboarding] Server registration failed: $e');
        state = state.copyWith(
          isLoading: false,
          error: 'Registration failed. Please try again.',
        );
        return;
      }

      // Step 3: Authenticate (challenge-response) to get JWT pair
      try {
        final snap = await authService.authenticate();
        await _ref.read(tokenManagerProvider).setFromLogin(snap);
        debugPrint('[Onboarding] Authentication successful');

        // Step 4: Upload initial E2EE pre-key bundle to the server.
        // This must happen after auth so the API call is authenticated.
        // Phase 8.7 round 4: _uploadPreKeysWithRetry now throws StateError
        // on final failure. We MUST surface that to the user — letting
        // onboarding finish with a placeholder identity (the previous
        // 'will retry later' path) is what created the CCC bug.
        await _uploadPreKeysWithRetry();

        // Step 5: Derive wallet keypair and register with server.
        await _deriveAndRegisterWallet(mnemonic.join(' '));
      } on StateError catch (e) {
        // PreKey upload exhausted retries — placeholder identity would
        // remain on the server, breaking group E2EE. Stop the flow and
        // show a real error so the user can retry the entire onboarding.
        debugPrint('[Onboarding] PreKey upload fatal: $e');
        state = state.copyWith(
          isLoading: false,
          error: 'Could not register encryption keys with the server. '
              'Please check your connection and try again.',
        );
        return;
      } catch (e) {
        debugPrint('[Onboarding] Authentication failed: $e');
        state = state.copyWith(
          isLoading: false,
          error: 'Authentication failed. Please try again.',
        );
        return;
      }

      state = state.copyWith(
        step: OnboardingStep.backupPhrase,
        mnemonic: mnemonic,
        snowChatId: snowId,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to create identity: $e',
      );
    }
  }

  /// Restore identity from mnemonic words, then authenticate with server.
  Future<void> restoreIdentity(List<String> words) async {
    state = state.copyWith(isLoading: true, error: null);

    final _swTotal = Stopwatch()..start();
    final _swStep = Stopwatch()..start();
    void _mark(String label) {
      debugPrint('[Perf] $label: ${_swStep.elapsedMilliseconds}ms');
      _swStep.reset();
    }

    try {
      // Clear any leftover session data before restore onboarding
      await _deleteStaleSessionStore();
      _mark('deleteStaleSessionStore');

      final identityManager = _ref.read(identityManagerProvider);
      final authService = _ref.read(authServiceProvider);
      _mark('read providers');

      // Step 1: Restore keypair from mnemonic
      final snowId = await identityManager.restoreIdentity(words);
      _mark('identityManager.restoreIdentity (BIP39 + 4 writes)');

      debugPrint('[Onboarding] Identity restored: $snowId');

      // Step 2: Check if already registered, if not → new user (needs nickname)
      var isNewUser = false;
      final isRegistered = await authService.isRegistered();
      _mark('authService.isRegistered (network)');
      if (!isRegistered) {
        // Server doesn't know this user → must go through setup-profile
        isNewUser = true;
        debugPrint('[Onboarding] User not registered on server — needs setup');
      }

      // Step 3: Authenticate (only if server knows this user)
      if (!isNewUser) {
        try {
          final snap = await authService.authenticate();
          _mark('authService.authenticate (network)');
          await _ref.read(tokenManagerProvider).setFromLogin(snap);
          debugPrint('[Onboarding] Authentication successful');

          // Step 3b: Check if existing user has displayName set.
          // Perf: Store the name in state so setup-profile doesn't have to
          // re-fetch (/users/$snowId was taking ~1.3s on iOS post-restore
          // due to concurrent network contention).
          if (!isNewUser) {
            try {
              final apiClient = _ref.read(apiClientProvider);
              final res = await apiClient.get('/users/$snowId');
              _mark('GET /users/\$snowId (network)');
              final name = (res.data as Map?)?['displayName'] as String?;
              if (name == null || name.isEmpty) {
                isNewUser = true;
              } else {
                // Save for setup-profile to avoid duplicate fetch
                state = state.copyWith(displayName: name);
              }
            } catch (_) {}
          }

          // Step 4: Upload E2EE pre-key bundle — FIRE AND FORGET.
          //
          // Perf (Phase 10.x): This used to block restoreIdentity for ~8.6s
          // (100 × X25519 generation + 7 secure_storage writes + network).
          // The user saw a frozen screen for ~13s before reaching PIN entry.
          //
          // Deferred to background: user reaches the PIN screen within ~4s,
          // prekey upload runs concurrently while they type. Prekeys are only
          // consumed by incoming X3DH handshakes, which can't happen before
          // the user returns to foreground after PIN setup (~10+ seconds).
          //
          // Failure recovery: socket reconnect triggers checkPreKeyCount()
          // which calls uploadPreKeys() if server reports missing keys.
          unawaited(_uploadPreKeysWithRetry().catchError((e) {
            debugPrint('[Onboarding] Background prekey upload failed '
                '(will retry on next socket reconnect): $e');
          }));
          _mark('uploadPreKeys SCHEDULED (background)');

          // Step 5: Restore wallet keypair — also fire-and-forget (867ms).
          // Wallet state is only needed when user opens the Wallet tab,
          // which requires at least one more navigation step.
          unawaited(_deriveAndRegisterWallet(words.join(' '))
              .timeout(const Duration(seconds: 5))
              .catchError((_) {
            debugPrint('[Onboarding] Background wallet registration failed');
          }));
          _mark('deriveAndRegisterWallet SCHEDULED (background)');
        } catch (e) {
          debugPrint('[Onboarding] Authentication failed: $e');

          if (e is DioException && e.response?.statusCode == 403) {
            final msg =
                e.response?.data?['error']?['message'] as String? ?? '';
            if (msg.contains('already logged in')) {
              state = state.copyWith(
                isLoading: false,
                error: 'Another device is already using this account. '
                    'Log out from the other device first.',
              );
              return;
            }
          }

          isNewUser = true;
        }
      }

      // Derive wallet locally if not already done (non-blocking, 5s timeout)
      if (isNewUser) {
        try {
          await _deriveWalletLocally(words.join(' '))
              .timeout(const Duration(seconds: 5));
          _mark('deriveWalletLocally');
        } catch (_) {
          _mark('deriveWalletLocally (timeout)');
          debugPrint('[Onboarding] Local wallet derivation timed out (non-fatal)');
        }
      }

      debugPrint('[Perf] ═══ restoreIdentity TOTAL: ${_swTotal.elapsedMilliseconds}ms ═══');

      state = state.copyWith(
        snowChatId: snowId,
        mnemonic: words,
        isLoading: false,
        isNewUserFromRestore: isNewUser,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to restore identity: $e',
      );
    }
  }

  /// Register on server and authenticate (for restore → new user flow).
  /// Called from SetupProfileScreen after nickname is entered.
  Future<bool> registerAndAuthenticate(String displayName) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final authService = _ref.read(authServiceProvider);

      // Step 1: Register with displayName
      try {
        await authService.register(displayName: displayName);
        debugPrint('[Onboarding] Server registration successful');
      } catch (e) {
        String errMsg = e.toString().toLowerCase();
        if (e is DioException && e.response?.data != null) {
          errMsg = e.response!.data.toString().toLowerCase();
        }
        if (errMsg.contains('nickname') || errMsg.contains('already taken') ||
            errMsg.contains('displayname') || errMsg.contains('duplicate')) {
          state = state.copyWith(
            isLoading: false,
            error: 'This nickname is already taken. Please choose a different one.',
          );
          return false;
        }
        if (errMsg.contains('already exists')) {
          // User already registered (race condition) — skip to auth
          debugPrint('[Onboarding] User already exists, proceeding to auth');
        } else {
          state = state.copyWith(isLoading: false, error: 'Registration failed: $e');
          return false;
        }
      }

      // Step 2: Authenticate
      try {
        final snap = await authService.authenticate();
        await _ref.read(tokenManagerProvider).setFromLogin(snap);
        debugPrint('[Onboarding] Authentication successful');
      } catch (e) {
        // Check if blocked by active session
        if (e is DioException && e.response?.statusCode == 403) {
          state = state.copyWith(
            isLoading: false,
            error: 'Another device is already using this account. '
                'Log out from the other device first.',
          );
          return false;
        }
        state = state.copyWith(isLoading: false, error: 'Authentication failed: $e');
        return false;
      }

      // Step 3: Upload prekeys + register wallet.
      // Phase 8.7 round 4: rethrow on final failure (was silent before).
      try {
        await _uploadPreKeysWithRetry();
      } on StateError catch (e) {
        debugPrint('[Onboarding] PreKey upload fatal during register: $e');
        state = state.copyWith(
          isLoading: false,
          error: 'Could not register encryption keys with the server. '
              'Please check your connection and try again.',
        );
        return false;
      }
      final mnemonic = state.mnemonic;
      if (mnemonic != null) {
        await _deriveAndRegisterWallet(mnemonic.join(' '));
      }

      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed: $e');
      return false;
    }
  }

  /// Mark backup phrase as viewed, proceed to verification.
  void proceedToVerify() {
    state = state.copyWith(step: OnboardingStep.verifyPhrase);
  }

  /// Complete the phrase verification and finish onboarding.
  void completeVerification() {
    if (state.snowChatId != null) {
      _completeOnboarding(state.snowChatId!);
    }
  }

  void _completeOnboarding(String snowId) {
    debugPrint('[Onboarding] *** _completeOnboarding called with snowId=$snowId ***');
    debugPrint('[Onboarding] *** Stack trace: ${StackTrace.current} ***');
    _ref.read(currentSnowIdProvider.notifier).state = snowId;
    _ref.read(isOnboardedProvider.notifier).state = true;
    state = state.copyWith(step: OnboardingStep.complete);

    // Auto-join pending invite channel (if user came via invite link)
    _joinPendingInvite();
  }

  /// Join channel from pending invite code saved during deep link.
  Future<void> _joinPendingInvite() async {
    try {
      final secureStorage = _ref.read(secureStorageProvider);
      final code = await secureStorage.read('pending_invite_code');
      if (code == null || code.isEmpty) return;

      final apiClient = _ref.read(apiClientProvider);
      await apiClient.post('/invite/$code/join');
      await secureStorage.delete('pending_invite_code');
      debugPrint('[Onboarding] Auto-joined channel via invite: $code');
    } catch (e) {
      debugPrint('[Onboarding] Auto-join failed: $e');
    }
  }

  /// Derive wallet keypair from mnemonic and register with server.
  /// KeypairManager.createWallet() handles both derivation and server registration.
  Future<void> _deriveAndRegisterWallet(String mnemonic) async {
    try {
      final walletNotifier = _ref.read(walletProvider.notifier);
      await walletNotifier.createFromMnemonic(mnemonic);

      final walletState = _ref.read(walletProvider);
      if (walletState.publicKey != null) {
        debugPrint('[Onboarding] Wallet derived: ${walletState.publicKey}');
      }
    } catch (e) {
      debugPrint('[Onboarding] Wallet derivation failed: $e');
    }
  }

  /// Derive wallet keypair locally without server registration.
  Future<void> _deriveWalletLocally(String mnemonic) async {
    try {
      final walletNotifier = _ref.read(walletProvider.notifier);
      await walletNotifier.createFromMnemonic(mnemonic);
      debugPrint('[Onboarding] Wallet derived locally');
    } catch (e) {
      debugPrint('[Onboarding] Local wallet derivation failed: $e');
    }
  }

  /// Upload initial E2EE pre-key bundle with retry logic.
  /// Retries up to 3 times with exponential backoff (1s, 2s, 4s).
  /// Failure is non-fatal: prekeys will be uploaded on next app start.
  /// Phase 8.7 round 4 — Layer C2: actually retry, with a wider timeout
  /// and a hard rethrow on final failure.
  ///
  /// Previous behaviour ignored the maxRetries parameter (single try),
  /// timed out at 5 seconds (too tight for cold-start emulators where the
  /// generateOneTimePreKeys batch and the HTTP roundtrip serialize through
  /// secure-storage I/O), and swallowed the failure as 'non-fatal' — the
  /// server then had a placeholder identityKey row that nothing came back
  /// to fix because prekey-count was already 100 from a stale attempt.
  ///
  /// New behaviour:
  ///  - 30 second per-attempt timeout (still bounded — never infinite)
  ///  - Exponential backoff between attempts (2s, 4s, 6s)
  ///  - rethrow on final failure so the onboarding caller can surface a
  ///    real error to the user instead of finishing with a broken device
  Future<void> _uploadPreKeysWithRetry({int maxRetries = 3}) async {
    final sessionManager = _ref.read(signalSessionManagerProvider);
    Object? lastError;
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await sessionManager
            .uploadPreKeys()
            .timeout(const Duration(seconds: 30));
        debugPrint('[Onboarding] PreKey upload successful (attempt $attempt)');
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[Onboarding] PreKey upload attempt $attempt FAILED: $e');
        if (attempt < maxRetries) {
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }
    debugPrint('[Onboarding] PreKey upload exhausted $maxRetries retries; '
        'rethrowing: $lastError');
    throw StateError(
      'PreKey upload failed after $maxRetries attempts: $lastError. '
      'The device will not be able to receive group messages until this '
      'succeeds. Retry by restarting the onboarding flow.',
    );
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final onboardingProvider =
    StateNotifierProvider<OnboardingNotifier, OnboardingState>((ref) {
  return OnboardingNotifier(ref);
});
