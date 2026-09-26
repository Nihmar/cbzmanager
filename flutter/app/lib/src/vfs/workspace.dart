import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../engine/models.dart';
import 'vfs.dart';

/// Backup suffix used by the reference for in-place operations.
const String kBackupSuffix = '_OLD.cbz';

/// Reads a source archive, runs an in-RAM operation and publishes the result
/// back through the same [Vfs].
///
/// Because the engine is byte-oriented, "localize" is a whole-file read into
/// memory and "publish" is a whole-file write; no page is ever extracted to
/// disk. The same code therefore works for local folders, SAF content URIs and
/// SMB shares.
class Workspace {
  const Workspace();

  /// Reads [path] as archive bytes.
  Future<ArchiveData> read(Vfs vfs, String path) async {
    final bytes = await vfs.readAll(path);
    return ArchiveData(p.basename(path), bytes);
  }

  /// Path of the `_OLD.cbz` backup for [path].
  String backupPath(String path) => '${p.withoutExtension(path)}$kBackupSuffix';

  /// Publishes [bytes] to [path]. When [backup] is true and the target exists,
  /// it is first renamed to the `_OLD` backup (replacing any previous backup),
  /// matching the reference's `BackupFile`.
  Future<void> publish(
    Vfs vfs,
    String path,
    Uint8List bytes, {
    bool backup = true,
  }) async {
    if (backup && await vfs.exists(path)) {
      final old = backupPath(path);
      if (await vfs.exists(old)) {
        await vfs.delete(old);
      }
      await vfs.rename(path, old);
    }
    await vfs.writeAll(path, bytes);
  }
}
