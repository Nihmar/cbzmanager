import 'dart:isolate';
import 'dart:typed_data';

import '../../engine/comicinfo.dart';
import '../../engine/engine_registry.dart';
import '../../engine/models.dart';

/// Isolate wrappers for the ComicInfo operations. They are top-level functions
/// on purpose: a closure created inside a `Pool.withResource` callback would
/// capture the pool (and its internal `Completer`), which cannot cross an
/// isolate boundary.
///
/// Collecting and rewriting a ZIP is the expensive part and happens entirely
/// inside the isolate; only bytes, strings and primitives are transferred. The
/// ComicInfo XML itself is small, so parsing/serialising it on the caller side
/// is free.

/// Whether the archive carries a ComicInfo.xml entry.
Future<bool> scanComicInfoInIsolate(
  Uint8List bytes,
  String name,
  String engineId,
) => Isolate.run(
  () =>
      engineFromId(engineId).scanComicInfoSync(ArchiveData(name, bytes)).found,
);

/// The ComicInfo.xml of the archive, or null when it has none.
Future<String?> readComicInfoXmlInIsolate(
  Uint8List bytes,
  String name,
  String engineId,
) => Isolate.run(
  () =>
      engineFromId(engineId)
          .readComicInfoSync(ArchiveData(name, bytes))
          ?.toXml(),
);

/// Rewrites the archive with [xml] as its ComicInfo.xml.
Future<Uint8List> writeComicInfoInIsolate(
  Uint8List bytes,
  String name,
  String xml,
  String engineId,
) => Isolate.run(
  () =>
      engineFromId(engineId)
          .writeComicInfoSync(ArchiveData(name, bytes), ComicInfo.parse(xml))
          .bytes,
);

/// Rewrites the archive without its ComicInfo.xml.
Future<Uint8List> stripComicInfoInIsolate(
  Uint8List bytes,
  String name,
  String engineId,
) => Isolate.run(
  () =>
      engineFromId(engineId).stripComicInfoSync(ArchiveData(name, bytes)).bytes,
);
