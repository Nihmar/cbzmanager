import 'package:cbzmanager/src/engine/image_edit.dart';
import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:cbzmanager/src/features/batch_edit/batch_edit_service.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fixtures.dart';

ArchiveItem item(String name) =>
    ArchiveItem(name: name, path: '/$name', size: 0, isCbr: false);

void main() {
  test('resizes and greyscales every page, keeping a backup', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/book.cbz',
      makeZip({
        'page_001.png': makeSolidPng(40, 40),
        'page_002.png': makeSolidPng(40, 40),
      }),
    );

    final outcomes = await const BatchEditService().applyMany(
      vfs,
      [item('book.cbz')],
      const BatchEditParams(percent: 50, adjust: ColorAdjust(grayscale: true)),
    );

    expect(outcomes.single.success, isTrue);
    expect(await vfs.exists('/book_OLD.cbz'), isTrue);

    final entries = collectZipEntries(await vfs.readAll('/book.cbz'));
    final decoded = img.decodeImage(entries.first.bytes)!;
    expect(decoded.width, 20);
    expect(decoded.height, 20);
    final p = decoded.getPixel(0, 0);
    expect(p.r.toInt(), p.g.toInt());
    expect(p.g.toInt(), p.b.toInt());
  });

  test('splits every page into pieces', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/book.cbz',
      makeZip({
        'page_001.png': makeSolidPng(20, 20),
        'page_002.png': makeSolidPng(20, 20),
      }),
    );

    await const BatchEditService().applyMany(
      vfs,
      [item('book.cbz')],
      const BatchEditParams(split: true, horizontal: true, pieces: 2),
    );

    final entries = collectZipEntries(await vfs.readAll('/book.cbz'));
    expect(entries.length, 4);
    expect(img.decodeImage(entries.first.bytes)!.height, 10);
  });

  test('neutral params are a no-op success', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('/book.cbz', makeZip({'a.png': makeSolidPng(8, 8)}));
    final outcomes = await const BatchEditService().applyMany(
      vfs,
      [item('book.cbz')],
      const BatchEditParams(),
    );
    expect(outcomes.single.success, isTrue);
    expect(await vfs.exists('/book_OLD.cbz'), isFalse);
  });

  test('fails the file instead of silently dropping a bad page', () async {
    final vfs = MemoryVfs();
    final original = makeZip({
      'page_001.png': makeSolidPng(20, 20),
      'page_002.png': <int>[0, 1, 2, 3, 4, 5],
    });
    await vfs.writeAll('/book.cbz', original);

    final outcomes = await const BatchEditService().applyMany(
      vfs,
      [item('book.cbz')],
      const BatchEditParams(percent: 50),
    );

    expect(outcomes.single.success, isFalse);
    expect(outcomes.single.error, contains('page_002.png'));
    // The archive must be untouched: no partial rewrite, no backup.
    expect(await vfs.readAll('/book.cbz'), equals(original));
    expect(await vfs.exists('/book_OLD.cbz'), isFalse);
  });
}
