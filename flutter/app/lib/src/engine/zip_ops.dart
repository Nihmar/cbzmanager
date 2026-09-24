import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';

/// The single entry the reference filters on every operation.
const String comicInfoName = 'ComicInfo.xml';

/// Reads every file entry of a ZIP/CBZ into memory. Directories are skipped.
/// Throws [ArchiveException] (or a format exception) on invalid input.
List<ZipEntryData> collectZipEntries(Uint8List zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final out = <ZipEntryData>[];
  for (final file in archive) {
    if (file.isDirectory) continue;
    out.add(ZipEntryData(file.name, Uint8List.fromList(file.content)));
  }
  return out;
}

/// Writes entries back to a deflate ZIP entirely in memory.
Uint8List writeZipEntries(
  List<ZipEntryData> entries, {
  int level = DeflateLevel.defaultCompression,
}) {
  final archive = Archive();
  for (final entry in entries) {
    archive.add(ArchiveFile.bytes(entry.name, entry.bytes));
  }
  return ZipEncoder().encodeBytes(archive, level: level);
}

/// Case-insensitive index of ComicInfo.xml, or -1. Mirrors
/// `FindComicInfoIndex`.
int findComicInfoIndex(List<ZipEntryData> entries) {
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].name.toLowerCase() == comicInfoName.toLowerCase()) {
      return i;
    }
  }
  return -1;
}

/// Returns a new list without any ComicInfo.xml entry. Mirrors
/// `StripComicInfo`.
List<ZipEntryData> stripComicInfoEntries(List<ZipEntryData> entries) {
  return entries
      .where((e) => e.name.toLowerCase() != comicInfoName.toLowerCase())
      .toList(growable: false);
}
