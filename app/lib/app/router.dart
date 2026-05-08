/// @file        router.dart
/// @description App routing config based on GoRouter. Defines onboarding, tab navigation, and full-screen routes (device management, message search, group info, group member add, friends list, marketplace)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-05-06 (option 2 Signal pattern: wrapped /call in a
///              PopScope that blocks back navigation during an active call
///              regardless of host Activity. Native CallActivity already
///              swallows back-press while the keyguard is locked; this is
///              the framework-level second line of defense for the
///              MainActivity-hosted path (call accepted while unlocked).
///              Earlier 2026-05-03 (v211): revert v210 _CallRouteHost iOS
///              guard — auto-push gate moved to app.dart, router renders
///              whatever app.dart pushed.)
///
/// @functions
///  - routerProvider: Riverpod provider for the GoRouter instance
///  - _MainShell: ShellRoute widget containing the bottom tab navigation bar

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_config.dart';
import '../shared/constants/colors.dart';
import '../features/onboarding/screens/welcome_screen.dart';
import '../features/onboarding/screens/create_identity_screen.dart';
import '../features/onboarding/screens/backup_phrase_screen.dart';
import '../features/onboarding/screens/verify_phrase_screen.dart';
import '../features/onboarding/screens/restore_screen.dart';
import '../features/onboarding/screens/setup_profile_screen.dart';
import '../features/onboarding/screens/pin_login_screen.dart';
import '../features/chat/screens/conversation_list_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/chat/screens/message_search_screen.dart';
import '../features/chat/screens/new_chat_screen.dart';
import '../features/chat/screens/create_group_screen.dart';
import '../features/group/screens/group_info_screen.dart';
import '../features/group/screens/add_group_members_screen.dart';
import '../features/contacts/screens/contact_list_screen.dart';
import '../features/channels/screens/channel_list_screen.dart';
import '../features/channels/screens/friend_list_screen.dart';
import '../features/channels/screens/add_channel_screen.dart';
import '../features/channels/screens/add_friend_screen.dart';
import '../features/channels/screens/create_channel_screen.dart';
import '../features/channels/screens/channel_info_screen.dart';
import '../features/channels/screens/invite_link_screen.dart';
import '../features/channels/screens/invite_preview_screen.dart';
import '../features/channels/screens/join_with_code_screen.dart';
import '../features/channels/screens/channel_admin_screen.dart';
import '../features/contacts/screens/add_contact_screen.dart';
import '../features/contacts/screens/blocked_contacts_screen.dart';
import '../features/contacts/screens/my_qr_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/device_management_screen.dart';
import '../features/settings/screens/network_settings_screen.dart';
import '../features/settings/screens/hidden_wallets_screen.dart';
import '../features/settings/screens/backup_screen.dart';
import '../features/wallet/screens/wallet_home_screen.dart';
import '../features/wallet/screens/send_screen.dart';
import '../features/wallet/screens/receive_screen.dart';
import '../features/wallet/screens/token_detail_screen.dart';
import '../features/wallet/screens/tx_detail_screen.dart';
import '../features/wallet/screens/tx_history_screen.dart';
import '../features/nft/screens/nft_gallery_screen.dart';
import '../features/nft/screens/nft_detail_screen.dart';
import '../features/nft/screens/nft_send_screen.dart';
import '../features/marketplace/screens/marketplace_screen.dart'
    as mp;
import '../features/marketplace/screens/create_listing_screen.dart';
import '../features/ai/screens/ai_chat_screen.dart';
import '../features/ai/screens/ai_onboarding_screen.dart';
import '../features/call/screens/outgoing_call_screen.dart';
import '../features/call/screens/incoming_call_screen.dart';
import '../features/call/screens/active_call_screen.dart';
import '../features/security/screens/verify_identity_screen.dart';
import '../shared/models/wallet_models.dart';
import '../shared/models/nft_models.dart';
import 'providers.dart';

