import 'dart:typed_data';

/// An in-memory archive: the engine never sees filesystem paths, only bytes.
class ArchiveData {
  const ArchiveData(this.name, this.bytes);

  /// Logical name (used for logging and output naming only).
  final String name;

  /// Raw archive bytes.
  final Uint8List bytes;
}

/// A single archive entry held entirely in memory.
class ZipEntryData {
  ZipEntryData(this.name, this.bytes);

  String name;
  Uint8List bytes;
}

/// Progress callback: percentage 0..100 plus a human-readable message.
typedef ProgressCallback = void Function(int percent, String message);

/// One per-page failure reported by a validation run.
class PageError {
  const PageError(this.page, this.message);

  final String page;
  final String message;

  @override
  String toString() => '$page: $message';
}

/// Outcome of validating one archive.
class ValidateResult {
  const ValidateResult({
    required this.name,
    required this.valid,
    this.imageCount = 0,
    this.errors = const <PageError>[],
    this.error,
  });

  final String name;
  final bool valid;
  final int imageCount;
  final List<PageError> errors;

  /// File-level error (unreadable archive, empty archive, ...).
  final String? error;
}

/// Options for the WebP conversion pipeline.
class ConvertOptions {
  const ConvertOptions({
    this.quality = 75,
    this.onlyIfSmaller = true,
    this.removeComicInfo = true,
    this.renumber = true,
  });

  final int quality;
  final bool onlyIfSmaller;
  final bool removeComicInfo;
  final bool renumber;
}

/// Outcome of a WebP conversion run.
class ConvertResult {
  const ConvertResult({
    required this.name,
    required this.success,
    this.output,
    this.converted = 0,
    this.kept = 0,
    this.error,
  });

  final String name;
  final bool success;

  /// New archive bytes; null when nothing was produced.
  final Uint8List? output;
  final int converted;
  final int kept;
  final String? error;
}

/// Outcome of scanning an archive for ComicInfo.xml.
class ScanResult {
  const ScanResult({required this.found, this.index = -1});

  final bool found;
  final int index;
}
