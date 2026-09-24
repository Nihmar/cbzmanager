/// A CBZ/CBR file shown in the browser.
class ArchiveItem {
  const ArchiveItem({
    required this.name,
    required this.path,
    required this.size,
    required this.isCbr,
  });

  final String name;
  final String path;
  final int size;
  final bool isCbr;

  static bool isArchiveName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.cbz') || lower.endsWith('.cbr');
  }
}
