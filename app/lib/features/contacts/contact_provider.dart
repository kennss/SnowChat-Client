/// @file        contact_provider.dart
/// @description Contact state-management Provider — fetches the reachable contact set from the server (GET /users, scoped to friends ∪ COMMUNITY co-members ∪ past 1:1 partners), block/unblock functions.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-21 (X1: block / unblock go through BlockList — on this device first, then the server (awaited, sent again when it cannot be reached); blockedContactsProvider lists this device's blocked accounts, named from the server's list when it can be had). Earlier 2026-11-10 (B-2: identity purge uses VerifiedIdentityStore.remove — record dropped, bound latch kept; replaces the old IdentityPinStore.unpin that targeted the wrong key slot). Earlier 2026-08-03 (privacy: removed the user_registered blind-add listener and the profile_updated add-unknown branch — both turned the contact list into the full server directory. Contacts now come only from the scoped GET /users; profile_updated only renames an existing contact). Earlier 2026-04-26 (header + inline English translation; P2: IdentityPinStore unpin + IdentityVerificationDao deleteByPeer on removeContact/blockContact)
///
/// @functions
///  - Contact: contact data-model class
///  - contactProvider: StateNotifierProvider that exposes the contact list
///  - ContactNotifier: load user list from server + local management
///  - blockedContactsProvider: this device's blocked accounts, named from the server's list

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';
import '../../core/network/api_endpoints.dart';

class Contact {
  final String snowChatId;
  final String? displayName;
  final bool isBlocked;
  final bool isTrusted;
  final DateTime addedAt;

  const Contact({
    required this.snowChatId,
    this.displayName,
    this.isBlocked = false,
    this.isTrusted = false,
    required this.addedAt,
  });

  Contact copyWith({
    String? displayName,
    bool? isBlocked,
    bool? isTrusted,
  }) {
    return Contact(
      snowChatId: snowChatId,
      displayName: displayName ?? this.displayName,
      isBlocked: isBlocked ?? this.isBlocked,
      isTrusted: isTrusted ?? this.isTrusted,
      addedAt: addedAt,
    );
  }
}

final contactProvider =
    StateNotifierProvider<ContactNotifier, List<Contact>>((ref) {
  return ContactNotifier(ref);
});

class ContactNotifier extends StateNotifier<List<Contact>> {
  final Ref _ref;
  bool _loaded = false;
  StreamSubscription<Map<String, dynamic>>? _profileUpdatedSubscription;

  ContactNotifier(this._ref) : super([]) {
    Future.microtask(() => _loadFromServer());
    _listenForProfileUpdates();
  }

  // NOTE: there is deliberately no user_registered listener. Blind-adding every
  // registering user turned the contact list into the full server directory
  // (privacy leak) and the server no longer broadcasts user_registered globally.
  // A new user shows up here only when they become reachable (friend accepted /
  // shared channel), via the next _loadFromServer() refresh.

  /// Listen for profile_updated socket events — real-time displayName refresh.
  void _listenForProfileUpdates() {
    final sm = _ref.read(socketManagerProvider);
    _profileUpdatedSubscription = sm.onProfileUpdated.listen((data) {
      final snowId = data['snowchatId'] as String?;
      final name = data['displayName'] as String?;
      if (snowId == null) return;

      final mySnowId = _ref.read(currentSnowIdProvider);
      if (snowId == mySnowId) return; // ignore self

      // Only RENAME an existing contact. Never add an unknown user here — the
      // server now scopes profile_updated to the updater's reachable set, but we
      // also refuse to let a rename event materialize a brand-new contact (that
      // was a second directory-leak path). Unknown reachable users arrive only
      // through the scoped GET /users in _loadFromServer.
      if (state.any((c) => c.snowChatId == snowId)) {
        updateContact(snowId, displayName: name);
        debugPrint('[Contacts] Profile updated: $snowId → $name');
      }
    });
  }

  @override
  void dispose() {
    _profileUpdatedSubscription?.cancel();
    super.dispose();
  }

