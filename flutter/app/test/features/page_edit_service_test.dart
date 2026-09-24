import 'dart:convert';

import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:cbzmanager/src/features/page_editor/page_edit_service.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../support/fixtures.dart';

void main() {
  test('loads a model and saves edits with renumbering + backup', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/book.cbz',
      makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'page_002.png': makeSolidPng(8, 8),
        'page_003.png': makeSolidPng(8, 8),
        'ComicInfo.xml': utf8.encode('<ComicInfo/>'),
      }),
    );

    final model = PageEditService.loadModel(await vfs.readAll('/book.cbz'));
    expect(model.pages.length, 3);

    model.deleteAt(2);
    model.markEdited(0, makeSolidPng(16, 16));
    await const PageEditService().save(vfs, '/book.cbz', model, renumber: true);

    final out = collectZipEntries(await vfs.readAll('/book.cbz'));
    expect(out.map((e) => e.name).toList(), [
      'page_0001.png',
      'page_0002.png',
      'ComicInfo.xml',
    ]);
    expect(await vfs.exists('/book_OLD.cbz'), isTrue);

    final edited = img.decodeImage(
      out.firstWhere((e) => e.name == 'page_0001.png').bytes,
    );
    expect(edited!.width, 16);
  });

  test('deleted pages do not reappear as leftover entries', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/book.cbz',
      makeZip({
        'page_001.png': makeSolidPng(8, 8),
        'page_002.png': makeSolidPng(8, 8),
      }),
    );
    final model = PageEditService.loadModel(await vfs.readAll('/book.cbz'));
    model.deleteAt(0);
    await const PageEditService().save(vfs, '/book.cbz', model, renumber: true);
    final out = collectZipEntries(await vfs.readAll('/book.cbz'));
    expect(out.map((e) => e.name).toList(), ['page_0001.png']);
  });
}
