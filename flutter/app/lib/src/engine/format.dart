/// Naming and format helpers mirroring the reference `uzipcore.pas`.
library;

/// Minimum padding used by [pagePaddingFor], matching `PAGE_PAD_MIN`.
const int kPagePadMin = 3;

/// Padding used when renumbering single-file operations, matching
/// `PAGE_PAD_DEFAULT`. The WebP conversion path uses this width.
const int kPagePadDefault = 4;

/// Extensions the reference treats as images.
const Set<String> kImageExtensions = <String>{
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.bmp',
  '.webp',
  '.tif',
  '.tiff',
};

/// True when [ext] (with or without leading dot, any case) is an image.
bool isImageExt(String ext) {
  var e = ext.toLowerCase();
  if (e.isNotEmpty && !e.startsWith('.')) e = '.$e';
  return kImageExtensions.contains(e);
}

/// Formats a page name as `page_<num>` zero-padded to [padding], plus [ext].
String formatPageName(int num, String ext, {int padding = kPagePadDefault}) {
  final e = ext.startsWith('.') ? ext : '.$ext';
  return 'page_${num.toString().padLeft(padding, '0')}$e';
}

/// Padding width for an archive of [pageCount] pages: [kPagePadMin], widened
/// when the count needs more digits. Mirrors `PagePaddingFor`.
int pagePaddingFor(int pageCount) {
  final digits = pageCount.abs().toString().length;
  return digits > kPagePadMin ? digits : kPagePadMin;
}

/// Lower-case extension including the leading dot, or '' when absent.
String extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot).toLowerCase();
}

/// Returns the leading-dot, lower-case extension to encode a page with.
///
/// JPEG and WebP keep their format; PNG and BMP are kept; GIF/TIFF have no
/// writer in the reference and map to PNG. Mirrors `EncodeExtFor`.
String encodeExtFor(String ext) {
  final e = ext.toLowerCase();
  switch (e) {
    case '.jpg':
    case '.jpeg':
      return '.jpg';
    case '.png':
      return '.png';
    case '.bmp':
      return '.bmp';
    case '.webp':
      return '.webp';
    default:
      return '.png';
  }
}
