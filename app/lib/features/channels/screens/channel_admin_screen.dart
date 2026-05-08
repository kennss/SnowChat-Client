/// @file        channel_admin_screen.dart
/// @description Channel admin screen — Owner/Admin-only unified dashboard.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-06
/// @lastUpdated 2026-04-26 (header + inline English translation; channel avatar upload/change UI added)
///
/// @functions
///  - ChannelAdminScreen: channel settings + member management + pending approval + invite link + delete
///  - _pickAvatar(): pick channel avatar image from gallery
///  - _uploadAvatar(): upload selected image to server and return fileId

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';
import '../../../shared/widgets/toast.dart';
import '../../../core/network/api_endpoints.dart';
import '../../chat/providers/conversation_list_provider.dart';
import '../models/channel.dart';
import '../providers/channel_provider.dart';
import '../../wallet/tensor/widgets/channel_community_section.dart';

/// Channel detail provider for admin screen.
final _adminDetailProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, channelId) async {
  try {
    final apiClient = ref.read(apiClientProvider);
    final res = await apiClient.get(ApiEndpoints.channelDetail(channelId));
    return Map<String, dynamic>.from(res.data as Map);
  } catch (e) {
    debugPrint('[ChannelAdmin] Detail failed: $e');
    return null;
  }
});

class ChannelAdminScreen extends ConsumerStatefulWidget {
  final String channelId;
  final String channelName;

  const ChannelAdminScreen({
    super.key,
    required this.channelId,
    required this.channelName,
  });

  @override
  ConsumerState<ChannelAdminScreen> createState() => _ChannelAdminScreenState();
}

