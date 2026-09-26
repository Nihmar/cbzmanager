import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'comicinfo.dart';
import 'engine.dart';
import 'format.dart';
import 'models.dart';
import 'zip_ops.dart';

/// Pure-Dart implementation of [CbzEngine].
///
/// ZIP handling is provided by `package:archive`; image decoding/encoding by
/// `package:image` (WebP lossy encoding included). This is the recommended
/// Option A core from `flutter/TARGET.md` (ADR-001).
///
/// Parallelism is not yet wired (Phase 0 keeps the pipeline sequential and
/// deterministic); the `threads` parameter is accepted for forward
/// compatibility. CBR (RAR) reading lives in `native/libarchive.dart` because
/// there is no pure-Dart RAR decoder.
class DartCbzEngine implements CbzEngine {
  const DartCbzEngine();

  /// Error returned for an archive without any decodable image page.  It is a
  /// benign no-op for the conversion pipeline, so callers (and the CLI) can
  /// distinguish it from a real failure without string guessing.
  static const String noImagesError = 'No images found in archive';

  /// Registry id used by [engineFromId] to rebuild this engine inside a
  /// background isolate.
  static const String engineId = 'dart';

  @override
  String get id => engineId;

  @override
  Future<ValidateResult> validate(
    ArchiveData data, {
    int threads = 0,
    ProgressCallback? onProgress,
  }) async => validateSync(data, onProgress: onProgress);

  /// Synchronous validation core, safe to run inside a background isolate.
  ///
  /// Per-page progress is not reportable across the `Isolate.run` boundary, so
  /// callers receive file-level progress only.
  @override
  ValidateResult validateSync(
    ArchiveData data, {
    ProgressCallback? onProgress,
  }) {
    final List<ZipEntryData> entries;
    try {
      entries = collectZipEntries(data.bytes);
    } catch (e) {
      return ValidateResult(
        name: data.name,
        valid: false,
        error: 'Not a valid ZIP archive: $e',
      );
    }

    final images = entries.where((e) => isImageExt(_ext(e.name))).toList();
    if (images.isEmpty) {
      return ValidateResult(
        name: data.name,
        valid: false,
        error: 'No images found in archive',
      );
    }

    final errors = <PageError>[];
    onProgress?.call(0, 'Validating ${images.length} page(s)');
    for (var i = 0; i < images.length; i++) {
      final entry = images[i];
      if (_decode(entry.bytes) == null) {
        errors.add(PageError(entry.name, 'Image could not be decoded'));
      }
      onProgress?.call(
        ((i + 1) * 100) ~/ images.length,
        'Validated ${i + 1}/${images.length}',
      );
    }

    return ValidateResult(
      name: data.name,
      valid: errors.isEmpty,
      imageCount: images.length,
      errors: errors,
    );
  }

  @override
  Future<ConvertResult> convertWebp(
    ArchiveData data,
    ConvertOptions options, {
    int threads = 0,
    ProgressCallback? onProgress,
  }) async =>
      convertWebpSync(data, options, threads: threads, onProgress: onProgress);

  /// Synchronous conversion core, safe to run inside a background isolate.
  ConvertResult convertWebpSync(
    ArchiveData data,
    ConvertOptions options, {
    int threads = 0,
    ProgressCallback? onProgress,
  }) {
    final List<ZipEntryData> source;
    try {
      source = collectZipEntries(data.bytes);
    } catch (e) {
      return ConvertResult(
        name: data.name,
        success: false,
        error: 'Not a valid ZIP archive: $e',
      );
    }

    final images = source.where((e) => isImageExt(_ext(e.name))).toList();
    if (images.isEmpty) {
      return ConvertResult(
        name: data.name,
        success: false,
        error: DartCbzEngine.noImagesError,
      );
    }

    // Walk the source in archive order so a preserved ComicInfo.xml keeps its
    // position.  Only images become pages (and only they consume a page
    // number); the reference drops other non-image entries too.
    final output = <ZipEntryData>[];
    var converted = 0;
    var kept = 0;
    var pageNum = 0;
    onProgress?.call(0, 'Converting ${images.length} page(s)');
    for (final entry in source) {
      var bytes = entry.bytes;
      var ext = _ext(entry.name);
      if (!isImageExt(ext)) {
        if (!options.removeComicInfo &&
            entry.name.toLowerCase() == comicInfoName.toLowerCase()) {
          output.add(entry);
        }
        continue;
      }
      pageNum++;

      // Existing WebP: keep the encoded bytes untouched when requested
      // (reference default).  The page still consumes its number and is
      // renamed like every other page.
      if (options.skipExistingWebp && ext.toLowerCase() == '.webp') {
        kept++;
        final name = options.renumber
            ? formatPageName(pageNum, ext)
            : entry.name;
        output.add(ZipEntryData(name, bytes));
        onProgress?.call(
          (pageNum * 100) ~/ images.length,
          'Converted $pageNum/${images.length}',
        );
        continue;
      }

      final decoded = _decode(entry.bytes);
      if (decoded != null) {
        final webp = img.encodeWebP(
          decoded,
          lossless: false,
          quality: options.quality,
        );
        if (!options.onlyIfSmaller || webp.length < entry.bytes.length) {
          bytes = Uint8List.fromList(webp);
          ext = '.webp';
          converted++;
        } else {
          kept++;
        }
      } else {
        kept++;
      }

      final name = options.renumber ? formatPageName(pageNum, ext) : entry.name;
      output.add(ZipEntryData(name, bytes));

      onProgress?.call(
        (pageNum * 100) ~/ images.length,
        'Converted $pageNum/${images.length}',
      );
    }

    return ConvertResult(
      name: data.name,
      success: true,
      output: writeZipEntries(output),
      converted: converted,
      kept: kept,
    );
  }

  @override
  Future<ScanResult> scanComicInfo(ArchiveData data) async =>
      scanComicInfoSync(data);

  @override
  ScanResult scanComicInfoSync(ArchiveData data) {
    final entries = collectZipEntries(data.bytes);
    final index = findComicInfoIndex(entries);
    return ScanResult(found: index >= 0, index: index);
  }

  @override
  Future<ComicInfo?> readComicInfo(ArchiveData data) async =>
      readComicInfoSync(data);

  @override
  ComicInfo? readComicInfoSync(ArchiveData data) {
    try {
      return comicInfoFromEntries(collectZipEntries(data.bytes));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ArchiveData> writeComicInfo(ArchiveData data, ComicInfo info) async =>
      writeComicInfoSync(data, info);

  @override
  ArchiveData writeComicInfoSync(ArchiveData data, ComicInfo info) {
    final entries = withComicInfo(collectZipEntries(data.bytes), info);
    return ArchiveData(data.name, writeZipEntries(entries));
  }

  @override
  Future<ArchiveData> stripComicInfo(ArchiveData data) async =>
      stripComicInfoSync(data);

  @override
  ArchiveData stripComicInfoSync(ArchiveData data) {
    final entries = stripComicInfoEntries(collectZipEntries(data.bytes));
    return ArchiveData(data.name, writeZipEntries(entries));
  }

  static String _ext(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot);
  }

  static img.Image? _decode(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }
}
