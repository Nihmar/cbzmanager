import 'package:cbzmanager/src/features/browser/archive_item.dart';
import 'package:cbzmanager/src/features/browser/thumbnail_service.dart';
import 'package:cbzmanager/src/native/cbr_reader.dart';
import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:cbzmanager/src/vfs/smb/smb_backend.dart';
import 'package:cbzmanager/src/vfs/smb_vfs.dart';
import 'package:flutter/foundation.dart';
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
  _sourceIdentityTests();
}

/// [SmbBackend] serving one archive, so a test can stand up two shares.
class _FakeSmbBackend implements SmbBackend {
  _FakeSmbBackend(this.bytes);

  final Uint8List bytes;
  int reads = 0;

  @override
  Future<Uint8List> read(String path) async {
    reads++;
    return bytes;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> exists(String path) async => false;

  @override
  Future<List<SmbBackendEntry>> list(String path) async => const [];

  @override
  Future<SmbBackendStat> stat(String path) async =>
      const SmbBackendStat.missing();

  @override
  Future<void> deleteFile(String path) async {}

  @override
  Future<void> mkdir(String path) async {}

  @override
  Future<void> rename(String from, String to) async {}

  @override
  Future<void> rmdir(String path) async {}

  @override
  Future<void> write(String path, Uint8List bytes) async {}
}

SmbVfs _share(String host, SmbBackend backend) => SmbVfs(
  SmbConfig(host: host, share: 'comics'),
  connect: (_) async => backend,
);

void _sourceIdentityTests() {
  test(
    'two shares with the same relative path get their own thumbnail',
    () async {
      // Regression: the cache key was scheme + share-relative path, so every
      // SMB share shared one entry and the second share showed the first
      // share's cover art.
      final shareA = _FakeSmbBackend(
        makeZip({'cover.png': makeNoisePng(32, 32, 1)}),
      );
      final shareB = _FakeSmbBackend(
        makeZip({'cover.png': makeNoisePng(32, 32, 2)}),
      );
      final service = ThumbnailService(
        readConcurrency: 1,
        decodeConcurrency: 1,
      );
      addTearDown(service.dispose);
      const item = ArchiveItem(
        name: 'book.cbz',
        path: 'Manga/book.cbz',
        size: 0,
        isCbr: false,
      );

      final a = await service.archiveThumbnail(_share('hostA', shareA), item);
      final b = await service.archiveThumbnail(_share('hostB', shareB), item);

      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(
        shareB.reads,
        1,
        reason: 'a different share must not be served from the cache',
      );
      expect(listEquals(a!, b!), isFalse);
    },
  );
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
