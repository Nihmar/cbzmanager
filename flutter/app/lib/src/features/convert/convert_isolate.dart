import 'dart:isolate';
import 'dart:typed_data';

import '../../engine/dart_engine.dart';
import '../../engine/models.dart';

/// Runs [convertWebpIsolate] in a background isolate.
///
/// This wrapper exists so the isolate closure is created in a scope whose only
/// captured values are sendable (a [Uint8List], a String and ints). Creating the
/// closure inside a `Pool.withResource` callback would capture the pool (and its
/// internal `Completer`), which cannot be sent to an isolate.
Future<List<Object?>> convertInIsolate(
  Uint8List bytes,
  String name, {
  int quality = 75,
  bool onlyIfSmaller = true,
  bool removeComicInfo = true,
  bool renumber = true,
}) {
  return Isolate.run(
    () => convertWebpIsolate(
      bytes,
      name,
      quality,
      onlyIfSmaller,
      removeComicInfo,
      renumber,
    ),
  );
}

/// Runs the pure-Dart WebP conversion inside a background isolate.
///
/// Synchronous on purpose: `Isolate.run` cannot return a `Future` from the
/// computation. Only primitives and a [Uint8List] cross the isolate boundary,
/// and the return value is a plain list `[outputBytes, converted, kept]`
/// (`outputBytes` is null when the archive could not be converted).
List<Object?> convertWebpIsolate(
  Uint8List bytes,
  String name,
  int quality,
  bool onlyIfSmaller,
  bool removeComicInfo,
  bool renumber,
) {
  const engine = DartCbzEngine();
  final result = engine.convertWebpSync(
    ArchiveData(name, bytes),
    ConvertOptions(
      quality: quality,
      onlyIfSmaller: onlyIfSmaller,
      removeComicInfo: removeComicInfo,
      renumber: renumber,
    ),
  );
  if (!result.success || result.output == null) {
    return <Object?>[null, 0, 0];
  }
  return <Object?>[result.output, result.converted, result.kept];
}
