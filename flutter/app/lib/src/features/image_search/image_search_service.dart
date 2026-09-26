import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../engine/image_search.dart';

/// Network layer for the image search: all reference providers plus a pasted
/// URL. Parsing lives in `engine/image_search.dart` so it can be tested
/// offline.
class ImageSearchService {
  ImageSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _userAgent =
      'cbzmanager/1.0 (+https://github.com/Nihmar/cbzmanager)';
  static const String _openverse = 'https://api.openverse.org/v1/images/';
  static const String _wikimedia = 'https://commons.wikimedia.org/w/api.php';
  static const String _openLibrary = 'https://openlibrary.org/search.json';
  static const String _artic = 'https://api.artic.edu/api/v1/artworks/search';
  static const String _cleveland = 'https://openaccess-api.clevelandart.org/api/artworks/';
  static const String _wellcome = 'https://api.wellcomecollection.org/catalogue/v2/works';
  static const String _nasa = 'https://images-api.nasa.gov/search';
  static const String _metSearch =
      'https://collectionapi.metmuseum.org/public/collection/v1/search';
  static const String _metObject =
      'https://collectionapi.metmuseum.org/public/collection/v1/objects/';
  static const String _mangaDex = 'https://api.mangadex.org';

  static const int _maxDownloadBytes = 20 * 1024 * 1024;

  /// Maximum Met detail fetches per search (mirrors `MAX_DETAIL_FETCHES`).
  static const int maxDetailFetches = 12;

  /// Per-request timeouts.  The reference sets a 15 s connect / 30–60 s I/O
  /// timeout; without these a stalled server hung the dialog forever.
  static const Duration _apiTimeout = Duration(seconds: 30);
  static const Duration _downloadTimeout = Duration(seconds: 60);

  Future<List<ImageResult>> search(
    ImageProvider provider,
    String query, {
    int limit = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <ImageResult>[];

    if (provider == ImageProvider.url) {
      return <ImageResult>[
        ImageResult(
          provider: ImageProvider.url,
          title: trimmed,
          thumbUrl: trimmed,
          fullUrl: trimmed,
          pageUrl: trimmed,
          ext: guessExtFromURL(trimmed),
        ),
      ];
    }

    if (provider == ImageProvider.all) {
      return _searchAll(trimmed, limit);
    }

    return _searchOne(provider, trimmed, limit);
  }

  Future<List<ImageResult>> _searchAll(String query, int limit) async {
    final perSource = limit < 8 ? limit : 8;
    final batches = await Future.wait(
      kFanOutProviders.map((provider) async {
        try {
          return await _searchOne(provider, query, perSource);
        } catch (_) {
          // A failing source must not sink the whole fan-out.
          return const <ImageResult>[];
        }
      }),
    );
    return <ImageResult>[for (final batch in batches) ...batch];
  }

  Future<List<ImageResult>> _searchOne(
    ImageProvider provider,
    String query,
    int limit,
  ) async {
    switch (provider) {
      case ImageProvider.openverse:
        final uri = Uri.parse(
          '$_openverse?q=${Uri.encodeQueryComponent(query)}&page_size=$limit',
        );
        final (results, error) = parseOpenverseResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.wikimedia:
        final uri = Uri.parse(
          '$_wikimedia?action=query&format=json&prop=imageinfo'
          '&iiprop=url%7Cextmetadata&iiurlwidth=512&generator=search'
          '&gsrsearch=${Uri.encodeQueryComponent(query)}'
          '&gsrnamespace=6&gsrlimit=$limit',
        );
        final (results, error) = parseWikimediaResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.openLibrary:
        final uri = Uri.parse(
          '$_openLibrary?q=${Uri.encodeQueryComponent(query)}&limit=$limit',
        );
        final (results, error) =
            parseOpenLibraryResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.artInstitute:
        final uri = Uri.parse(
          '$_artic?q=${Uri.encodeQueryComponent(query)}&limit=$limit'
          '&fields=id,title,artist_title,date_display,image_id,is_public_domain',
        );
        final (results, error) =
            parseArtInstituteResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.cleveland:
        final uri = Uri.parse(
          '$_cleveland?q=${Uri.encodeQueryComponent(query)}&limit=$limit'
          '&has_image=1'
          '&fields=id,title,creators,creation_date,images,url,share_license_status',
        );
        final (results, error) = parseClevelandResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.wellcome:
        final uri = Uri.parse(
          '$_wellcome?query=${Uri.encodeQueryComponent(query)}'
          '&pageSize=$limit&include=items',
        );
        final (results, error) = parseWellcomeResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.nasa:
        final uri = Uri.parse(
          '$_nasa?q=${Uri.encodeQueryComponent(query)}'
          '&media_type=image&page_size=$limit',
        );
        final (results, error) = parseNasaResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.met:
        final searchUri = Uri.parse(
          '$_metSearch?q=${Uri.encodeQueryComponent(query)}&hasImages=true',
        );
        final (ids, idError) = parseMetIds(await _getString(searchUri));
        if (idError != null) throw Exception(idError);
        final capped = ids.take(maxDetailFetches);
        final results = <ImageResult>[];
        for (final id in capped) {
          try {
            final (result, _) =
                parseMetObject(await _getString(Uri.parse('$_metObject$id')));
            if (result != null) results.add(result);
          } catch (_) {
            // Skip an object that fails; keep the rest.
          }
        }
        return results;

      case ImageProvider.mangaDex:
        final seriesUri = Uri.parse(
          '$_mangaDex/manga?title=${Uri.encodeQueryComponent(query)}&limit=5',
        );
        final (series, seriesError) =
            parseMangaDexSeries(await _getString(seriesUri));
        if (seriesError != null) throw Exception(seriesError);
        if (series.isEmpty) return const <ImageResult>[];

        final ids = series.map((s) => s.id).join('&manga[]=');
        final coverUri = Uri.parse(
          '$_mangaDex/cover?manga[]=$ids&limit=$limit&order%5Bvolume%5D=asc',
        );
        final (results, coverError) =
            parseMangaDexCovers(await _getString(coverUri), series);
        if (coverError != null) throw Exception(coverError);
        return results;

      case ImageProvider.all:
      case ImageProvider.url:
        return const <ImageResult>[];
    }
  }

  /// Downloads image bytes, enforcing the 20 MB cap while streaming.  The
  /// body is never buffered past the cap (a declared Content-Length larger
  /// than the cap aborts before reading, and an undeclared/lying length is
  /// checked chunk by chunk).
  Future<Uint8List> download(String url) async {
    final request = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = _userAgent;
    final response = await _client.send(request).timeout(_downloadTimeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final declared = response.contentLength;
    if (declared != null && declared > _maxDownloadBytes) {
      throw Exception('Image exceeds 20 MB');
    }

    final builder = BytesBuilder();
    var total = 0;
    await for (final chunk in response.stream.timeout(_downloadTimeout)) {
      total += chunk.length;
      if (total > _maxDownloadBytes) {
        throw Exception('Image exceeds 20 MB');
      }
      builder.add(chunk);
    }
    final bytes = builder.toBytes();
    if (bytes.isEmpty) throw Exception('Empty response');
    return bytes;
  }

  Future<String> _getString(Uri uri) async {
    final response = await _client
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(_apiTimeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return response.body;
  }

  void dispose() => _client.close();
}
