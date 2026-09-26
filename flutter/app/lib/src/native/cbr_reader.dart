import 'dart:typed_data';

import '../engine/format.dart';
import '../engine/models.dart';
import '../vfs/vfs.dart';
import 'libarchive.dart';

/// High-level CBR (RAR) reader built on [Libarchive].
///
/// Mirrors the reference `uarchive.pas`: read-only, entirely in RAM, and
/// graceful when libarchive is absent.
class CbrReader {
  const CbrReader._();

  /// True when the platform can read CBR archives.
  static bool get isSupported => Libarchive.isAvailable;

  /// Reads every file entry of a CBR archive.
  ///
  /// Throws [VfsException] when libarchive is unavailable or the archive is
  /// unreadable (for example encrypted or corrupt).
  static List<ZipEntryData> collectEntries(Uint8List bytes) {
    final lib = Libarchive.tryLoad();
    if (lib == null) {
      throw const VfsException(
        'CBR support requires libarchive, which is not available',
      );
    }
    try {
      return lib.collectEntries(bytes);
    } on StateError catch (e) {
      throw VfsException('Unable to read CBR archive: ${e.message}');
    }
  }

  /// Convenience: only the image entries, in archive order.
  static List<ZipEntryData> imageEntries(Uint8List bytes) =>
      collectEntries(bytes)
          .where((e) => isImageExt(_ext(e.name)))
          .toList(growable: false);

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }
}
