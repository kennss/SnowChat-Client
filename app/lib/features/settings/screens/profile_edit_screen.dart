/// @file        profile_edit_screen.dart
/// @description Profile edit screen — change display nickname via PUT /users/profile.
///              The SnowChat ID is derived from the recovery-phrase keys and is
///              immutable; only the human-facing nickname is editable here.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-08-03
/// @lastUpdated 2026-08-03
///
/// @functions
///  - ProfileEditScreen: nickname edit form
///  - _ProfileEditScreenState._save(): validate + PUT /users/profile + persist locally + pop
///  - _ProfileEditScreenState._load(): pre-fill the field with the current nickname

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/snow_avatar.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key});

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _original = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final name = await ref.read(secureStorageProvider).getDisplayName() ?? '';
    if (!mounted) return;
    setState(() {
      _original = name;
      _controller.text = name;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Nickname cannot be empty');
      return;
    }
    if (name == _original) {
      context.pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).put(
        ApiEndpoints.userProfile,
        data: {'displayName': name},
      );
      // Persist locally so the Settings header / PIN screen reflect it offline;
      // the server also broadcasts `profile_updated` so contacts refresh live.
      await ref.read(secureStorageProvider).storeDisplayName(name);
      // Push into the reactive display-name state so the Settings header (and
      // anything else watching it) updates immediately on pop instead of only
      // after the next rebuild.
      ref.read(currentDisplayNameProvider.notifier).state = name;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      // Server returns 409 when the nickname is already taken (unique column).
      final taken = e.response?.statusCode == 409;
      setState(() {
        _saving = false;
        _error = taken
            ? 'This nickname is already taken'
            : 'Failed to update profile. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to update profile. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(currentSnowIdProvider) ?? '';
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(title: const Text('Edit Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(SnowSizes.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SnowAvatar(
                        snowId: myId,
                        size: 88,
                        displayName:
                            _controller.text.isEmpty ? 'Me' : _controller.text,
                      ),
                    ),
                    const SizedBox(height: SnowSizes.xl),
                    const Text(
                      'Nickname',
                      style: TextStyle(
                        color: SnowColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: SnowSizes.sm),
                    const Text(
                      'This is how others will see you in SnowChat. Your '
                      'SnowChat ID never changes.',
                      style: TextStyle(
                        color: SnowColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: SnowSizes.md),
                    TextField(
                      controller: _controller,
                      maxLength: 20,
                      enabled: !_saving,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _saving ? null : _save(),
                      onChanged: (_) {
                        if (_error != null) setState(() => _error = null);
                        // Refresh the avatar initial as the name changes.
                        setState(() {});
                      },
                      style: const TextStyle(color: SnowColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Nickname',
                        errorText: _error,
                        filled: true,
                        fillColor: SnowColors.surfaceVariant,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: SnowSizes.xl),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
