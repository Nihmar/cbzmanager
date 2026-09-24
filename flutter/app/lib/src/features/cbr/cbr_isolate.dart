import 'dart:isolate';
import 'dart:typed_data';

import '../../engine/cbr_convert.dart';
import '../../engine/zip_ops.dart';
import '../../native/cbr_reader.dart';

/// Converts a CBR archive held in [bytes] to CBZ bytes, synchronously.
///
/// Returns `[outputBytes, pageCount]`; `outputBytes` is null when the archive
/// has no images. Throws (via [CbrReader]) when libarchive is unavailable or the
/// archive is unreadable. Synchronous on purpose so it can run in an isolate.
List<Object?> convertCbrIsolate(Uint8List bytes) {
  final entries = renumberCbrImages(CbrReader.collectEntries(bytes));
  if (entries.isEmpty) return <Object?>[null, 0];
  return <Object?>[writeZipEntries(entries), entries.length];
}

/// Runs [convertCbrIsolate] in a background isolate.
///
/// Top-level so the isolate closure captures only its argument (a background
/// closure created inside a `Pool.withResource` callback would capture the pool
/// and fail to send).
Future<List<Object?>> convertCbrInIsolate(Uint8List bytes) =>
    Isolate.run(() => convertCbrIsolate(bytes));
