/// @file        log_ref_test.dart
/// @description logRef (security review S11): an id in a log line is a short tag — the same for
///              the same id within a run, different for different ids, never the id or a part
///              of it.
/// @author      Kennt Kim
/// @company     Calida Lab
/// @created     2026-11-22
/// @lastUpdated 2026-11-22
///
/// @functions
///  - main(): the cases above
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:snowchat/core/diagnostics/log_ref.dart';

void main() {
  const a = 'snow0123456789abcdef0123456789abcdef';
  const b = 'snow1123456789abcdef0123456789abcdef';

  test('a short tag, stable within the run, distinct per id, never the id', () {
    final tag = logRef(a);
    expect(tag, matches(RegExp(r'^ref:[0-9a-f]{8}$')));
    expect(logRef(a), tag);
    expect(logRef(b), isNot(tag));
    expect(tag.contains(a.substring(4, 12)), isFalse);
    expect(logRef(null), 'ref:-');
    expect(logRef(''), 'ref:-');
  });
}
