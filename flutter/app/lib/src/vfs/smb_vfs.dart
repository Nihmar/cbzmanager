import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';

import 'vfs.dart';

/// Connection parameters for an SMB2/3 share.
///
/// Passwords are supplied by the caller (in the app they come from
/// `flutter_secure_storage`) and are never written to settings.
class SmbConfig {
  const SmbConfig({
    required this.host,
    required this.share,
    this.user,
    this.password,
    this.domain,
    this.workers = 4,
  });

  final String host;
  final String share;
  final String? user;
  final String? password;
  final String? domain;
  final int workers;

  @override
  String toString() => 'smb://$host/$share${user == null ? '' : ' ($user)'}';
}

/// [Vfs] backed by an SMB2/3 share through `dart_smb2` (libsmb2).
///
/// Paths are share-relative; a leading `/` is accepted and stripped. The pool
/// is opened lazily on first use and reused for the lifetime of the instance;
/// call [disconnect] when done.
class SmbVfs implements Vfs {
  SmbVfs(this.config);

  final SmbConfig config;
  Smb2Pool? _pool;

  @override
  String get scheme => 'smb';

  Future<Smb2Pool> _ensurePool() async {
    final existing = _pool;
    if (existing != null) return existing;
    final pool = await Smb2Pool.connect(
      host: config.host,
      share: config.share,
      user: config.user,
      password: config.password,
      domain: config.domain,
      workers: config.workers,
    );
    _pool = pool;
    return pool;
  }

  /// Closes the worker pool. Safe to call more than once.
  Future<void> disconnect() async {
    final pool = _pool;
    _pool = null;
    await pool?.disconnect();
  }

  static String _rel(String path) {
    var p = path.replaceAll('\\', '/');
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  @override
  Future<List<VfsEntry>> list(String dir) async {
    final pool = await _ensurePool();
    final entries = await pool.listDirectory(_rel(dir));
    return entries
        .map(
          (e) => VfsEntry(
            name: e.name,
            isDirectory: e.isDirectory,
            size: e.size,
            modified: e.stat.modified,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<VfsStat> stat(String path) async {
    final pool = await _ensurePool();
    final rel = _rel(path);
    if (!await pool.exists(rel)) return const VfsStat.missing();
    final s = await pool.stat(rel);
    return VfsStat(
      exists: true,
      isDirectory: s.isDirectory,
      size: s.size,
      modified: s.modified,
    );
  }

  @override
  Future<bool> exists(String path) async {
    final pool = await _ensurePool();
    return pool.exists(_rel(path));
  }

  @override
  Future<Uint8List> readAll(String path) async {
    final pool = await _ensurePool();
    return pool.readFile(_rel(path));
  }

  @override
  Future<void> writeAll(String path, List<int> bytes) async {
    final pool = await _ensurePool();
    await pool.writeFile(_rel(path), Uint8List.fromList(bytes));
  }

  @override
  Future<void> rename(String from, String to) async {
    final pool = await _ensurePool();
    await pool.rename(_rel(from), _rel(to));
  }

  @override
  Future<void> delete(String path) async {
    final pool = await _ensurePool();
    final rel = _rel(path);
    final s = await pool.exists(rel) ? await pool.stat(rel) : null;
    if (s == null) return;
    if (s.isDirectory) {
      await pool.rmdir(rel);
    } else {
      await pool.deleteFile(rel);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final pool = await _ensurePool();
    await pool.mkdir(_rel(path));
  }
}