/// Public so app.dart's securityAlert and other global dialog sites can use it.
final rootNavigatorKey = GlobalKey<NavigatorState>();
final _rootNavigatorKey = rootNavigatorKey;
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Deeplink rewriter — used by both the GoRouter `redirect` and `errorBuilder`
/// fallback. Returns the rewritten internal path, or null if [loc] is not a
/// known SnowChat deeplink form. Centralised so the two intercept points stay
/// in sync.
String? _rewriteDeeplink(String loc) {
  const customPrefix = 'snowchat://invite/';
  const httpsPrefix = 'https://snowchat.calidalab.ai/invite/';
  if (loc.startsWith(customPrefix)) {
    final code = loc.substring(customPrefix.length);
    return code.isEmpty ? null : '/invite/$code';
  }
  if (loc.startsWith(httpsPrefix)) {
    final code = loc.substring(httpsPrefix.length);
    return code.isEmpty ? null : '/invite/$code';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final isOnboarded = ref.watch(isOnboardedProvider);
  final requiresPinSetup = ref.watch(requiresPinSetupProvider);
  final isLocked = ref.watch(isLockedProvider);

  final String initialLocation;
  if (!isOnboarded) {
    initialLocation = '/welcome';
  } else if (requiresPinSetup) {
    // Phase 8.7 round 5: identity exists but no PIN — restore flow skipped
    // setup-profile because the user already existed on the server. Force
    // setup-profile in restore mode so the user enters a PIN before any
    // chat content is reachable.
    initialLocation = '/setup-profile?restore=true';
  } else if (isLocked) {
    initialLocation = '/pin-login';
  } else {
    initialLocation = '/chat';
  }

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: initialLocation,
    // Last-line-of-defense for deeplinks the redirect somehow misses
    // (some GoRouter versions evaluate the URI before redirect for path-only
    // matches). Show a transparent loading frame while we push the corrected
    // location, instead of rendering the raw "no routes" exception.
    errorBuilder: (context, state) {
      final rewritten = _rewriteDeeplink(state.matchedLocation) ??
          _rewriteDeeplink(state.uri.toString());
      if (rewritten != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          rootNavigatorKey.currentState?.context.go(rewritten);
        });
        return const Scaffold(
          backgroundColor: SnowColors.background,
          body: Center(
            child: CircularProgressIndicator(color: SnowColors.primary),
          ),
        );
      }
      return Scaffold(
        backgroundColor: SnowColors.background,
        appBar: AppBar(title: const Text('Not found')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('No route for: ${state.matchedLocation}',
                  style: const TextStyle(color: SnowColors.textTertiary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => rootNavigatorKey.currentState?.context.go('/chat'),
                child: const Text('Home'),
              ),
            ],
          ),
        ),
      );
    },
    // Cold-start deeplink redirect — Flutter PlatformRouteInformationProvider
    // delivers the launch URL (e.g. snowchat://invite/<code>) directly to
    // GoRouter as initialLocation. GoRouter cannot match a full custom-scheme
    // URI against path-style routes ("/invite/:code") and surfaces
    // "GoException: no routes for location: snowchat://invite/<code>".
    // Rewrite known custom-scheme URIs to their internal path form so the
    // user never sees the error page, even before DeeplinkHandler.start
    // wires up. Universal Link (Phase 2 https://snowchat.calidalab.ai/...)
    // is also handled here for consistency.
    //
    // NOTE — state.matchedLocation 에 cold-start URI 가 안 들어올 수 있어서
    // (GoRouter 가 Uri 파싱 후 path 만 사용하는 경우) state.uri 도 같이 검사.
    redirect: (context, state) {
      final rewritten = _rewriteDeeplink(state.matchedLocation) ??
          _rewriteDeeplink(state.uri.toString());
      return rewritten;
    },
    routes: [
      // --- Onboarding ---
      GoRoute(
        path: '/welcome',
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/setup-profile',
        builder: (_, state) => SetupProfileScreen(
          isRestore: state.extra == true ||
              state.uri.queryParameters['restore'] == 'true',
        ),
      ),
      GoRoute(
        path: '/pin-login',
        builder: (_, __) => const PinLoginScreen(),
      ),
      GoRoute(
        path: '/create-identity',
        builder: (_, __) => const CreateIdentityScreen(),
      ),
      GoRoute(
        path: '/backup-phrase',
        builder: (_, __) => const BackupPhraseScreen(),
      ),
      GoRoute(
        path: '/verify-phrase',
        builder: (_, __) => const VerifyPhraseScreen(),
      ),
      GoRoute(
        path: '/restore',
        builder: (_, __) => const RestoreScreen(),
      ),

      // --- Phase 8.2 VoIP: single /call route, branches screens by call state ---
      GoRoute(
        path: '/call',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const _CallRouteHost(),
      ),

      // --- Main Shell (Tab Navigation) ---
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (_, state, child) => _MainShell(child: child),
        routes: [
          GoRoute(
            path: '/chat',
            pageBuilder: (_, __) => const NoTransitionPage(
              child: ConversationListScreen(),
            ),
            routes: [
              GoRoute(
                path: ':conversationId',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (_, state) => ChatScreen(
                  conversationId:
                      state.pathParameters['conversationId'] ?? '',
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/friends',
            pageBuilder: (_, __) => const NoTransitionPage(
              child: FriendListScreen(),
            ),
          ),
          GoRoute(
            path: '/contacts',
            pageBuilder: (_, __) => const NoTransitionPage(
              child: ChannelListScreen(),
            ),
          ),
          if (AppConfig.enableWallet)
            GoRoute(
              path: '/wallet',
              pageBuilder: (_, __) => const NoTransitionPage(
                child: WalletHomeScreen(),
              ),
            ),
          GoRoute(
            path: '/settings',
            pageBuilder: (_, __) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),

      // --- Full-screen routes ---
      GoRoute(
        path: '/message-search',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const MessageSearchScreen(),
      ),
      GoRoute(
        path: '/new-chat',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const NewChatScreen(),
      ),
      GoRoute(
        path: '/create-group',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const CreateGroupScreen(),
      ),
      GoRoute(
        path: '/add-channel',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AddChannelScreen(),
      ),
      GoRoute(
        path: '/add-friend',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AddFriendScreen(),
      ),
      GoRoute(
        path: '/create-channel',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const CreateChannelScreen(),
      ),
      GoRoute(
        path: '/channel-info/:groupId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => ChannelInfoScreen(
          groupId: state.pathParameters['groupId']!,
        ),
      ),
      GoRoute(
        path: '/channel-admin/:channelId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => ChannelAdminScreen(
          channelId: state.pathParameters['channelId']!,
          channelName: state.uri.queryParameters['name'] ?? 'Channel',
        ),
      ),
      GoRoute(
        path: '/invite/:code',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => InvitePreviewScreen(
          code: state.pathParameters['code']!,
        ),
      ),
      GoRoute(
        path: '/join-with-code',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const JoinWithCodeScreen(),
      ),
      GoRoute(
        path: '/invite-link/:groupId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => InviteLinkScreen(
          groupId: state.pathParameters['groupId']!,
          channelName: state.uri.queryParameters['name'] ?? 'Channel',
        ),
      ),
      GoRoute(
        path: '/group-info/:groupId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => GroupInfoScreen(
          groupId: state.pathParameters['groupId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/add-group-members/:groupId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => AddGroupMembersScreen(
          groupId: state.pathParameters['groupId'] ?? '',
          existingMemberSnowchatIds:
              (state.extra as List<String>?) ?? [],
        ),
      ),
      GoRoute(
        path: '/add-contact',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AddContactScreen(),
      ),
      GoRoute(
        path: '/my-qr',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const MyQrScreen(),
      ),
      GoRoute(
        path: '/backup',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const BackupScreen(),
      ),
      GoRoute(
        path: '/settings/devices',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const DeviceManagementScreen(),
      ),
      GoRoute(
        path: '/settings/network',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const NetworkSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/hidden-wallets',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const HiddenWalletsScreen(),
      ),
      GoRoute(
        path: '/settings/blocked-contacts',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const BlockedContactsScreen(),
      ),

      // --- Wallet full-screen routes (ENABLE_WALLET flag) ---
      if (AppConfig.enableWallet) GoRoute(
        path: '/wallet/send',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) {
          final extra = state.extra;
          // Send Again passes a Map to prefill the address; the original path passes TokenInfo for token selection
          if (extra is Map) {
            return SendScreen(
              initialAddress: extra['address'] as String?,
            );
          }
          return SendScreen(
            preselectedToken: extra as TokenInfo?,
          );
        },
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/wallet/receive',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ReceiveScreen(),
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/wallet/token',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => TokenDetailScreen(
          token: state.extra as TokenInfo,
        ),
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/wallet/history',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const TxHistoryScreen(),
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/wallet/tx-detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) =>
            TxDetailScreen(signature: state.extra as String),
      ),

      // --- NFT full-screen routes (ENABLE_WALLET flag) ---
      if (AppConfig.enableWallet) GoRoute(
        path: '/nft/gallery',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const NFTGalleryScreen(),
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/nft/detail',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => NFTDetailScreen(
          nft: state.extra as NFTAsset,
        ),
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/nft/send',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => NFTSendScreen(
          nft: state.extra as NFTAsset,
        ),
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/marketplace',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const mp.MarketplaceScreen(),
      ),
      if (AppConfig.enableWallet) GoRoute(
        path: '/marketplace/create',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const CreateListingScreen(),
      ),
      // Phase 10: AI
      GoRoute(
        path: '/ai-chat',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AiChatScreen(),
      ),
      GoRoute(
        path: '/ai-onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AiOnboardingScreen(),
      ),

      // P0-2: Safety Number verification screen (1:1 only).
      // peerSnowId in the path; peerDisplayName from query string so a
      // shared link / future deep-link without UI context still works.
      GoRoute(
        path: '/safety/:peerSnowId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => VerifyIdentityScreen(
          peerSnowchatId: state.pathParameters['peerSnowId'] ?? '',
          peerDisplayName:
              state.uri.queryParameters['name'] ?? 'Contact',
        ),
      ),

    ],
  );
});

