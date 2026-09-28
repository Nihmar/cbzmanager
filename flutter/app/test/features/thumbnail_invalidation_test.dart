import 'dart:typed_data';

import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/browser/thumbnail_service.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// [MemoryVfs] counting whole-file reads, to observe cache hits.
class _CountingVfs extends MemoryVfs {
  int reads = 0;

  @override
  Future<Uint8List> readAll(String path) {
    reads++;
    return super.readAll(path);
  }
}

void main() {
  test('invalidate drops the cached thumbnail for a path', () async {
    // Nothing else can drop an entry: the cache key has no mtime, so an
    // archive rewritten in place kept showing its pre-edit cover.
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

    await service.archiveThumbnail(vfs, item);
    service.invalidate(item.path);
    await service.archiveThumbnail(vfs, item);
    expect(vfs.reads, 2, reason: 'the entry was dropped and recomputed');
  });
}
