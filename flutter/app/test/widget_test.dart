import 'package:cbzmanager/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shell builds and shows the title', (tester) async {
    await tester.pumpWidget(const CbzManagerApp());
    expect(find.text('CBZ Manager'), findsWidgets);
    expect(find.text('Run engine self-test'), findsOneWidget);
  });
}
