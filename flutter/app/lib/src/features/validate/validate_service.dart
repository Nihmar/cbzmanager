import 'package:pool/pool.dart';

import '../../engine/engine.dart';
import '../../engine/models.dart';
import '../../util/cpu.dart';
import '../../vfs/vfs.dart';
import '../browser/archive_item.dart';
import 'validate_isolate.dart';

/// One archive's validation outcome.
class ValidateOutcome {
  const ValidateOutcome({required this.item, required this.result});

  final ArchiveItem item;
  final ValidateResult result;
}

/// Runs deep validation over a set of archives, reporting progress and
/// honouring cooperative cancellation. Never throws: per-file failures become
/// invalid results.
///
/// Each file is decoded in its own background isolate, so a folder of large
/// archives never blocks the UI isolate. Results are written into per-source
/// slots and compacted in archive order after the join, which makes the outcome
/// order independent of the worker count (0 = one worker per CPU core, capped
/// at [maxThreads]; every worker holds one whole archive plus one decoded page
/// in RAM).
class ValidateService {
  const ValidateService(this.engine);

  final CbzEngine engine;

  static const int maxThreads = 8;

  Future<List<ValidateOutcome>> validateMany(
    Vfs vfs,
    List<ArchiveItem> items, {
    int threads = 0,
    void Function(int done, int total, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = items.length;
    if (total == 0) return const <ValidateOutcome>[];

    final requested = threads <= 0 ? onlineCpuCount() : threads;
    final limit = requested.clamp(1, maxThreads);
    final effective = limit < total ? limit : total;
    final pool = Pool(effective);
    final slots = List<ValidateOutcome?>.filled(total, null);
    final engineId = engine.id;
    var done = 0;

    try {
      await Future.wait(
        List.generate(total, (i) async {
          await pool.withResource(() async {
            if (isCancelled?.call() ?? false) return;
            final item = items[i];
            ValidateResult result;
            try {
              final bytes = await vfs.readAll(item.path);
              final raw = await validateInIsolate(bytes, item.name, engineId);
              result = ValidateResult(
                name: item.name,
                valid: raw[0]! as bool,
                imageCount: raw[1]! as int,
                error: raw[2] as String?,
                errors: <PageError>[
                  for (final pair in raw[3]! as List<List<String>>)
                    PageError(pair[0], pair[1]),
                ],
              );
            } catch (e) {
              result = ValidateResult(
                name: item.name,
                valid: false,
                error: '$e',
              );
            }
            slots[i] = ValidateOutcome(item: item, result: result);
            done++;
            onProgress?.call(done, total, item.name);
          });
        }),
      );
    } finally {
      pool.close();
    }

    final outcomes = slots.whereType<ValidateOutcome>().toList(growable: false);
    onProgress?.call(outcomes.length, total, 'Done');
    return outcomes;
  }
}
