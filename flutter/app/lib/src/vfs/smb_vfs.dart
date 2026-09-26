import 'dart:typed_data';

import 'package:dart_smb2/dart_smb2.dart';

import 'vfs.dart';

/// Connection parameters for an SMB2/3 share.
///
/// Passwords are supplied by the caller and kept in memory only: the app does
/// not persist them (the connect dialog asks every time).
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
/// [close] (or [disconnect]) releases it and is called when the browsing
/// source is replaced.
class SmbVfs extends Vfs {
  SmbVfs(this.config);

  final SmbConfig config;

  /// Pending/live pool.  Stored as a Future so concurrent callers await the
  /// same connection instead of racing two `Smb2Pool.connect` calls (the
  /// second used to overwrite the first, leaking its worker isolates).
  Future<Smb2Pool>? _poolFuture;

  @override
  String get scheme => 'smb';

  Future<Smb2Pool> _ensurePool() {
    final existing = _poolFuture;
    if (existing != null) return existing;
    final future = Smb2Pool.connect(
      host: config.host,
      share: config.share,
      user: config.user,
      password: config.password,
      domain: config.domain,
      workers: config.workers,
    );
    _poolFuture = future;
    return future;
  }

  /// Closes the worker pool. Safe to call more than once.  A connect that is
  /// still in flight is awaited first, so the pool is closed either way.
  Future<void> disconnect() async {
    final future = _poolFuture;
    _poolFuture = null;
    if (future == null) return;
    try {
      final pool = await future;
      await pool.disconnect();
    } catch (_) {
      // The connect itself failed: nothing to release.
    }
  }

  @override
  Future<void> close() => disconnect();

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
    final rel = _rel(path);
    final tmp = '$rel.new';
    try {
      // Write to a sibling temp file first: `writeFile` opens the
      // destination with truncate, so a dropped connection mid-write would
      // destroy the archive.  SMB2/libsmb2 has no atomic replace (rename
      // fails on an existing target), hence delete-then-rename; a crash
      // between the two steps leaves the temp file instead of a truncated
      // original.
      await pool.writeFile(tmp, Uint8List.fromList(bytes));
      if (await pool.exists(rel)) {
        await pool.deleteFile(rel);
      }
      await pool.rename(tmp, rel);
    } catch (_) {
      try {
        if (await pool.exists(tmp)) await pool.deleteFile(tmp);
      } catch (_) {
        // Best-effort cleanup; the original error is the one to report.
      }
      rethrow;
    }
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