class _MainShell extends ConsumerStatefulWidget {
  final Widget child;
  const _MainShell({required this.child});

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  int _currentIndex = 0;

  static final _tabs = [
    '/chat',
    '/friends',
    '/contacts',
    if (AppConfig.enableWallet) '/wallet',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    final friendBadge = ref.watch(pendingFriendBadgeProvider);

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: SnowColors.divider, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: _currentIndex,
          onTap: (index) {
            if (index != _currentIndex) {
              // Clear friend badge when entering Friends tab
              if (index == 1) {
                ref.read(pendingFriendBadgeProvider.notifier).state = 0;
              }
              setState(() => _currentIndex = index);
              context.go(_tabs[index]);
            }
          },
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: friendBadge > 0
                  ? const Badge(
                      smallSize: 8,
                      child: Icon(Icons.people_rounded),
                    )
                  : const Icon(Icons.people_rounded),
              activeIcon: const Icon(Icons.people_rounded),
              label: 'Friends',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.forum_rounded),
              activeIcon: Icon(Icons.forum_rounded),
              label: 'Channels',
            ),
            if (AppConfig.enableWallet)
              const BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_rounded),
                activeIcon: Icon(Icons.account_balance_wallet_rounded),
                label: 'Wallet',
              ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

/// Phase 8.2 VoIP: host widget for the `/call` route.
///
/// Branches between 3 screens based on CallNotifier's status.
/// Auto-pops back when status returns to idle/ended.
class _CallRouteHost extends ConsumerWidget {
  const _CallRouteHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(callProvider).status;
    debugPrint('[DIAG:CallRouteHost] BUILD status=$status');

