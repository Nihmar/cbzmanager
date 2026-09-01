unit test_uimgsrc;

{$mode objfpc}{$h+}

{ Offline tests for uimgsrc — no network access.  The JSON parsers are
  exercised against canned provider responses; the search dispatch and the
  URL provider are tested directly. }

interface

uses
  fpcunit, testregistry, Classes, SysUtils;

type
  TImgSrcTest = class(TTestCase)
  published
    procedure ProviderToNameAll;
    procedure GuessExtKnown;
    procedure GuessExtUnknown;
    procedure UrlProviderSingleResult;
    procedure UrlProviderRejectsNonHttp;
    procedure ParseOpenverseBasic;
    procedure ParseOpenverseFallsBackThumbnail;
    procedure ParseOpenverseSkipsBad;
    procedure ParseOpenverseInvalidJson;
    procedure ParseOpenverseMissingResults;
    procedure ParseOpenverseEmptyResults;
    procedure ParseWikimediaBasic;
    procedure ParseWikimediaLicense;
    procedure ParseWikimediaSkipsMissingImageinfo;
    procedure ParseWikimediaInvalidJson;
    procedure ParseWikimediaMissingPages;
    procedure ParseWikimediaEmptyPages;
    procedure GuessExtCombined;
    procedure UrlProviderRejectsLoose;
    procedure SearchRejectsEmpty;
    procedure ParsersStampSource;
    procedure ParseOpenLibraryBasic;
    procedure ParseOpenLibrarySkipsCoverless;
    procedure ParseOpenLibraryTitleParts;
    procedure ParseOpenLibraryMissingDocs;
    procedure ParseOpenLibraryInvalidJson;
    procedure ParseArtInstituteBasic;
    procedure ParseArtInstituteLicense;
    procedure ParseArtInstituteMissingData;
    procedure ParseClevelandBasic;
    procedure ParseClevelandSkipsImageless;
    procedure ParseClevelandWebOnly;
    procedure ParseWellcomeBasic;
    procedure ParseWellcomeUnknownThumbShape;
    procedure ParseWellcomeSkipsThumbless;
    procedure ParseNasaBasic;
    procedure ParseNasaOddHref;
    procedure ParseNasaSkipsLinkless;
    procedure ParseMetIdList;
    procedure ParseMetIdsEmptyIsNotAnError;
    procedure ParseMetObjectBasic;
    procedure ParseMetObjectRejectsImageless;
    procedure ParseMangaDexSeriesBasic;
    procedure ParseMangaDexSeriesOddTitles;
    procedure ParseMangaDexSeriesMissingData;
    procedure ParseMangaDexCoversBasic;
    procedure ParseMangaDexCoversVolumeless;
    procedure ParseMangaDexCoversUnknownSeries;
    procedure ParseMangaDexCoversSkipsIncomplete;
  end;

implementation

uses
  uimgsrc;

