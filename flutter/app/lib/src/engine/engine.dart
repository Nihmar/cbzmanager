import 'comicinfo.dart';
import 'models.dart';

/// The byte-oriented engine facade. Implementations never touch paths or the
/// filesystem; they receive and return in-memory data only. This is what makes
/// local folders, SAF trees and SMB shares transparent to every operation.
abstract class CbzEngine {
  /// Deep validation: the archive must be a readable ZIP and every image
  /// (including `.webp`) must decode.
  Future<ValidateResult> validate(
    ArchiveData data, {
    int threads = 0,
    ProgressCallback? onProgress,
  });

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

  /// Parses ComicInfo.xml, or null when absent/unreadable.
  Future<ComicInfo?> readComicInfo(ArchiveData data);

  /// Returns a copy of the archive with [info] written as ComicInfo.xml.
  Future<ArchiveData> writeComicInfo(ArchiveData data, ComicInfo info);

  /// Returns a copy of the archive without ComicInfo.xml.
  Future<ArchiveData> stripComicInfo(ArchiveData data);
}
