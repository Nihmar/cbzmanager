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

  /// Operations currently holding the backend, and the completer [disconnect]
  /// waits on before closing it (`_idle` is set only while waiting).
  int _pending = 0;
  Completer<void>? _idle;

  @override
  String get scheme => 'smb';

  Future<SmbBackend> _ensureBackend() {
    final existing = _backendFuture;
    if (existing != null) return existing;
    final future = _connect(config);
    _backendFuture = future;
    return future;
  }

  /// Runs [op] on the backend while counting it as in flight, so a concurrent
  /// [disconnect] waits for it instead of closing the pool under its feet.
  Future<T> _withBackend<T>(Future<T> Function(SmbBackend) op) async {
    _pending++;
    try {
      return await op(await _ensureBackend());
    } finally {
      _pending--;
      if (_pending == 0) {
        _idle?.complete();
        _idle = null;
      }
    }
  }

  /// Closes the backend. Safe to call more than once.  A connect that is still
  /// in flight is awaited first, then any operation already running is awaited
  /// before the pool is closed.
  Future<void> disconnect() async {
    final future = _backendFuture;
    _backendFuture = null;
    if (future == null) return;
    final SmbBackend backend;
    try {
      backend = await future;
    } catch (_) {
      // The connect itself failed: nothing to release.
      return;
    }
    if (_pending > 0) {
      final idle = Completer<void>();
      _idle = idle;
      await idle.future;
    }
    await backend.disconnect();
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
    final entries = await _withBackend((b) => b.list(_rel(dir)));
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
  Future<VfsStat> stat(String path) => _withBackend((backend) async {
    final rel = _rel(path);
    if (!await backend.exists(rel)) return const VfsStat.missing();
    final stat = await backend.stat(rel);
    return VfsStat(
      exists: true,
      isDirectory: stat.isDirectory,
      size: stat.size,
      modified: stat.modified,
    );
  });

  @override
  Future<bool> exists(String path) => _withBackend((b) => b.exists(_rel(path)));

  @override
  Future<Uint8List> readAll(String path) =>
      _withBackend((b) => b.read(_rel(path)));

  @override
  Future<void> writeAll(String path, List<int> bytes) =>
      _withBackend((backend) => _write(backend, _rel(path), bytes));

  /// Publishes [bytes] to [rel] without ever leaving the destination missing.
  ///
  /// SMB2/libsmb2 has no atomic replace (rename fails on an existing target),
  /// so the previous file is first renamed aside, the temp file is renamed
  /// into place and only then the aside copy is deleted.  A failed final
  /// rename restores the original instead of deleting it.
  static Future<void> _write(
    SmbBackend backend,
    String rel,
    List<int> bytes,
  ) async {
    final tmp = '$rel.new';
    final old = '$rel.old';
    await backend.write(tmp, Uint8List.fromList(bytes));
    final hadTarget = await backend.exists(rel);
    if (hadTarget) {
      if (await backend.exists(old)) await backend.deleteFile(old);
      await backend.rename(rel, old);
    }
    try {
      await backend.rename(tmp, rel);
    } catch (_) {
      // Restore the original before reporting the failure; its copy was
      // never deleted, so the worst case leaves <rel>.old on the share.
      if (hadTarget) {
        try {
          await backend.rename(old, rel);
        } catch (_) {
          // Best-effort restore; keep the .old copy for manual recovery.
        }
      }
      try {
        if (await backend.exists(tmp)) await backend.deleteFile(tmp);
      } catch (_) {
        // Best-effort cleanup; the original error is the one to report.
      }
      rethrow;
    }
    if (hadTarget) {
      try {
        await backend.deleteFile(old);
      } catch (_) {
        // The destination is already the new file; a stale .old is harmless.
      }
    }
  }

  @override
  Future<void> rename(String from, String to) =>
      _withBackend((b) => b.rename(_rel(from), _rel(to)));

  @override
  Future<void> delete(String path) => _withBackend((backend) async {
    final rel = _rel(path);
    final stat = await backend.exists(rel) ? await backend.stat(rel) : null;
    if (stat == null) return;
    if (stat.isDirectory) {
      await backend.rmdir(rel);
    } else {
      await backend.deleteFile(rel);
    }
  });

  @override
  Future<void> mkdir(String path) => _withBackend((b) => b.mkdir(_rel(path)));
}
