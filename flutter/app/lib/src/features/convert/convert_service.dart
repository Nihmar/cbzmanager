import 'dart:typed_data';

import 'package:pool/pool.dart';

import '../../util/cpu.dart';
import '../../vfs/vfs.dart';
import '../../vfs/workspace.dart';
import '../browser/archive_item.dart';
import 'convert_isolate.dart';

/// Outcome of converting one archive.
class ConvertOutcome {
  const ConvertOutcome({
    required this.item,
    this.converted = 0,
    this.kept = 0,
    this.inputBytes = 0,
    this.outputBytes = 0,
    this.error,
    this.skipped = false,
  });

  final ArchiveItem item;
  final int converted;
  final int kept;
  final int inputBytes;
  final int outputBytes;
  final String? error;
  final bool skipped;

  bool get success => error == null && !skipped;
}

/// Batch WebP conversion (quality 75, only-if-smaller, ComicInfo filtered, pages
/// renumbered). Files are converted concurrently on isolates; each file's output
/// is independent, so the result is deterministic for any thread count.
class ConvertService {
  const ConvertService();

  static const _workspace = Workspace();

  /// Reference default (quality 75, only-if-smaller, skip existing WebP,
  /// strip ComicInfo.xml, renumber pages).
  static const int defaultQuality = 75;
  static const int maxThreads = 8;

  Future<List<ConvertOutcome>> convertMany(
    Vfs vfs,
    List<ArchiveItem> items, {
    required bool backup,
    int threads = 0,
    int quality = defaultQuality,
    bool onlyIfSmaller = true,
    bool skipExistingWebp = true,
    bool removeComicInfo = true,
    bool renumber = true,
    void Function(int done, int total, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final total = items.length;
    if (total == 0) return const <ConvertOutcome>[];

    final requested = threads <= 0 ? onlineCpuCount() : threads;
    final limit = requested.clamp(1, maxThreads);
    final effective = limit < total ? limit : total;
    final pool = Pool(effective);
    final slots = List<ConvertOutcome?>.filled(total, null);
    var done = 0;

    try {
      await Future.wait(
        List.generate(total, (i) async {
          await pool.withResource(() async {
            final item = items[i];
            if (isCancelled?.call() ?? false) {
              slots[i] = ConvertOutcome(item: item, skipped: true);
              return;
            }
            try {
              final bytes = await vfs.readAll(item.path);
              final name = item.name;
              final result = await convertInIsolate(
                bytes,
                name,
                quality: quality,
                onlyIfSmaller: onlyIfSmaller,
                skipExistingWebp: skipExistingWebp,
                removeComicInfo: removeComicInfo,
                renumber: renumber,
              );
              final output = result[0] as Uint8List?;
              final fileError = result[3] as String?;
              if (fileError != null) {
                slots[i] = ConvertOutcome(item: item, error: fileError);
              } else if (output == null) {
                // No images: a benign no-op like the reference, not a
                // failure (the CLI must exit 0 for it).
                slots[i] = ConvertOutcome(item: item, skipped: true);
              } else {
                await _workspace.publish(
                  vfs,
                  item.path,
                  output,
                  backup: backup,
                );
                slots[i] = ConvertOutcome(
                  item: item,
                  converted: result[1]! as int,
                  kept: result[2]! as int,
                  inputBytes: bytes.length,
                  outputBytes: output.length,
                );
              }
            } catch (e) {
              slots[i] = ConvertOutcome(item: item, error: '$e');
            }
            done++;
            onProgress?.call(done, total, item.name);
          });
        }),
      );
    } finally {
      pool.close();
    }

    return slots.whereType<ConvertOutcome>().toList(growable: false);
  }
}
