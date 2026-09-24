import '../../engine/comicinfo.dart';
import '../../engine/engine.dart';
import '../../vfs/vfs.dart';
import '../../vfs/workspace.dart';
import '../browser/archive_item.dart';

/// Result of reading ComicInfo.xml from one archive.
class ComicInfoReadResult {
  const ComicInfoReadResult({
    required this.item,
    this.info,
    this.found = false,
    this.error,
  });

  final ArchiveItem item;
  final ComicInfo? info;
  final bool found;
  final String? error;
}

/// Outcome of a batch ComicInfo operation.
class ComicInfoBatchResult {
  const ComicInfoBatchResult({
    this.scanned = 0,
    this.changed = 0,
    this.skipped = 0,
    this.errors = const <String>[],
  });

  final int scanned;
  final int changed;
  final int skipped;
  final List<String> errors;
}

/// Reads, writes and removes ComicInfo.xml. All archive I/O goes through
/// [Workspace], so it works unchanged on local folders and SMB shares.
class ComicInfoService {
  const ComicInfoService(this.engine);

  final CbzEngine engine;
  static const _workspace = Workspace();

  Future<ComicInfoReadResult> read(Vfs vfs, ArchiveItem item) async {
    try {
      final data = await _workspace.read(vfs, item.path);
      final info = await engine.readComicInfo(data);
      return ComicInfoReadResult(
        item: item,
        info: info,
        found: info != null,
      );
    } catch (e) {
      return ComicInfoReadResult(item: item, error: '$e');
    }
  }

  Future<void> write(
    Vfs vfs,
    ArchiveItem item,
    ComicInfo info, {
    bool backup = true,
  }) async {
    final data = await _workspace.read(vfs, item.path);
    final updated = await engine.writeComicInfo(data, info);
    await _workspace.publish(vfs, item.path, updated.bytes, backup: backup);
  }

  /// Removes ComicInfo.xml. Returns false when it was not present.
  Future<bool> remove(Vfs vfs, ArchiveItem item, {bool backup = true}) async {
    final data = await _workspace.read(vfs, item.path);
    final scan = await engine.scanComicInfo(data);
    if (!scan.found) return false;
    final updated = await engine.stripComicInfo(data);
    await _workspace.publish(vfs, item.path, updated.bytes, backup: backup);
    return true;
  }

  /// Removes ComicInfo.xml from every archive that has one, reporting progress.
  Future<ComicInfoBatchResult> removeMany(
    Vfs vfs,
    List<ArchiveItem> items, {
    bool backup = true,
    void Function(int done, int total, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var scanned = 0;
    var changed = 0;
    var skipped = 0;
    final errors = <String>[];
    final total = items.length;

    for (var i = 0; i < total; i++) {
      if (isCancelled?.call() ?? false) break;
      final item = items[i];
      onProgress?.call(i, total, 'Scanning ${item.name}');
      scanned++;
      try {
        final removed = await remove(vfs, item, backup: backup);
        if (removed) {
          changed++;
        } else {
          skipped++;
        }
      } catch (e) {
        errors.add('${item.name}: $e');
      }
    }
    onProgress?.call(scanned, total, 'Done');
    return ComicInfoBatchResult(
      scanned: scanned,
      changed: changed,
      skipped: skipped,
      errors: errors,
    );
  }
}
