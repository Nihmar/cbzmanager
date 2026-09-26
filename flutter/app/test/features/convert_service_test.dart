import 'dart:typed_data';

import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/convert/convert_service.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

ArchiveItem item(String name) =>
    ArchiveItem(name: name, path: name, size: 0, isCbr: false);

void expectSameArchive(Uint8List a, Uint8List b) {
  final ea = collectZipEntries(a);
  final eb = collectZipEntries(b);
  expect(ea.map((e) => e.name).toList(), eb.map((e) => e.name).toList());
  for (var i = 0; i < ea.length; i++) {
    expect(ea[i].bytes, eb[i].bytes);
  }
}

void main() {
  test('converts pages, renames them and keeps a backup', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll(
      'book.cbz',
      makeZip({
        'a.png': makeNoisePng(64, 64),
        'ComicInfo.xml': '<ComicInfo/>'.codeUnits,
      }),
    );

    final outcomes = await const ConvertService().convertMany(vfs, [
      item('book.cbz'),
    ], backup: true);

    expect(outcomes.single.success, isTrue);
    expect(outcomes.single.converted, 1);
    expect(await vfs.exists('/book_OLD.cbz'), isTrue);

    final entries = collectZipEntries(await vfs.readAll('/book.cbz'));
    expect(entries.map((e) => e.name), ['page_0001.webp']);
  });

  test('delete mode leaves no backup', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('book.cbz', makeZip({'a.png': makeNoisePng(64, 64)}));

    await const ConvertService().convertMany(vfs, [
      item('book.cbz'),
    ], backup: false);
    expect(await vfs.exists('/book_OLD.cbz'), isFalse);
  });

  test('output is deterministic for any thread count', () async {
    final one = MemoryVfs();
    final four = MemoryVfs();
    for (final vfs in [one, four]) {
      await vfs.writeAll(
        'a.cbz',
        makeZip({
          'p1.png': makeNoisePng(64, 64),
          'p2.png': makeNoisePng(64, 64),
        }),
      );
      await vfs.writeAll('b.cbz', makeZip({'p1.png': makeNoisePng(64, 64)}));
    }

    final r1 = await const ConvertService().convertMany(
      one,
      [item('a.cbz'), item('b.cbz')],
      backup: true,
      threads: 1,
    );
    final r4 = await const ConvertService().convertMany(
      four,
      [item('a.cbz'), item('b.cbz')],
      backup: true,
      threads: 4,
    );

    expect(r1.every((o) => o.success), isTrue);
    expect(r4.every((o) => o.success), isTrue);
    expectSameArchive(
      await one.readAll('/a.cbz'),
      await four.readAll('/a.cbz'),
    );
    expectSameArchive(
      await one.readAll('/b.cbz'),
      await four.readAll('/b.cbz'),
    );
  });

  test('a bad file reports an error without aborting the batch', () async {
    final vfs = MemoryVfs();
    await vfs.writeAll('bad.cbz', [1, 2, 3, 4]);
    await vfs.writeAll('good.cbz', makeZip({'a.png': makeNoisePng(64, 64)}));

    final outcomes = await const ConvertService().convertMany(vfs, [
      item('bad.cbz'),
      item('good.cbz'),
    ], backup: true);

    expect(outcomes.length, 2);
    expect(outcomes.first.error, isNotNull);
    expect(outcomes[1].success, isTrue);
  });

  test('an archive with no images is a benign skip, not an error', () async {
    // Regression: the engine returns no output for a ComicInfo-only archive;
    // the service used to report that as a per-file failure (the CLI then
    // exited 1 where the reference exits 0).
    final vfs = MemoryVfs();
    final original = makeZip({'ComicInfo.xml': '<ComicInfo/>'.codeUnits});
    await vfs.writeAll('empty.cbz', original);

    final outcomes = await const ConvertService().convertMany(vfs, [
      item('empty.cbz'),
    ], backup: true);

    expect(outcomes.single.error, isNull);
    expect(outcomes.single.skipped, isTrue);
    expect(outcomes.single.success, isFalse);
    expect(await vfs.exists('/empty_OLD.cbz'), isFalse);
    expectSameArchive(await vfs.readAll('/empty.cbz'), original);
  });
}
