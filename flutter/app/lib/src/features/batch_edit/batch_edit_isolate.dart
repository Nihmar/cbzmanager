import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../engine/format.dart';
import '../../engine/image_edit.dart';
import '../../engine/models.dart';
import '../../engine/zip_ops.dart';

/// Applies a uniform batch edit to every image of an archive, synchronously.
///
/// [params] holds only primitives so the call is isolate-safe (a custom params
/// object could not be sent). Returns `[outputBytes, pageCount]`.
List<Object?> batchEditArchiveIsolate(
  Uint8List bytes,
  Map<String, Object?> params,
) {
  final adjust = ColorAdjust(
    invert: params['invert'] as bool? ?? false,
    grayscale: params['grayscale'] as bool? ?? false,
    sepia: params['sepia'] as bool? ?? false,
    rGain: params['rGain'] as double? ?? 1.0,
    gGain: params['gGain'] as double? ?? 1.0,
    bGain: params['bGain'] as double? ?? 1.0,
    saturation: params['saturation'] as double? ?? 1.0,
    contrast: params['contrast'] as double? ?? 1.0,
    brightness: params['brightness'] as double? ?? 0.0,
    gamma: params['gamma'] as double? ?? 1.0,
  );
  final percent = params['percent'] as int? ?? 0;
  final split = params['split'] as bool? ?? false;
  final horizontal = params['horizontal'] as bool? ?? true;
  final pieces = params['pieces'] as int? ?? 2;

  final entries = collectZipEntries(bytes);
  final output = <ZipEntryData>[];
  var pageNum = 0;

  for (final entry in entries) {
    final ext = extensionOf(entry.name);
    if (!isImageExt(ext)) continue;
    final decoded = img.decodeImage(entry.bytes);
    if (decoded == null) {
      // Never drop a page silently: the service turns this into a per-file
      // error and the archive is left untouched (a partial rewrite would
      // lose the undecodable page).
      throw StateError('Page ${entry.name} could not be decoded');
    }

    final targetExt = encodeExtFor(ext);
    final w = percent > 0
        ? (decoded.width * percent / 100).round().clamp(1, 1 << 20)
        : null;
    final h = percent > 0
        ? (decoded.height * percent / 100).round().clamp(1, 1 << 20)
        : null;
    final encoded = applyEditPipeline(
      decoded,
      width: w,
      height: h,
      adjust: adjust,
      split: split,
      horizontal: horizontal,
      pieces: pieces,
      targetExt: targetExt,
    );
    for (final piece in encoded) {
      pageNum++;
      output.add(ZipEntryData(formatPageName(pageNum, targetExt), piece));
    }
  }

  // Preserve non-image entries (e.g. ComicInfo.xml).
  for (final entry in entries) {
    if (!isImageExt(extensionOf(entry.name))) output.add(entry);
  }

  return <Object?>[writeZipEntries(output), pageNum];
}

/// Runs [batchEditArchiveIsolate] in a background isolate.
Future<List<Object?>> batchEditInIsolate(
  Uint8List bytes,
  Map<String, Object?> params,
) => Isolate.run(() => batchEditArchiveIsolate(bytes, params));
