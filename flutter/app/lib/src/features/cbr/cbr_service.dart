import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import '../../native/cbr_reader.dart';
import '../../util/cpu.dart';
import '../../vfs/vfs.dart';
import 'cbr_isolate.dart';

/// Outcome of converting one CBR file.
class CbrConvertOutcome {
  const CbrConvertOutcome({
    required this.name,
    this.success = false,
    this.pages = 0,
    this.skipped = false,
    this.deletedSource = false,
    this.error,
  });

  final String name;
  final bool success;
  final int pages;
  final bool skipped;
  final bool deletedSource;
  final String? error;
}

/// Batch CBR→CBZ conversion (entirely in RAM). Each file is independent, so the
/// output is deterministic for any thread count; per-file failures never abort
/// the batch, and the source is deleted only after the target was written.
class CbrConvertService {
  const CbrConvertService();

  static const int maxThreads = 4;

  Future<List<CbrConvertOutcome>> convertMany(
    Vfs vfs,
    String dir,
    List<String> cbrNames, {
    required bool skipExisting,
    required bool deleteSource,
    int threads = 0,
    void Function(int percent, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = cbrNames.length;
    if (total == 0) return const <CbrConvertOutcome>[];

    final slots = List<CbrConvertOutcome?>.filled(total, null);
    var done = 0;

    if (!CbrReader.isSupported) {
      return <CbrConvertOutcome>[
        for (final name in cbrNames)
          CbrConvertOutcome(
            name: name,
            error: 'CBR support requires libarchive, which is not available',
          ),
      ];
    }

    final requested = threads <= 0 ? onlineCpuCount() : threads;
    final limit = requested.clamp(1, maxThreads);
    final effective = limit < total ? limit : total;
    final pool = Pool(effective);

    try {
      await Future.wait(
        List.generate(total, (i) async {
          await pool.withResource(() async {
            final name = cbrNames[i];
            if (isCancelled?.call() ?? false) return;
            final targetName = p.setExtension(name, '.cbz');
            final targetPath = p.join(dir, targetName);
            final sourcePath = p.join(dir, name);

            try {
              if (skipExisting && await vfs.exists(targetPath)) {
                slots[i] = CbrConvertOutcome(
                  name: name,
                  success: true,
                  skipped: true,
                );
              } else {
                final bytes = await vfs.readAll(sourcePath);
                final result = await convertCbrInIsolate(bytes);
                final output = result[0] as Uint8List?;
                if (output == null) {
                  slots[i] = CbrConvertOutcome(
                    name: name,
                    error: 'No images found',
                  );
                } else {
                  await vfs.writeAll(targetPath, output);
                  var deleted = false;
                  if (deleteSource) {
                    await vfs.delete(sourcePath);
                    deleted = true;
                  }
                  slots[i] = CbrConvertOutcome(
                    name: name,
                    success: true,
                    pages: result[1]! as int,
                    deletedSource: deleted,
                  );
                }
              }
            } catch (e) {
              slots[i] = CbrConvertOutcome(name: name, error: '$e');
            }
            done++;
            onProgress?.call(done * 100 ~/ total, 'Converted $done/$total');
          });
        }),
      );
    } finally {
      pool.close();
    }

    return slots.whereType<CbrConvertOutcome>().toList(growable: false);
  }
}
