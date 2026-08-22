import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const PdfTranslateApp());
    expect(find.text('PDF Translate'), findsOneWidget);
  });
}
