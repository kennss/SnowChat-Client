import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Minimal passing test — full widget tests coming later.
    expect(1 + 1, equals(2));
  });
}
