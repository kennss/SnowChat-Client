/// @file        add_contact_screen.dart
/// @description Add-contact screen — SnowChat ID input/validation, clipboard paste, my QR code display.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-04-26 (header English translation; QR scan tab removed — single-screen layout)
///
/// @functions
///  - AddContactScreen: add-contact ConsumerStatefulWidget
///  - _validateAndLookup(): SnowChat ID format validation and server user lookup
///  - _pasteFromClipboard(): paste SnowChat ID from clipboard

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/constants/colors.dart';
import '../../../shared/constants/sizes.dart';
import '../../../shared/widgets/toast.dart';
import '../../../core/crypto/key_derivation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../app/providers.dart';
import '../contact_provider.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String? _error;
  bool _isLookingUp = false;
  String? _lookedUpDisplayName;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Validate SnowChat ID format: "snow" + 32 hex chars = 36 total.
  bool _isValidFormat(String id) {
    return KeyDerivation.isValidSnowChatId(id);
  }

  /// Validate ID format and look up user on the server.
  Future<void> _validateAndLookup(String snowId) async {
    if (snowId.isEmpty) {
      setState(() {
        _error = null;
        _lookedUpDisplayName = null;
      });
      return;
    }

    if (!_isValidFormat(snowId)) {
      setState(() {
        _error = 'Invalid format. Must be "snow" + 32 hex characters.';
        _lookedUpDisplayName = null;
      });
      return;
    }

    // Check not adding self
    final myId = ref.read(currentSnowIdProvider);
    if (myId != null && snowId == myId) {
      setState(() {
        _error = 'You cannot add yourself as a contact.';
        _lookedUpDisplayName = null;
      });
      return;
    }

    setState(() {
      _error = null;
      _isLookingUp = true;
      _lookedUpDisplayName = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get(ApiEndpoints.userLookup(snowId));
      final data = response.data;
      if (data != null && data is Map && data['displayName'] != null) {
        setState(() {
          _lookedUpDisplayName = data['displayName'] as String;
          if (_nameController.text.isEmpty) {
            _nameController.text = _lookedUpDisplayName!;
          }
        });
      }
    } catch (_) {
      // User not found on server is OK — still allow adding by ID
    } finally {
      if (mounted) {
        setState(() => _isLookingUp = false);
      }
    }
  }

  /// Add the contact and pop the screen.
  void _addContact() {
    final snowId = _idController.text.trim();
    final name = _nameController.text.trim();

    if (snowId.isEmpty) {
      setState(() => _error = 'Please enter a SnowChat ID');
      return;
    }

    if (!_isValidFormat(snowId)) {
      setState(() => _error = 'Invalid SnowChat ID format');
      return;
    }

    ref.read(contactProvider.notifier).addContact(
          Contact(
            snowChatId: snowId,
            displayName: name.isNotEmpty ? name : _lookedUpDisplayName,
            addedAt: DateTime.now(),
          ),
        );

    SnowToast.show(
      context,
      message: 'Contact added',
      type: ToastType.success,
    );
    context.pop();
  }

  /// Paste SnowChat ID from clipboard and validate.
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';

    if (text.isEmpty) {
      if (mounted) {
        SnowToast.show(
          context,
          message: 'Clipboard is empty',
          type: ToastType.warning,
        );
      }
      return;
    }

    if (_isValidFormat(text)) {
      _idController.text = text;
      await _validateAndLookup(text);
    } else {
      if (mounted) {
        SnowToast.show(
          context,
          message: 'Clipboard does not contain a valid SnowChat ID',
          type: ToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Add Contact'),
      ),
      body: _buildEnterIdTab(),
    );
  }

  /// "Enter ID" tab — text field for SnowChat ID + display name.
  Widget _buildEnterIdTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SnowSizes.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SnowChat ID input
          const Text(
            'SnowChat ID',
            style: TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: SnowSizes.sm),
          TextField(
            controller: _idController,
            onChanged: (value) {
              setState(() => _error = null);
              final trimmed = value.trim();
              if (trimmed.length == 36) {
                _validateAndLookup(trimmed);
              }
            },
            style: const TextStyle(
              color: SnowColors.textPrimary,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            maxLength: 36,
            decoration: InputDecoration(
              hintText: 'snow...',
              counterText: '${_idController.text.trim().length}/36',
              counterStyle: const TextStyle(
                color: SnowColors.textTertiary,
                fontSize: 11,
              ),
              errorText: _error,
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLookingUp)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: SnowColors.primary,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.content_paste_rounded,
                      color: SnowColors.primary,
                    ),
                    tooltip: 'Paste from clipboard',
                    onPressed: _pasteFromClipboard,
                  ),
                ],
              ),
            ),
          ),

          // Looked-up user hint
          if (_lookedUpDisplayName != null) ...[
            const SizedBox(height: SnowSizes.xs),
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: SnowColors.success,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Found: $_lookedUpDisplayName',
                  style: const TextStyle(
                    color: SnowColors.success,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: SnowSizes.lg),

          // Display name input
          const Text(
            'Display Name (optional)',
            style: TextStyle(
              color: SnowColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: SnowSizes.sm),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: SnowColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Enter a name...',
            ),
          ),

          const SizedBox(height: SnowSizes.xl),

          // Add button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _addContact,
              child: const Text('Add Contact'),
            ),
          ),

          const SizedBox(height: SnowSizes.xl),

          // Show My QR Code button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                context.pop();
                context.push('/my-qr');
              },
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Show My QR Code'),
            ),
          ),
        ],
      ),
    );
  }

}
