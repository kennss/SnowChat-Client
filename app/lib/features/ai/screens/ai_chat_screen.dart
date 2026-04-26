/// @file        ai_chat_screen.dart
/// @description SnowChat AI dedicated conversation screen. Token streaming + drift AiMessages persistence.
///              Local AI conversation room fully separated from E2EE chat.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-04-10
/// @lastUpdated 2026-04-26 (header + inline English translation; AI dedicated conversation screen)
///
/// @functions
///  - AiChatScreen: AI dedicated conversation ConsumerStatefulWidget
///  - _initializeAI(): verify model install + engine init (Retry UI on failure)
///  - _sendMessage(): send user message + stream AI response
///  - _buildInitErrorScreen(): Retry / Re-download screen on engine init failure
///  - _buildMessageBubble(): render AI/user message bubble
///  - _buildStreamingBubble(): bubble for AI response while streaming

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../app/providers.dart';
import '../../../shared/constants/colors.dart';
import '../../../core/storage/database.dart';
import '../providers/ai_provider.dart';

const _uuid = Uuid();

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  String _streamingText = '';
  bool _isStreaming = false;
  bool _ready = false;
  bool _initFailed = false;
  String? _initError;
  Map<String, dynamic>? _pendingConfirmation;

  @override
  void initState() {
    super.initState();
    _initializeAI();
  }

  Future<void> _initializeAI() async {
    if (mounted) {
      setState(() {
        _initFailed = false;
        _initError = null;
      });
    }

    final modelManager = ref.read(aiModelManagerProvider);

    // Missing model file is the only legitimate case for bouncing to onboarding —
    // it actually needs to be downloaded. Other cases (init failure etc.) must NOT
    // bounce to onboarding: pressing Download on the onboarding screen deletes the
    // existing file, but init failure is usually a runtime issue (memory pressure,
    // engine state, etc.) rather than a file problem, so retry/restart can fix it.
    bool installed;
    try {
      installed = await modelManager.isModelInstalled();
      debugPrint('[AiChat] isModelInstalled=$installed');
    } catch (e) {
      debugPrint('[AiChat] isModelInstalled error: $e');
      if (mounted) {
        setState(() {
          _initFailed = true;
          _initError = 'Failed to check model status: $e';
        });
      }
      return;
    }

    if (!installed) {
      if (mounted) context.pushReplacement('/ai-onboarding');
      return;
    }

    final aiService = ref.read(onDeviceAIProvider);
    if (!aiService.isInitialized) {
      try {
        final modelPath = await modelManager.modelPath;
        debugPrint('[AiChat] Initializing AI with path: $modelPath');
        await aiService.initialize(modelPath: modelPath);
        debugPrint('[AiChat] AI initialized successfully');
      } catch (e) {
        debugPrint('[AiChat] AI initialize FAILED: $e');
        if (mounted) {
          setState(() {
            _initFailed = true;
            _initError = e.toString();
          });
        }
        return;
      }
    }

    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();

    final aiService = ref.read(onDeviceAIProvider);
    if (!aiService.isInitialized || aiService.isBusy) return;

    final dao = ref.read(aiMessageDaoProvider);

    // Persist user message
    await dao.insertMessage(AiMessagesCompanion(
      id: Value(_uuid.v4()),
      role: const Value('user'),
      content: Value(text),
      createdAt: Value(DateTime.now()),
    ));

    _scrollToBottom();

    setState(() {
      _isStreaming = true;
      _streamingText = '';
    });

    try {
      final response = await aiService.sendMessage(
        text,
        onToken: (accumulated) {
          if (mounted) {
            setState(() => _streamingText = accumulated);
            _scrollToBottom();
          }
        },
      );

      // Persist response (strip tags)
      final clean = response
          .replaceAll('<end_of_turn>', '')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
      if (clean.isNotEmpty) {
        await dao.insertMessage(AiMessagesCompanion(
          id: Value(_uuid.v4()),
          role: const Value('assistant'),
          content: Value(clean),
          createdAt: Value(DateTime.now()),
        ));
      }
    } catch (e) {
      debugPrint('[AiChat] processWithTools error: $e');
      if (mounted) {
        await dao.insertMessage(AiMessagesCompanion(
          id: Value(_uuid.v4()),
          role: const Value('assistant'),
          content: const Value('Sorry, I could not generate a response.'),
          createdAt: Value(DateTime.now()),
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStreaming = false;
          _streamingText = '';
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initFailed) {
      return _buildInitErrorScreen();
    }
    if (!_ready) {
      return const Scaffold(
        backgroundColor: SnowColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final dao = ref.read(aiMessageDaoProvider);

    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        backgroundColor: SnowColors.surface,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF00D2FF), size: 20),
            SizedBox(width: 8),
            Text('SnowChat AI',
                style: TextStyle(color: SnowColors.textPrimary, fontSize: 18)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: SnowColors.textSecondary),
            color: SnowColors.surfaceVariant,
            onSelected: (value) {
              if (value == 'clear') _confirmClearHistory();
              if (value == 'reset') _resetSession();
              if (value == 'download') _redownloadModel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('New Session', style: TextStyle(color: SnowColors.textPrimary))),
              PopupMenuItem(value: 'download', child: Text('Download Model', style: TextStyle(color: SnowColors.textPrimary))),
              PopupMenuItem(value: 'clear', child: Text('Clear History', style: TextStyle(color: SnowColors.error))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<AiMessage>>(
              stream: dao.watchMessages(),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];

                if (messages.isEmpty && !_isStreaming) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: messages.length + (_isStreaming ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < messages.length) {
                      return _buildMessageBubble(messages[index]);
                    }
                    return _buildStreamingBubble();
                  },
                );
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: const Text(
              'All AI processing happens on this device only',
              style: TextStyle(fontSize: 11, color: SnowColors.textTertiary),
            ),
          ),

          _buildInputBar(),
        ],
      ),
    );
  }

  /// State where the model is on disk but initialization (llama.cpp / LiteRT-LM) failed.
  /// Mostly memory pressure / engine state issues — typically resolvable by retrying.
  /// Bouncing to onboarding and showing "Download" would delete the existing file, so
  /// this screen lets the user choose Retry or explicit Re-download instead.
  Widget _buildInitErrorScreen() {
    return Scaffold(
      backgroundColor: SnowColors.background,
      appBar: AppBar(
        backgroundColor: SnowColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: SnowColors.textSecondary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'SnowChat AI',
          style: TextStyle(color: SnowColors.textPrimary, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: SnowColors.error, size: 48),
              const SizedBox(height: 16),
              const Text(
                'AI failed to start',
                style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The model is on your device but the AI engine could not initialize. '
                'This is usually temporary — try again, or restart the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SnowColors.textSecondary, fontSize: 14, height: 1.4),
              ),
              if (_initError != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SnowColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _initError!,
                    style: const TextStyle(
                      color: SnowColors.textTertiary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _initializeAI,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Retry',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _redownloadModel,
                child: const Text(
                  'Re-download model',
                  style: TextStyle(color: SnowColors.textTertiary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome, color: Color(0xFF00D2FF), size: 48),
          SizedBox(height: 16),
          Text('SnowChat AI',
              style: TextStyle(
                  color: SnowColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Ask me anything',
              style: TextStyle(color: SnowColors.textSecondary, fontSize: 14)),
          SizedBox(height: 4),
          Text('All conversations stay on your device',
              style: TextStyle(color: SnowColors.textTertiary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(AiMessage message) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? SnowColors.primary : SnowColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.content,
          style: TextStyle(
            color: isUser ? Colors.black : SnowColors.textPrimary,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildStreamingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: SnowColors.surfaceLight,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _streamingText.isEmpty ? '...' : _streamingText,
          style: const TextStyle(color: SnowColors.textPrimary, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final aiService = ref.watch(onDeviceAIProvider);

    return Container(
      color: SnowColors.surface,
      padding: EdgeInsets.only(
        left: 16, right: 8, top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: const TextStyle(color: SnowColors.textPrimary),
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: aiService.isChatBusy ? 'AI responding...' : 'Message...',
                hintStyle: const TextStyle(color: SnowColors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: SnowColors.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isStreaming ? null : _sendMessage,
            icon: Icon(
              _isStreaming ? Icons.hourglass_top : Icons.send,
              color: _isStreaming ? SnowColors.textTertiary : SnowColors.primary,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _redownloadModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SnowColors.surfaceVariant,
        title: const Text('Re-download AI Model', style: TextStyle(color: SnowColors.textPrimary)),
        content: const Text(
          'Delete current model and download the latest version?\nThis may take several minutes on WiFi.',
          style: TextStyle(color: SnowColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: SnowColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download', style: TextStyle(color: Color(0xFF00D2FF))),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final manager = ref.read(aiModelManagerProvider);
      await ref.read(onDeviceAIProvider).dispose();
      await manager.deleteModel();
      manager.startManualDownload();
      if (mounted) context.pushReplacement('/ai-onboarding');
    }
  }

  Future<void> _resetSession() async {
    await ref.read(onDeviceAIProvider).resetChat();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New AI session started')),
      );
    }
  }

  Future<void> _confirmClearHistory() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SnowColors.surfaceVariant,
        title: const Text('Clear AI History', style: TextStyle(color: SnowColors.textPrimary)),
        content: const Text('All AI conversations will be deleted.\nThis cannot be undone.',
            style: TextStyle(color: SnowColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: SnowColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: SnowColors.error)),
          ),
        ],
      ),
    );
    if (result == true) {
      await ref.read(aiMessageDaoProvider).clearAll();
      await ref.read(onDeviceAIProvider).resetChat();
    }
  }
}
