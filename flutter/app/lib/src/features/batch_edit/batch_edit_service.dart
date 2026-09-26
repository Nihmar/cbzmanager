import 'dart:typed_data';

import 'package:pool/pool.dart';

import '../../engine/image_edit.dart';
import '../../util/cpu.dart';
import '../../vfs/vfs.dart';
import '../../vfs/workspace.dart';
import '../browser/archive_item.dart';
import 'batch_edit_isolate.dart';

/// Uniform batch edit applied to every page of an archive.
class BatchEditParams {
  const BatchEditParams({
    this.percent = 0,
    this.adjust = ColorAdjust.neutral,
    this.split = false,
    this.horizontal = true,
    this.pieces = 2,
    this.backup = true,
  });

  /// Resize percentage (0 = no resize).
  final int percent;
  final ColorAdjust adjust;
  final bool split;
  final bool horizontal;
  final int pieces;
  final bool backup;

  bool get isNeutral => percent <= 0 && adjust.isNeutral && !split;

  Map<String, Object?> toMap() => <String, Object?>{
    'percent': percent,
    'invert': adjust.invert,
    'grayscale': adjust.grayscale,
    'sepia': adjust.sepia,
    'rGain': adjust.rGain,
    'gGain': adjust.gGain,
    'bGain': adjust.bGain,
    'saturation': adjust.saturation,
    'contrast': adjust.contrast,
    'brightness': adjust.brightness,
    'gamma': adjust.gamma,
    'split': split,
    'horizontal': horizontal,
    'pieces': pieces,
  };
}

class BatchEditOutcome {
  const BatchEditOutcome({
    required this.item,
    required this.success,
    this.pages = 0,
    this.error,
  });

  final ArchiveItem item;
  final bool success;
  final int pages;
  final String? error;
}

/// Applies a [BatchEditParams] to each selected archive (resize → colours →
/// split), renumbers pages and publishes through the [Vfs]. Files are processed
/// concurrently on isolates; each file is independent, so the result is
/// deterministic for any thread count.
class BatchEditService {
  const BatchEditService();

  static const _workspace = Workspace();
  static const int maxThreads = 4;

  Future<List<BatchEditOutcome>> applyMany(
    Vfs vfs,
    List<ArchiveItem> items,
    BatchEditParams params, {
    int threads = 0,
    void Function(int percent, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = items.length;
    if (total == 0) return const <BatchEditOutcome>[];
    if (params.isNeutral) {
      return <BatchEditOutcome>[
        for (final item in items) BatchEditOutcome(item: item, success: true),
      ];
    }

    final slots = List<BatchEditOutcome?>.filled(total, null);
    var done = 0;
    final requested = threads <= 0 ? onlineCpuCount() : threads;
    final limit = requested.clamp(1, maxThreads);
    final effective = limit < total ? limit : total;
    final pool = Pool(effective);

    try {
      await Future.wait(
        List.generate(total, (i) async {
          await pool.withResource(() async {
            final item = items[i];
            if (isCancelled?.call() ?? false) return;
            try {
              final bytes = await vfs.readAll(item.path);
              final result = await batchEditInIsolate(bytes, params.toMap());
              final output = result[0] as Uint8List?;
              if (output == null) {
                slots[i] = BatchEditOutcome(
                  item: item,
                  success: false,
                  error: 'No images found',
                );
              } else {
                await _workspace.publish(
                  vfs,
                  item.path,
                  output,
                  backup: params.backup,
                );
                slots[i] = BatchEditOutcome(
                  item: item,
                  success: true,
                  pages: result[1]! as int,
                );
              }
            } catch (e) {
              slots[i] = BatchEditOutcome(
                item: item,
                success: false,
                error: '$e',
              );
            }
            done++;
            onProgress?.call(done * 100 ~/ total, 'Edited $done/$total');
          });
        }),
      );
    } finally {
      pool.close();
    }

    return slots.whereType<BatchEditOutcome>().toList(growable: false);
  }
}
