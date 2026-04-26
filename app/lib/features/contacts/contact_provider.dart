/// @file        contact_provider.dart
/// @description Contact state-management Provider — fetch full user list from server, block/unblock functions.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header + inline English translation; P2: IdentityPinStore unpin + IdentityVerificationDao deleteByPeer on removeContact/blockContact)
///
/// @functions
///  - Contact: contact data-model class
///  - contactProvider: StateNotifierProvider that exposes the contact list
///  - ContactNotifier: load user list from server + local management
///  - blockedContactsProvider: FutureProvider that fetches only blocked users from server

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/providers.dart';

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
  StreamSubscription<Map<String, dynamic>>? _userRegisteredSubscription;
  StreamSubscription<Map<String, dynamic>>? _profileUpdatedSubscription;

  ContactNotifier(this._ref) : super([]) {
    Future.microtask(() => _loadFromServer());
    _listenForNewUsers();
    _listenForProfileUpdates();
  }

  /// Subscribe to user_registered socket events for real-time contact updates.
  void _listenForNewUsers() {
    final sm = _ref.read(socketManagerProvider);
    _userRegisteredSubscription = sm.onUserRegistered.listen((data) {
      final snowId = data['snowchatId'] as String?;
      final name = data['displayName'] as String?;
      final mySnowId = _ref.read(currentSnowIdProvider);
      if (snowId == null || snowId == mySnowId) return;

      // Deduplicate before adding
      if (!state.any((c) => c.snowChatId == snowId)) {
        state = [
          ...state,
          Contact(
            snowChatId: snowId,
            displayName: name,
            isTrusted: true,
            addedAt: DateTime.now(),
          ),
        ];
        debugPrint('[Contacts] New user registered: $snowId ($name)');
      }
    });
  }

  /// Listen for profile_updated socket events — real-time displayName refresh.
  void _listenForProfileUpdates() {
    final sm = _ref.read(socketManagerProvider);
    _profileUpdatedSubscription = sm.onProfileUpdated.listen((data) {
      final snowId = data['snowchatId'] as String?;
      final name = data['displayName'] as String?;
      if (snowId == null) return;

      final mySnowId = _ref.read(currentSnowIdProvider);
      if (snowId == mySnowId) return; // ignore self

      if (state.any((c) => c.snowChatId == snowId)) {
        // Existing contact — update displayName
        updateContact(snowId, displayName: name);
        debugPrint('[Contacts] Profile updated: $snowId → $name');
      } else if (name != null && name.isNotEmpty) {
        // New user with displayName — add to contacts
        addContact(Contact(
          snowChatId: snowId,
          displayName: name,
          isTrusted: true,
          addedAt: DateTime.now(),
        ));
        debugPrint('[Contacts] New contact from profile_updated: $snowId ($name)');
      }
    });
  }

  @override
  void dispose() {
    _userRegisteredSubscription?.cancel();
    _profileUpdatedSubscription?.cancel();
    super.dispose();
  }

  /// Load all registered users from server (excluding self + blocked)
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

  void blockContact(String snowChatId) {
    updateContact(snowChatId, isBlocked: true);
    // Also call server
    try {
      final apiClient = _ref.read(apiClientProvider);
      apiClient.post('/users/block', data: {'snowchatId': snowChatId});
    } catch (_) {}
    _purgeIdentityState(snowChatId);
  }

  /// P2: clean up TOFU pin + Safety Number verification row.
  /// Ensures the next re-access (e.g. new contact add) after friend
  /// remove/block runs as a clean first-encounter TOFU. Also prevents
  /// SecureStorage bloat.
  void _purgeIdentityState(String snowChatId) {
    if (snowChatId.isEmpty) return;
    Future.microtask(() async {
      try {
        await _ref.read(identityPinStoreProvider).unpin(snowChatId);
        await _ref.read(identityVerificationDaoProvider).deleteByPeer(snowChatId);
      } catch (e) {
        debugPrint('[ContactNotifier] _purgeIdentityState failed: $e');
      }
    });
  }

  void unblockContact(String snowChatId) {
    updateContact(snowChatId, isBlocked: false);
    try {
      final apiClient = _ref.read(apiClientProvider);
      apiClient.delete('/users/block/$snowChatId');
    } catch (_) {}
  }
}

/// Server-backed list of users the current user has blocked.
///
/// The main contact list (`/users`) filters blocked users out, so the local
/// `contactProvider` cannot tell us who is blocked. This provider hits the
/// dedicated `GET /users/blocked` endpoint and returns minimal info
/// ({ snowchatId, displayName }) per blocked entry.
///
/// Invalidate this provider after `unblockContact` to refresh the list.
final blockedContactsProvider =
    FutureProvider<List<Contact>>((ref) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get('/users/blocked');
    final list = (res.data?['blockedUsers'] as List?) ?? const [];
    return list.map<Contact>((u) {
      final m = u as Map;
      return Contact(
        snowChatId: (m['snowchatId'] as String?) ?? '',
        displayName: m['displayName'] as String?,
        isBlocked: true,
        addedAt: DateTime.now(),
      );
    }).where((c) => c.snowChatId.isNotEmpty).toList();
  } catch (e) {
    debugPrint('[Contacts] Failed to load blocked list: $e');
    return const [];
  }
});