const
  OPENVERSE_JSON =
    '{"result_count":2,"results":[' +
    '{"title":"Cat","url":"https://ex.com/cat.png","thumbnail":"https://ex.com/cat_t.jpg","foreign_landing_url":"https://page.com/cat","license":"CC0"},' +
    '{"title":"Dog","url":"https://ex.com/dog.jpg","foreign_landing_url":"https://page.com/dog","license":"BY"}' +
    ']}';

  OPENLIBRARY_JSON =
    '{"numFound":2,"start":0,"docs":[' +
    '{"key":"/works/OL2897789W","title":"Batman",' +
    '"author_name":["Alan Moore","Brian Bolland"],' +
    '"cover_i":2737891,"first_publish_year":1988},' +
    '{"key":"/works/OL999W","title":"No Cover Here","first_publish_year":1970}' +
    ']}';

  MANGADEX_SERIES_JSON =
    '{"result":"ok","response":"collection","data":[' +
    '{"id":"30196491-8fc2-4961-8886-a58f898b1b3e","type":"manga",' +
    '"attributes":{"title":{"ja-ro":"Boushoku no Berserk"}}},' +
    '{"id":"aaa-bbb","type":"manga",' +
    '"attributes":{"title":{"en":"Berserk","ja-ro":"Berserk JA"}}}' +
    '],"total":2}';

  MANGADEX_COVERS_JSON =
    '{"result":"ok","data":[' +
    '{"id":"c1","type":"cover_art","attributes":{"volume":"1",' +
    '"fileName":"94a8a850-aae1-4b37-969a-09491ca47092.jpg","locale":"ja"},' +
    '"relationships":[{"id":"30196491-8fc2-4961-8886-a58f898b1b3e",' +
    '"type":"manga"}]},' +
    '{"id":"c2","type":"cover_art","attributes":{"volume":null,' +
    '"fileName":"zzz.jpg","locale":"en"},' +
    '"relationships":[{"id":"aaa-bbb","type":"manga"}]},' +
    '{"id":"c3","type":"cover_art","attributes":{"volume":"2",' +
    '"fileName":"qqq.jpg"},' +
    '"relationships":[{"id":"not-in-the-search","type":"manga"}]}' +
    '],"total":3}';

  ARTIC_JSON =
    '{"data":[' +
    '{"id":181693,"title":"Bear","artist_title":"Charles Pearson",' +
    '"date_display":"n.d.","image_id":"abc-123","is_public_domain":false},' +
    '{"id":2,"title":"Old Print","artist_title":"Anon","date_display":"1850",' +
    '"image_id":"def-456","is_public_domain":true},' +
    '{"id":3,"title":"Undigitised","artist_title":"Nobody"}' +
    '],"config":{"iiif_url":"https://www.artic.edu/iiif/2"}}';

  CLEVELAND_JSON =
    '{"data":[{"id":153401,"title":"Jar with Dragon Design",' +
    '"creation_date":"1700s","share_license_status":"CC0",' +
    '"url":"https://clevelandart.org/art/1986.85","creators":[],"images":{' +
    '"web":{"url":"https://openaccess-cdn.clevelandart.org/1986.85/1986.85_web.jpg"},' +
    '"print":{"url":"https://openaccess-cdn.clevelandart.org/1986.85/1986.85_print.jpg"},' +
    '"full":{"url":"https://openaccess-cdn.clevelandart.org/1986.85/1986.85_full.tif"}' +
    '}}]}';

  WELLCOME_JSON =
    '{"type":"ResultList","results":[{"id":"r32p4n5s","title":"Anatomy",' +
    '"thumbnail":{"url":"https://iiif.wellcomecollection.org/thumbs/' +
    'b22396147_0003.jp2/full/!200,200/0/default.jpg",' +
    '"license":{"id":"pdm","label":"Public Domain Mark"}}}]}';

  NASA_JSON =
    '{"collection":{"items":[{"data":[{"title":"Dumbbell Nebula",' +
    '"nasa_id":"PIA14417","date_created":"2011-08-10T21:00:09Z"}],' +
    '"links":[{"href":"https://images-assets.nasa.gov/image/PIA14417/' +
    'PIA14417~thumb.jpg","rel":"preview","render":"image"}]}]}}';

  MET_OBJECT_JSON =
    '{"objectID":436535,"title":"Wheat Field with Cypresses",' +
    '"artistDisplayName":"Vincent van Gogh","objectDate":"1889",' +
    '"primaryImage":"https://images.metmuseum.org/CRDImages/ep/original/DP-42549-001.jpg",' +
    '"primaryImageSmall":"https://images.metmuseum.org/CRDImages/ep/web-large/DP-42549-001.jpg",' +
    '"isPublicDomain":true,' +
    '"objectURL":"https://www.metmuseum.org/art/collection/search/436535"}';

  WIKIMEDIA_JSON =
    '{"query":{"pages":{"123":{"title":"File:Cat.jpg","imageinfo":[' +
    '{"url":"https://upload.wikimedia.org/cat.jpg","thumburl":"https://upload.wikimedia.org/cat_320.jpg",' +
    '"extmetadata":{"License":{"value":"CC BY-SA 4.0"}}}]},' +
    '"456":{"title":"File:NoImage.txt","imageinfo":[]}}}}';

procedure TImgSrcTest.ProviderToNameAll;
begin
  AssertEquals('mangadex', 'MangaDex (manga volumes)',
    ProviderToName(ispMangaDex));
  AssertEquals('openverse', 'Openverse', ProviderToName(ispOpenverse));
  AssertEquals('wikimedia', 'Wikimedia Commons', ProviderToName(ispWikimedia));
  AssertEquals('openlibrary', 'Open Library', ProviderToName(ispOpenLibrary));
  AssertEquals('artic', 'Art Institute of Chicago',
    ProviderToName(ispArtInstitute));
  AssertEquals('met', 'Metropolitan Museum', ProviderToName(ispMet));
  AssertEquals('cleveland', 'Cleveland Museum of Art',
    ProviderToName(ispCleveland));
  AssertEquals('wellcome', 'Wellcome Collection', ProviderToName(ispWellcome));
  AssertEquals('nasa', 'NASA Images', ProviderToName(ispNasa));
  AssertEquals('url', 'Image URL', ProviderToName(ispUrl));
