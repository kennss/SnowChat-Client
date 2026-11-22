/// @file        notification_tap_test.dart
/// @description Where a tapped local notification goes (design 2026-11-22-friend-graph-off-server
///              §5.2): a friend notification (payload NotificationService.friendsPayload) opens the
///              Friends tab through onRouteTap('/friends') — never a chat; any other payload is a
///              conversation for onNotificationTap; an empty payload goes nowhere.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases above
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/notifications/notification_service.dart';

void main() {
  late List<String> routes;
  late List<String> chats;
  final service = NotificationService();

  setUp(() {
    routes = [];
    chats = [];
    service.onRouteTap = routes.add;
    service.onNotificationTap = chats.add;
  });

  tearDown(() {
    service.onRouteTap = null;
    service.onNotificationTap = null;
  });

  test('a friend notification opens the Friends tab, not a chat', () {
    service.handleTapPayload(NotificationService.friendsPayload);
    expect(routes, ['/friends']);
    expect(chats, isEmpty);
  });

  test('a group invite notification opens the chat list, where invites wait', () {
    service.handleTapPayload(NotificationService.chatListPayload);
    expect(routes, ['/chat']);
    expect(chats, isEmpty);
  });

  test('a message notification opens its conversation', () {
    const peer = 'snow0123456789abcdef0123456789abcdef';
    service.handleTapPayload(peer);
    expect(chats, [peer]);
    expect(routes, isEmpty);
  });

  test('an empty payload goes nowhere', () {
    service.handleTapPayload(null);
    service.handleTapPayload('');
    expect(routes, isEmpty);
    expect(chats, isEmpty);
  });
}
