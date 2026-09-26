import 'dart:async';
import 'dart:typed_data';

import 'smb/dart_smb2_backend.dart';
import 'smb/smb_backend.dart';
import 'vfs.dart';

export 'smb/smb_backend.dart' show SmbConfig;

/// Builds the backend for a share.  Defaults to the dart_smb2 adapter; tests
/// inject a fake to exercise this class without a live share.
typedef SmbBackendFactory = Future<SmbBackend> Function(SmbConfig config);

/// [Vfs] backed by an SMB2/3 share.
///
/// Paths are share-relative; a leading `/` is accepted and stripped.  The
/// backend is opened lazily on first use and reused for the lifetime of the
/// instance; [close] (or [disconnect]) releases it and is called when the
/// browsing source is replaced.
class SmbVfs extends Vfs {
  SmbVfs(this.config, {SmbBackendFactory? connect})
    : _connect = connect ?? DartSmb2Backend.connect;

  final SmbConfig config;
  final SmbBackendFactory _connect;

  /// Pending/live backend.  Stored as a Future so concurrent callers await the
  /// same connection instead of racing two connects (the second used to
  /// overwrite the first, leaking its worker isolates).
  Future<SmbBackend>? _backendFuture;

  @override
  String get scheme => 'smb';

  Future<SmbBackend> _ensureBackend() {
    final existing = _backendFuture;
    if (existing != null) return existing;
    final future = _connect(config);
    _backendFuture = future;
    return future;
  }

  /// Closes the backend. Safe to call more than once.  A connect that is still
  /// in flight is awaited first, so the backend is closed either way.
  Future<void> disconnect() async {
    final future = _backendFuture;
    _backendFuture = null;
    if (future == null) return;
    try {
      final backend = await future;
      await backend.disconnect();
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
    final backend = await _ensureBackend();
    final entries = await backend.list(_rel(dir));
    return <VfsEntry>[
      for (final entry in entries)
        VfsEntry(
          name: entry.name,
          isDirectory: entry.isDirectory,
          size: entry.size,
          modified: entry.modified,
        ),
    ];
  }

  @override
  Future<VfsStat> stat(String path) async {
    final backend = await _ensureBackend();
    final rel = _rel(path);
    if (!await backend.exists(rel)) return const VfsStat.missing();
    final stat = await backend.stat(rel);
    return VfsStat(
      exists: true,
      isDirectory: stat.isDirectory,
      size: stat.size,
      modified: stat.modified,
    );
  }

  @override
  Future<bool> exists(String path) async {
    final backend = await _ensureBackend();
    return backend.exists(_rel(path));
  }

  @override
  Future<Uint8List> readAll(String path) async {
    final backend = await _ensureBackend();
    return backend.read(_rel(path));
  }

  @override
  Future<void> writeAll(String path, List<int> bytes) async {
    final backend = await _ensureBackend();
    final rel = _rel(path);
    final tmp = '$rel.new';
    try {
      // Write to a sibling temp file first: the backend's write opens the
      // destination with truncate, so a dropped connection mid-write would
      // destroy the archive.  SMB2/libsmb2 has no atomic replace (rename
      // fails on an existing target), hence delete-then-rename; a crash
      // between the two steps leaves the temp file instead of a truncated
      // original.
      await backend.write(tmp, Uint8List.fromList(bytes));
      if (await backend.exists(rel)) {
        await backend.deleteFile(rel);
      }
      await backend.rename(tmp, rel);
    } catch (_) {
      try {
        if (await backend.exists(tmp)) await backend.deleteFile(tmp);
      } catch (_) {
        // Best-effort cleanup; the original error is the one to report.
      }
      rethrow;
    }
  }

  @override
  Future<void> rename(String from, String to) async {
    final backend = await _ensureBackend();
    await backend.rename(_rel(from), _rel(to));
  }

  @override
  Future<void> delete(String path) async {
    final backend = await _ensureBackend();
    final rel = _rel(path);
    final stat = await backend.exists(rel) ? await backend.stat(rel) : null;
    if (stat == null) return;
    if (stat.isDirectory) {
      await backend.rmdir(rel);
    } else {
      await backend.deleteFile(rel);
    }
  }

  @override
  Future<void> mkdir(String path) async {
    final backend = await _ensureBackend();
    await backend.mkdir(_rel(path));
  }
}
