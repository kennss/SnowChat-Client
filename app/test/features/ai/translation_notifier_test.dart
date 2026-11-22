/// @file        translation_notifier_test.dart
/// @description TranslationNotifier queue semantics: one translation in flight
///              at a time, a result for a superseded target is dropped, and a
///              message that produced no translation is not retried.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-11
/// @lastUpdated 2026-11-11
///
/// @functions
///  - main(): sequential processing, stale-target drop, settled no-retry,
///    recentIncomingForTranslation selection
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/ai/providers/translation_provider.dart';
import 'package:snowchat/features/ai/service/translation_service.dart';
import 'package:snowchat/features/chat/models/message.dart';

/// Records calls and lets each test complete them by hand.
class _FakeTranslationService extends TranslationService {
  final List<Completer<String>> pending = [];
  int calls = 0;
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<String> translate(String text, String preferredLanguage) {
    calls++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final c = Completer<String>();
    pending.add(c);
    return c.future.whenComplete(() => inFlight--);
  }

  @override
  void dispose() {}
}

const _fr1 = 'Bonjour mes amis, comment allez-vous ce matin';
const _fr2 = 'Merci beaucoup pour votre aide hier soir';
const _fr3 = 'Nous partons demain matin pour la montagne';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('only one translation is in flight at a time', () async {
    final svc = _FakeTranslationService();
    final n = TranslationNotifier(svc, 'Korean');
    n.translate('m1', _fr1);
    n.translate('m2', _fr2);
    n.translate('m3', _fr3);
    await _settle();
    expect(svc.calls, 1);

    for (var i = 0; i < 3; i++) {
      svc.pending[i].complete('번역 $i');
      await _settle();
    }
    expect(svc.calls, 3);
    expect(svc.maxInFlight, 1);
    expect(n.debugState.keys, containsAll(['m1', 'm2', 'm3']));
    expect(n.debugState['m3']!.translatedText, '번역 2');
    n.dispose();
  });

  test('a result for a superseded target is dropped', () async {
    final svc = _FakeTranslationService();
    final n = TranslationNotifier(svc, 'Korean');
    n.translate('m1', _fr1);
    await _settle();
    expect(n.debugState['m1']!.isLoading, isTrue);

    n.updateTarget('Japanese');
    svc.pending.single.complete('안녕하세요');
    await _settle();
    expect(n.debugState.containsKey('m1'), isFalse,
        reason: 'a Korean result must not be stored after switching to Japanese');

    // The same message can be translated again for the new target.
    n.translate('m1', _fr1);
    await _settle();
    expect(svc.calls, 2);
    n.dispose();
  });

  test('a message that produced no translation is not retried', () async {
    final svc = _FakeTranslationService();
    final n = TranslationNotifier(svc, 'Korean');
    n.translate('m1', _fr1);
    await _settle();
    svc.pending.single.complete('');
    await _settle();
    expect(n.debugState.containsKey('m1'), isFalse);

    n.translate('m1', _fr1);
    await _settle();
    expect(svc.calls, 1);

    // A target change clears the settled set — the new target may translate it.
    n.updateTarget('Japanese');
    n.translate('m1', _fr1);
    await _settle();
    expect(svc.calls, 2);
    n.dispose();
  });

  test('recentIncomingForTranslation picks the last 10 incoming text messages', () {
    Message msg(int i, {String sender = 'peer', MessageType type = MessageType.text, String text = 'texte'}) =>
        Message(
          id: 'm$i',
          conversationId: 'c',
          senderSnowchatId: sender,
          plaintext: text,
          timestamp: DateTime.fromMillisecondsSinceEpoch(i * 1000),
          type: type,
        );
    final messages = [
      for (var i = 0; i < 12; i++) msg(i),
      msg(12, sender: 'me'),
      msg(13, type: MessageType.file),
      msg(14, text: ''),
    ];
    final picked = recentIncomingForTranslation(messages, 'me');
    expect(picked.map((m) => m.id), [for (var i = 2; i < 12; i++) 'm$i']);
  });
}
