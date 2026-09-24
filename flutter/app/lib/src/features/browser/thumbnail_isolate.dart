import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../engine/format.dart';
import '../../engine/zip_ops.dart';
import '../../native/cbr_reader.dart';
import '../../util/str_compare.dart';

/// Isolate wrappers. They live at the top level (not inside the service) so the
/// closure sent to the isolate captures only sendable arguments — a closure
/// created inside a `Pool.withResource` callback would capture the pool and its
/// internal `Completer`, which cannot cross an isolate boundary.
Future<Uint8List?> decodeFirstThumbInIsolate(
  Uint8List bytes,
  String name,
  int maxWidth,
  int maxHeight,
) =>
    Isolate.run(() => decodeFirstPageThumbnail(bytes, name, maxWidth, maxHeight));

Future<Uint8List?> decodePageThumbInIsolate(
  Uint8List bytes,
  String name,
  int index,
  int maxWidth,
  int maxHeight,
) =>
    Isolate.run(
      () => decodePageThumbnail(bytes, name, index, maxWidth, maxHeight),
    );

Future<int> countPagesInIsolate(Uint8List bytes, String name) =>
    Isolate.run(() => countImagePages(bytes, name));

/// Top-level functions safe to run in a background isolate (via `Isolate.run`).

/// Decodes the alphabetically-first image page of an archive into a small JPEG.
/// Returns null when the archive is unreadable or has no images.
Uint8List? decodeFirstPageThumbnail(
  Uint8List bytes,
  String archiveName,
  int maxWidth,
  int maxHeight,
) =>
    decodePageThumbnail(bytes, archiveName, 0, maxWidth, maxHeight);

/// Decodes the image page at [index] (0-based, alphabetical order) into a small
/// JPEG. Returns null when the page is missing or undecodable.
Uint8List? decodePageThumbnail(
  Uint8List bytes,
  String archiveName,
  int index,
  int maxWidth,
  int maxHeight,
) {
  final imageBytes = _pageBytes(bytes, archiveName, index);
  if (imageBytes == null) return null;
  final decoded = img.decodeImage(imageBytes);
  if (decoded == null) return null;
  final fitted = _fit(decoded, maxWidth, maxHeight);
  return Uint8List.fromList(img.encodeJpg(fitted, quality: 80));
}

/// Number of image pages in an archive (0 when unreadable/empty).
int countImagePages(Uint8List bytes, String archiveName) =>
    _imageNames(bytes, archiveName).length;

/// Whether the archive contains a ComicInfo.xml entry.
bool hasComicInfo(Uint8List bytes, String archiveName) {
  if (_isCbr(archiveName)) {
    try {
      return findComicInfoIndex(CbrReader.collectEntries(bytes)) >= 0;
    } catch (_) {
      return false;
    }
  }
  try {
    return findComicInfoIndex(collectZipEntries(bytes)) >= 0;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------

bool _isCbr(String name) => name.toLowerCase().endsWith('.cbr');

List<String> _imageNames(Uint8List bytes, String archiveName) {
  if (_isCbr(archiveName)) {
    try {
      final names = CbrReader.collectEntries(bytes)
          .where((e) => isImageExt(_ext(e.name)))
          .map((e) => e.name)
          .toList()
        ..sort(compareStr);
      return names;
    } catch (_) {
      return const <String>[];
    }
  }
  try {
    return sortedImageNamesInZip(bytes);
  } catch (_) {
    return const <String>[];
  }
}

Uint8List? _pageBytes(Uint8List bytes, String archiveName, int index) {
  if (index < 0) return null;
  if (_isCbr(archiveName)) {
    // RAR has no central directory: one streaming pass is needed, so read all
    // entries once and pick the page rather than scanning the archive twice.
    try {
      final images = CbrReader.collectEntries(bytes)
          .where((e) => isImageExt(_ext(e.name)))
          .toList()
        ..sort((a, b) => compareStr(a.name, b.name));
      if (index >= images.length) return null;
      return images[index].bytes;
    } catch (_) {
      return null;
    }
  }
  try {
    final names = sortedImageNamesInZip(bytes);
    if (index >= names.length) return null;
    return readZipEntryByName(bytes, names[index]);
  } catch (_) {
    return null;
  }
}

img.Image _fit(img.Image source, int maxWidth, int maxHeight) {
  final w = source.width;
  final h = source.height;
  if (w <= maxWidth && h <= maxHeight) return source;
  final scaleX = maxWidth / w;
  final scaleY = maxHeight / h;
  final scale = scaleX < scaleY ? scaleX : scaleY;
  return img.copyResize(
    source,
    width: (w * scale).round().clamp(1, maxWidth),
    height: (h * scale).round().clamp(1, maxHeight),
    interpolation: img.Interpolation.average,
  );
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot);
}
