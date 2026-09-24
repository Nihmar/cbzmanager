import 'dart:typed_data';

import 'vfs.dart';

/// In-memory [Vfs], used by tests and for staging results before publishing.
class MemoryVfs implements Vfs {
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final Set<String> _dirs = <String>{'/'};

  @override
  String get scheme => 'memory';

  static String _norm(String path) {
    var s = path.replaceAll('\\', '/');
    if (!s.startsWith('/')) s = '/$s';
    while (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String _parent(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? '/' : path.substring(0, i);
  }

  static String _base(String path) => path.substring(path.lastIndexOf('/') + 1);

  @override
  Future<List<VfsEntry>> list(String dir) async {
    final d = _norm(dir);
    if (!_dirs.contains(d)) {
      throw VfsException('No such directory: $dir');
    }
    final out = <VfsEntry>[];
    for (final e in _dirs) {
      if (e != '/' && _parent(e) == d) {
        out.add(VfsEntry(name: _base(e), isDirectory: true));
      }
    }
    _files.forEach((path, bytes) {
      if (_parent(path) == d) {
        out.add(
          VfsEntry(name: _base(path), isDirectory: false, size: bytes.length),
        );
      }
    });
    return out;
  }

  @override
  Future<VfsStat> stat(String path) async {
    final p = _norm(path);
    if (_dirs.contains(p)) return const VfsStat(exists: true, isDirectory: true);
    final bytes = _files[p];
    if (bytes == null) return const VfsStat.missing();
    return VfsStat(exists: true, size: bytes.length);
  }

  @override
  Future<bool> exists(String path) async =>
      (await stat(path)).exists;

  @override
  Future<Uint8List> readAll(String path) async {
    final bytes = _files[_norm(path)];
    if (bytes == null) throw VfsException('No such file: $path');
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeAll(String path, List<int> bytes) async {
    final p = _norm(path);
    _dirs.add(_parent(p));
    _files[p] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> rename(String from, String to) async {
    final f = _norm(from);
    final t = _norm(to);
    final bytes = _files.remove(f);
    if (bytes == null) throw VfsException('No such file: $from');
    _dirs.add(_parent(t));
    _files[t] = bytes;
  }

  @override
  Future<void> delete(String path) async {
    final p = _norm(path);
    _files.remove(p);
    _dirs.remove(p);
  }

  @override
  Future<void> mkdir(String path) async {
    final p = _norm(path);
    var cur = '';
    for (final part in p.split('/')) {
      if (part.isEmpty) continue;
      cur = '$cur/$part';
      _dirs.add(cur);
    }
  }
}