end;

procedure TImgSrcTest.GuessExtKnown;
begin
  AssertEquals('.png', GuessExtFromURL('https://ex.com/a/b/cat.PNG?x=1'));
  AssertEquals('.jpg', GuessExtFromURL('https://ex.com/dog.jpg#frag'));
  AssertEquals('.webp', GuessExtFromURL('https://ex.com/x/image.WEBP'));
end;

procedure TImgSrcTest.GuessExtUnknown;
begin
  AssertEquals('', GuessExtFromURL('https://ex.com/noext'));
  AssertEquals('', GuessExtFromURL('https://ex.com/file.txt'));
end;

procedure TImgSrcTest.UrlProviderSingleResult;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('search ok', SearchImages('https://ex.com/cat.png', ispUrl, R, Err));
  AssertEquals('one result', 1, Length(R));
  AssertEquals('title is url', 'https://ex.com/cat.png', R[0].Title);
  AssertEquals('full is url', 'https://ex.com/cat.png', R[0].FullURL);
  AssertEquals('thumb is url', 'https://ex.com/cat.png', R[0].ThumbURL);
  AssertEquals('.png', R[0].Ext);
end;

procedure TImgSrcTest.UrlProviderRejectsNonHttp;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('rejects bare word', SearchImages('cat', ispUrl, R, Err));
  AssertFalse('rejects ftp', SearchImages('ftp://x/y.png', ispUrl, R, Err));
  AssertEquals('no results', 0, Length(R));
end;

procedure TImgSrcTest.ParseOpenverseBasic;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseOpenverseResults(OPENVERSE_JSON, R, Err));
  AssertEquals('two results', 2, Length(R));
  AssertEquals('title0', 'Cat', R[0].Title);
  AssertEquals('full0', 'https://ex.com/cat.png', R[0].FullURL);
  AssertEquals('thumb0', 'https://ex.com/cat_t.jpg', R[0].ThumbURL);
  AssertEquals('license0', 'CC0', R[0].License);
  AssertEquals('.png', R[0].Ext);
  AssertEquals('title1', 'Dog', R[1].Title);
  AssertEquals('.jpg', R[1].Ext);
end;

procedure TImgSrcTest.ParseOpenverseFallsBackThumbnail;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  J := '{"results":[{"title":"X","url":"https://ex.com/x.png"}]}';
  AssertTrue('parse ok', ParseOpenverseResults(J, R, Err));
  AssertEquals('thumb falls back to full', 'https://ex.com/x.png', R[0].ThumbURL);
end;

procedure TImgSrcTest.ParseWikimediaBasic;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseWikimediaResults(WIKIMEDIA_JSON, R, Err));
  AssertEquals('one usable result', 1, Length(R));
  AssertEquals('title', 'File:Cat.jpg', R[0].Title);
  AssertEquals('full', 'https://upload.wikimedia.org/cat.jpg', R[0].FullURL);
  AssertEquals('thumb', 'https://upload.wikimedia.org/cat_320.jpg', R[0].ThumbURL);
end;

procedure TImgSrcTest.ParseWikimediaLicense;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseWikimediaResults(WIKIMEDIA_JSON, R, Err));
  AssertEquals('license', 'CC BY-SA 4.0', R[0].License);
end;

procedure TImgSrcTest.ParseWikimediaSkipsMissingImageinfo;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseWikimediaResults(WIKIMEDIA_JSON, R, Err));
  // The second page has empty imageinfo and must be skipped.
  AssertEquals('skipped', 1, Length(R));
end;

procedure TImgSrcTest.ParseOpenverseSkipsBad;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  J := '{"results":[' +
       'null,' +
       '{"title":"A","url":"https://ex.com/a.png"},' +
       '{"title":"B"}' +
       ']}';
  AssertTrue('parse ok', ParseOpenverseResults(J, R, Err));
  AssertEquals('one usable', 1, Length(R));
  AssertEquals('url', 'https://ex.com/a.png', R[0].FullURL);
