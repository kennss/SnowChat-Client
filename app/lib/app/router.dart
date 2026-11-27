/// @file        router.dart
/// @description App routing config based on GoRouter. Defines onboarding, tab navigation, and full-screen routes (device management, message search, group info, group member add, friends list)
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-03-29
/// @lastUpdated 2026-11-27 (wallet removed: no Wallet tab, no /wallet, /nft, /settings/network or
///              /settings/hidden-wallets routes, no AppConfig). Earlier 2026-11-22 (the restore notice of a backup that did not open offers "Try again"
///              — ContactBackup.retryRestore — and, put off, comes back at the next start). Earlier 2026-11-22 (the selected tab follows the location — a go('/friends') from a friend
///              notification, or any other go to a tab, lights the right tab (it was a field set only
///              by taps); the Friends tab badge shows the number of received requests; the main shell
///              shows the contact restore notice once — showContactRestoreNotice). Earlier 2026-11-22
///              (friend graph off the server: the Friends tab badge is the count of
///              received requests on this device (it stays while they wait — no reset on tab
///              entry); /add-contact and the unused ContactListScreen import are gone). Earlier 2026-11-22 (the /call route takes its screen from callScreenFor(), shared with the app lock — SC-19; /settings/passcode — ChangePasscodeScreen). Earlier 2026-11-22 (every route change drops the keyboard focus — DismissKeyboardOnRouteChange
///              on the root GoRouter and the ShellRoute). Earlier 2026-11-21 (_CallRouteHost closes the in-app incoming screen when a late CallKit
///              window takes the call over). Earlier 2026-11-21 (/add-group-members takes the places taken with the existing accounts). Earlier 2026-11-21 (/create-group?community=&name=: a new group from a community roster). Earlier 2026-11-20 (v1 groups removed: /contacts?expand=<channelId> opens the Communities tab with that community expanded; the community routes name their parameter channelId; /group-info is always Gv2GroupInfoScreen — an id that is not a group on this device reads as such there). Earlier 2026-11-20 (/pin-reset: PinResetScreen for a forgotten PIN). Earlier 2026-11-20 (/group-info shows Gv2GroupInfoScreen for a group protocol v2 group id). Earlier 2026-11-12 (removed the /marketplace and /marketplace/create routes with the NFT marketplace feature). Earlier 2026-11-10 (B-2: first-contact deeplinks forward the inviter account key ?k= to AddFriendScreen via addFriendDeeplinkPath()). Earlier 2026-11-08 (ENABLE_WALLET=false hardening: /settings/network and /settings/hidden-wallets are now behind AppConfig.enableWallet like the other wallet routes). Earlier 2026-08-05 (bottom-nav "Channels"→"Communities"; Channel→Community route display fallbacks). Earlier 2026-05-06 (option 2 Signal pattern: wrapped /call in a
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
///  - _MainShell: ShellRoute widget containing the bottom tab navigation bar (the selected tab
///    follows the location; the Friends badge counts received requests; shows the contact
///    restore notice once)

