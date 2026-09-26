import 'package:cbzmanager/main.dart';
import 'package:cbzmanager/src/features/settings/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('welcome screen offers a source choice', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: const CbzManagerApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open a comics folder'), findsOneWidget);
    expect(find.text('SMB share'), findsOneWidget);
  });
}