end;

procedure TImgSrcTest.GuessExtCombined;
begin
  AssertEquals('.png', GuessExtFromURL('https://ex.com/a/b/cat.PNG?x=1#frag'));
  AssertEquals('.jpg', GuessExtFromURL('https://ex.com/dog.jpg#frag?x=1'));
  AssertEquals('.jpeg', GuessExtFromURL('https://ex.com/x/image.jpeg'));
  AssertEquals('.tif', GuessExtFromURL('https://ex.com/x/image.tif'));
  AssertEquals('.tiff', GuessExtFromURL('https://ex.com/x/image.tiff'));
  AssertEquals('.gif', GuessExtFromURL('https://ex.com/x/image.gif'));
  AssertEquals('.bmp', GuessExtFromURL('https://ex.com/x/image.bmp'));
end;

procedure TImgSrcTest.UrlProviderRejectsLoose;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('httpx', SearchImages('httpx://x/y.png', ispUrl, R, Err));
  AssertFalse('httpsomething', SearchImages('httpsomething', ispUrl, R, Err));
  AssertFalse('bare http', SearchImages('http', ispUrl, R, Err));
  AssertFalse('bare https', SearchImages('https', ispUrl, R, Err));
  AssertTrue('https ok', SearchImages('https://x/y.png', ispUrl, R, Err));
end;

procedure TImgSrcTest.SearchRejectsEmpty;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('openverse empty', SearchImages('', ispOpenverse, R, Err));
  AssertEquals('msg', 'Enter search terms', Err);
  AssertFalse('url empty', SearchImages('   ', ispUrl, R, Err));
  AssertEquals('msg2', 'Enter search terms', Err);
end;

procedure TImgSrcTest.ParseOpenLibraryBasic;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseOpenLibraryResults(OPENLIBRARY_JSON, R, Err));
  AssertEquals('one usable', 1, Length(R));
  AssertEquals('source', Ord(ispOpenLibrary), Ord(R[0].Source));
  AssertEquals('full is the large cover',
    'https://covers.openlibrary.org/b/id/2737891-L.jpg?default=false',
    R[0].FullURL);
  AssertEquals('thumb is the medium cover',
    'https://covers.openlibrary.org/b/id/2737891-M.jpg?default=false',
    R[0].ThumbURL);
  AssertEquals('page', 'https://openlibrary.org/works/OL2897789W', R[0].PageURL);
  AssertEquals('.jpg', R[0].Ext);
  { The query string must not confuse extension detection. }
  AssertEquals('ext from url', '.jpg', GuessExtFromURL(R[0].FullURL));
end;

procedure TImgSrcTest.ParseOpenLibrarySkipsCoverless;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseOpenLibraryResults(OPENLIBRARY_JSON, R, Err));
  { The second doc has no cover_i: there is no image to offer. }
  AssertEquals('coverless dropped', 1, Length(R));
end;

procedure TImgSrcTest.ParseOpenLibraryTitleParts;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  AssertTrue('full', ParseOpenLibraryResults(OPENLIBRARY_JSON, R, Err));
  AssertEquals('title with year and author',
    'Batman (1988) — Alan Moore', R[0].Title);

  J := '{"docs":[{"title":"Bare","cover_i":7}]}';
  AssertTrue('bare', ParseOpenLibraryResults(J, R, Err));
  AssertEquals('title alone', 'Bare', R[0].Title);

  J := '{"docs":[{"title":"Yearly","cover_i":7,"first_publish_year":1955}]}';
  AssertTrue('year only', ParseOpenLibraryResults(J, R, Err));
  AssertEquals('title with year', 'Yearly (1955)', R[0].Title);

  J := '{"docs":[{"cover_i":7,"author_name":["Solo"]}]}';
  AssertTrue('no title', ParseOpenLibraryResults(J, R, Err));
  AssertEquals('untitled fallback', '(untitled) — Solo', R[0].Title);
end;

procedure TImgSrcTest.ParseOpenLibraryMissingDocs;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('no docs', ParseOpenLibraryResults('{"numFound":0}', R, Err));
  AssertTrue('error names docs', Pos('docs', Err) > 0);
  AssertEquals('no results', 0, Length(R));
end;

procedure TImgSrcTest.ParseOpenLibraryInvalidJson;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('malformed', ParseOpenLibraryResults('{oops', R, Err));
  AssertEquals('error prefix', 'Invalid JSON: ', Copy(Err, 1, 14));
