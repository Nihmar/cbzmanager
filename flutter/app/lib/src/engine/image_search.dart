import 'dart:convert';

/// Search backends exposed in the UI. `url` wraps a pasted URL (no network
/// search). Port of the provider enum from `uimgsrc.pas`.
enum ImageProvider { mangaDex, openverse, wikimedia, url }

String providerName(ImageProvider p) => switch (p) {
      ImageProvider.mangaDex => 'MangaDex (manga volumes)',
      ImageProvider.openverse => 'Openverse',
      ImageProvider.wikimedia => 'Wikimedia Commons',
      ImageProvider.url => 'Paste a URL',
    };

class ImageResult {
  const ImageResult({
    required this.provider,
    required this.title,
    required this.thumbUrl,
    required this.fullUrl,
    this.pageUrl = '',
    this.license = '',
    this.ext = '',
  });

  final ImageProvider provider;
  final String title;
  final String thumbUrl;
  final String fullUrl;
  final String pageUrl;
  final String license;
  final String ext;
}

class MangaSeries {
  const MangaSeries(this.id, this.title);

  final String id;
  final String title;
}

const Set<String> _imageExts = {
  '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tif', '.tiff',
};

/// Best-effort image extension (leading dot) inferred from a URL's path.
String guessExtFromURL(String url) {
  var path = url;
  final hash = path.indexOf('#');
  if (hash >= 0) path = path.substring(0, hash);
  final q = path.indexOf('?');
  if (q >= 0) path = path.substring(0, q);
  final slash = path.lastIndexOf('/');
  if (slash >= 0) path = path.substring(slash + 1);
  final dot = path.lastIndexOf('.');
  if (dot < 0) return '';
  final ext = path.substring(dot).toLowerCase();
  return _imageExts.contains(ext) ? ext : '';
}

String _str(Object? v, [String fallback = '']) {
  if (v is String) return v;
  if (v is num || v is bool) return '$v';
  return fallback;
}

(List<ImageResult>, String?) parseOpenverseResults(String json) {
  try {
    final data = jsonDecode(json);
    final results = data is Map ? data['results'] : null;
    if (results is! List) {
      return (const <ImageResult>[], 'No "results" array in response');
    }
    final out = <ImageResult>[];
    for (final el in results) {
      if (el is! Map) continue;
      final full = _str(el['url']);
      if (full.isEmpty) continue;
      final thumb = _str(el['thumbnail']);
      out.add(
        ImageResult(
          provider: ImageProvider.openverse,
          title: _str(el['title'], '(untitled)'),
          thumbUrl: thumb.isEmpty ? full : thumb,
          fullUrl: full,
          pageUrl: _str(el['foreign_landing_url']),
          license: _str(el['license']),
          ext: guessExtFromURL(full),
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}

(List<ImageResult>, String?) parseWikimediaResults(String json) {
  try {
    final data = jsonDecode(json);
    final pages = data is Map && data['query'] is Map
        ? (data['query'] as Map)['pages']
        : null;
    if (pages is! Map) {
      return (const <ImageResult>[], 'No "query.pages" in response');
    }
    final out = <ImageResult>[];
    for (final page in pages.values) {
      if (page is! Map) continue;
      final imageinfo = page['imageinfo'];
      if (imageinfo is! List || imageinfo.isEmpty) continue;
      final im = imageinfo.first;
      if (im is! Map) continue;
      final full = _str(im['url']);
      if (full.isEmpty) continue;
      var license = '';
      final em = im['extmetadata'];
      if (em is Map && em['License'] is Map) {
        license = _str((em['License'] as Map)['value']);
      }
      out.add(
        ImageResult(
          provider: ImageProvider.wikimedia,
          title: _str(page['title'], '(untitled)'),
          thumbUrl: _str(im['thumburl'], full),
          fullUrl: full,
          pageUrl: full,
          license: license,
          ext: guessExtFromURL(full),
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}

String _mangaTitle(Object? attributes) {
  if (attributes is! Map) return '';
  final titles = attributes['title'];
  if (titles is! Map) return '';
  final en = _str(titles['en']);
  if (en.isNotEmpty) return en;
  final jaRo = _str(titles['ja-ro']);
  if (jaRo.isNotEmpty) return jaRo;
  for (final value in titles.values) {
    if (value is String && value.isNotEmpty) return value;
  }
  return '';
}

String _coverMangaId(Map el) {
  final rels = el['relationships'];
  if (rels is! List) return '';
  for (final rel in rels) {
    if (rel is Map && _str(rel['type']) == 'manga') return _str(rel['id']);
  }
  return '';
}

(List<MangaSeries>, String?) parseMangaDexSeries(String json) {
  try {
    final data = jsonDecode(json);
    final arr = data is Map ? data['data'] : null;
    if (arr is! List) return (const <MangaSeries>[], 'No "data" array in response');
    final out = <MangaSeries>[];
    for (final el in arr) {
      if (el is! Map) continue;
      final id = _str(el['id']);
      if (id.isEmpty) continue;
      var title = _mangaTitle(el['attributes']);
      if (title.isEmpty) title = '(untitled)';
      out.add(MangaSeries(id, title));
    }
    return (out, null);
  } catch (e) {
    return (const <MangaSeries>[], 'Invalid JSON: $e');
  }
}

(List<ImageResult>, String?) parseMangaDexCovers(
  String json,
  List<MangaSeries> series,
) {
  try {
    final data = jsonDecode(json);
    final arr = data is Map ? data['data'] : null;
    if (arr is! List) return (const <ImageResult>[], 'No "data" array in response');
    final out = <ImageResult>[];
    for (final el in arr) {
      if (el is! Map) continue;
      final attrs = el['attributes'];
      if (attrs is! Map) continue;
      final fileName = _str(attrs['fileName']);
      if (fileName.isEmpty) continue;
      final mangaId = _coverMangaId(el);
      if (mangaId.isEmpty) continue;

      var title = '';
      for (final s in series) {
        if (s.id == mangaId) {
          title = s.title;
          break;
        }
      }
      if (title.isEmpty) title = '(unknown series)';
      final volume = _str(attrs['volume']);
      title += volume.isNotEmpty ? ' — Vol. $volume' : ' — (no volume)';
      final locale = _str(attrs['locale']);
      if (locale.isNotEmpty) title += ' [$locale]';

      final full = 'https://uploads.mangadex.org/covers/$mangaId/$fileName';
      final ext = guessExtFromURL(fileName);
      out.add(
        ImageResult(
          provider: ImageProvider.mangaDex,
          title: title,
          thumbUrl: '$full.512.jpg',
          fullUrl: full,
          pageUrl: 'https://mangadex.org/title/$mangaId',
          license: 'Publisher cover art — rights held by the publisher',
          ext: ext.isEmpty ? '.jpg' : ext,
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}
