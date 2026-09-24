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

  @override
  Future<ValidateResult> validate(
    ArchiveData data, {
    int threads = 0,
    ProgressCallback? onProgress,
  }) async {
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

    if (options.removeComicInfo) {
      source.removeWhere(
        (e) => e.name.toLowerCase() == comicInfoName.toLowerCase(),
      );
    }

    final images = source.where((e) => isImageExt(_ext(e.name))).toList();
    if (images.isEmpty) {
      return ConvertResult(
        name: data.name,
        success: false,
        error: 'No images found in archive',
      );
    }

    final output = <ZipEntryData>[];
    var converted = 0;
    var kept = 0;
    onProgress?.call(0, 'Converting ${images.length} page(s)');
    for (var i = 0; i < images.length; i++) {
      final entry = images[i];
      var bytes = entry.bytes;
      var ext = _ext(entry.name);

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

      final name = options.renumber
          ? formatPageName(i + 1, ext)
          : entry.name;
      output.add(ZipEntryData(name, bytes));

      onProgress?.call(
        ((i + 1) * 100) ~/ images.length,
        'Converted ${i + 1}/${images.length}',
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
  Future<ScanResult> scanComicInfo(ArchiveData data) async {
    final entries = collectZipEntries(data.bytes);
    final index = findComicInfoIndex(entries);
    return ScanResult(found: index >= 0, index: index);
  }

  @override
  Future<ComicInfo?> readComicInfo(ArchiveData data) async {
    try {
      return comicInfoFromEntries(collectZipEntries(data.bytes));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ArchiveData> writeComicInfo(ArchiveData data, ComicInfo info) async {
    final entries = withComicInfo(collectZipEntries(data.bytes), info);
    return ArchiveData(data.name, writeZipEntries(entries));
  }

  @override
  Future<ArchiveData> stripComicInfo(ArchiveData data) async {
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
