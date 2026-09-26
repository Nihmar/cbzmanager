import 'format.dart';
import 'models.dart';
import 'zip_ops.dart';

/// Filters out ComicInfo.xml and non-image entries, renumbers the survivors as
/// `page_<n>` (padding via [pagePaddingFor]). Mirrors `ConvertCbrToCbz`.
List<ZipEntryData> renumberCbrImages(List<ZipEntryData> entries) {
  final images = <ZipEntryData>[];
  for (final entry in entries) {
    if (entry.name.toLowerCase() == comicInfoName.toLowerCase()) continue;
    if (!isImageExt(extensionOf(entry.name))) continue;
    images.add(entry);
  }
  final padding = pagePaddingFor(images.length);
  return <ZipEntryData>[
    for (var i = 0; i < images.length; i++)
      ZipEntryData(
        formatPageName(i + 1, extensionOf(images[i].name), padding: padding),
        images[i].bytes,
      ),
  ];
}
