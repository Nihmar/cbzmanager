import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cbzmanager/src/engine/comicinfo.dart';
import 'package:cbzmanager/src/engine/dart_engine.dart';
import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/comicinfo/comicinfo_service.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// Compares two archives by entry name and content (ZIP timestamps differ).
void expectSameArchive(Uint8List a, Uint8List b) {
  final ea = collectZipEntries(a);
  final eb = collectZipEntries(b);
  expect(ea.map((e) => e.name).toList(), eb.map((e) => e.name).toList());
  for (var i = 0; i < ea.length; i++) {
    expect(ea[i].bytes, eb[i].bytes);
  }
}

void main() {
  const service = ComicInfoService(DartCbzEngine());

  ArchiveItem item(String name) =>
      ArchiveItem(name: name, path: '/$name', size: 0, isCbr: false);

  Future<MemoryVfs> bookWithComicInfo(ComicInfo info) async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/book.cbz',
      makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'ComicInfo.xml': utf8.encode(info.toXml()),
      }),
    );
    return vfs;
  }

  test('reads existing ComicInfo', () async {
    final vfs = await bookWithComicInfo(ComicInfo(series: 'Saga', number: '1'));
    final read = await service.read(vfs, item('book.cbz'));
    expect(read.found, isTrue);
    expect(read.info!.series, 'Saga');
    expect(read.info!.number, '1');
  });

  test('write replaces and backs up the original', () async {
    final vfs = await bookWithComicInfo(ComicInfo(series: 'Saga', number: '1'));
    await service.write(
      vfs,
      item('book.cbz'),
      ComicInfo(series: 'Saga', number: '2', title: 'Two'),
    );

    expect(await vfs.exists('/book_OLD.cbz'), isTrue);
    final reread = await service.read(vfs, item('book.cbz'));
    expect(reread.info!.number, '2');
    expect(reread.info!.title, 'Two');
  });

  test('remove strips ComicInfo and reports a second run as a no-op', () async {
    final vfs = await bookWithComicInfo(ComicInfo(series: 'Saga'));

    expect(await service.remove(vfs, item('book.cbz')), isTrue);
    expect((await service.read(vfs, item('book.cbz'))).found, isFalse);
    expect(await service.remove(vfs, item('book.cbz')), isFalse);
  });

  test('removeMany aggregates changed and skipped files', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/with.cbz',
      makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'ComicInfo.xml': utf8.encode(ComicInfo(series: 'X').toXml()),
      }),
    );
    await vfs.writeAll(
      '/without.cbz',
      makeZip({'page_001.png': makeSolidPng(8, 8)}),
    );

    final result = await service.removeMany(vfs, [
      item('with.cbz'),
      item('without.cbz'),
    ]);
    expect(result.scanned, 2);
    expect(result.changed, 1);
    expect(result.skipped, 1);
    expect(result.errors, isEmpty);
  });

  test('a missing archive is reported without aborting the batch', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/with.cbz',
      makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'ComicInfo.xml': utf8.encode(ComicInfo(series: 'X').toXml()),
      }),
    );

    final result = await service.removeMany(vfs, [
      item('gone.cbz'),
      item('with.cbz'),
    ]);
    expect(result.scanned, 2);
    expect(result.changed, 1);
    expect(result.skipped, 0);
    expect(result.errors.single, contains('gone.cbz'));
  });

  test('removal is deterministic for any thread count', () async {
    final one = MemoryVfs();
    final four = MemoryVfs();
    for (final vfs in [one, four]) {
      await vfs.writeAll(
        '/a.cbz',
        makeZip({
          'page_001.png': makeSolidPng(8, 8),
          'ComicInfo.xml': utf8.encode(ComicInfo(series: 'A').toXml()),
        }),
      );
      await vfs.writeAll(
        '/b.cbz',
        makeZip({'page_001.png': makeSolidPng(8, 8)}),
      );
      await vfs.writeAll(
        '/c.cbz',
        makeZip({
          'page_001.png': makeSolidPng(8, 8),
          'ComicInfo.xml': utf8.encode(ComicInfo(series: 'C').toXml()),
        }),
      );
    }

    final r1 = await service.removeMany(one, [
      item('a.cbz'),
      item('b.cbz'),
      item('c.cbz'),
    ], threads: 1);
    final r4 = await service.removeMany(four, [
      item('a.cbz'),
      item('b.cbz'),
      item('c.cbz'),
    ], threads: 4);

    expect(r1.changed, 2);
    expect(r4.changed, 2);
    expect(r4.skipped, r1.skipped);
    expect(r4.errors, r1.errors);
    for (final name in ['a', 'b', 'c']) {
      expectSameArchive(
        await one.readAll('/$name.cbz'),
        await four.readAll('/$name.cbz'),
      );
    }
  });

  // Regression: rewriting an archive used to happen on the UI isolate, which
  // froze the app. A pending timer can only run if the main isolate is handed
  // back to the event loop, which now happens while the isolate works.
  test('leaves the UI isolate free to run timers', () async {
    final vfs = MemoryVfs();
    for (var i = 0; i < 4; i++) {
      await vfs.writeAll(
        '/book$i.cbz',
        makeZip({
          for (var p = 0; p < 3; p++)
            'page_00$p.png': makeNoisePng(200, 200, p),
          'ComicInfo.xml': utf8.encode(ComicInfo(series: 'S$i').toXml()),
        }),
      );
    }

    var ticks = 0;
    final timer = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => ticks++,
    );
    addTearDown(timer.cancel);

    final result = await service.removeMany(vfs, [
      for (var i = 0; i < 4; i++) item('book$i.cbz'),
    ]);

    expect(result.changed, 4);
    expect(ticks, greaterThan(0));
  });
}
