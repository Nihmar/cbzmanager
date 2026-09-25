import 'dart:isolate';
import 'dart:typed_data';

import '../../engine/engine_registry.dart';
import '../../engine/models.dart';

/// Runs [validateArchiveBytes] in a background isolate.
///
/// This wrapper is a top-level function on purpose: a closure built inside a
/// `Pool.withResource` callback would capture the pool (and its internal
/// `Completer`), which cannot cross an isolate boundary.
Future<List<Object?>> validateInIsolate(
  Uint8List bytes,
  String name,
  String engineId,
) =>
    Isolate.run(() => validateArchiveBytes(bytes, name, engineId));

/// Synchronous deep-validation core, safe to run inside a background isolate.
///
/// Only sendable values cross the isolate boundary:
/// `[valid, imageCount, fileError, pageErrors]`, where `pageErrors` is a list of
/// `[entryName, message]` pairs.
List<Object?> validateArchiveBytes(
  Uint8List bytes,
  String name,
  String engineId,
) {
  final result = engineFromId(engineId).validateSync(ArchiveData(name, bytes));
  return <Object?>[
    result.valid,
    result.imageCount,
    result.error,
    <List<String>>[
      for (final error in result.errors) <String>[error.page, error.message],
    ],
  ];
}
