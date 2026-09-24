import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/browser/thumbnail_service.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  test('ThumbnailService decodes a real CBZ through an isolate', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      'book.cbz',
      makeZip({
        'a.png': makeSolidPng(32, 32),
        'b.png': makeSolidPng(32, 32),
      }),
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
}