end;

{ Merged multi-provider result sets are labelled and de-duplicated by
  Source, so each parser must stamp its own origin. }
procedure TImgSrcTest.ParsersStampSource;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('openverse parse', ParseOpenverseResults(OPENVERSE_JSON, R, Err));
  AssertEquals('openverse source', Ord(ispOpenverse), Ord(R[0].Source));
  AssertEquals('openverse source 1', Ord(ispOpenverse), Ord(R[1].Source));
  AssertTrue('wikimedia parse', ParseWikimediaResults(WIKIMEDIA_JSON, R, Err));
  AssertEquals('wikimedia source', Ord(ispWikimedia), Ord(R[0].Source));
  AssertTrue('openlibrary parse',
    ParseOpenLibraryResults(OPENLIBRARY_JSON, R, Err));
  AssertEquals('openlibrary source', Ord(ispOpenLibrary), Ord(R[0].Source));
  AssertTrue('url ok', SearchImages('https://ex.com/cat.png', ispUrl, R, Err));
  AssertEquals('url source', Ord(ispUrl), Ord(R[0].Source));
end;

procedure TImgSrcTest.ParseOpenverseInvalidJson;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('malformed json', ParseOpenverseResults('not json!!!', R, Err));
  AssertEquals('error prefix', 'Invalid JSON: ', Copy(Err, 1, 14));
  AssertEquals('no results', 0, Length(R));
end;

procedure TImgSrcTest.ParseOpenverseMissingResults;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('no results key', ParseOpenverseResults('{"foo":"bar"}', R, Err));
  AssertTrue('error', Pos('results', Err) > 0);
  AssertEquals('no results', 0, Length(R));
end;

procedure TImgSrcTest.ParseOpenverseEmptyResults;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('empty array', ParseOpenverseResults('{"results":[]}', R, Err));
  AssertEquals('zero results', 0, Length(R));
end;

procedure TImgSrcTest.ParseWikimediaInvalidJson;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('malformed json', ParseWikimediaResults('{bad', R, Err));
  AssertEquals('error prefix', 'Invalid JSON: ', Copy(Err, 1, 14));
  AssertEquals('no results', 0, Length(R));
end;

procedure TImgSrcTest.ParseWikimediaMissingPages;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('no pages', ParseWikimediaResults('{"query":{}}', R, Err));
  AssertTrue('error', Pos('query.pages', Err) > 0);
  AssertEquals('no results', 0, Length(R));
end;

procedure TImgSrcTest.ParseWikimediaEmptyPages;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('empty pages', ParseWikimediaResults('{"query":{"pages":{}}}', R, Err));
  AssertEquals('zero results', 0, Length(R));
end;

procedure TImgSrcTest.ParseArtInstituteBasic;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseArtInstituteResults(ARTIC_JSON, R, Err));
  { The third entry has no image_id, so it carries no image to offer. }
  AssertEquals('two usable', 2, Length(R));
  AssertEquals('source', Ord(ispArtInstitute), Ord(R[0].Source));
  AssertEquals('title', 'Bear (n.d.) — Charles Pearson', R[0].Title);
  AssertEquals('full',
    'https://www.artic.edu/iiif/2/abc-123/full/843,/0/default.jpg', R[0].FullURL);
  AssertEquals('thumb',
    'https://www.artic.edu/iiif/2/abc-123/full/200,/0/default.jpg', R[0].ThumbURL);
  AssertEquals('page', 'https://www.artic.edu/artworks/181693', R[0].PageURL);
  AssertEquals('.jpg', R[0].Ext);
end;

procedure TImgSrcTest.ParseArtInstituteLicense;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseArtInstituteResults(ARTIC_JSON, R, Err));
  AssertEquals('not pd', 'In copyright — museum terms apply', R[0].License);
  AssertEquals('pd', 'Public domain', R[1].License);
end;

procedure TImgSrcTest.ParseArtInstituteMissingData;
var
  R: TSearchResults;
  Err: string;
begin
  AssertFalse('no data key', ParseArtInstituteResults('{"info":{}}', R, Err));
  AssertTrue('error names data', Pos('data', Err) > 0);
  AssertFalse('malformed', ParseArtInstituteResults('{nope', R, Err));
  AssertEquals('error prefix', 'Invalid JSON: ', Copy(Err, 1, 14));
