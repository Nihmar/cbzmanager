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
     procedure ParseWikimediaBasic;
     procedure ParseWikimediaLicense;
     procedure ParseWikimediaSkipsMissingImageinfo;
     procedure GuessExtCombined;
     procedure UrlProviderRejectsLoose;
     procedure SearchRejectsEmpty;
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

  WIKIMEDIA_JSON =
    '{"query":{"pages":{"123":{"title":"File:Cat.jpg","imageinfo":[' +
    '{"url":"https://upload.wikimedia.org/cat.jpg","thumburl":"https://upload.wikimedia.org/cat_320.jpg",' +
    '"extmetadata":{"License":{"value":"CC BY-SA 4.0"}}}]},' +
    '"456":{"title":"File:NoImage.txt","imageinfo":[]}}}}';

procedure TImgSrcTest.ProviderToNameAll;
begin
  AssertEquals('openverse', 'Openverse', ProviderToName(ispOpenverse));
  AssertEquals('wikimedia', 'Wikimedia Commons', ProviderToName(ispWikimedia));
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

initialization
  RegisterTest(TImgSrcTest);

end.
