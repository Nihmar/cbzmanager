import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../engine/image_search.dart';

/// Network layer for the image search: Openverse, Wikimedia Commons and the
/// two-stage MangaDex (series → covers), plus a pasted-URL provider. Parsing is
/// kept in `engine/image_search.dart` so it can be tested offline.
class ImageSearchService {
  ImageSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _userAgent =
      'cbzmanager/1.0 (+https://github.com/Nihmar/cbzmanager)';
  static const String _openverse = 'https://api.openverse.org/v1/images/';
  static const String _wikimedia = 'https://commons.wikimedia.org/w/api.php';
  static const String _mangaDex = 'https://api.mangadex.org';
  static const int _maxDownloadBytes = 20 * 1024 * 1024;

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

    switch (provider) {
      case ImageProvider.openverse:
        final uri = Uri.parse(
          '$_openverse?q=${Uri.encodeQueryComponent(trimmed)}&page_size=$limit',
        );
        final (results, error) = parseOpenverseResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.wikimedia:
        final uri = Uri.parse(
          '$_wikimedia?action=query&format=json&prop=imageinfo'
          '&iiprop=url%7Cextmetadata&iiurlwidth=512&generator=search'
          '&gsrsearch=${Uri.encodeQueryComponent(trimmed)}'
          '&gsrnamespace=6&gsrlimit=$limit',
        );
        final (results, error) = parseWikimediaResults(await _getString(uri));
        if (error != null) throw Exception(error);
        return results;

      case ImageProvider.mangaDex:
        final seriesUri = Uri.parse(
          '$_mangaDex/manga?title=${Uri.encodeQueryComponent(trimmed)}&limit=5',
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

      case ImageProvider.url:
        return const <ImageResult>[];
    }
  }

  /// Downloads image bytes, enforcing the 20 MB cap.
  Future<Uint8List> download(String url) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final bytes = response.bodyBytes;
    if (bytes.isEmpty) throw Exception('Empty response');
    if (bytes.length > _maxDownloadBytes) {
      throw Exception('Image exceeds 20 MB');
    }
    return bytes;
  }

  Future<String> _getString(Uri uri) async {
    final response = await _client.get(uri, headers: {'User-Agent': _userAgent});
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return response.body;
  }

  void dispose() => _client.close();
}
