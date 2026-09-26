import 'dart:typed_data';

/// A virtual-filesystem error (missing file, permission, remote failure).
class VfsException implements Exception {
  const VfsException(this.message);

  final String message;

  @override
  String toString() => 'VfsException: $message';
}

/// One directory entry as seen through a [Vfs].
class VfsEntry {
  const VfsEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  /// Bare entry name (no parent path).
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
}

/// Metadata for a single path.
class VfsStat {
  const VfsStat({
    required this.exists,
    this.isDirectory = false,
    this.size = 0,
    this.modified,
  });

  const VfsStat.missing()
      : exists = false,
        isDirectory = false,
        size = 0,
        modified = null;

  final bool exists;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
}

/// A byte-oriented virtual filesystem.
///
/// The engine only ever needs whole-file reads and writes, so this small
/// surface is enough to make local folders, Android SAF trees and SMB shares
/// interchangeable. Implementations must never leak platform handles to
/// callers.
abstract class Vfs {
  /// Allows concrete implementations with `const` constructors (e.g.
  /// `LocalVfs`).
  const Vfs();

  /// Scheme identifier: `file`, `memory`, `content`, `smb`, ...
  String get scheme;

  /// Non-recursive directory listing.
  Future<List<VfsEntry>> list(String dir);

  Future<VfsStat> stat(String path);

  Future<bool> exists(String path);

  Future<Uint8List> readAll(String path);

  Future<void> writeAll(String path, List<int> bytes);

  Future<void> rename(String from, String to);

  Future<void> delete(String path);

  Future<void> mkdir(String path);

  /// Releases any underlying resources (connections, worker pools).  The
  /// default is a no-op; implementations that own resources override it.
  /// Called by [ArchiveSource] owners when a source is replaced.
  Future<void> close() async {}
}
