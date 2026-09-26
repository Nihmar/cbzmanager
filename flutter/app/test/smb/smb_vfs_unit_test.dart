import 'dart:typed_data';

import 'package:cbzmanager/src/vfs/smb/smb_backend.dart';
import 'package:cbzmanager/src/vfs/smb_vfs.dart';
import 'package:cbzmanager/src/vfs/vfs.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [SmbBackend] recording the calls it receives, so the SmbVfs
/// logic (path normalization, temp-file write, file-vs-directory delete,
/// single connect) is testable without a live share.
class _FakeBackend implements SmbBackend {
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final Set<String> dirs = <String>{''}; // share root
  final List<String> calls = <String>[];
  bool failWrites = false;

  static String _parent(String path) =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';

  @override
  Future<List<SmbBackendEntry>> list(String path) async {
    calls.add('list:$path');
    return <SmbBackendEntry>[
      for (final dir in dirs)
        if (dir.isNotEmpty && _parent(dir) == path)
          SmbBackendEntry(name: dir.split('/').last, isDirectory: true),
      for (final entry in files.entries)
        if (_parent(entry.key) == path)
          SmbBackendEntry(
            name: entry.key.split('/').last,
            isDirectory: false,
            size: entry.value.length,
          ),
    ];
  }

  @override
  Future<SmbBackendStat> stat(String path) async {
    calls.add('stat:$path');
    if (dirs.contains(path)) {
      return const SmbBackendStat(exists: true, isDirectory: true);
    }
    final bytes = files[path];
    if (bytes == null) return const SmbBackendStat.missing();
    return SmbBackendStat(exists: true, size: bytes.length);
  }

  @override
  Future<bool> exists(String path) async {
    calls.add('exists:$path');
    return dirs.contains(path) || files.containsKey(path);
  }

  @override
  Future<Uint8List> read(String path) async {
    calls.add('read:$path');
    final bytes = files[path];
    if (bytes == null) throw VfsException('No such file: $path');
    return bytes;
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    calls.add('write:$path');
    if (failWrites) throw const VfsException('write failed');
    files[path] = bytes;
  }

  @override
  Future<void> rename(String from, String to) async {
    calls.add('rename:$from->$to');
    final bytes = files.remove(from);
    if (bytes == null) throw VfsException('No such file: $from');
    files[to] = bytes;
  }

  @override
  Future<void> deleteFile(String path) async {
    calls.add('deleteFile:$path');
    files.remove(path);
  }

  @override
  Future<void> mkdir(String path) async {
    calls.add('mkdir:$path');
    dirs.add(path);
  }

  @override
  Future<void> rmdir(String path) async {
    calls.add('rmdir:$path');
    dirs.remove(path);
  }

  @override
  Future<void> disconnect() async => calls.add('disconnect');
}

SmbVfs _vfsWith(_FakeBackend backend) => SmbVfs(
  const SmbConfig(host: 'h', share: 's'),
  connect: (_) async => backend,
);

void main() {
  test('writeAll publishes via a temp file and replaces the target', () async {
    final backend = _FakeBackend();
    final vfs = _vfsWith(backend);

    await vfs.writeAll('/dir/book.cbz', Uint8List.fromList([1, 2, 3]));
    expect(backend.files['dir/book.cbz'], Uint8List.fromList([1, 2, 3]));
    expect(backend.calls, contains('write:dir/book.cbz.new'));
    expect(backend.calls, contains('rename:dir/book.cbz.new->dir/book.cbz'));
    expect(
      backend.calls.where((c) => c == 'deleteFile:dir/book.cbz'),
      isEmpty,
      reason: 'a new target needs no delete',
    );

    backend.calls.clear();
    await vfs.writeAll('/dir/book.cbz', Uint8List.fromList([9]));
    expect(backend.calls, contains('deleteFile:dir/book.cbz'));
    expect(backend.files['dir/book.cbz'], Uint8List.fromList([9]));
  });

  test('a failed write keeps the original and cleans the temp', () async {
    final backend = _FakeBackend();
    backend.files['dir/book.cbz'] = Uint8List.fromList([1, 2, 3]);
    backend.failWrites = true;
    final vfs = _vfsWith(backend);

    await expectLater(
      vfs.writeAll('/dir/book.cbz', Uint8List.fromList([9])),
      throwsA(isA<VfsException>()),
    );
    expect(backend.files['dir/book.cbz'], Uint8List.fromList([1, 2, 3]));
    expect(backend.files.containsKey('dir/book.cbz.new'), isFalse);
  });

  test('paths are normalized to share-relative form', () async {
    final backend = _FakeBackend();
    final vfs = _vfsWith(backend);

    await vfs.mkdir(r'/Comics\');
    expect(backend.calls, contains('mkdir:Comics'));
    expect(await vfs.exists('/Comics/'), isTrue);
    await vfs.writeAll(r'\Comics\book.cbz', Uint8List.fromList([7]));
    expect(backend.files.containsKey('Comics/book.cbz'), isTrue);
  });

  test('list, stat and read map the backend values', () async {
    final backend = _FakeBackend();
    backend.dirs.add('lib');
    backend.files['lib/a.cbz'] = Uint8List.fromList([1, 2]);
    final vfs = _vfsWith(backend);

    final entries = await vfs.list('');
    expect(entries.single.name, 'lib');
    expect(entries.single.isDirectory, isTrue);

    final nested = await vfs.list('lib');
    expect(nested.single.name, 'a.cbz');
    expect(nested.single.size, 2);

    final stat = await vfs.stat('lib/a.cbz');
    expect(stat.exists, isTrue);
    expect(stat.isDirectory, isFalse);
    expect(stat.size, 2);
    expect(await vfs.readAll('lib/a.cbz'), Uint8List.fromList([1, 2]));

    expect((await vfs.stat('missing.cbz')).exists, isFalse);
  });

  test('delete uses rmdir for directories and deleteFile for files', () async {
    final backend = _FakeBackend();
    backend.dirs.add('lib');
    backend.files['lib/a.cbz'] = Uint8List.fromList([1]);
    final vfs = _vfsWith(backend);

    await vfs.delete('lib');
    expect(backend.calls, contains('rmdir:lib'));
    await vfs.delete('missing');
    expect(backend.calls.where((c) => c.startsWith('rmdir:missing')), isEmpty);
  });

  test('concurrent first uses open a single backend', () async {
    var connects = 0;
    final backend = _FakeBackend();
    final vfs = SmbVfs(
      const SmbConfig(host: 'h', share: 's'),
      connect: (_) async {
        connects++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return backend;
      },
    );

    await Future.wait([vfs.exists('a'), vfs.exists('b'), vfs.list('')]);
    expect(connects, 1, reason: 'the in-flight connect is shared');
  });

  test('close disconnects the opened backend once', () async {
    final backend = _FakeBackend();
    final vfs = _vfsWith(backend);

    await vfs.exists('a'); // opens the backend
    await vfs.close();
    await vfs.close(); // idempotent
    expect(backend.calls.where((c) => c == 'disconnect'), hasLength(1));

    // A close before any use has nothing to release.
    final untouched = _FakeBackend();
    await _vfsWith(untouched).close();
    expect(untouched.calls, isEmpty);
  });
}
