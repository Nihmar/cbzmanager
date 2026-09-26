import 'comicinfo.dart';
import 'models.dart';

/// The byte-oriented engine facade. Implementations never touch paths or the
/// filesystem; they receive and return in-memory data only. This is what makes
/// local folders, SAF trees and SMB shares transparent to every operation.
abstract class CbzEngine {
  /// Stable id of this implementation. The isolate boundary cannot carry the
  /// instance itself, so services forward this id and `engineFromId`
  /// reconstructs the same implementation inside the background isolate.
  String get id;

  /// Deep validation: the archive must be a readable ZIP and every image
  /// (including `.webp`) must decode.
  Future<ValidateResult> validate(
    ArchiveData data, {
    int threads = 0,
    ProgressCallback? onProgress,
  });

  /// Synchronous validation core, safe to run inside a background isolate
  /// (`Isolate.run` cannot await). It must not touch the filesystem and must
  /// not rely on isolate-local state.
  ValidateResult validateSync(ArchiveData data, {ProgressCallback? onProgress});

  /// Converts the images to WebP (quality 75 by default), keeping the encoded
  /// bytes only when smaller, filtering ComicInfo.xml and renumbering
  /// survivors as `page_NNNN.*`.
  Future<ConvertResult> convertWebp(
    ArchiveData data,
    ConvertOptions options, {
    int threads = 0,
    ProgressCallback? onProgress,
  });

  /// Reports whether a ComicInfo.xml entry is present.
  Future<ScanResult> scanComicInfo(ArchiveData data);

  /// Synchronous scan core, safe to run inside a background isolate.
  ScanResult scanComicInfoSync(ArchiveData data);

  /// Parses ComicInfo.xml, or null when absent/unreadable.
  Future<ComicInfo?> readComicInfo(ArchiveData data);

  /// Synchronous read core, safe to run inside a background isolate.
  ComicInfo? readComicInfoSync(ArchiveData data);

  /// Returns a copy of the archive with [info] written as ComicInfo.xml.
  Future<ArchiveData> writeComicInfo(ArchiveData data, ComicInfo info);

  /// Synchronous write core, safe to run inside a background isolate.
  ArchiveData writeComicInfoSync(ArchiveData data, ComicInfo info);

  /// Returns a copy of the archive without ComicInfo.xml.
  Future<ArchiveData> stripComicInfo(ArchiveData data);

  /// Synchronous strip core, safe to run inside a background isolate.
  ArchiveData stripComicInfoSync(ArchiveData data);
}
