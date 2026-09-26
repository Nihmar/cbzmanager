import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';

import 'smb_backend.dart';

/// [SmbBackend] implemented on top of `dart_smb2` (libsmb2).
///
/// This is the ONLY file in the app that imports `dart_smb2`: the package is
/// pre-1.0, so the adapter keeps its API (and any future breaking change, or a
/// swap to another client) contained to this file.  Everything else talks to
/// [SmbBackend].
class DartSmb2Backend implements SmbBackend {
  DartSmb2Backend._(this._pool);

  final Smb2Pool _pool;

  /// Opens a worker pool for [config].  Throws when the share is unreachable
  /// or libsmb2 cannot be loaded.
  static Future<SmbBackend> connect(SmbConfig config) async {
    final pool = await Smb2Pool.connect(
      host: config.host,
      share: config.share,
      user: config.user,
      password: config.password,
      domain: config.domain,
      workers: config.workers,
    );
    return DartSmb2Backend._(pool);
  }

  @override
  Future<List<SmbBackendEntry>> list(String path) async {
    final entries = await _pool.listDirectory(path);
    return <SmbBackendEntry>[
      for (final entry in entries)
        SmbBackendEntry(
          name: entry.name,
          isDirectory: entry.isDirectory,
          size: entry.stat.size,
          modified: entry.stat.modified,
        ),
    ];
  }

  @override
  Future<SmbBackendStat> stat(String path) async {
    final stat = await _pool.stat(path);
    return SmbBackendStat(
      exists: true,
      isDirectory: stat.isDirectory,
      size: stat.size,
      modified: stat.modified,
    );
  }

  @override
  Future<bool> exists(String path) => _pool.exists(path);

  @override
  Future<Uint8List> read(String path) => _pool.readFile(path);

  @override
  Future<void> write(String path, Uint8List bytes) =>
      _pool.writeFile(path, bytes);

  @override
  Future<void> rename(String from, String to) => _pool.rename(from, to);

  @override
  Future<void> deleteFile(String path) => _pool.deleteFile(path);

  @override
  Future<void> mkdir(String path) => _pool.mkdir(path);

  @override
  Future<void> rmdir(String path) => _pool.rmdir(path);

  @override
  Future<void> disconnect() => _pool.disconnect();
}
