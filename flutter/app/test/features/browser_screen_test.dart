import 'dart:typed_data';

import 'package:cbzmanager/l10n/generated/app_localizations.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/browser/browser_controller.dart';
import 'package:cbzmanager/src/features/browser/browser_screen.dart';
import 'package:cbzmanager/src/features/browser/thumbnail_service.dart';
import 'package:cbzmanager/src/features/sources/source_controller.dart';
import 'package:cbzmanager/src/jobs/job_controller.dart';
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
  }) async => makeSolidPng(8, 8);
}

/// Pumps a browser screen over [vfs] and returns the provider container.
Future<ProviderContainer> _pumpBrowser(
  WidgetTester tester,
  MemoryVfs vfs,
  String dir,
) async {
  final container = ProviderContainer(
    overrides: [thumbnailServiceProvider.overrideWithValue(_FakeThumbnails())],
  );
  addTearDown(container.dispose);
  container
      .read(sourceProvider.notifier)
      .set(ArchiveSource(vfs: vfs, root: dir, label: 'lib'));
  await container.read(browserProvider.notifier).load(vfs, dir);

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
  return container;
}

Future<void> _openTileMenu(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(Card),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

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
    container
        .read(sourceProvider.notifier)
        .set(ArchiveSource(vfs: vfs, root: '/lib', label: 'lib'));
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

  testWidgets('tapping a folder browses into it and up returns', (
    tester,
  ) async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/root.cbz', [1, 2, 3]);
    await vfs.mkdir('/lib/Manga');
    await vfs.writeAll('/lib/Manga/vol1.cbz', [4, 5, 6]);

    final container = ProviderContainer(
      overrides: [
        thumbnailServiceProvider.overrideWithValue(_FakeThumbnails()),
      ],
    );
    addTearDown(container.dispose);
    container
        .read(sourceProvider.notifier)
        .set(ArchiveSource(vfs: vfs, root: '/lib', label: 'lib'));
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

    expect(find.text('root.cbz'), findsOneWidget);
    expect(find.text('Manga'), findsOneWidget);
    expect(find.text('vol1.cbz'), findsNothing);
    // At the browsing root there is nothing to climb up to.
    expect(find.byTooltip('Up'), findsNothing);

    await tester.tap(find.text('Manga'));
    await tester.pumpAndSettle();

    expect(find.text('vol1.cbz'), findsOneWidget);
    expect(find.text('root.cbz'), findsNothing);
    expect(container.read(browserProvider).path, '/lib/Manga');
    // The breadcrumb names the current folder and the up button appears.
    expect(find.text('Manga'), findsOneWidget);
    expect(find.byTooltip('Up'), findsOneWidget);

    await tester.tap(find.byTooltip('Up'));
    await tester.pumpAndSettle();

    expect(container.read(browserProvider).path, '/lib');
    expect(find.text('root.cbz'), findsOneWidget);
    expect(find.text('vol1.cbz'), findsNothing);
    expect(find.byTooltip('Up'), findsNothing);
  });

  testWidgets('a CBR tile offers only the CBR-safe action', (tester) async {
    // The ComicInfo editor was offered for CBRs too: reading reported "no
    // ComicInfo" (a blank editor) and saving failed with "Not a ZIP
    // archive".  CBR previews are read-only.
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/book.cbr', [1, 2, 3]);
    await _pumpBrowser(tester, vfs, '/lib');
    await _openTileMenu(tester);

    expect(find.text(l10n.convertCbz), findsOneWidget);
    expect(find.text(l10n.editComicInfo), findsNothing);
    expect(find.text(l10n.validate), findsNothing);
  });

  testWidgets('a CBZ tile offers the ComicInfo editor', (tester) async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/book.cbz', [1, 2, 3]);
    await _pumpBrowser(tester, vfs, '/lib');
    await _openTileMenu(tester);

    expect(find.text(l10n.editComicInfo), findsOneWidget);
    expect(find.text(l10n.convertCbz), findsNothing);
  });

  testWidgets('tile actions are unavailable while a job is running', (
    tester,
  ) async {
    // One job at a time: the app-bar buttons are gated on job.running, but
    // the tile menu was not, so a second operation could clobber the running
    // job's state.
    final vfs = MemoryVfs();
    await vfs.writeAll('/lib/book.cbz', [1, 2, 3]);
    final container = await _pumpBrowser(tester, vfs, '/lib');

    container.read(jobProvider.notifier).start('Merge');
    await tester.pump();

    final menu = find.descendant(
      of: find.byType(Card),
      matching: find.byType(PopupMenuButton<String>),
    );
    expect(tester.widget<PopupMenuButton<String>>(menu).enabled, isFalse);
  });
}
