/// @file        address_book_sheet.dart
/// @description Address book pick/save bottom sheet — Phase 6.1 §3.5.
///              Shows entries list, new-entry add form, returns callback on
///              selection.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-08
/// @lastUpdated 2026-04-26 (header + inline English translation)
///
/// @functions
///  - showAddressBookPickerSheet(): address book entry point
///  - showSaveAddressDialog(): label-input dialog after a transfer
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../wallet_provider.dart';
import 'address_book_repository.dart';

const _surface = Color(0xFF111111);
const _surfaceVariant = Color(0xFF1A1A1A);
const _accent = Color(0xFF00F782);
const _text = Color(0xFFFFFFFF);
const _muted = Color(0xFF9E9E9E);
const _divider = Color(0xFF1F1F1F);

/// Address book picker bottom sheet. Returns [AddressBookEntry] when the
/// user picks one; null if cancelled.
Future<AddressBookEntry?> showAddressBookPickerSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String ownerAddress,
}) {
  return showModalBottomSheet<AddressBookEntry>(
    context: context,
    backgroundColor: _surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AddressBookSheet(
      ownerAddress: ownerAddress,
      repository: ref.read(addressBookRepositoryProvider),
    ),
  );
}

/// Right after a transfer, the "Save this address?" dialog. Saves after label input.
Future<bool> showSaveAddressDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String ownerAddress,
  required String address,
  String network = 'mainnet',
}) async {
  final controller = TextEditingController();
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _surface,
      title: const Text('Save to address book?',
          style: TextStyle(color: _text, fontSize: 16)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            address,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: _text),
            decoration: const InputDecoration(
              hintText: 'Label (e.g. Mom, Coffee shop)',
              hintStyle: TextStyle(color: _muted),
              filled: true,
              fillColor: _surfaceVariant,
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Skip', style: TextStyle(color: _muted)),
        ),
        TextButton(
          onPressed: () async {
            final label = controller.text.trim();
            if (label.isEmpty) return;
            await ref.read(addressBookRepositoryProvider).add(
                  ownerAddress: ownerAddress,
                  label: label,
                  address: address,
                  network: network,
                );
            if (ctx.mounted) Navigator.pop(ctx, true);
          },
          child: const Text('Save', style: TextStyle(color: _accent)),
        ),
      ],
    ),
  );
  return saved ?? false;
}

class _AddressBookSheet extends StatefulWidget {
  const _AddressBookSheet({
    required this.ownerAddress,
    required this.repository,
  });

  final String ownerAddress;
  final AddressBookRepository repository;

  @override
  State<_AddressBookSheet> createState() => _AddressBookSheetState();
}

class _AddressBookSheetState extends State<_AddressBookSheet> {
  late Future<List<AddressBookEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.list(widget.ownerAddress);
  }

  void _reload() {
    setState(() {
      _future = widget.repository.list(widget.ownerAddress);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Address book',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: FutureBuilder<List<AddressBookEntry>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const SizedBox(
                      height: 80,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: _accent,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    );
                  }
                  final entries = snap.data ?? [];
                  if (entries.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          'No saved addresses yet.\nSave one after sending.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, fontSize: 13),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: _divider, height: 1),
                    itemBuilder: (_, i) {
                      final e = entries[i];
                      return Dismissible(
                        key: ValueKey(e.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: const Color(0xFF441515),
                          child: const Icon(Icons.delete_outline,
                              color: Color(0xFFFF4444)),
                        ),
                        onDismissed: (_) async {
                          await widget.repository.remove(e.id);
                          _reload();
                        },
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            e.label,
                            style: const TextStyle(color: _text, fontSize: 14),
                          ),
                          subtitle: Text(
                            _shortAddress(e.address),
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                          ),
                          onTap: () async {
                            await widget.repository.touch(e.id);
                            if (mounted) Navigator.pop(context, e);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortAddress(String addr) {
    if (addr.length <= 16) return addr;
    return '${addr.substring(0, 8)}…${addr.substring(addr.length - 8)}';
  }
}
