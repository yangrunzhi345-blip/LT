import 'package:flutter_test/flutter_test.dart';
import 'package:lt_dialogue/main.dart';

void main() {
  testWidgets('App smoke test initializes MyApp', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('LT Dialogue'), findsOneWidget);
  });
}
