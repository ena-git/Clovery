import 'package:flutter_test/flutter_test.dart';
import 'package:clovery_mobile/app.dart';

void main() {
  testWidgets('shows the offline startup shell', (tester) async {
    await tester.pumpWidget(const CloveryApp());

    expect(find.text('Clovery'), findsOneWidget);
    expect(find.text('Initializing secure vault…'), findsOneWidget);
  });
}