import 'keyboard_behavior.dart';
import '../features/settings/screens/change_passcode_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/constants/colors.dart';
import '../features/onboarding/screens/welcome_screen.dart';
import '../features/onboarding/screens/create_identity_screen.dart';
import '../features/onboarding/screens/backup_phrase_screen.dart';
import '../features/onboarding/screens/verify_phrase_screen.dart';
import '../features/onboarding/screens/restore_screen.dart';
import '../features/onboarding/screens/setup_profile_screen.dart';
import '../features/onboarding/screens/pin_login_screen.dart';
import '../features/onboarding/screens/pin_reset_screen.dart';
import '../features/chat/screens/conversation_list_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/chat/screens/message_search_screen.dart';
import '../features/chat/screens/new_chat_screen.dart';
import '../features/chat/screens/create_group_screen.dart';
import '../features/group/screens/gv2_group_info_screen.dart';
import '../features/group/screens/add_group_members_screen.dart';
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
import '../features/contacts/screens/blocked_contacts_screen.dart';
import '../features/contacts/screens/my_qr_screen.dart';
import '../features/contacts/widgets/contact_restore_notice.dart';
import '../core/contacts/contact_backup.dart' show ContactRestoreReport;
import 'deeplink_handler.dart' show addFriendDeeplinkPath;
import '../features/settings/screens/settings_screen.dart';
import '../features/settings/screens/device_management_screen.dart';
import '../features/settings/screens/profile_edit_screen.dart';
import '../features/settings/screens/backup_screen.dart';
import '../features/ai/screens/ai_chat_screen.dart';
import '../features/ai/screens/ai_onboarding_screen.dart';
import '../features/call/screens/call_screen_for.dart';
import '../features/security/screens/verify_identity_screen.dart';
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
  // Community invite forms → /invite/<code>.
  const inviteCustom = 'snowchat://invite/';
  const inviteHttps = 'https://snowchat.calidalab.ai/invite/';
  if (loc.startsWith(inviteCustom)) {
    final code = loc.substring(inviteCustom.length);
    return code.isEmpty ? null : '/invite/$code';
  }
  if (loc.startsWith(inviteHttps)) {
    final code = loc.substring(inviteHttps.length);
    return code.isEmpty ? null : '/invite/$code';
  }
  // Friend first-contact forms → /add-friend?id=<id> (A shares their own id).
  const userCustom = 'snowchat://user/';
  const userHttps = 'https://snowchat.calidalab.ai/u/';
  // B-2: the link may carry the inviter's account key as `?k=<64 hex>`.
  for (final prefix in const [userCustom, userHttps]) {
    if (!loc.startsWith(prefix)) continue;
    final id = loc.substring(prefix.length).split(RegExp(r'[/?#]')).first;
    if (id.isEmpty) return null;
    final k = Uri.tryParse(loc)?.queryParameters['k'];
    return addFriendDeeplinkPath(id, k);
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
    // A keyboard opened on one screen never stays over the next one.
    observers: [DismissKeyboardOnRouteChange()],
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
        path: '/pin-reset',
        builder: (_, __) => const PinResetScreen(),
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
        // Tab changes too (a NavigatorObserver serves one navigator).
        observers: [DismissKeyboardOnRouteChange()],
        navigatorKey: _shellNavigatorKey,
        builder: (_, state, child) =>
            _MainShell(location: state.uri.path, child: child),
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
            pageBuilder: (_, state) => NoTransitionPage(
              child: ChannelListScreen(
                expandChannelId: state.uri.queryParameters['expand'],
              ),
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
        // ?community=<id>&name=<name>: pick from that community's roster.
        builder: (_, state) => CreateGroupScreen(
          communityId: state.uri.queryParameters['community'],
          communityName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/add-channel',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const AddChannelScreen(),
      ),
      GoRoute(
        path: '/add-friend',
        parentNavigatorKey: _rootNavigatorKey,
        // ?id=<snowchatId> arrives from a snowchat://user/<id> first-contact
        // deeplink (QR scan / shared link) — AddFriendScreen opens straight to
        // the SnowChat-ID confirm, pre-filled with that id.
        builder: (_, state) => AddFriendScreen(
          initialId: state.uri.queryParameters['id'],
          initialAccountKeyHex: state.uri.queryParameters['k'],
        ),
      ),
      GoRoute(
        path: '/create-channel',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const CreateChannelScreen(),
      ),
      GoRoute(
        path: '/channel-info/:channelId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => ChannelInfoScreen(
          channelId: state.pathParameters['channelId']!,
        ),
      ),
      GoRoute(
        path: '/channel-admin/:channelId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => ChannelAdminScreen(
          channelId: state.pathParameters['channelId']!,
          channelName: state.uri.queryParameters['name'] ?? 'Community',
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
        path: '/invite-link/:channelId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) => InviteLinkScreen(
          channelId: state.pathParameters['channelId']!,
          channelName: state.uri.queryParameters['name'] ?? 'Community',
        ),
      ),
      GoRoute(
        path: '/group-info/:groupId',
        parentNavigatorKey: _rootNavigatorKey,
        // What it shows and changes is the group's change log, as this
        // device holds it ("not on this device" for any other id).
        builder: (_, state) => Gv2GroupInfoScreen(
          groupId: state.pathParameters['groupId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/add-group-members/:groupId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, state) {
          // What the group info screen hands over. Opened otherwise, the
          // picker allows the whole size; the server's log decides in the
          // end (an invite past the limit is refused as `full`).
          final extra =
              state.extra as ({List<String> existing, int taken})?;
          return AddGroupMembersScreen(
            groupId: state.pathParameters['groupId'] ?? '',
            existingMemberSnowchatIds: extra?.existing ?? const [],
            placesTaken: extra?.taken ?? 0,
          );
        },
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
        path: '/settings/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/settings/devices',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const DeviceManagementScreen(),
      ),
      GoRoute(
        path: '/settings/passcode',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const ChangePasscodeScreen(),
      ),
      GoRoute(
        path: '/settings/blocked-contacts',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const BlockedContactsScreen(),
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

  /// The path the shell shows (the selected tab follows it).
  final String location;

  const _MainShell({required this.location, required this.child});

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell> {
  static final _tabs = [
    '/chat',
    '/friends',
    '/contacts',
    '/settings',
  ];

  /// The tab of [location] (its first path segment); the Chats tab for a
  /// path no tab owns.
  static int _tabOf(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (location == _tabs[i] || location.startsWith('${_tabs[i]}/')) return i;
    }
    return 0;
  }

  ProviderSubscription<AsyncValue<ContactRestoreReport?>>? _restoreNotice;
  bool _restoreNoticeShown = false;

  @override
  void initState() {
    super.initState();
    // The contact restore of a new install is told once (design §5.10) —
    // also when it finished before this shell was built.
    _restoreNotice = ref.listenManual<AsyncValue<ContactRestoreReport?>>(
      contactRestoreNoticeProvider,
      (_, next) {
        final report = next.valueOrNull;
        if (report != null) _showRestoreNotice(report);
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _restoreNotice?.close();
    super.dispose();
  }

  void _showRestoreNotice(ContactRestoreReport report) {
    if (_restoreNoticeShown) return;
    _restoreNoticeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final retry = await showContactRestoreNotice(context, report);
      final backup = ref.read(contactBackupProvider);
      if (retry) {
        // A backup that did not open: fetched again now; a new failure is
        // told again.
        await backup.retryRestore();
      } else if (report.unreadable) {
        // "Later": not shown again in this run, but at the next start —
        // until the backup opens.
        return;
      } else {
        await backup.dismissRestoreNotice();
      }
      _restoreNoticeShown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = _tabOf(widget.location);
    // Received friend requests waiting for an answer (this device's list).
    final friendBadge = ref.watch(pendingFriendBadgeProvider).valueOrNull ?? 0;

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
          currentIndex: currentIndex,
          onTap: (index) {
            if (index != currentIndex) context.go(_tabs[index]);
          },
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_rounded),
              activeIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                isLabelVisible: friendBadge > 0,
                label: Text(friendBadge > 99 ? '99+' : '$friendBadge'),
                child: const Icon(Icons.people_rounded),
              ),
              activeIcon: Badge(
                isLabelVisible: friendBadge > 0,
                label: Text(friendBadge > 99 ? '99+' : '$friendBadge'),
                child: const Icon(Icons.people_rounded),
              ),
              label: 'Friends',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.forum_rounded),
              activeIcon: Icon(Icons.forum_rounded),
              label: 'Communities',
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
        return;
      }
      // V3: a late CallKit window took over a call ringing on the in-app
      // screen — close the screen so only one incoming UI is up.
      if (next.status == CallStatus.incoming &&
          (prev?.inAppIncoming ?? false) &&
          !next.inAppIncoming) {
        if (context.canPop()) context.pop();
      }
    });

    // Option 2 (Signal pattern, 2026-05-06): block back navigation while
    // the call is in any non-idle state. CallActivity (Android) already
    // swallows back-press when the keyguard is locked; this PopScope is
    // the framework-level guard that also covers MainActivity-hosted
    // paths (call accepted while the device is already unlocked) and iOS
    // (where the gesture-pop would otherwise leak the user out of /call
    // into the chat routes underneath). The auto-pop on idle above
    // remains the only legitimate exit, fired when CallNotifier ends.
    final canExit = status == CallStatus.idle;
    return PopScope(
      canPop: canExit,
      child: _buildCallScreen(context, status),
    );
  }

  Widget _buildCallScreen(BuildContext context, CallStatus status) {
    // `incoming` reaches this route only when CallState.inAppIncoming is set
    // (app.dart pushes /call for nothing else); otherwise CallKit /
    // ConnectionService owns the incoming UI.
    final screen = callScreenFor(status);
    if (screen != null) return screen;
    // idle:
    // 2026-05-04 fix v2: answering from BG/lock and coming in regressed to
    // black. The earlier fix (the global ref.listen in app.dart) covers only
    // the prev != idle && next == idle *transition* — when the state had
    // already ended as idle while the isolate was frozen in BG, or recovery
    // failed on a cold launch from PushKit, there is no transition and the
    // listener never fires. Scheduling a pop every time the router build
    // itself hits idle covers every path.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && context.canPop()) {
        context.pop();
      }
    });
    // The pop fires on the next frame — until then the route underneath
    // must show. Returning a bare SizedBox.shrink() instead of a Scaffold's
    // default opaque background keeps the black flash minimal.
    return const SizedBox.shrink();
  }
}
