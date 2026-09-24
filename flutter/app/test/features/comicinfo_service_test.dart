import 'dart:convert';

import 'package:cbzmanager/src/engine/comicinfo.dart';
import 'package:cbzmanager/src/engine/dart_engine.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/comicinfo/comicinfo_service.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

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

    final result = await service.removeMany(
      vfs,
      [item('with.cbz'), item('without.cbz')],
    );
    expect(result.scanned, 2);
    expect(result.changed, 1);
    expect(result.skipped, 1);
    expect(result.errors, isEmpty);
  });
}