  /// Load the reachable contact set from the server (GET /users) — friends ∪
  /// COMMUNITY channel co-members ∪ past 1:1 partners, minus blocked/self. This
  /// is NOT the full user directory; the server scopes it per-user.
  Future<void> _loadFromServer() async {
    try {
      final token = _ref.read(authTokenProvider);
      if (token == null) return;

      final apiClient = _ref.read(apiClientProvider);
      final res = await apiClient.get('/users').timeout(const Duration(seconds: 5));

      if (res.data != null && res.data['users'] is List) {
        final users = res.data['users'] as List;
        final seen = <String>{};
        // Read currentSnowIdProvider at filter time; fall back to
        // identityManagerProvider.getSnowChatId() so self-filtering works
        // even when the StateProvider has not yet been populated after re-login.
        var mySnowId = _ref.read(currentSnowIdProvider);
        if (mySnowId == null || mySnowId.isEmpty) {
          try {
            final identity = _ref.read(identityManagerProvider);
            mySnowId = await identity.getSnowChatId();
          } catch (_) {
            // identityManagerProvider may not be ready yet
          }
        }
        final contacts = users.map<Contact>((u) => Contact(
          snowChatId: u['snowchatId'] ?? u['snowChatId'] ?? '',
          displayName: u['displayName'],
          isBlocked: false,
          isTrusted: true,
          addedAt: DateTime.now(),
        )).where((c) =>
          c.snowChatId.isNotEmpty &&
          c.snowChatId != mySnowId &&  // exclude self
          seen.add(c.snowChatId)        // deduplicate
        ).toList();

        state = contacts;
        _loaded = true;
        debugPrint('[Contacts] Loaded ${contacts.length} users from server');
      }
    } catch (e) {
      debugPrint('[Contacts] Failed to load from server: $e');
    }
  }

  /// Refresh contacts from server
  Future<void> refresh() async {
    await _loadFromServer();
  }

  bool get isLoaded => _loaded;

  void addContact(Contact contact) {
    if (state.any((c) => c.snowChatId == contact.snowChatId)) return;
    state = [...state, contact];
  }

  void removeContact(String snowChatId) {
    state = state.where((c) => c.snowChatId != snowChatId).toList();
    _purgeIdentityState(snowChatId);
  }

  void updateContact(String snowChatId, {String? displayName, bool? isBlocked}) {
    state = state.map((c) {
      if (c.snowChatId == snowChatId) {
        return c.copyWith(displayName: displayName, isBlocked: isBlocked);
      }
      return c;
    }).toList();
  }

  /// Block [snowChatId]: on this device at once (what it sends is dropped
  /// from now on), then on the server — sent again on the next connect when
  /// it cannot be reached now (BlockList).
  Future<void> blockContact(String snowChatId) async {
    updateContact(snowChatId, isBlocked: true);
    _purgeIdentityState(snowChatId);
    await _ref.read(blockListProvider).block(snowChatId);
  }

  /// P2: clean up TOFU pin + Safety Number verification row.
  /// Ensures the next re-access (e.g. new contact add) after friend
  /// remove/block runs as a clean first-encounter TOFU. Also prevents
  /// SecureStorage bloat.
  void _purgeIdentityState(String snowChatId) {
    if (snowChatId.isEmpty) return;
    Future.microtask(() async {
      try {
        // B-2: drop the identity record (the bound latch is kept).
        await _ref.read(verifiedIdentityStoreProvider).remove(snowChatId);
        await _ref.read(identityVerificationDaoProvider).deleteByPeer(snowChatId);
      } catch (e) {
        debugPrint('[ContactNotifier] _purgeIdentityState failed: $e');
      }
    });
  }

  /// Unblock [snowChatId] (what it sent while blocked does not come back).
  Future<void> unblockContact(String snowChatId) async {
    updateContact(snowChatId, isBlocked: false);
    await _ref.read(blockListProvider).unblock(snowChatId);
  }
}

/// The accounts this user blocked — this device's list (BlockList), so an
/// unblock shows at once even while the server has not taken it — named
/// from the server's list (`GET /users/blocked`, { snowchatId, displayName })
/// when it can be had. Recomputed when the list changes.
final blockedContactsProvider =
    FutureProvider.autoDispose<List<Contact>>((ref) async {
  final blocked = await ref.watch(blockedAccountsProvider.future);
  final names = <String, String?>{};
  try {
    final res = await ref.read(apiClientProvider).get(ApiEndpoints.blockedUsers);
    final list = (res.data?['blockedUsers'] as List?) ?? const [];
    for (final u in list) {
      if (u is Map && u['snowchatId'] is String) {
        names[u['snowchatId'] as String] = u['displayName'] as String?;
      }
    }
  } catch (_) {
    // Unnamed: the list itself is this device's.
  }
  return [
    for (final id in blocked)
      Contact(
        snowChatId: id,
        displayName: names[id],
        isBlocked: true,
        addedAt: DateTime.now(),
      ),
  ]..sort((a, b) => a.snowChatId.compareTo(b.snowChatId));
});
