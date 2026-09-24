import 'dart:typed_data';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/browser/browser_controller.dart';
import 'package:cbzmanager/src/features/browser/browser_screen.dart';
import 'package:cbzmanager/src/features/browser/thumbnail_service.dart';
import 'package:cbzmanager/src/features/sources/source_controller.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:cbzmanager/src/vfs/vfs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

class _FakeThumbnails extends ThumbnailService {
  _FakeThumbnails() : super(readConcurrency: 1, decodeConcurrency: 1);

  @override
  Future<Uint8List?> archiveThumbnail(
    Vfs vfs,
    ArchiveItem item, {
    int maxWidth = 320,
    int maxHeight = 400,
  }) async =>
      makeSolidPng(8, 8);
}

void main() {
  testWidgets('browser grid lists archives with thumbnails', (tester) async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/book1.cbz', [1, 2, 3]);
    await vfs.writeAll('/lib/book2.cbz', [4, 5, 6]);
    await vfs.writeAll('/lib/readme.txt', [7]);

    final container = ProviderContainer(
      overrides: [
        thumbnailServiceProvider.overrideWithValue(_FakeThumbnails()),
      ],
    );
    addTearDown(container.dispose);
    container.read(sourceProvider.notifier).set(
          ArchiveSource(vfs: vfs, root: '/lib', label: 'lib'),
        );
    await container.read(browserProvider.notifier).load(vfs, '/lib');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BrowserScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('book1.cbz'), findsOneWidget);
    expect(find.text('book2.cbz'), findsOneWidget);
    expect(find.text('readme.txt'), findsNothing);
    expect(find.byType(Image), findsNWidgets(2));
  });
}
