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

  WIKIMEDIA_JSON =
    '{"query":{"pages":{"123":{"title":"File:Cat.jpg","imageinfo":[' +
    '{"url":"https://upload.wikimedia.org/cat.jpg","thumburl":"https://upload.wikimedia.org/cat_320.jpg",' +
    '"extmetadata":{"License":{"value":"CC BY-SA 4.0"}}}]},' +
    '"456":{"title":"File:NoImage.txt","imageinfo":[]}}}}';

procedure TImgSrcTest.ProviderToNameAll;
begin
  AssertEquals('openverse', 'Openverse', ProviderToName(ispOpenverse));
  AssertEquals('wikimedia', 'Wikimedia Commons', ProviderToName(ispWikimedia));
  AssertEquals('openlibrary', 'Open Library', ProviderToName(ispOpenLibrary));
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

initialization
  RegisterTest(TImgSrcTest);

end.
