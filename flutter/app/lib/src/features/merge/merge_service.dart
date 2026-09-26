import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import '../../engine/merge.dart';
import '../../util/cpu.dart';
import '../../vfs/vfs.dart';
import '../../vfs/workspace.dart';
import 'merge_isolate.dart';

/// Outcome of a merge run.
class MergeOutcome {
  const MergeOutcome({
    required this.success,
    this.volumesCreated = 0,
    this.volumes = const <String>[],
    this.error,
  });

  final bool success;
  final int volumesCreated;
  final List<String> volumes;
  final String? error;
}

/// Chapter-to-volume merge. Planning is sequential and I/O-free; volumes are
/// built concurrently (each independent, so the output is deterministic for any
/// thread count) and written through the [Vfs], so it works on local folders and
/// SMB shares alike.
class MergeService {
  const MergeService();

  static const _workspace = Workspace();
  static const int maxThreads = 4;

  Future<MergeOutcome> merge(
    Vfs vfs,
    String dir,
    MergeOptions options, {
    void Function(int percent, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final entries = await vfs.list(dir);
    final files = <String>[
      for (final entry in entries)
        if (!entry.isDirectory && entry.name.toLowerCase().endsWith('.cbz'))
          entry.name,
    ];

    final planResult = planMerge(files, options);
    if (planResult.error != null) {
      return MergeOutcome(success: false, error: planResult.error);
    }
    final plan = planResult.plan!;
    final total = plan.batches.length;
    if (total == 0) {
      return const MergeOutcome(
        success: false,
        error: 'Not enough chapters for a full volume',
      );
    }

    final wrote = List<bool>.filled(total, false);
    final errors = List<String?>.filled(total, null);
    var done = 0;
    final requested = options.threads <= 0 ? onlineCpuCount() : options.threads;
    final limit = requested.clamp(1, maxThreads);
    final effective = limit < total ? limit : total;
    final pool = Pool(effective);

    try {
      await Future.wait(
        List.generate(total, (i) async {
          await pool.withResource(() async {
            if (isCancelled?.call() ?? false) return;
            final batch = plan.batches[i];
            try {
              final target = p.join(dir, batch.fileName);
              // A volume name that already existed may be a file this run must
              // not destroy: only a target this run created is marked for
              // rollback-deletion before the write.  A failed write over a
              // pre-existing file leaves it alone (the reference's LocalVfs
              // write is atomic; a direct SMB write cannot be restored
              // anyway).
              final existedBefore = await vfs.exists(target);
              final archives = <Uint8List>[];
              final numbers = <int>[];
              for (final file in batch.files) {
                archives.add(await vfs.readAll(p.join(dir, file)));
                numbers.add(extractChapterNum(file));
              }
              final bytes = await buildVolumeInIsolate(
                archives,
                plan.seriesName,
                batch.volNum,
                numbers,
                options.generateComicInfo,
              );
              if (bytes != null) {
                // Mark before writing only when this run created the target,
                // so a partial write is rolled back too; a pre-existing
                // volume is marked after success (never delete it on
                // failure).  An empty batch (bytes == null) writes nothing
                // and stays unmarked.
                if (!existedBefore) wrote[i] = true;
                await vfs.writeAll(target, bytes);
                wrote[i] = true;
              }
            } catch (e) {
              errors[i] = '$e';
            } finally {
              done++;
              onProgress?.call(
                done * 100 ~/ total,
                'Building volumes ($done/$total)',
              );
            }
          });
        }),
      );
    } finally {
      pool.close();
    }

    final firstError = errors.firstWhere((e) => e != null, orElse: () => null);
    if (firstError != null) {
      for (var i = 0; i < total; i++) {
        if (!wrote[i]) continue;
        try {
          await vfs.delete(p.join(dir, plan.batches[i].fileName));
        } catch (_) {
          // best-effort rollback
        }
      }
      return MergeOutcome(
        success: false,
        error: 'Error during merge — created volumes have been removed '
            '($firstError)',
      );
    }

    await _cleanupSources(vfs, dir, plan, wrote, options.delete);

    final created = <String>[
      for (var i = 0; i < total; i++)
        if (wrote[i]) plan.batches[i].fileName,
    ];
    if (created.isEmpty && (isCancelled?.call() ?? false)) {
      // Cancelled before any volume was written: "not enough chapters" would
      // be a lie.
      return const MergeOutcome(success: false, error: 'Merge cancelled');
    }
    return MergeOutcome(
      success: created.isNotEmpty,
      volumesCreated: created.length,
      volumes: created,
      error: created.isEmpty ? 'Not enough chapters for a full volume' : null,
    );
  }

  /// Deletes or backs up the sources of every written volume. A guard re-checks
  /// the strict classification so volumes, backups and other series can never
  /// be touched.
  Future<void> _cleanupSources(
    Vfs vfs,
    String dir,
    MergePlan plan,
    List<bool> wrote,
    bool delete,
  ) async {
    final toClean = <String>[];
    for (var i = 0; i < plan.batches.length; i++) {
      if (wrote[i]) toClean.addAll(plan.batches[i].files);
    }
    for (final file in toClean) {
      final chapter = classifyChapter(file);
      if (chapter == null || chapter.series != plan.seriesName) continue;
      final path = p.join(dir, file);
      try {
        if (delete) {
          await vfs.delete(path);
        } else {
          await vfs.rename(path, _workspace.backupPath(path));
        }
      } catch (_) {
        // best-effort cleanup
      }
    }
  }
}
