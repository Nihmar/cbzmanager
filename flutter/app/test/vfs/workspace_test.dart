import 'dart:typed_data';

import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:cbzmanager/src/vfs/vfs.dart';
import 'package:cbzmanager/src/vfs/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const workspace = Workspace();
  late MemoryVfs vfs;

  setUp(() => vfs = MemoryVfs());

  test('backupPath mirrors the reference _OLD.cbz naming', () {
    expect(workspace.backupPath('/books/a.cbz'), '/books/a_OLD.cbz');
  });

  test('publish is atomic and backs up an existing file', () async {
    await vfs.writeAll('/books/a.cbz', [1, 1, 1]);
    await workspace.publish(vfs, '/books/a.cbz', Uint8List.fromList([2, 2]));

    expect(await vfs.readAll('/books/a.cbz'), Uint8List.fromList([2, 2]));
    expect(
      await vfs.readAll('/books/a_OLD.cbz'),
      Uint8List.fromList([1, 1, 1]),
    );
  });

  test('publish without an existing target writes directly', () async {
    await workspace.publish(vfs, '/books/new.cbz', Uint8List.fromList([7]));
    expect(await vfs.readAll('/books/new.cbz'), Uint8List.fromList([7]));
    expect(await vfs.exists('/books/new_OLD.cbz'), isFalse);
  });

  test('publish replaces an older backup', () async {
    await vfs.writeAll('/books/a.cbz', [1]);
    await workspace.publish(vfs, '/books/a.cbz', Uint8List.fromList([2]));
    await workspace.publish(vfs, '/books/a.cbz', Uint8List.fromList([3]));
    expect(await vfs.readAll('/books/a_OLD.cbz'), Uint8List.fromList([2]));
  });

  test('a failed publish keeps the archive at its path', () async {
    // Regression: the original was renamed aside (and a previous backup
    // deleted) before the new bytes were written; a write failure left the
    // folder without the book, only a backup copy.
    final failing = _FailingWriteVfs();
    await failing.writeAll('/books/a.cbz', [1, 1, 1]);
    failing.fail = true;

    await expectLater(
      workspace.publish(failing, '/books/a.cbz', Uint8List.fromList([2])),
      throwsA(isA<VfsException>()),
    );

    expect(await failing.exists('/books/a.cbz'), isTrue);
    expect(
      await failing.readAll('/books/a.cbz'),
      Uint8List.fromList([1, 1, 1]),
    );
  });
}

/// [MemoryVfs] whose writes fail while [fail] is set, like a full disk or a
/// dropped share.
class _FailingWriteVfs extends MemoryVfs {
  bool fail = false;

  @override
  Future<void> writeAll(String path, List<int> bytes) async {
    if (fail) throw const VfsException('disk full');
    return super.writeAll(path, bytes);
  }
}
