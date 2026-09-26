import 'dart:typed_data';

import '../../engine/format.dart';
import '../../engine/page_model.dart';
import '../../engine/zip_ops.dart';
import '../../vfs/vfs.dart';
import '../../vfs/workspace.dart';

/// Loads and saves the in-memory page model for an archive.
class PageEditService {
  const PageEditService();

  static const _workspace = Workspace();

  /// Builds a model from an archive's image entries (origName == name).
  static PageEditModel loadModel(Uint8List archiveBytes) {
    final entries = collectZipEntries(archiveBytes);
    final pages = <PageState>[];
    var index = 0;
    for (final entry in entries) {
      if (!isImageExt(extensionOf(entry.name))) continue;
      pages.add(
        PageState(origName: entry.name, name: entry.name, origIndex: index++),
      );
    }
    return PageEditModel(pages);
  }

  /// Rebuilds [path] from [model] and publishes it (backup unless [backup] is
  /// false). Non-page entries (ComicInfo.xml, ...) are preserved.
  Future<void> save(
    Vfs vfs,
    String path,
    PageEditModel model, {
    bool renumber = true,
    bool backup = true,
  }) async {
    final entries = collectZipEntries(await vfs.readAll(path));
    final bytes = buildEditedArchive(entries, model, renumber: renumber);
    await _workspace.publish(vfs, path, bytes, backup: backup);
  }
}
