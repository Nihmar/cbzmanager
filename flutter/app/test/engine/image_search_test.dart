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
    final (results, error) = parseMangaDexCovers(json, const [
      MangaSeries('abc', 'One Piece'),
    ]);
    expect(error, isNull);
    final r = results.single;
    expect(r.fullUrl, 'https://uploads.mangadex.org/covers/abc/cover.jpg');
    expect(r.thumbUrl, endsWith('.512.jpg'));
    expect(r.title, contains('One Piece'));
    expect(r.title, contains('Vol. 1'));
    expect(r.title, contains('[en]'));
    expect(r.ext, '.jpg');
  });

  museumParsers();
}

void museumParsers() {
  test('parseOpenLibraryResults builds cover URLs', () {
    const json = '''
    {"docs":[{"title":"Dune","first_publish_year":1965,
      "author_name":["Herbert"],"cover_i":123,"key":"/works/OL1W"}]}''';
    final (results, error) = parseOpenLibraryResults(json);
    expect(error, isNull);
    final r = results.single;
    expect(r.title, contains('Dune'));
    expect(r.title, contains('1965'));
    expect(r.title, contains('Herbert'));
    expect(r.fullUrl, contains('/123-L.jpg'));
    expect(r.thumbUrl, contains('/123-M.jpg'));
    expect(r.pageUrl, 'https://openlibrary.org/works/OL1W');
    expect(r.ext, '.jpg');
  });

  test('parseArtInstituteResults uses IIIF URLs and public-domain flag', () {
    const json = '''
    {"data":[{"id":42,"title":"Starry Night","artist_title":"van Gogh",
      "date_display":"1889","image_id":"abc","is_public_domain":true}]}''';
    final (results, error) = parseArtInstituteResults(json);
    expect(error, isNull);
    final r = results.single;
    expect(r.title, contains('Starry Night'));
    expect(r.title, contains('van Gogh'));
    expect(r.fullUrl, contains('/iiif/2/abc/full/843,/0/default.jpg'));
    expect(r.license, 'Public domain');
  });

  test('parseClevelandResults prefers print over web', () {
    const json = '''
    {"data":[{"title":"Cleveland","creation_date":"1900",
      "creators":[{"description":"Someone"}],"url":"page",
      "share_license_status":"CC0",
      "images":{"web":{"url":"https://x/web.jpg"},
                "print":{"url":"https://x/print.jpg"}}}]}''';
    final (results, error) = parseClevelandResults(json);
    expect(error, isNull);
    final r = results.single;
    expect(r.fullUrl, 'https://x/print.jpg');
    expect(r.thumbUrl, 'https://x/web.jpg');
    expect(r.title, contains('Someone'));
  });

  test('parseWellcomeResults rewrites the thumbnail IIIF URL', () {
    const json = '''
    {"results":[{"id":"w1","title":"Wellcome","thumbnail":{
      "url":"https://iiif.wellcomecollection.org/thumbs/w1.jp2/full/!200,200/0/default.jpg",
      "license":{"label":"CC BY"}}}]}''';
    final (results, error) = parseWellcomeResults(json);
    expect(error, isNull);
    final r = results.single;
    expect(r.fullUrl, contains('/image/'));
    expect(r.fullUrl, contains('/full/1200,/'));
    expect(r.license, 'CC BY');
    expect(r.pageUrl, 'https://wellcomecollection.org/works/w1');
  });

  test('parseNasaResults upgrades ~thumb to ~orig', () {
    const json = '''
    {"collection":{"items":[{"links":[{"href":"https://x/a~thumb.jpg"}],
      "data":[{"title":"NASA","nasa_id":"n1"}]}]}}''';
    final (results, error) = parseNasaResults(json);
    expect(error, isNull);
    final r = results.single;
    expect(r.fullUrl, 'https://x/a~orig.jpg');
    expect(r.pageUrl, 'https://images.nasa.gov/details/n1');
  });

  test('parseMetIds treats null objectIDs as an empty result', () {
    final (ids, error) = parseMetIds('{"objectIDs":null}');
    expect(error, isNull);
    expect(ids, isEmpty);
    final (ids2, _) = parseMetIds('{"objectIDs":[1,2]}');
    expect(ids2, [1, 2]);
  });

  test('parseMetObject reads the primary image', () {
    const json = '''
    {"title":"Met","artistDisplayName":"A","objectDate":"1900",
     "primaryImage":"https://x/met.jpg","primaryImageSmall":"https://x/small.jpg",
     "objectURL":"https://x/page","isPublicDomain":false}''';
    final (result, error) = parseMetObject(json);
    expect(error, isNull);
    expect(result!.fullUrl, 'https://x/met.jpg');
    expect(result.thumbUrl, 'https://x/small.jpg');
    expect(result.license, 'In copyright — museum terms apply');
  });

  test('parseMetObject returns null when undigitised', () {
    final (result, _) = parseMetObject('{"primaryImage":""}');
    expect(result, isNull);
  });
}
