import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../util/str_compare.dart';
import 'format.dart';
import 'models.dart';

/// The single entry the reference filters on every operation.
const String comicInfoName = 'ComicInfo.xml';

/// Byte length of a ZIP end-of-central-directory record without comment.
const int _eocdMinLength = 22;

/// ZIP comment field length limit: the EOCD signature can sit up to 65535
/// bytes before the end of the file.
const int _maxZipComment = 65535;

/// True when [bytes] carries the ZIP end-of-central-directory signature
/// (`PK\x05\x06`) in the last 64 KiB.
///
/// `package:archive` silently returns an empty archive for arbitrary input
/// instead of throwing, so without this check a corrupt file would be
/// indistinguishable from a valid ZIP with no entries ("No images found").
bool isZipData(Uint8List bytes) {
  if (bytes.length < _eocdMinLength) return false;
  final last = bytes.length - _eocdMinLength;
  final first = last - _maxZipComment < 0 ? 0 : last - _maxZipComment;
  for (var i = last; i >= first; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      return true;
    }
  }
  return false;
}

/// Reads every file entry of a ZIP/CBZ into memory. Directories are skipped.
/// Throws [FormatException] for data that is not a ZIP at all, or an archive
/// exception for a structurally broken one.
List<ZipEntryData> collectZipEntries(Uint8List zipBytes) {
  if (!isZipData(zipBytes)) {
    throw const FormatException('Not a ZIP archive');
  }
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

/// Image entry names of a ZIP, byte-wise sorted, without decompressing page
/// content (only the central directory is read).
List<String> sortedImageNamesInZip(Uint8List zipBytes) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final names = <String>[];
  for (final file in archive) {
    if (file.isDirectory) continue;
    if (isImageExt(_ext(file.name))) names.add(file.name);
  }
  names.sort(compareStr);
  return names;
}

/// Reads exactly one entry by name, decompressing only that entry.
/// Returns null when the entry is absent or not a file.
Uint8List? readZipEntryByName(Uint8List zipBytes, String name) {
  final archive = ZipDecoder().decodeBytes(zipBytes);
  for (final file in archive) {
    if (!file.isDirectory && file.name == name) {
      return Uint8List.fromList(file.content);
    }
  }
  return null;
}

String _ext(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot);
}
