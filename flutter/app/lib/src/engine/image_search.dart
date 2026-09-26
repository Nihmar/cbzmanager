import 'dart:convert';

/// Search backends exposed in the UI.
///
/// `all` fans out across [kFanOutProviders]; `url` wraps a pasted URL (no
/// network search). Port of the provider enum from `uimgsrc.pas`.
enum ImageProvider {
  all,
  mangaDex,
  openverse,
  wikimedia,
  openLibrary,
  artInstitute,
  met,
  cleveland,
  wellcome,
  nasa,
  url,
}

String providerName(ImageProvider p) => switch (p) {
  ImageProvider.all => 'All sources',
  ImageProvider.mangaDex => 'MangaDex (manga volumes)',
  ImageProvider.openverse => 'Openverse',
  ImageProvider.wikimedia => 'Wikimedia Commons',
  ImageProvider.openLibrary => 'Open Library',
  ImageProvider.artInstitute => 'Art Institute of Chicago',
  ImageProvider.met => 'The Met',
  ImageProvider.cleveland => 'Cleveland Museum of Art',
  ImageProvider.wellcome => 'Wellcome Collection',
  ImageProvider.nasa => 'NASA Images',
  ImageProvider.url => 'Paste a URL',
};

/// Providers combined by the `all` fan-out (the URL pseudo-provider is not a
/// backend and is excluded).
const List<ImageProvider> kFanOutProviders = <ImageProvider>[
  ImageProvider.mangaDex,
  ImageProvider.openverse,
  ImageProvider.wikimedia,
  ImageProvider.openLibrary,
  ImageProvider.artInstitute,
  ImageProvider.met,
  ImageProvider.cleveland,
  ImageProvider.wellcome,
  ImageProvider.nasa,
];

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
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.bmp',
  '.webp',
  '.tif',
  '.tiff',
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

