/// @file        pick_candidates_test.dart
/// @description The accounts a group picker offers: rosterCandidates() and
///              contactCandidates() leave out this account, blocked
///              accounts, the excluded ones, duplicates and what is not a
///              snowId, mark each known by the given check, and order known
///              first, then by name (unnamed last); a detail without a
///              member list is an error. PickSelection: at most max picked,
///              "select all" takes the known ones as far as they fit and
///              clears them when they are all taken (or the group is full).
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-21
/// @lastUpdated 2026-11-21 (from roster_candidates_test.dart: contactCandidates and PickSelection)
///
/// @functions
///  - main(): the cases above
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/features/contacts/contact_provider.dart';
import 'package:snowchat/features/group/providers/pick_candidates.dart';

String _snow(int i) => 'snow${i.toRadixString(16).padLeft(32, '0')}';

Map<String, Object?> _member(String snowId, Object? name) => {
      'userId': 'u-$snowId',
      'role': 'MEMBER',
      'user': {'snowchatId': snowId, 'displayName': name},
    };

PickCandidate _c(int i, {bool known = true}) =>
    PickCandidate(snowId: _snow(i), name: 'P$i', known: known);

void main() {
  test('roster: leaves out this account, blocked accounts, duplicates and '
      'what is not a snowId; marks known; known first, then by name, '
      'unnamed last', () async {
    final asked = <String>[];
    final out = await rosterCandidates(
      detail: {
        'members': [
          _member(_snow(1), 'Zoe'),
          _member(_snow(2), 'adam'),
          _member(_snow(3), null),
          _member(_snow(4), '   '),
          _member(_snow(5), 'Bea'),
          _member(_snow(6), 'Blocked'),
          _member(_snow(9), 'Me'),
          _member(_snow(2), 'adam again'),
          _member('snowNOTHEX', 'Bad'),
          _member('', 'Empty'),
          {'user': null},
          'junk',
        ],
      },
      mySnowId: _snow(9),
      blocked: {_snow(6)},
      isKnown: (id) async {
        asked.add(id);
        return id == _snow(1) || id == _snow(3);
      },
    );
    expect([for (final c in out) (c.snowId, c.name, c.known)], [
      (_snow(1), 'Zoe', true),
      (_snow(3), null, true),
      (_snow(2), 'adam', false),
      (_snow(5), 'Bea', false),
      (_snow(4), null, false),
    ]);
    // Asked once per account, never for this account, a blocked one or a
    // non-snowId.
    expect(asked, [_snow(1), _snow(2), _snow(3), _snow(4), _snow(5)]);
  });

  test('roster: an answer without a member list is an error', () async {
    for (final detail in [null, 'x', <String, Object?>{}, {'members': 'x'}]) {
      await expectLater(
        () => rosterCandidates(
          detail: detail,
          mySnowId: null,
          blocked: const {},
          isKnown: (_) async => true,
        ),
        throwsFormatException,
        reason: '$detail',
      );
    }
  });

  test('contacts: without blocked, excluded and this account; known first',
      () async {
    final now = DateTime(2026);
    final out = await contactCandidates(
      contacts: [
        Contact(snowChatId: _snow(1), displayName: 'Ann', addedAt: now),
        Contact(snowChatId: _snow(2), displayName: 'Ben', addedAt: now),
        Contact(
          snowChatId: _snow(3),
          displayName: 'Blocked',
          isBlocked: true,
          addedAt: now,
        ),
        Contact(snowChatId: _snow(4), displayName: 'In the group', addedAt: now),
        Contact(snowChatId: _snow(9), displayName: 'Me', addedAt: now),
      ],
      mySnowId: _snow(9),
      exclude: {_snow(4)},
      isKnown: (id) async => id == _snow(2),
    );
    expect([for (final c in out) (c.name, c.known)], [
      ('Ben', true),
      ('Ann', false),
    ]);
  });

  group('PickSelection', () {
    test('picks up to max, and unpicks', () {
      final s = PickSelection(2);
      expect(s.toggle(_snow(1)), isTrue);
      expect(s.toggle(_snow(2)), isTrue);
      expect(s.toggle(_snow(3)), isFalse, reason: 'full');
      expect(s.ids, {_snow(1), _snow(2)});
      expect(s.toggle(_snow(1)), isTrue);
      expect(s.ids, {_snow(2)});
    });

    test('select all takes the known ones only, as far as they fit; then '
        'clears them', () {
      final candidates = [_c(1), _c(2), _c(3), _c(4, known: false)];
      final s = PickSelection(10)..toggle(_snow(4));
      expect(s.selectAllKnown(candidates), isFalse);
      expect(s.ids, {_snow(1), _snow(2), _snow(3), _snow(4)});
      expect(s.allKnownTaken(candidates), isTrue);
      expect(s.selectAllKnown(candidates), isFalse);
      expect(s.ids, {_snow(4)}, reason: 'clear leaves the others');

      final small = PickSelection(2);
      expect(small.selectAllKnown(candidates), isTrue, reason: 'cut short');
      expect(small.ids, hasLength(2));
      expect(small.allKnownTaken(candidates), isTrue, reason: 'full');
      small.selectAllKnown(candidates);
      expect(small.ids, isEmpty);
    });

    test('nothing known: never "all taken"', () {
      final s = PickSelection(5);
      expect(s.allKnownTaken([_c(1, known: false)]), isFalse);
      expect(s.selectAllKnown([_c(1, known: false)]), isFalse);
      expect(s.ids, isEmpty);
    });
  });
}