    // Auto-dismiss when call truly ends
    ref.listen<CallState>(callProvider, (prev, next) {
      if (next.status == CallStatus.idle && (prev?.status != CallStatus.idle)) {
        if (context.canPop()) context.pop();
      }
    });

    // Option 2 (Signal pattern, 2026-05-06): block back navigation while
    // the call is in any non-idle state. CallActivity (Android) already
    // swallows back-press when the keyguard is locked; this PopScope is
    // the framework-level guard that also covers MainActivity-hosted
    // paths (call accepted while the device is already unlocked) and iOS
    // (where the gesture-pop would otherwise leak the user out of /call
    // into chat / wallet routes underneath). The auto-pop on idle above
    // remains the only legitimate exit, fired when CallNotifier ends.
    final canExit = status == CallStatus.idle;
    return PopScope(
      canPop: canExit,
      child: _buildCallScreen(context, status),
    );
  }

  Widget _buildCallScreen(BuildContext context, CallStatus status) {
    switch (status) {
      case CallStatus.outgoing:
        return const OutgoingCallScreen();
      case CallStatus.incoming:
        // v211 (2026-05-03): platform分岐 없음. /call route 진입 자체가
        // app.dart 의 lifecycle/platform aware 가드로 제어됨 — iOS FG 만
        // 여기 도달 가능 (BG/Lock 은 PushKit native CallKit 가 owns,
        // Android 는 ConnectionService 가 owns).
        return const IncomingCallScreen();
      case CallStatus.connecting:
      case CallStatus.active:
      case CallStatus.ended:
        return const ActiveCallScreen();
      case CallStatus.idle:
        // 2026-05-04 fix v2: BG/lock 에서 전화받고 진입 시 black 회귀.
        // 이전 fix (app.dart 의 global ref.listen) 는 prev != idle &&
        // next == idle 의 *전이* 만 cover — BG 에서 isolate frozen 중에
        // 상태가 이미 idle 로 끝난 케이스나 cold-launch from PushKit 에서
        // recovery 가 fail 한 경우에는 transition 이 발생 안 해서 listener
        // 가 fire 안 됨. router build 가 직접 호출하는 idle 케이스에서
        // 매번 pop 스케줄 해서 어떤 path 든 cover.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted && context.canPop()) {
            context.pop();
          }
        });
        // pop 이 다음 frame 에서 fire — 그 동안은 underlying route 가 보여야
        // 한다. Scaffold 의 default opaque background 대신 SizedBox.shrink()
        // 만 return 해서 black 깜빡임 최소화.
        return const SizedBox.shrink();
    }
  }
}
