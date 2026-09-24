import 'dart:typed_data';

import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:cbzmanager/src/features/cbr/cbr_service.dart';
import 'package:cbzmanager/src/native/cbr_reader.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void expectSameArchive(Uint8List a, Uint8List b) {
  final ea = collectZipEntries(a);
  final eb = collectZipEntries(b);
  expect(ea.map((e) => e.name).toList(), eb.map((e) => e.name).toList());
  for (var i = 0; i < ea.length; i++) {
    expect(ea[i].bytes, eb[i].bytes);
  }
}

void main() {
  // libarchive can read plain ZIP files, which lets us exercise the CBR path
  // without a real RAR on every machine.
  final supported = CbrReader.isSupported;

  test('converts a zip-format CBR into a CBZ (source kept)', () async {
    if (!supported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final vfs = MemoryVfs();
    await vfs.writeAll(
      '/book.cbr',
      makeZip({
        'a.png': makeSolidPng(8, 8),
        'ComicInfo.xml': [1],
        'readme.txt': [2],
      }),
    );

    final outcomes = await const CbrConvertService().convertMany(
      vfs,
      '/',
      ['book.cbr'],
      skipExisting: false,
      deleteSource: false,
    );

    expect(outcomes.single.success, isTrue);
    expect(await vfs.exists('/book.cbz'), isTrue);
    expect(await vfs.exists('/book.cbr'), isTrue);
    final entries = collectZipEntries(await vfs.readAll('/book.cbz'));
    expect(entries.map((e) => e.name), ['page_001.png']);
  });

  test('deleteSource removes the CBR after writing the CBZ', () async {
    if (!supported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final vfs = MemoryVfs();
    await vfs.writeAll('/book.cbr', makeZip({'a.png': makeSolidPng(8, 8)}));

    await const CbrConvertService().convertMany(
      vfs,
      '/',
      ['book.cbr'],
      skipExisting: false,
      deleteSource: true,
    );

    expect(await vfs.exists('/book.cbz'), isTrue);
    expect(await vfs.exists('/book.cbr'), isFalse);
  });

  test('skipExisting leaves an existing target untouched', () async {
    if (!supported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final vfs = MemoryVfs();
    await vfs.writeAll('/book.cbr', makeZip({'a.png': makeSolidPng(8, 8)}));
    await vfs.writeAll('/book.cbz', [9, 9]);

    final outcomes = await const CbrConvertService().convertMany(
      vfs,
      '/',
      ['book.cbr'],
      skipExisting: true,
      deleteSource: false,
    );

    expect(outcomes.single.skipped, isTrue);
    expect(await vfs.readAll('/book.cbz'), [9, 9]);
  });

  test('an imageless archive reports an error without aborting', () async {
    if (!supported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final vfs = MemoryVfs();
    await vfs.writeAll('/empty.cbr', makeZip({'readme.txt': [1]}));

    final outcomes = await const CbrConvertService().convertMany(
      vfs,
      '/',
      ['empty.cbr'],
      skipExisting: false,
      deleteSource: false,
    );

    expect(outcomes.single.error, isNotNull);
    expect(await vfs.exists('/empty.cbz'), isFalse);
  });

  test('output is deterministic for any thread count', () async {
    if (!supported) {
      markTestSkipped('libarchive is not available on this host');
      return;
    }
    final one = MemoryVfs();
    final four = MemoryVfs();
    for (final vfs in [one, four]) {
      await vfs.writeAll('a.cbr', makeZip({'p1.png': makeSolidPng(8, 8)}));
      await vfs.writeAll('b.cbr', makeZip({'p2.png': makeSolidPng(8, 8)}));
    }

    await const CbrConvertService().convertMany(
      one,
      '/',
      ['a.cbr', 'b.cbr'],
      skipExisting: false,
      deleteSource: false,
      threads: 1,
    );
    await const CbrConvertService().convertMany(
      four,
      '/',
      ['a.cbr', 'b.cbr'],
      skipExisting: false,
      deleteSource: false,
      threads: 4,
    );

    expectSameArchive(await one.readAll('/a.cbz'), await four.readAll('/a.cbz'));
    expectSameArchive(await one.readAll('/b.cbz'), await four.readAll('/b.cbz'));
  });
}
