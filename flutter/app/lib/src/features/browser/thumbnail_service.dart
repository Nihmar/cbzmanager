import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pool/pool.dart';

import '../../vfs/vfs.dart';
import 'archive_item.dart';
import 'thumbnail_isolate.dart';

/// Decodes archive thumbnails on a bounded pool of short-lived isolates, with
/// a small cache of the produced JPEG bytes (keyed by source + path).
///
/// Reads are limited by [readConcurrency] so a directory of archives on SMB is
/// not fetched all at once; decoding is CPU-bound and runs off the UI isolate.
class ThumbnailService {
  ThumbnailService({int readConcurrency = 4, int decodeConcurrency = 4})
    : _readPool = Pool(readConcurrency),
      _decodePool = Pool(decodeConcurrency);

  final Pool _readPool;
  final Pool _decodePool;
  final Map<String, Future<Uint8List?>> _cache = <String, Future<Uint8List?>>{};

  static const int _maxCacheEntries = 256;

  /// First-page thumbnail for a browser item, or null on failure.
  Future<Uint8List?> archiveThumbnail(
    Vfs vfs,
    ArchiveItem item, {
    int maxWidth = 320,
    int maxHeight = 400,
  }) {
    // The requested size is part of the key: the same archive can be asked
    // for thumbnails at different sizes and a size-less key served the first
    // one for all of them.
    final key = 'archive:${vfs.scheme}:${item.path}:$maxWidth:$maxHeight';
    return _cached(
      key,
      () => _readPool.withResource(() async {
        final Uint8List bytes;
        try {
          bytes = await vfs.readAll(item.path);
        } catch (_) {
          return null;
        }
        return _decodePool.withResource(
          () =>
              decodeFirstThumbInIsolate(bytes, item.name, maxWidth, maxHeight),
        );
      }),
    );
  }

  /// Number of image pages, computed off the UI isolate.
  Future<int> pageCount(Uint8List bytes, String name) async {
    try {
      return await _decodePool.withResource(
        () => countPagesInIsolate(bytes, name),
      );
    } catch (_) {
      return 0;
    }
  }

  /// Thumbnail of a single page (used by the preview carousel).
  Future<Uint8List?> pageThumbnail(
    String key,
    Uint8List bytes,
    String name,
    int index, {
    int maxWidth = 1200,
    int maxHeight = 1600,
  }) {
    return _cached(
      '$key:$index:$maxWidth:$maxHeight',
      () => _decodePool.withResource(
        () => decodePageThumbInIsolate(bytes, name, index, maxWidth, maxHeight),
      ),
    );
  }

  Future<Uint8List?> _cached(
    String key,
    Future<Uint8List?> Function() compute,
  ) {
    final existing = _cache[key];
    if (existing != null) return existing;
    if (_cache.length >= _maxCacheEntries) _cache.clear();
    final future = compute();
    _cache[key] = future;
    return future;
  }

  void dispose() {
    _readPool.close();
    _decodePool.close();
  }
}

final thumbnailServiceProvider = Provider<ThumbnailService>((ref) {
  final service = ThumbnailService();
  ref.onDispose(service.dispose);
  return service;
});