end;

procedure TImgSrcTest.ParseClevelandBasic;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseClevelandResults(CLEVELAND_JSON, R, Err));
  AssertEquals('one usable', 1, Length(R));
  AssertEquals('source', Ord(ispCleveland), Ord(R[0].Source));
  AssertEquals('title', 'Jar with Dragon Design (1700s)', R[0].Title);
  { "print" is the page-sized asset; "full" is a multi-hundred-MB TIFF and
    must never be offered. }
  AssertEquals('full is print',
    'https://openaccess-cdn.clevelandart.org/1986.85/1986.85_print.jpg',
    R[0].FullURL);
  AssertEquals('thumb is web',
    'https://openaccess-cdn.clevelandart.org/1986.85/1986.85_web.jpg',
    R[0].ThumbURL);
  AssertEquals('license', 'CC0', R[0].License);
  AssertEquals('.jpg', R[0].Ext);
end;

procedure TImgSrcTest.ParseClevelandSkipsImageless;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  J := '{"data":[{"id":1,"title":"No Images"},' +
       '{"id":2,"title":"Empty","images":{}}]}';
  AssertTrue('parse ok', ParseClevelandResults(J, R, Err));
  AssertEquals('both dropped', 0, Length(R));
end;

procedure TImgSrcTest.ParseClevelandWebOnly;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  { No "print" derivative: the web image is the best we can offer. }
  J := '{"data":[{"id":3,"title":"Web Only","images":{"web":' +
       '{"url":"https://cdn.example/w.jpg"}}}]}';
  AssertTrue('parse ok', ParseClevelandResults(J, R, Err));
  AssertEquals('one', 1, Length(R));
  AssertEquals('full falls back to web', 'https://cdn.example/w.jpg', R[0].FullURL);
end;

procedure TImgSrcTest.ParseWellcomeBasic;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseWellcomeResults(WELLCOME_JSON, R, Err));
  AssertEquals('one usable', 1, Length(R));
  AssertEquals('source', Ord(ispWellcome), Ord(R[0].Source));
  { The full-size URL is derived from the thumbnail: /thumbs/ -> /image/ and
    the fixed !200,200 size -> a usable width. }
  AssertEquals('derived full',
    'https://iiif.wellcomecollection.org/image/b22396147_0003.jp2/full/1200,/0/default.jpg',
    R[0].FullURL);
  AssertEquals('license', 'Public Domain Mark', R[0].License);
  AssertEquals('page', 'https://wellcomecollection.org/works/r32p4n5s', R[0].PageURL);
end;

procedure TImgSrcTest.ParseWellcomeUnknownThumbShape;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  { An unrecognised thumbnail URL must not be mangled — fall back to it. }
  J := '{"results":[{"id":"x","title":"Odd",' +
       '"thumbnail":{"url":"https://example.org/odd.png"}}]}';
  AssertTrue('parse ok', ParseWellcomeResults(J, R, Err));
  AssertEquals('one', 1, Length(R));
  AssertEquals('full is the thumb', 'https://example.org/odd.png', R[0].FullURL);
end;

procedure TImgSrcTest.ParseWellcomeSkipsThumbless;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok',
    ParseWellcomeResults('{"results":[{"id":"y","title":"Nothing"}]}', R, Err));
  AssertEquals('dropped', 0, Length(R));
end;