int _int(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _bool(Object? v, [bool fallback = false]) => v is bool ? v : fallback;

/// Row label shared by the museum backends: `Title (date) — Artist`, dropping
/// whichever parts the record does not carry.
String _artworkTitle(Map o, String titleKey, String artistKey, String dateKey) {
  var title = _str(o[titleKey]);
  if (title.trim().isEmpty) title = '(untitled)';
  final date = _str(o[dateKey]).trim();
  if (date.isNotEmpty) title += ' ($date)';
  final artist = _str(o[artistKey]).trim();
  if (artist.isNotEmpty) title += ' — $artist';
  return title;
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
    if (arr is! List) {
      return (const <MangaSeries>[], 'No "data" array in response');
    }
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
    if (arr is! List) {
      return (const <ImageResult>[], 'No "data" array in response');
    }
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

(List<ImageResult>, String?) parseOpenLibraryResults(String json) {
  try {
    final data = jsonDecode(json);
    final docs = data is Map ? data['docs'] : null;
    if (docs is! List) {
      return (const <ImageResult>[], 'No "docs" array in response');
    }
    final out = <ImageResult>[];
    for (final el in docs) {
      if (el is! Map) continue;
      final cover = _int(el['cover_i']);
      if (cover <= 0) continue;
      var title = _str(el['title'], '(untitled)');
      final year = _int(el['first_publish_year']);
      if (year > 0) title += ' ($year)';
      final authors = el['author_name'];
      if (authors is List && authors.isNotEmpty && authors.first is String) {
        title += ' — ${authors.first}';
      }
      final key = _str(el['key']);
      out.add(
        ImageResult(
          provider: ImageProvider.openLibrary,
          title: title,
          fullUrl:
              'https://covers.openlibrary.org/b/id/$cover-L.jpg?default=false',
          thumbUrl:
              'https://covers.openlibrary.org/b/id/$cover-M.jpg?default=false',
          pageUrl: key.isEmpty ? '' : 'https://openlibrary.org$key',
          license: 'Cover art — rights vary by edition',
          ext: '.jpg',
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}

(List<ImageResult>, String?) parseArtInstituteResults(String json) {
  try {
    final data = jsonDecode(json);
    final arr = data is Map ? data['data'] : null;
    if (arr is! List) {
      return (const <ImageResult>[], 'No "data" array in response');
    }
    final out = <ImageResult>[];
    for (final el in arr) {
      if (el is! Map) continue;
      final imageId = _str(el['image_id']);
      if (imageId.isEmpty) continue;
      out.add(
        ImageResult(
          provider: ImageProvider.artInstitute,
          title: _artworkTitle(el, 'title', 'artist_title', 'date_display'),
          fullUrl:
              'https://www.artic.edu/iiif/2/$imageId/full/843,/0/default.jpg',
          thumbUrl:
              'https://www.artic.edu/iiif/2/$imageId/full/200,/0/default.jpg',
          pageUrl: 'https://www.artic.edu/artworks/${_int(el['id'])}',
          license: _bool(el['is_public_domain'])
              ? 'Public domain'
              : 'In copyright — museum terms apply',
          ext: '.jpg',
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}

(List<ImageResult>, String?) parseClevelandResults(String json) {
  try {
    final data = jsonDecode(json);
    final arr = data is Map ? data['data'] : null;
    if (arr is! List) {
      return (const <ImageResult>[], 'No "data" array in response');
    }
    final out = <ImageResult>[];
    for (final el in arr) {
      if (el is! Map) continue;
      final images = el['images'];
      if (images is! Map) continue;
      final web = images['web'];
      if (web is! Map) continue;
      final thumb = _str(web['url']);
      final print = images['print'];
      final full = print is Map ? _str(print['url'], thumb) : thumb;
      if (full.isEmpty) continue;
      var title = _str(el['title'], '(untitled)');
      final date = _str(el['creation_date']).trim();
      if (date.isNotEmpty) title += ' ($date)';
      final creators = el['creators'];
      if (creators is List && creators.isNotEmpty && creators.first is Map) {
        final desc = _str((creators.first as Map)['description']).trim();
        if (desc.isNotEmpty) title += ' — $desc';
      }
      final ext = guessExtFromURL(full);
      out.add(
        ImageResult(
          provider: ImageProvider.cleveland,
          title: title,
          fullUrl: full,
          thumbUrl: thumb,
          pageUrl: _str(el['url']),
          license: _str(el['share_license_status']),
          ext: ext.isEmpty ? '.jpg' : ext,
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}

/// Rewrites a Wellcome thumbnail IIIF URL to the same image at 1200px, or ''
/// when the URL is not the expected shape.
String wellcomeFullUrl(String thumb) {
  if (!thumb.contains('/thumbs/') || !thumb.contains('/full/!200,200/')) {
    return '';
  }
  return thumb
      .replaceAll('/thumbs/', '/image/')
      .replaceAll('/full/!200,200/', '/full/1200,/');
}

(List<ImageResult>, String?) parseWellcomeResults(String json) {
  try {
    final data = jsonDecode(json);
    final arr = data is Map ? data['results'] : null;
    if (arr is! List) {
      return (const <ImageResult>[], 'No "results" array in response');
    }
    final out = <ImageResult>[];
    for (final el in arr) {
      if (el is! Map) continue;
      final thumb = el['thumbnail'];
      if (thumb is! Map) continue;
      final thumbUrl = _str(thumb['url']);
      if (thumbUrl.isEmpty) continue;
      final full = wellcomeFullUrl(thumbUrl);
      final id = _str(el['id']);
      final license = thumb['license'];
      out.add(
        ImageResult(
          provider: ImageProvider.wellcome,
          title: _str(el['title'], '(untitled)'),
          fullUrl: full.isEmpty ? thumbUrl : full,
          thumbUrl: thumbUrl,
          pageUrl: id.isEmpty ? '' : 'https://wellcomecollection.org/works/$id',
          license: license is Map ? _str(license['label']) : '',
          ext: '.jpg',
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}

(List<ImageResult>, String?) parseNasaResults(String json) {
  try {
    final data = jsonDecode(json);
    final collection = data is Map && data['collection'] is Map
        ? data['collection']
        : null;
    final items = collection is Map ? collection['items'] : null;
    if (items is! List) {
      return (const <ImageResult>[], 'No "collection.items" array in response');
    }
    final out = <ImageResult>[];
    for (final item in items) {
      if (item is! Map) continue;
      final links = item['links'];
      if (links is! List || links.isEmpty || links.first is! Map) continue;
      final thumb = _str((links.first as Map)['href']);
      if (thumb.isEmpty) continue;
      final dataArr = item['data'];
      final meta = dataArr is List && dataArr.isNotEmpty && dataArr.first is Map
          ? dataArr.first as Map
          : null;
      final full = thumb.contains('~thumb.jpg')
          ? thumb.replaceAll('~thumb.jpg', '~orig.jpg')
          : thumb;
      final nasaId = meta == null ? '' : _str(meta['nasa_id']);
      out.add(
        ImageResult(
          provider: ImageProvider.nasa,
          title: meta == null
              ? '(untitled)'
              : _str(meta['title'], '(untitled)'),
          fullUrl: full,
          thumbUrl: thumb,
          pageUrl: nasaId.isEmpty
              ? ''
              : 'https://images.nasa.gov/details/$nasaId',
          license: 'NASA media usage guidelines',
          ext: '.jpg',
        ),
      );
    }
    return (out, null);
  } catch (e) {
    return (const <ImageResult>[], 'Invalid JSON: $e');
  }
}

/// Two-stage provider: search returns bare object ids.
(List<int>, String?) parseMetIds(String json) {
  try {
    final data = jsonDecode(json);
    final arr = data is Map ? data['objectIDs'] : null;
    if (arr == null) return (const <int>[], null); // legitimate empty result
    if (arr is! List) {
      return (const <int>[], 'No "objectIDs" array in response');
    }
    return (
      <int>[
        for (final v in arr)
          if (v is num) v.toInt(),
      ],
      null,
    );
  } catch (e) {
    return (const <int>[], 'Invalid JSON: $e');
  }
}

/// Second stage of the Met provider. Returns (null, null) for an undigitised
/// object rather than an error.
(ImageResult?, String?) parseMetObject(String json) {
  try {
    final o = jsonDecode(json);
    if (o is! Map) return (null, null);
    final full = _str(o['primaryImage']);
    if (full.isEmpty) return (null, null);
    final ext = guessExtFromURL(full);
    return (
      ImageResult(
        provider: ImageProvider.met,
        title: _artworkTitle(o, 'title', 'artistDisplayName', 'objectDate'),
        fullUrl: full,
        thumbUrl: _str(o['primaryImageSmall'], full),
        pageUrl: _str(o['objectURL']),
        license: _bool(o['isPublicDomain'])
            ? 'Public domain (CC0)'
            : 'In copyright — museum terms apply',
        ext: ext.isEmpty ? '.jpg' : ext,
      ),
      null,
    );
  } catch (_) {
    return (null, null);
  }
}
