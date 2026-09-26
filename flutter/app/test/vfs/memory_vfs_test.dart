import 'dart:typed_data';

import 'package:cbzmanager/src/vfs/memory_vfs.dart';
import 'package:cbzmanager/src/vfs/vfs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MemoryVfs vfs;

  setUp(() => vfs = MemoryVfs());

  test('write/read/list/stat round-trip', () async {
    await vfs.writeAll('/books/a.cbz', [1, 2, 3]);
    await vfs.mkdir('/books/sub');

    final entries = await vfs.list('/books');
    final names = entries.map((e) => e.name).toSet();
    expect(names, containsAll(['a.cbz', 'sub']));
    expect(entries.firstWhere((e) => e.name == 'a.cbz').isDirectory, isFalse);
    expect(entries.firstWhere((e) => e.name == 'sub').isDirectory, isTrue);

    expect(await vfs.readAll('/books/a.cbz'), Uint8List.fromList([1, 2, 3]));
    final stat = await vfs.stat('/books/a.cbz');
    expect(stat.exists, isTrue);
    expect(stat.isDirectory, isFalse);
    expect(stat.size, 3);
  });

  test('missing paths report cleanly', () async {
    expect(await vfs.exists('/nope.cbz'), isFalse);
    expect((await vfs.stat('/nope.cbz')).exists, isFalse);
    expect(() => vfs.readAll('/nope.cbz'), throwsA(isA<VfsException>()));
  });

  test('rename moves bytes and delete removes', () async {
    await vfs.writeAll('/a.cbz', [9]);
    await vfs.rename('/a.cbz', '/b.cbz');
    expect(await vfs.exists('/a.cbz'), isFalse);
    expect(await vfs.readAll('/b.cbz'), Uint8List.fromList([9]));

    await vfs.delete('/b.cbz');
    expect(await vfs.exists('/b.cbz'), isFalse);
  });

  test('listing a missing directory throws', () {
    expect(() => vfs.list('/missing'), throwsA(isA<VfsException>()));
  });
}
