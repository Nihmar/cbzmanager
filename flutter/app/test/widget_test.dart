import 'package:cbzmanager/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('welcome screen offers a source choice', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: CbzManagerApp()));
    expect(find.text('Open a comics folder'), findsOneWidget);
    expect(find.text('SMB share'), findsOneWidget);
  });
}
