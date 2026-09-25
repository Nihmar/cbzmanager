import 'package:pool/pool.dart';

import '../../engine/comicinfo.dart';
import '../../engine/engine.dart';
import '../../util/cpu.dart';
import '../../vfs/vfs.dart';
import '../../vfs/workspace.dart';
import '../browser/archive_item.dart';
import 'comicinfo_isolate.dart';

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
///
/// The ZIP work happens in a background isolate (see [comicinfo_isolate]): a
/// single archive rewrite takes hundreds of milliseconds, so running it inline
/// froze the UI. Batch removals claim files from a pool (0 = one worker per CPU
/// core, capped at [maxThreads]; every worker holds one whole archive in RAM),
/// and results are aggregated in source order, so counts and errors do not
/// depend on the worker count.
class ComicInfoService {
  const ComicInfoService(this.engine);

  final CbzEngine engine;
  static const _workspace = Workspace();
  static const int maxThreads = 4;

  Future<ComicInfoReadResult> read(Vfs vfs, ArchiveItem item) async {
    try {
      final data = await _workspace.read(vfs, item.path);
      final xml = await readComicInfoXmlInIsolate(
        data.bytes,
        data.name,
        engine.id,
      );
      return ComicInfoReadResult(
        item: item,
        info: xml == null ? null : ComicInfo.parse(xml),
        found: xml != null,
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
    final updated = await writeComicInfoInIsolate(
      data.bytes,
      data.name,
      info.toXml(),
      engine.id,
    );
    await _workspace.publish(vfs, item.path, updated, backup: backup);
  }

  /// Removes ComicInfo.xml. Returns false when it was not present.
  Future<bool> remove(Vfs vfs, ArchiveItem item, {bool backup = true}) async {
    final data = await _workspace.read(vfs, item.path);
    if (!await scanComicInfoInIsolate(data.bytes, data.name, engine.id)) {
      return false;
    }
    final updated = await stripComicInfoInIsolate(
      data.bytes,
      data.name,
      engine.id,
    );
    await _workspace.publish(vfs, item.path, updated, backup: backup);
    return true;
  }

  /// Removes ComicInfo.xml from every archive that has one, reporting progress.
  Future<ComicInfoBatchResult> removeMany(
    Vfs vfs,
    List<ArchiveItem> items, {
    bool backup = true,
    int threads = 0,
    void Function(int done, int total, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = items.length;
    if (total == 0) return const ComicInfoBatchResult();

    final requested = threads <= 0 ? onlineCpuCount() : threads;
    final limit = requested.clamp(1, maxThreads);
    final effective = limit < total ? limit : total;
    final pool = Pool(effective);
    final slots = List<({bool removed, String? error})?>.filled(total, null);
    var done = 0;

    try {
      await Future.wait(
        List.generate(total, (i) async {
          await pool.withResource(() async {
            if (isCancelled?.call() ?? false) return;
            final item = items[i];
            try {
              final removed = await remove(vfs, item, backup: backup);
              slots[i] = (removed: removed, error: null);
            } catch (e) {
              slots[i] = (removed: false, error: '${item.name}: $e');
            }
            done++;
            onProgress?.call(done, total, item.name);
          });
        }),
      );
    } finally {
      pool.close();
    }

    var scanned = 0;
    var changed = 0;
    var skipped = 0;
    final errors = <String>[];
    for (final slot in slots) {
      if (slot == null) continue;
      scanned++;
      if (slot.error != null) {
        errors.add(slot.error!);
      } else if (slot.removed) {
        changed++;
      } else {
        skipped++;
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
