import 'package:cbzmanager/src/engine/image_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guessExtFromURL strips query/fragment and is case-insensitive', () {
    expect(guessExtFromURL('https://x/y/cat.JPG'), '.jpg');
    expect(guessExtFromURL('https://x/y/cat.webp?size=1#z'), '.webp');
    expect(guessExtFromURL('https://x/y/noext'), '');
    expect(guessExtFromURL('https://x/y/doc.pdf'), '');
  });

  test('parseOpenverseResults', () {
    const json = '''
    {"results":[
      {"title":"Cat","url":"https://example.com/cat.JPG",
       "thumbnail":"https://example.com/cat_thumb.jpg",
       "foreign_landing_url":"https://example.com/page","license":"cc0"}
    ]}''';
    final (results, error) = parseOpenverseResults(json);
    expect(error, isNull);
    expect(results.single.title, 'Cat');
    expect(results.single.fullUrl, 'https://example.com/cat.JPG');
    expect(results.single.thumbUrl, 'https://example.com/cat_thumb.jpg');
    expect(results.single.license, 'cc0');
    expect(results.single.ext, '.jpg');
  });

  test('parseOpenverseResults reports a missing array', () {
    final (results, error) = parseOpenverseResults('{"nope":true}');
    expect(results, isEmpty);
    expect(error, contains('results'));
  });

  test('parseOpenverseResults tolerates invalid JSON', () {
    final (results, error) = parseOpenverseResults('<not json');
    expect(results, isEmpty);
    expect(error, contains('Invalid JSON'));
  });

  test('parseWikimediaResults reads imageinfo and license', () {
    const json = '''
    {"query":{"pages":{"123":{"title":"File:Cat.jpg","imageinfo":[
      {"url":"https://upload.wikimedia.org/cat.jpg",
       "thumburl":"https://upload.wikimedia.org/cat_thumb.jpg",
       "extmetadata":{"License":{"value":"CC BY-SA 4.0"}}}]}}}}''';
    final (results, error) = parseWikimediaResults(json);
    expect(error, isNull);
    expect(results.single.title, 'File:Cat.jpg');
    expect(results.single.fullUrl, 'https://upload.wikimedia.org/cat.jpg');
    expect(results.single.license, 'CC BY-SA 4.0');
  });

  test('parseMangaDexSeries reads id and title', () {
    const json = '''
    {"data":[{"id":"abc","attributes":{"title":{"en":"One Piece","ja-ro":"OP"}}}]}''';
    final (series, error) = parseMangaDexSeries(json);
    expect(error, isNull);
    expect(series.single.id, 'abc');
    expect(series.single.title, 'One Piece');
  });

  test('parseMangaDexCovers links covers to their series', () {
    const json = '''
    {"data":[{"id":"c1","attributes":{"fileName":"cover.jpg","volume":"1","locale":"en"},
      "relationships":[{"type":"manga","id":"abc"}]}]}''';
    final (results, error) = parseMangaDexCovers(json, const [MangaSeries('abc', 'One Piece')]);
    expect(error, isNull);
    final r = results.single;
    expect(r.fullUrl, 'https://uploads.mangadex.org/covers/abc/cover.jpg');
    expect(r.thumbUrl, endsWith('.512.jpg'));
    expect(r.title, contains('One Piece'));
    expect(r.title, contains('Vol. 1'));
    expect(r.title, contains('[en]'));
    expect(r.ext, '.jpg');
  });
}
