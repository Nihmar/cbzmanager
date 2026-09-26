import 'package:cbzmanager/src/features/batch_edit/batch_edit_dialog.dart';
import 'package:cbzmanager/src/features/cbr/cbr_dialog.dart';
import 'package:cbzmanager/src/features/convert/convert_dialog.dart';
import 'package:cbzmanager/src/features/merge/merge_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a button that opens [open] in a dialog.
Future<void> pumpDialog(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// Regression: the operation dialogs never read the persisted settings, so
// "Default threads" and "Keep _OLD backups by default" had no effect.
void main() {
  testWidgets('convert dialog starts from the settings defaults',
      (tester) async {
    await pumpDialog(
      tester,
      (context) => showConvertOptionsDialog(
        context,
        fileCount: 3,
        defaultThreads: 4,
        defaultBackup: false,
      ),
    );
    expect(find.widgetWithText(TextField, '4'), findsOneWidget);
    final backup = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(backup.selected, {false});
  });

  testWidgets('cbr dialog starts from the settings defaults', (tester) async {
    await pumpDialog(
      tester,
      (context) => showCbrOptionsDialog(
        context,
        fileCount: 2,
        defaultThreads: 6,
      ),
    );
    expect(find.widgetWithText(TextField, '6'), findsOneWidget);
  });

  testWidgets('merge dialog starts from the settings defaults', (tester) async {
    await pumpDialog(
      tester,
      (context) => showMergeDialog(
        context,
        files: const ['Test - 01.cbz', 'Test - 02.cbz'],
        defaultThreads: 3,
        defaultBackup: false,
      ),
    );
    expect(find.widgetWithText(TextField, '3'), findsOneWidget);
    final backup = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(backup.selected, {false});
  });

  testWidgets('batch edit dialog starts from the settings defaults',
      (tester) async {
    await pumpDialog(
      tester,
      (context) => showBatchEditDialog(
        context,
        fileCount: 2,
        defaultBackup: false,
      ),
    );
    final backup = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Backup originals (_OLD.cbz)'),
    );
    expect(backup.value, isFalse);
  });
}