class _ChannelAdminScreenState extends ConsumerState<ChannelAdminScreen> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  String _selectedCategory = 'Other';
  String _joinPolicy = 'OPEN';
  bool _allowMemberInvite = false;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  // upload-on-pick 으로 받은 새 avatar fileId. _saveSettings 에서 PUT body
  // 의 avatarUrl 로 사용. _avatarFile 보존에 의존하지 않으므로 picker 가
  // 떠있는 동안 OS 가 액티비티 회수해도 손실되지 않음 (업로드 완료된 fileId
  // 만 보존).
  String? _pendingAvatarUrl;
  // _initFromDetail 가 매 build 마다 호출되면 사용자가 토글한 직후 setState
  // 의 rebuild 로 detail 의 stale 값 (서버 동기화 전) 이 즉시 덮어쓰기 →
  // 토글이 OFF 로 자동 복귀하는 버그 (allowMemberInvite, joinPolicy,
  // category 모두 동일). 최초 1회만 init 후엔 사용자 입력만 반영.
  bool _detailInitialized = false;
  bool _isDeleting = false;
  File? _avatarFile;
  String? _currentAvatarUrl;

  StreamSubscription<Map<String, dynamic>>? _applicationSub;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.channelName);
    _descController = TextEditingController();
    // Always fetch latest data on screen enter
    Future.microtask(() {
      ref.invalidate(_adminDetailProvider(widget.channelId));
    });
    // Listen for new applications while admin screen is open
    Future.microtask(() {
      final sm = ref.read(socketManagerProvider);
      _applicationSub = sm.onChannelApplicationReceived.listen((data) {
        ref.invalidate(_adminDetailProvider(widget.channelId));
        if (mounted) {
          final name = data['displayName'] as String? ?? 'Someone';
          SnowToast.show(
            context,
            message: '$name applied to join',
            type: ToastType.info,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _applicationSub?.cancel();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _initFromDetail(Map<String, dynamic> detail) {
    // Guard: 최초 1회만 stateful 필드 초기화. setState rebuild 마다 호출되면
    // 사용자 입력 (토글 ON, dropdown 변경 등) 이 즉시 stale server 값으로
    // 덮여서 UI 가 입력을 받지 않는 것처럼 보임.
    if (_detailInitialized) return;
    _detailInitialized = true;

    if (_nameController.text == widget.channelName) {
      _nameController.text = detail['name'] as String? ?? widget.channelName;
    }
    if (_descController.text.isEmpty) {
      _descController.text = detail['description'] as String? ?? '';
    }
    _selectedCategory = detail['category'] as String? ?? 'Other';
    _joinPolicy = detail['joinPolicy'] as String? ?? 'OPEN';
    _allowMemberInvite = detail['allowMemberInvite'] as bool? ?? false;
    _currentAvatarUrl ??= detail['avatarUrl'] as String?;
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;

    // 미리보기는 즉시 노출 (네트워크 왕복 전).
    setState(() {
      _avatarFile = File(image.path);
      _isUploadingAvatar = true;
    });

    // upload-on-pick — 갤러리 picker 가 띄워져 있는 동안 OS 가 main
    // activity 메모리 회수하면 _avatarFile 손실되어 _saveSettings 시점에
    // null → upload 0 회 → avatar 미반영 채로 PUT 만 성공 (사용자가 본
    // "save 가 않됨" 의 진짜 원인). pick 직후 업로드해서 fileId 만 보존.
    final fileId = await _uploadAvatarBytes(_avatarFile!);
    if (!mounted) return;
    setState(() {
      _isUploadingAvatar = false;
      if (fileId != null) {
        _pendingAvatarUrl = fileId;
      } else {
        // 업로드 실패 시 미리보기 롤백
        _avatarFile = null;
      }
    });
    if (fileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Avatar upload failed. Try again.'),
          backgroundColor: SnowColors.error,
        ),
      );
    }
  }

  Future<String?> _uploadAvatarBytes(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes).toString();
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.postRaw(
        ApiEndpoints.uploadFile,
        bytes: bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'x-content-hash': hash,
        },
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      return data['fileId'] as String?;
    } catch (e) {
      debugPrint('[ChannelAdmin] Avatar upload failed: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(_adminDetailProvider(widget.channelId));

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(widget.channelName),
      ),
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            return const Center(
              child: Text('Failed to load channel',
                  style: TextStyle(color: SnowColors.textTertiary)),
            );
          }
          _initFromDetail(detail);
          return _buildBody(detail);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Text('Error loading channel',
              style: TextStyle(color: SnowColors.textTertiary)),
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> detail) {
    final members = (detail['members'] as List?) ?? [];
    final pendingMembers = (detail['pendingMembers'] as List?) ?? [];
    final creatorId = detail['creatorId'] as String?;
    final mySnowId = ref.read(currentSnowIdProvider);

    // Determine my role
    final myMember = members.firstWhere(
      (m) => (m['user']?['snowchatId'] as String?) == mySnowId,
      orElse: () => null,
    );
    final isOwner = myMember != null &&
        (myMember['role'] == 'OWNER' || myMember['userId'] == creatorId);

    // Sort members: Owner → Admin → Member
    final sortedMembers = [...members]..sort((a, b) {
        int roleOrder(dynamic m) {
          if (m['userId'] == creatorId) return 0;
          if (m['role'] == 'ADMIN') return 1;
          return 2;
        }
        return roleOrder(a).compareTo(roleOrder(b));
      });

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(_adminDetailProvider(widget.channelId));
      },
      color: SnowColors.primary,
      child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(SnowSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Settings ──
          _buildSectionHeader('Settings'),
          const SizedBox(height: SnowSizes.sm),
          _buildSettingsSection(detail),

          const SizedBox(height: SnowSizes.xl),

          // ── Pending Members ──
          if (pendingMembers.isNotEmpty) ...[
            _buildSectionHeader('Pending (${pendingMembers.length})'),
            const SizedBox(height: SnowSizes.sm),
            ...pendingMembers.map((m) => _buildPendingTile(m)),
            const SizedBox(height: SnowSizes.xl),
          ],

          // ── Members ──
          _buildSectionHeader('Members (${members.length})'),
          const SizedBox(height: SnowSizes.sm),
          ...sortedMembers.map((m) =>
              _buildMemberTile(m, creatorId: creatorId, isOwner: isOwner)),

          const SizedBox(height: SnowSizes.xl),

          // ── Invite Link ──
          _buildSectionHeader('Invite Link'),
          const SizedBox(height: SnowSizes.sm),
          OutlinedButton.icon(
            onPressed: () => context.push(
              '/invite-link/${widget.channelId}?name=${Uri.encodeComponent(widget.channelName)}',
            ),
            icon: const Icon(Icons.link_rounded),
            label: const Text('Manage Invite Links'),
          ),

          // ── Community NFT (owner only) ──
          if (isOwner) ...[
            const SizedBox(height: SnowSizes.xl),
            _buildSectionHeader('Community NFT Fee Share'),
            const SizedBox(height: SnowSizes.xs),
            const Text(
              'Register this channel\'s NFT collection to receive 50% of '
              'Tensor protocol fees on every trade. Sealed metadata '
              '(one-way) required.',
              style: TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: SnowSizes.sm),
            ChannelCommunitySection(channelId: widget.channelId),
          ],

          const SizedBox(height: SnowSizes.xl),

          // ── Danger Zone ──
          if (isOwner) ...[
            _buildSectionHeader('Danger Zone'),
            const SizedBox(height: SnowSizes.sm),
            // Transfer Ownership
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showTransferOwnershipPicker(sortedMembers, creatorId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.amber,
                  side: const BorderSide(color: Colors.amber),
                ),
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Transfer Ownership'),
              ),
            ),
            const SizedBox(height: SnowSizes.sm),
            // Delete Channel
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isDeleting ? null : () => _confirmDelete(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SnowColors.error,
                  side: const BorderSide(color: SnowColors.error),
                ),
                icon: _isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: SnowColors.error))
                    : const Icon(Icons.delete_forever_rounded),
                label: const Text('Delete Channel'),
              ),
            ),
          ],

          const SizedBox(height: SnowSizes.xl),
        ],
      ),
    ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: SnowColors.textTertiary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Settings Section
  // ---------------------------------------------------------------------------

  Widget _buildSettingsSection(Map<String, dynamic> detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Channel avatar
        Center(
          child: GestureDetector(
            onTap: _pickAvatar,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: SnowColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: SnowColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_avatarFile != null)
                    Image.file(
                      _avatarFile!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    )
                  else if (_currentAvatarUrl != null)
                    Image.network(
                      '${ApiEndpoints.getBaseUrl()}/files/${_currentAvatarUrl!}',
                      // 서버 GET /files/:fileId 는 auth 필수 — 토큰 없으면
                      // 401 → errorBuilder 의 generic icon 으로 fallback →
                      // 사용자 입장에선 "save 가 안 됨" 으로 보임.
                      // (서버 저장은 됐지만 client 가 표시 못 함.)
                      //
                      // Phase 11 (2026-05-04 회귀 fix): 이전엔 Dio default
                      // headers 에 Authorization 박혀있었지만 cut over 후
                      // 매 request interceptor 가 동적 주입 → default 는 비었음
                      // → 옛 lookup 이 null → 401. authHeaderProvider 가
                      // tokenSnapshotProvider 를 watch 해서 token 회전 시
                      // 자동 rebuild.
                      headers: () {
                        final h = ref.watch(authHeaderProvider);
                        return h != null ? {'Authorization': h} : null;
                      }(),
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.groups_rounded,
                        color: SnowColors.textTertiary,
                        size: 32,
                      ),
                    )
                  else
                    const Icon(
                      Icons.camera_alt_rounded,
                      color: SnowColors.textTertiary,
                      size: 32,
                    ),
                  // upload-on-pick 진행 중 — preview 위에 spinner 오버레이.
                  // 끝나기 전에 Save 누르면 race guard 가 잡지만 시각적
                  // feedback 으로 명시적 표시.
                  if (_isUploadingAvatar)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SnowColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _avatarFile != null
                ? 'Tap to change'
                : _currentAvatarUrl != null
                    ? 'Tap to change icon'
                    : 'Upload Channel Icon',
            style: const TextStyle(
                color: SnowColors.textTertiary, fontSize: 12),
          ),
        ),
        const SizedBox(height: SnowSizes.md),

        // Channel name
        TextField(
          controller: _nameController,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'Channel Name',
            counterText: '',
          ),
        ),
        const SizedBox(height: SnowSizes.sm),

        // Description
        TextField(
          controller: _descController,
          maxLines: 2,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Description',
            counterText: '',
          ),
        ),
        const SizedBox(height: SnowSizes.md),

        // Category
        DropdownButtonFormField<String>(
          value: channelCategories.contains(_selectedCategory)
              ? _selectedCategory
              : 'Other',
          dropdownColor: SnowColors.surface,
          style: const TextStyle(color: SnowColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Category'),
          items: channelCategories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) => setState(() => _selectedCategory = v ?? 'Other'),
        ),
        const SizedBox(height: SnowSizes.md),

        // Join policy
        DropdownButtonFormField<String>(
          value: _joinPolicy,
          dropdownColor: SnowColors.surface,
          style: const TextStyle(color: SnowColors.textPrimary),
          decoration: const InputDecoration(labelText: 'Join Policy'),
          items: const [
            DropdownMenuItem(value: 'OPEN', child: Text('Open')),
            DropdownMenuItem(value: 'APPROVAL', child: Text('Approval')),
            DropdownMenuItem(value: 'INVITE_ONLY', child: Text('Invite Only')),
          ],
          onChanged: (v) {
            setState(() {
              _joinPolicy = v ?? 'OPEN';
              // INVITE_ONLY 면 멤버 invite 강제 off (서버 enforce 와 동기화).
              if (_joinPolicy == 'INVITE_ONLY') {
                _allowMemberInvite = false;
              }
            });
          },
        ),
        const SizedBox(height: SnowSizes.md),

        // Allow members to invite (Telegram pattern). INVITE_ONLY 채널엔
        // disabled — 비공개인데 누구나 초대하면 게이트키핑 무력화됨.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow members to invite',
              style: TextStyle(color: SnowColors.textPrimary)),
          subtitle: Text(
            _joinPolicy == 'INVITE_ONLY'
                ? 'Disabled — Invite Only channels require admin approval.'
                : 'Members can create invite links to bring in friends.',
            style: const TextStyle(color: SnowColors.textTertiary, fontSize: 12),
          ),
          value: _allowMemberInvite,
          activeThumbColor: SnowColors.primary,
          onChanged: _joinPolicy == 'INVITE_ONLY'
              ? null
              : (v) => setState(() => _allowMemberInvite = v),
        ),
        const SizedBox(height: SnowSizes.md),

        // Save button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save Changes'),
          ),
        ),
      ],
    );
  }

  Future<void> _saveSettings() async {
    // upload-on-pick 이 아직 끝나지 않은 상태로 Save 시 race 차단.
    if (_isUploadingAvatar) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Avatar still uploading… please wait')),
      );
      return;
    }
    setState(() => _isSaving = true);

    // Avatar 는 _pickAvatar 에서 이미 upload 완료 → fileId 만 사용.
    final newAvatarUrl = _pendingAvatarUrl;

    final updateData = <String, dynamic>{
      'name': _nameController.text.trim(),
      'description': _descController.text.trim(),
      'category': _selectedCategory,
      'joinPolicy': _joinPolicy,
      'isPublic': _joinPolicy != 'INVITE_ONLY',
      'allowMemberInvite':
          _joinPolicy == 'INVITE_ONLY' ? false : _allowMemberInvite,
      if (newAvatarUrl != null) 'avatarUrl': newAvatarUrl,
    };

    final success = await ref
        .read(channelActionsProvider)
        .updateSettings(widget.channelId, updateData);
    if (newAvatarUrl != null && success) {
      _currentAvatarUrl = newAvatarUrl;
      _avatarFile = null;
      _pendingAvatarUrl = null;
      // 다른 화면들의 캐시도 새로 fetch — 채널 list 의 avatarUrl 동기화.
      ref.invalidate(myChannelsProvider);
      ref.invalidate(_adminDetailProvider(widget.channelId));
    }
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Settings saved' : 'Failed to save'),
          backgroundColor: success ? SnowColors.primary : SnowColors.error,
        ),
      );
      if (success) {
        ref.invalidate(myChannelsProvider);
        ref.invalidate(_adminDetailProvider(widget.channelId));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Pending Members
  // ---------------------------------------------------------------------------

  Widget _buildPendingTile(dynamic member) {
    final user = member['user'] as Map<String, dynamic>? ?? {};
    final displayName = user['displayName'] as String? ?? '';
    final snowchatId = user['snowchatId'] as String? ?? '';
    final userId = member['userId'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SnowColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Text('  ', style: TextStyle(fontSize: 14)),
          SnowAvatar(
            snowId: snowchatId,
            size: 32,
            displayName: displayName,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              displayName.isNotEmpty ? displayName : snowchatId.substring(0, 12),
              style: const TextStyle(
                color: SnowColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
          // Approve
          IconButton(
            onPressed: () => _handleApprove(userId),
            icon: const Icon(Icons.check_circle_rounded,
                color: SnowColors.primary, size: 28),
            tooltip: 'Approve',
          ),
          // Reject
          IconButton(
            onPressed: () => _handleReject(userId),
            icon: const Icon(Icons.cancel_rounded,
                color: SnowColors.error, size: 28),
            tooltip: 'Reject',
          ),
        ],
      ),
    );
  }

  Future<void> _handleApprove(String userId) async {
    debugPrint('[ChannelAdmin] Approving userId=$userId channelId=${widget.channelId}');
    final success = await ref
        .read(channelActionsProvider)
        .approveApplication(widget.channelId, userId);
    debugPrint('[ChannelAdmin] Approve result: $success');
    if (success) {
      ref.invalidate(_adminDetailProvider(widget.channelId));
      ref.invalidate(myChannelsProvider);
    }
  }

  Future<void> _handleReject(String userId) async {
    final success = await ref
        .read(channelActionsProvider)
        .rejectApplication(widget.channelId, userId);
    if (success) {
      ref.invalidate(_adminDetailProvider(widget.channelId));
    }
  }

  // ---------------------------------------------------------------------------
  // Member Tiles
  // ---------------------------------------------------------------------------

  Widget _buildMemberTile(
    dynamic member, {
    String? creatorId,
    required bool isOwner,
  }) {
    final user = member['user'] as Map<String, dynamic>? ?? {};
    final displayName = user['displayName'] as String? ?? '';
    final snowchatId = user['snowchatId'] as String? ?? '';
    final userId = member['userId'] as String? ?? '';
    final role = member['role'] as String? ?? 'MEMBER';
    final isMemberOwner = userId == creatorId;
    final isMemberAdmin = role == 'ADMIN';
    final mySnowId = ref.read(currentSnowIdProvider);
    final isMe = snowchatId == mySnowId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Role badge
          if (isMemberOwner)
            const Text('  ', style: TextStyle(fontSize: 14))
          else if (isMemberAdmin)
            const Text('  ', style: TextStyle(fontSize: 14))
          else
            const SizedBox(width: 22),
          SnowAvatar(
            snowId: snowchatId,
            size: 32,
            displayName: displayName,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName.isNotEmpty
                      ? displayName
                      : snowchatId.substring(0, 12),
                  style: TextStyle(
                    color: SnowColors.textPrimary,
                    fontSize: 14,
                    fontWeight: isMemberOwner || isMemberAdmin
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
                Text(
                  isMemberOwner
                      ? 'Owner'
                      : isMemberAdmin
                          ? 'Admin'
                          : 'Member',
                  style: TextStyle(
                    color: isMemberOwner
                        ? Colors.amber
                        : isMemberAdmin
                            ? SnowColors.primary
                            : SnowColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Action menu (not for self, not for owner)
          if (!isMe && !isMemberOwner)
            IconButton(
              onPressed: () => _showMemberActions(
                userId: userId,
                displayName: displayName,
                role: role,
                isOwner: isOwner,
              ),
              icon: const Icon(Icons.more_vert_rounded,
                  color: SnowColors.textTertiary, size: 20),
            ),
        ],
      ),
    );
  }

  void _showMemberActions({
    required String userId,
    required String displayName,
    required String role,
    required bool isOwner,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SnowColors.surfaceVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: SnowColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(displayName,
                  style: const TextStyle(
                      color: SnowColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
            ),
            const SizedBox(height: 8),
            const Divider(color: SnowColors.divider),

            // Make Admin / Remove Admin (Owner only)
            if (isOwner && role == 'MEMBER')
              ListTile(
                leading: const Icon(Icons.shield_rounded,
                    color: SnowColors.primary),
                title: const Text('Make Admin',
                    style: TextStyle(color: SnowColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handleSetRole(userId, 'ADMIN');
                },
              ),
            if (isOwner && role == 'ADMIN')
              ListTile(
                leading: const Icon(Icons.shield_outlined,
                    color: SnowColors.textTertiary),
                title: const Text('Remove Admin',
                    style: TextStyle(color: SnowColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _handleSetRole(userId, 'MEMBER');
                },
              ),

            // Kick
            ListTile(
              leading:
                  const Icon(Icons.person_remove_rounded, color: Colors.orange),
              title: const Text('Kick',
                  style: TextStyle(color: SnowColors.textPrimary)),
              onTap: () {
                Navigator.pop(context);
                _handleKick(userId, displayName);
              },
            ),

            // Ban (Owner only)
            if (isOwner)
              ListTile(
                leading: const Icon(Icons.block_rounded,
                    color: SnowColors.error),
                title: const Text('Ban',
                    style: TextStyle(color: SnowColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  _handleBan(userId, displayName);
                },
              ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSetRole(String userId, String role) async {
    final success = await ref
        .read(channelActionsProvider)
        .setRole(widget.channelId, userId, role);
    if (success) {
      ref.invalidate(_adminDetailProvider(widget.channelId));
      ref.invalidate(myChannelsProvider);
    }
  }

  Future<void> _handleKick(String userId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Kick Member',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Text('Remove $displayName from the channel?',
            style: const TextStyle(color: SnowColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kick', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final success = await ref
          .read(channelActionsProvider)
          .kickMember(widget.channelId, userId);
      if (success) {
        ref.invalidate(_adminDetailProvider(widget.channelId));
        ref.invalidate(myChannelsProvider);
      }
    }
  }

  Future<void> _handleBan(String userId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Ban Member',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Text(
            'Ban $displayName from the channel? They will not be able to rejoin.',
            style: const TextStyle(color: SnowColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ban', style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final success = await ref
          .read(channelActionsProvider)
          .banMember(widget.channelId, userId);
      if (success) {
        ref.invalidate(_adminDetailProvider(widget.channelId));
        ref.invalidate(myChannelsProvider);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Transfer Ownership
  // ---------------------------------------------------------------------------

  void _showTransferOwnershipPicker(List<dynamic> members, String? creatorId) {
    // Filter: non-owner accepted members only, ADMINs first
    final candidates = members.where((m) {
      final role = m['role'] as String?;
      return role != 'OWNER' && m['userId'] != creatorId;
    }).toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No members to transfer ownership to')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: SnowColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Transfer Ownership',
                style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Select a member to become the new owner. You will become an Admin.',
                style: TextStyle(color: SnowColors.textSecondary, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
            ...candidates.map((m) {
              final displayName = m['user']?['displayName'] ??
                  m['user']?['snowchatId'] ??
                  'Unknown';
              final role = m['role'] as String? ?? 'MEMBER';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: SnowColors.primary.withValues(alpha: 0.2),
                  child: Text(
                    (displayName as String).substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: SnowColors.primary),
                  ),
                ),
                title: Text(displayName,
                    style: const TextStyle(color: SnowColors.textPrimary)),
                subtitle: Text(role,
                    style: const TextStyle(color: SnowColors.textTertiary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmTransferOwnership(
                    m['userId'] as String,
                    displayName,
                  );
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmTransferOwnership(String userId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Transfer Ownership',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: Text(
          'Transfer channel ownership to $displayName? You will become an Admin.',
          style: const TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Transfer',
                style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      debugPrint('[ChannelAdmin] Transferring ownership to $userId ($displayName) for channel ${widget.channelId}');
      final success = await ref
          .read(channelActionsProvider)
          .transferOwnership(widget.channelId, userId);
      debugPrint('[ChannelAdmin] Transfer result: $success');
      if (mounted) {
        if (success) {
          ref.invalidate(_adminDetailProvider(widget.channelId));
          ref.invalidate(myChannelsProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ownership transferred to $displayName')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Transfer failed')),
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Delete Channel
  // ---------------------------------------------------------------------------

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surface,
        title: const Text('Delete Channel',
            style: TextStyle(color: SnowColors.textPrimary)),
        content: const Text(
          'This will permanently delete the channel and all its rooms. This action cannot be undone.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete',
                style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _isDeleting = true);
      final success = await ref
          .read(channelActionsProvider)
          .deleteChannel(widget.channelId);
      setState(() => _isDeleting = false);
      if (success && mounted) {
        ref.invalidate(myChannelsProvider);
        ref.read(conversationListProvider.notifier).refresh();
        context.pop();
      }
    }
  }
}
