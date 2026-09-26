import 'dart:typed_data';

import 'package:cbzmanager/src/engine/merge.dart';
import 'package:cbzmanager/src/engine/zip_ops.dart';
import 'package:cbzmanager/src/features/merge/merge_service.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// [MemoryVfs] with injectable write failures.  [shadowExists] simulates a
/// volume created by another process between listing and write; [delete]
/// removes it too so the rollback is observable.
class _FailingWriteVfs extends MemoryVfs {
  final Set<String> shadowExists = <String>{};
  bool fail = false;
  bool partialWrite = false;
  String? failPath;

  @override
  Future<bool> exists(String path) async =>
      shadowExists.contains(path) || await super.exists(path);

  @override
  Future<void> delete(String path) async {
    shadowExists.remove(path);
    return super.delete(path);
  }

  @override
  Future<void> writeAll(String path, List<int> bytes) async {
    if (fail && path == failPath) {
      if (partialWrite) {
        await super.writeAll(path, bytes.take(bytes.length ~/ 2).toList());
      }
      throw StateError('disk full');
    }
    return super.writeAll(path, bytes);
  }
}

Future<void> putChapter(MemoryVfs vfs, String name, int pages) async {
  await vfs.writeAll(
    '/$name',
    makeZip({
      for (var i = 1; i <= pages; i++) 'p$i.png': makeSolidPng(8, 8),
    }),
  );
}

Future<void> putChapters(MemoryVfs vfs, int count) async {
  for (var i = 1; i <= count; i++) {
    await putChapter(vfs, 'Test - ${i.toString().padLeft(2, '0')}.cbz', 1);
  }
}

void expectSameArchive(Uint8List a, Uint8List b) {
  final ea = collectZipEntries(a);
  final eb = collectZipEntries(b);
  expect(ea.map((e) => e.name).toList(), eb.map((e) => e.name).toList());
  for (var i = 0; i < ea.length; i++) {
    expect(ea[i].bytes, eb[i].bytes);
  }
}

void main() {
  test('merges full volumes and backs up sources', () async {    final vfs = MemoryVfs();
    await putChapters(vfs, 6);

    final outcome = await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(chaptersPerVolume: 2),
    );

    expect(outcome.success, isTrue);
    expect(outcome.volumesCreated, 3);
    for (var i = 1; i <= 3; i++) {
      expect(await vfs.exists('/Test V00$i.cbz'), isTrue);
      expect(
        collectZipEntries(await vfs.readAll('/Test V00$i.cbz')).length,
        2,
      );
    }
    expect(await vfs.exists('/Test - 01_OLD.cbz'), isTrue);
    expect(await vfs.exists('/Test - 01.cbz'), isFalse);
  });

  test('rollback keeps a pre-existing target it could not overwrite',
      () async {
    // Models a volume appearing between the listing/plan and the write (the
    // CLI plan is built from a snapshot).  The old code marked the batch as
    // written before writeAll, so a failed write made rollback delete a file
    // this run had not created.
    final vfs = _FailingWriteVfs();
    await putChapters(vfs, 2);
    vfs.shadowExists.add('/Test V001.cbz');
    vfs.fail = true;
    vfs.failPath = '/Test V001.cbz';

    final outcome = await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(seriesName: 'Test', chaptersPerVolume: 2),
    );

    expect(outcome.success, isFalse);
    expect(await vfs.exists('/Test V001.cbz'), isTrue,
        reason: 'not created by this run: leave it alone');
    expect(await vfs.exists('/Test - 01.cbz'), isTrue,
        reason: 'failed run keeps its sources');
  });

  test('rollback removes a partial volume this run created', () async {
    final vfs = _FailingWriteVfs();
    await putChapters(vfs, 2);
    vfs.fail = true;
    vfs.failPath = '/Test V001.cbz';
    vfs.partialWrite = true; // write a truncated file, then throw

    final outcome = await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(seriesName: 'Test', chaptersPerVolume: 2),
    );

    expect(outcome.success, isFalse);
    expect(await vfs.exists('/Test V001.cbz'), isFalse,
        reason: 'the truncated file created by this run is rolled back');
  });

  test('delete mode removes sources with no backup', () async {
    final vfs = MemoryVfs();
    await putChapters(vfs, 4);

    await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(chaptersPerVolume: 2, delete: true),
    );

    expect(await vfs.exists('/Test - 01.cbz'), isFalse);
    expect(await vfs.exists('/Test - 01_OLD.cbz'), isFalse);
  });

  test('force absorbs the leftover chapters', () async {
    final vfs = MemoryVfs();
    await putChapters(vfs, 5);

    final outcome = await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(chaptersPerVolume: 2, force: true),
    );

    expect(outcome.volumesCreated, 2);
    expect(
      collectZipEntries(await vfs.readAll('/Test V002.cbz')).length,
      3,
    );
  });

  test('not enough chapters is a benign no-op', () async {
    final vfs = MemoryVfs();
    await putChapters(vfs, 3);

    final outcome = await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(chaptersPerVolume: 7),
    );

    expect(outcome.success, isFalse);
    expect(outcome.volumesCreated, 0);
    expect(await vfs.exists('/Test V001.cbz'), isFalse);
    expect(await vfs.exists('/Test - 01.cbz'), isTrue);
  });

  test('output is deterministic for any thread count', () async {
    final one = MemoryVfs();
    final four = MemoryVfs();
    await putChapters(one, 6);
    await putChapters(four, 6);

    await const MergeService().merge(
      one,
      '/',
      const MergeOptions(chaptersPerVolume: 2, threads: 1),
    );
    await const MergeService().merge(
      four,
      '/',
      const MergeOptions(chaptersPerVolume: 2, threads: 4),
    );

    for (var i = 1; i <= 3; i++) {
      expectSameArchive(
        await one.readAll('/Test V00$i.cbz'),
        await four.readAll('/Test V00$i.cbz'),
      );
    }
  });

  test('generates a volume ComicInfo when asked', () async {
    final vfs = MemoryVfs();
    await putChapters(vfs, 2);

    await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(chaptersPerVolume: 2, generateComicInfo: true),
    );

    final entries = collectZipEntries(await vfs.readAll('/Test V001.cbz'));
    expect(entries.map((e) => e.name), contains('ComicInfo.xml'));
  });

  test('ignores volume files, backups and other series', () async {
    final vfs = MemoryVfs();
    await putChapters(vfs, 4);
    await putChapter(vfs, 'Test V001.cbz', 5);
    await putChapter(vfs, 'Test - 01_OLD.cbz', 1);
    await putChapter(vfs, 'Other - 01.cbz', 1);

    final outcome = await const MergeService().merge(
      vfs,
      '/',
      const MergeOptions(seriesName: 'Test', chaptersPerVolume: 2),
    );

    // Starting after the existing Test V001 → V002 and V003.
    expect(outcome.volumes, ['Test V002.cbz', 'Test V003.cbz']);
    expect(await vfs.exists('/Test V001.cbz'), isTrue);
    expect(await vfs.exists('/Other - 01.cbz'), isTrue);
    expect(await vfs.exists('/Test - 01_OLD_OLD.cbz'), isFalse);
    expect(await vfs.exists('/Test - 01_OLD.cbz'), isTrue);
  });
}