procedure TImgSrcTest.ParseNasaBasic;
var
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('parse ok', ParseNasaResults(NASA_JSON, R, Err));
  AssertEquals('one usable', 1, Length(R));
  AssertEquals('source', Ord(ispNasa), Ord(R[0].Source));
  AssertEquals('title', 'Dumbbell Nebula', R[0].Title);
  AssertEquals('thumb',
    'https://images-assets.nasa.gov/image/PIA14417/PIA14417~thumb.jpg',
    R[0].ThumbURL);
  { ~thumb is swapped for ~orig by NASA's asset naming convention. }
  AssertEquals('full is the original',
    'https://images-assets.nasa.gov/image/PIA14417/PIA14417~orig.jpg',
    R[0].FullURL);
  AssertEquals('page', 'https://images.nasa.gov/details/PIA14417', R[0].PageURL);
end;

procedure TImgSrcTest.ParseNasaOddHref;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  { An href that does not follow the convention is used as-is for both. }
  J := '{"collection":{"items":[{"data":[{"title":"T","nasa_id":"N"}],' +
       '"links":[{"href":"https://x/y.png","render":"image"}]}]}}';
  AssertTrue('parse ok', ParseNasaResults(J, R, Err));
  AssertEquals('one', 1, Length(R));
  AssertEquals('full', 'https://x/y.png', R[0].FullURL);
  AssertEquals('thumb', 'https://x/y.png', R[0].ThumbURL);
end;

procedure TImgSrcTest.ParseNasaSkipsLinkless;
var
  R: TSearchResults;
  Err: string;
  J: string;
begin
  J := '{"collection":{"items":[{"data":[{"title":"T"}]},' +
       '{"data":[{"title":"U"}],"links":[]}]}}';
  AssertTrue('parse ok', ParseNasaResults(J, R, Err));
  AssertEquals('both dropped', 0, Length(R));
  AssertFalse('missing items', ParseNasaResults('{"collection":{}}', R, Err));
  AssertTrue('error names items', Pos('items', Err) > 0);
end;

procedure TImgSrcTest.ParseMetIdList;
var
  Ids: TIntegerArray;
  Err: string;
begin
  AssertTrue('parse ok',
    ParseMetIds('{"total":3,"objectIDs":[11,22,33]}', Ids, Err));
  AssertEquals('three', 3, Length(Ids));
  AssertEquals('first', 11, Ids[0]);
  AssertEquals('last', 33, Ids[2]);
end;

procedure TImgSrcTest.ParseMetIdsEmptyIsNotAnError;
var
  Ids: TIntegerArray;
  Err: string;
begin
  { A search with no hits answers "objectIDs": null.  That is an empty
    result, not a broken response. }
  AssertTrue('null is ok',
    ParseMetIds('{"total":0,"objectIDs":null}', Ids, Err));
  AssertEquals('none', 0, Length(Ids));
  AssertEquals('no error', '', Err);
  AssertFalse('malformed', ParseMetIds('{oops', Ids, Err));
end;

procedure TImgSrcTest.ParseMetObjectBasic;
var
  R: TSearchResult;
begin
  AssertTrue('parse ok', ParseMetObject(MET_OBJECT_JSON, R));
  AssertEquals('source', Ord(ispMet), Ord(R.Source));
  AssertEquals('title', 'Wheat Field with Cypresses (1889) — Vincent van Gogh',
    R.Title);
  AssertEquals('full',
    'https://images.metmuseum.org/CRDImages/ep/original/DP-42549-001.jpg',
    R.FullURL);
  AssertEquals('thumb',
    'https://images.metmuseum.org/CRDImages/ep/web-large/DP-42549-001.jpg',
    R.ThumbURL);
  AssertEquals('license', 'Public domain (CC0)', R.License);
  AssertEquals('.jpg', R.Ext);
end;

procedure TImgSrcTest.ParseMetObjectRejectsImageless;
var
  R: TSearchResult;
begin
  { An object with no primaryImage cannot be inserted as a page. }
  AssertFalse('no image',
    ParseMetObject('{"objectID":1,"title":"T","primaryImage":""}', R));
  AssertFalse('malformed', ParseMetObject('{nope', R));
end;

procedure TImgSrcTest.ParseMangaDexSeriesBasic;
var
  S: TMangaSeriesList;
  Err: string;
begin
  AssertTrue('parse ok', ParseMangaDexSeries(MANGADEX_SERIES_JSON, S, Err));
  AssertEquals('two series', 2, Length(S));
  AssertEquals('id', '30196491-8fc2-4961-8886-a58f898b1b3e', S[0].Id);
  { Only a romanised title is on offer here. }
  AssertEquals('ja-ro title', 'Boushoku no Berserk', S[0].Title);
  { English wins when both are present. }
  AssertEquals('en preferred', 'Berserk', S[1].Title);
end;

procedure TImgSrcTest.ParseMangaDexSeriesOddTitles;
var
  S: TMangaSeriesList;
  Err: string;
  J: string;
begin
  { Neither en nor ja-ro: fall back to whatever locale is there. }
  J := '{"data":[{"id":"x","attributes":{"title":{"de":"Nur Deutsch"}}}]}';
  AssertTrue('parse ok', ParseMangaDexSeries(J, S, Err));
  AssertEquals('other locale', 'Nur Deutsch', S[0].Title);

  { No title map at all still yields a usable row. }
  J := '{"data":[{"id":"y","attributes":{}}]}';
  AssertTrue('parse ok', ParseMangaDexSeries(J, S, Err));
  AssertEquals('placeholder', '(untitled)', S[0].Title);

  { An entry with no id cannot be keyed to its covers. }
  J := '{"data":[{"attributes":{"title":{"en":"Orphan"}}}]}';
  AssertTrue('parse ok', ParseMangaDexSeries(J, S, Err));
  AssertEquals('dropped', 0, Length(S));
end;

procedure TImgSrcTest.ParseMangaDexSeriesMissingData;
var
  S: TMangaSeriesList;
  Err: string;
begin
  AssertFalse('no data', ParseMangaDexSeries('{"result":"ok"}', S, Err));
  AssertTrue('error names data', Pos('data', Err) > 0);
  AssertFalse('malformed', ParseMangaDexSeries('{bad', S, Err));
  AssertEquals('error prefix', 'Invalid JSON: ', Copy(Err, 1, 14));
end;

procedure TImgSrcTest.ParseMangaDexCoversBasic;
var
  S: TMangaSeriesList;
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('series ok', ParseMangaDexSeries(MANGADEX_SERIES_JSON, S, Err));
  AssertTrue('covers ok',
    ParseMangaDexCovers(MANGADEX_COVERS_JSON, S, R, Err));
  AssertEquals('three covers', 3, Length(R));
  AssertEquals('source', Ord(ispMangaDex), Ord(R[0].Source));
  { The volume number is the whole point: it must reach the row label. }
  AssertEquals('volume row', 'Boushoku no Berserk — Vol. 1 [ja]', R[0].Title);
  AssertEquals('full',
    'https://uploads.mangadex.org/covers/30196491-8fc2-4961-8886-a58f898b1b3e/' +
    '94a8a850-aae1-4b37-969a-09491ca47092.jpg', R[0].FullURL);
  { The CDN derives thumbnails by suffixing the full file name. }
  AssertEquals('thumb', R[0].FullURL + '.512.jpg', R[0].ThumbURL);
  AssertEquals('page',
    'https://mangadex.org/title/30196491-8fc2-4961-8886-a58f898b1b3e',
    R[0].PageURL);
  AssertEquals('.jpg', R[0].Ext);
end;

procedure TImgSrcTest.ParseMangaDexCoversVolumeless;
var
  S: TMangaSeriesList;
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('series ok', ParseMangaDexSeries(MANGADEX_SERIES_JSON, S, Err));
  AssertTrue('covers ok',
    ParseMangaDexCovers(MANGADEX_COVERS_JSON, S, R, Err));
  { volume is null on covers not tied to a numbered volume; they are still
    worth offering, just labelled honestly. }
  AssertEquals('no volume', 'Berserk — (no volume) [en]', R[1].Title);
end;

procedure TImgSrcTest.ParseMangaDexCoversUnknownSeries;
var
  S: TMangaSeriesList;
  R: TSearchResults;
  Err: string;
begin
  AssertTrue('series ok', ParseMangaDexSeries(MANGADEX_SERIES_JSON, S, Err));
  AssertTrue('covers ok',
    ParseMangaDexCovers(MANGADEX_COVERS_JSON, S, R, Err));
  { A cover whose manga relationship is not among the searched series still
    has a usable image, so it is kept rather than dropped.  No locale on this
    one either, so no bracket. }
  AssertEquals('unknown series', '(unknown series) — Vol. 2', R[2].Title);
end;

procedure TImgSrcTest.ParseMangaDexCoversSkipsIncomplete;
var
  S: TMangaSeriesList;
  R: TSearchResults;
  Err: string;
  J: string;
begin
  SetLength(S, 0);
  { No fileName means no image; no manga relationship means no URL to build. }
  J := '{"data":[' +
       '{"id":"a","attributes":{"volume":"1"},' +
       '"relationships":[{"id":"m","type":"manga"}]},' +
       '{"id":"b","attributes":{"volume":"2","fileName":"f.jpg"},' +
       '"relationships":[{"id":"au","type":"author"}]}' +
       ']}';
  AssertTrue('parse ok', ParseMangaDexCovers(J, S, R, Err));
  AssertEquals('both dropped', 0, Length(R));
  AssertFalse('no data', ParseMangaDexCovers('{"result":"ok"}', S, R, Err));
end;

initialization
  RegisterTest(TImgSrcTest);

end.
