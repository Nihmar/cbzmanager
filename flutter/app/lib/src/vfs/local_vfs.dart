import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'vfs.dart';

/// Local-filesystem [Vfs] backed by `dart:io`.
class LocalVfs implements Vfs {
  const LocalVfs();

  @override
  String get scheme => 'file';

  @override
  Future<List<VfsEntry>> list(String dir) async {
    final d = Directory(dir);
    if (!await d.exists()) {
      throw VfsException('No such directory: $dir');
    }
    final out = <VfsEntry>[];
    await for (final entity in d.list(followLinks: false)) {
      final stat = await entity.stat();
      out.add(
        VfsEntry(
          name: p.basename(entity.path),
          isDirectory: stat.type == FileSystemEntityType.directory,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    return out;
  }

  @override
  Future<VfsStat> stat(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const VfsStat.missing();
    final stat = await FileStat.stat(path);
    return VfsStat(
      exists: true,
      isDirectory: type == FileSystemEntityType.directory,
      size: stat.size,
      modified: stat.modified,
    );
  }

  @override
  Future<bool> exists(String path) async => (await stat(path)).exists;

  @override
  Future<Uint8List> readAll(String path) async {
    final file = File(path);
    if (!await file.exists()) throw VfsException('No such file: $path');
    return file.readAsBytes();
  }

  @override
  Future<void> writeAll(String path, List<int> bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmp = File('$path.new');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  @override
  Future<void> rename(String from, String to) async {
    final src = File(from);
    if (!await src.exists()) throw VfsException('No such file: $from');
    await src.rename(to);
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    final dir = Directory(path);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<void> mkdir(String path) async {
    await Directory(path).create(recursive: true);
  }
}
