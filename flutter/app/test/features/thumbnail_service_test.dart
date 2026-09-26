import 'dart:typed_data';

import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/browser/thumbnail_service.dart';
import 'package:cbzmanager/src/native/cbr_reader.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  test('ThumbnailService decodes a real CBZ through an isolate', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      'book.cbz',
      makeZip({'a.png': makeSolidPng(32, 32), 'b.png': makeSolidPng(32, 32)}),
    );

    final service = ThumbnailService(readConcurrency: 1, decodeConcurrency: 1);
    addTearDown(service.dispose);
    const item = ArchiveItem(
      name: 'book.cbz',
      path: 'book.cbz',
      size: 0,
      isCbr: false,
    );

    expect(await service.archiveThumbnail(vfs, item), isNotNull);

    final bytes = await vfs.readAll('book.cbz');
    expect(await service.pageCount(bytes, 'book.cbz'), 2);
    expect(await service.pageThumbnail('k', bytes, 'book.cbz', 1), isNotNull);
  });

  test(
    'ThumbnailService decodes a zip-format CBR through an isolate',
    () async {
      if (!CbrReader.isSupported) {
        markTestSkipped('libarchive is not available on this host');
        return;
      }
      final vfs = MemoryVfs();
      await vfs.writeAll('book.cbr', makeZip({'a.png': makeSolidPng(32, 32)}));
      final service = ThumbnailService(
        readConcurrency: 1,
        decodeConcurrency: 1,
      );
      addTearDown(service.dispose);
      const item = ArchiveItem(
        name: 'book.cbr',
        path: 'book.cbr',
        size: 0,
        isCbr: true,
      );
      expect(await service.archiveThumbnail(vfs, item), isNotNull);
    },
  );

  _cacheTests();
}

/// [MemoryVfs] counting whole-file reads, to observe cache hits.
class _CountingVfs extends MemoryVfs {
  int reads = 0;

  @override
  Future<Uint8List> readAll(String path) {
    reads++;
    return super.readAll(path);
  }
}

void _cacheTests() {
  test('a successful archive thumbnail is memoized', () async {
    final vfs = _CountingVfs();
    await vfs.writeAll('book.cbz', makeZip({'a.png': makeSolidPng(32, 32)}));
    final service = ThumbnailService(readConcurrency: 1, decodeConcurrency: 1);
    addTearDown(service.dispose);
    const item = ArchiveItem(
      name: 'book.cbz',
      path: 'book.cbz',
      size: 0,
      isCbr: false,
    );

    expect(await service.archiveThumbnail(vfs, item), isNotNull);
    expect(await service.archiveThumbnail(vfs, item), isNotNull);
    expect(vfs.reads, 1, reason: 'the second call is served from the cache');
  });

  test('a failed decode is not cached, so a retry reads again', () async {
    final vfs = _CountingVfs();
    await vfs.writeAll('bad.cbz', Uint8List.fromList([1, 2, 3]));
    final service = ThumbnailService(readConcurrency: 1, decodeConcurrency: 1);
    addTearDown(service.dispose);
    const item = ArchiveItem(
      name: 'bad.cbz',
      path: 'bad.cbz',
      size: 0,
      isCbr: false,
    );

    expect(await service.archiveThumbnail(vfs, item), isNull);
    expect(await service.archiveThumbnail(vfs, item), isNull);
    expect(vfs.reads, 2, reason: 'a null result must be evicted');
  });
}
