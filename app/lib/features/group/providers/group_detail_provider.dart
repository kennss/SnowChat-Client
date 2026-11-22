/// @file        group_detail_provider.dart
/// @description Group detail provider: a read-only view of a group protocol v2 group as this
///              device holds it — members, roles, name — kept current from the local store.
///              Nothing is asked of the server; the group's screens act through
///              Gv2GroupActions.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-31
/// @lastUpdated 2026-11-21 (P5.6: groupDetailProvider is released when nothing watches it). Earlier 2026-11-20 (v1 groups removed: no server load, no GMK-encrypted name, no member
///              removal / admin toggle / leave / rename through the server — the provider
///              is the v2 view only; an id that is not a v2 group id is an empty detail).
///              Earlier same day (group protocol v2: read-only view of a v2 group from the
///              local store). Earlier 2026-11-12 (GMK name resolution). Earlier 2026-11-10
///              (B-2 §5.7 identity exceptions terminal). Earlier 2026-04-26 (header English
///              translation)
///
/// @functions
///  - GroupMember: group-member data model
///  - GroupDetail: group-detail data model
///  - GroupDetailNotifier: StateNotifier keeping a v2 group's detail in step with the store
///  - GroupDetailNotifier.loadGroup(): read the detail from the local store again
///  - groupDetailProvider: family StateNotifierProvider keyed by group ID

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/group_v2/gv2_codec.dart';
import '../../../core/storage/tables/gv2_tables.dart';
import '../../../app/providers.dart';
import 'gv2_group_provider.dart';

/// A single member within a group.
class GroupMember {
  final String userId;
  final String snowchatId;
  final String? displayName;
  final bool isAdmin;
  final String status;
  final String joinedAt;

  const GroupMember({
    required this.userId,
    required this.snowchatId,
    this.displayName,
    this.isAdmin = false,
    this.status = 'active',
    this.joinedAt = '',
  });

  GroupMember copyWith({
    String? displayName,
    bool? isAdmin,
    String? status,
  }) {
    return GroupMember(
      userId: userId,
      snowchatId: snowchatId,
      displayName: displayName ?? this.displayName,
      isAdmin: isAdmin ?? this.isAdmin,
      status: status ?? this.status,
      joinedAt: joinedAt,
    );
  }
}

/// Full detail of a group including its member list.
class GroupDetail {
  final String id;
  final String? name;
  final String creatorId;
  final List<GroupMember> members;
  final bool isLoading;
  final String? error;

  const GroupDetail({
    required this.id,
    this.name,
    this.creatorId = '',
    this.members = const [],
    this.isLoading = false,
    this.error,
  });

  GroupDetail copyWith({
    String? name,
    String? creatorId,
    List<GroupMember>? members,
    bool? isLoading,
    String? error,
  }) {
    return GroupDetail(
      id: id,
      name: name ?? this.name,
      creatorId: creatorId ?? this.creatorId,
      members: members ?? this.members,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  /// Find a member by userId or snowchatId.
  GroupMember? findMember(String id) {
    return members
        .where((m) => m.userId == id || m.snowchatId == id)
        .firstOrNull;
  }

  /// Check if a user is the group creator (superadmin).
  bool isSuperAdmin(String id) => creatorId == id;

  /// Check if a user is an admin (either superadmin or assigned admin).
  bool isAdmin(String id) {
    if (isSuperAdmin(id)) return true;
    final member = findMember(id);
    return member?.isAdmin ?? false;
  }
}

class GroupDetailNotifier extends StateNotifier<GroupDetail> {
  final String _groupId;
  final Ref _ref;

  GroupDetailNotifier({
    required String groupId,
    required Ref ref,
  })  : _groupId = groupId,
        _ref = ref,
        super(GroupDetail(id: groupId, isLoading: gv2IsGroupId(groupId))) {
    // Only a group protocol v2 group has a detail; any other id stays an
    // empty, settled detail.
    if (gv2IsGroupId(groupId)) _watch();
  }

  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  /// Keep the detail in step with the local store.
  void _watch() {
    final store = _ref.read(snowDatabaseProvider).gv2Store;
    _subscriptions
      ..add(store.watchGroup(_groupId).listen((_) => _load()))
      ..add(store.watchMemberRows(_groupId).listen((_) => _load()));
  }

  /// Read the detail from the local store again.
  Future<void> loadGroup() async {
    if (!mounted || !gv2IsGroupId(_groupId)) return;
    await _load();
  }

  /// The detail from the local store: the confirmed and unconfirmed members
  /// as the change log names them, with the owner as "creator". An
  /// account's id doubles as its user id here (a v2 group knows no server
  /// user ids).
  Future<void> _load() async {
    try {
      final store = _ref.read(snowDatabaseProvider).gv2Store;
      final row = await store.group(_groupId);
      final rows = row == null ? const <Never>[] : await store.memberRows(_groupId);
      if (!mounted) return;
      final known = _ref.read(gv2KnownNamesProvider);
      var owner = '';
      final members = <GroupMember>[];
      for (final m in rows) {
        final snowId = m.snowId;
        if (snowId == null) continue;
        if (m.role == gv2RoleOwner) owner = snowId;
        final name = known[snowId] ?? m.nickname;
        members.add(GroupMember(
          userId: snowId,
          snowchatId: snowId,
          displayName: (name == null || name.isEmpty) ? null : name,
          isAdmin: m.role == gv2RoleAdmin,
          status: m.checkState == Gv2MemberCheckState.confirmed
              ? 'accepted'
              : 'pending',
          joinedAt: '',
        ));
      }
      state = GroupDetail(
        id: _groupId,
        name: row?.title,
        creatorId: owner,
        members: members,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(isLoading: false, error: e.runtimeType.toString());
    }
  }
}

// Released when no screen watches it: each one held two whole-table
// watches of the group tables for every group opened in the session, and
// read up to 256 members again on every write to them.
final groupDetailProvider = StateNotifierProvider.autoDispose
    .family<GroupDetailNotifier, GroupDetail, String>(
  (ref, groupId) => GroupDetailNotifier(groupId: groupId, ref: ref),
);
