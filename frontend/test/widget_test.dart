// Basic widget test for Fabio
import 'package:flutter_test/flutter_test.dart';
import 'package:fabio/main.dart';

void main() {
  testWidgets('Fabio app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const FabioApp());
    expect(find.text('Fabio'), findsWidgets);
  });
}
