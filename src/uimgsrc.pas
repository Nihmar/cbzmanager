unit uimgsrc;

{ ============================================================================
  uimgsrc – Internet image search + download (no GUI, no temp files).

  Provides a small provider abstraction over two free, key-less image
  search APIs (Openverse and Wikimedia Commons) plus a direct "paste a URL"
  mode.  Every download lands in a TMemoryStream kept entirely in RAM,
  matching the rest of the application's in-RAM policy.

  HTTPS works through fphttpclient + the opensslsockets unit; the latter is
  only pulled in by this unit, so the rest of the app is unaffected.
  ============================================================================ }

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, fpjson, jsonparser, fphttpclient, opensslsockets;

const
  MAX_DOWNLOAD_SIZE = 20 * 1024 * 1024; { 20 MB }

type
  EMaxDownloadSize = class(Exception);
  { Search backends exposed in the UI. }
  TImageSearchProvider = (ispOpenverse, ispWikimedia, ispUrl);

  { A single hit returned by a search.  ThumbURL is what the picker shows;
    FullURL is the actual image bytes that get inserted into the CBZ. }
  TSearchResult = record
    Title: string;
    ThumbURL: string;
    FullURL: string;
    PageURL: string;
    License: string;
    Ext: string;
  end;
  TSearchResults = array of TSearchResult;

function ProviderToName(P: TImageSearchProvider): string;

{ Runs a search for AQuery using the given provider.  On success populates
  Results and returns True; on failure returns False and fills ErrMsg.  The
  ispUrl provider treats AQuery itself as the image URL (no network call). }
function SearchImages(const AQuery: string; AProvider: TImageSearchProvider;
  out Results: TSearchResults; out ErrMsg: string): boolean;

{ Downloads the image at URL into a freshly created TMemoryStream (caller
  owns it).  Returns True on HTTP 200 with a non-empty body. }
function DownloadImage(const URL: string; out Stream: TMemoryStream;
  out ErrMsg: string): boolean;

{ Parses a raw Openverse / Wikimedia JSON body into result records.  Exposed
  separately from the network layer so it can be unit-tested offline. }
function ParseOpenverseResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
function ParseWikimediaResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;

{ Best-effort file extension (leading dot) inferred from a URL's path. }
function GuessExtFromURL(const URL: string): string;

implementation

const
  USER_AGENT = 'cbzmanager/1.0';
  OPENVERSE_API = 'https://api.openverse.org/v1/images/';
  WIKIMEDIA_API = 'https://commons.wikimedia.org/w/api.php';
  IMAGE_EXTS: array[0..7] of string =
    ('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tif', '.tiff');

{ Tiny object whose OnDataReceived callback enforces the download cap.
  Stored on the stack; the TFPHTTPClient holds only a plain-method pointer. }
type
  TDownloadGuard = class
    procedure Check(Sender: TObject; const ContentLength, CurrentPos: Int64);
  end;

procedure TDownloadGuard.Check(Sender: TObject; const ContentLength, CurrentPos: Int64);
begin
  if CurrentPos > MAX_DOWNLOAD_SIZE then
    raise EMaxDownloadSize.Create('Download exceeds 20 MB limit');
end;

function ProviderToName(P: TImageSearchProvider): string;
begin
  case P of
    ispOpenverse: Result := 'Openverse';
    ispWikimedia: Result := 'Wikimedia Commons';
    ispUrl:       Result := 'Image URL';
  end;
end;

{ Minimal percent-encoder for query parameters.  Keeps the unreserved set
  intact, encodes spaces as '+', and escapes everything else. }
function URLEncode(const S: string): string;
var
  i: integer;
  c: char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_', '.', '~'] then
      Result := Result + c
    else if c = ' ' then
      Result := Result + '+'
    else
      Result := Result + '%' + IntToHex(Ord(c), 2);
  end;
end;

function AsObj(d: TJSONData): TJSONObject;
begin
  if Assigned(d) and (d.JSONType = jtObject) then
    Result := TJSONObject(d)
  else
    Result := nil;
end;

function AsArr(d: TJSONData): TJSONArray;
begin
  if Assigned(d) and (d.JSONType = jtArray) then
    Result := TJSONArray(d)
  else
    Result := nil;
end;

function JStr(o: TJSONObject; const Key, Def: string): string;
var
  v: TJSONData;
begin
  Result := Def;
  if o = nil then Exit;
  v := o.Find(Key);
  if Assigned(v) and (v.JSONType = jtString) then
    Result := v.AsString;
end;

{ Single GET returning the body as a string.  Sets AllowRedirect and a
  descriptive User-Agent. }
function HttpGetString(const URL: string; out Body: string;
  out ErrMsg: string): boolean;
var
  http: TFPHTTPClient;
  guard: TDownloadGuard;
begin
  Result := False;
  Body := '';
  guard := TDownloadGuard.Create;
  http := TFPHTTPClient.Create(nil);
  try
    http.AllowRedirect := True;
    http.ConnectTimeout := 15000;
    http.IOTimeout := 30000;
    http.AddHeader('User-Agent', USER_AGENT);
    http.AddHeader('Accept', 'application/json');
    http.OnDataReceived := @guard.Check;
    try
      Body := http.Get(URL);
      if http.ResponseStatusCode = 200 then
        Result := True
      else
        ErrMsg := Format('HTTP %d from %s', [http.ResponseStatusCode, URL]);
    except
      on E: Exception do
        ErrMsg := E.Message;
    end;
  finally
    http.Free;
    guard.Free;
  end;
end;

function DownloadImage(const URL: string; out Stream: TMemoryStream;
  out ErrMsg: string): boolean;
var
  http: TFPHTTPClient;
  guard: TDownloadGuard;
begin
  Result := False;
  Stream := nil;
  ErrMsg := '';
  guard := TDownloadGuard.Create;
  http := TFPHTTPClient.Create(nil);
  try
    http.AllowRedirect := True;
    http.ConnectTimeout := 15000;
    http.IOTimeout := 60000;
    http.AddHeader('User-Agent', USER_AGENT);
    http.OnDataReceived := @guard.Check;
    try
      Stream := TMemoryStream.Create;
      http.Get(URL, Stream);
      if http.ResponseStatusCode = 200 then
      begin
        Stream.Position := 0;
        Result := Stream.Size > 0;
        if not Result then
          ErrMsg := 'Empty response body';
      end
      else
      begin
        FreeAndNil(Stream);
        ErrMsg := Format('HTTP %d from %s', [http.ResponseStatusCode, URL]);
      end;
    except
      on E: Exception do
      begin
        FreeAndNil(Stream);
        ErrMsg := E.Message;
      end;
    end;
  finally
    http.Free;
    guard.Free;
  end;
end;

function GuessExtFromURL(const URL: string): string;
var
  i, slash, dot: integer;
  path, ext: string;
begin
  Result := '';
  path := URL;
  i := path.IndexOf('#');
  if i >= 0 then
    path := path.Substring(0, i);
  i := path.IndexOf('?');
  if i >= 0 then
    path := path.Substring(0, i);
  slash := path.LastDelimiter('/');
  if slash >= 0 then
    path := path.Substring(slash + 1);
  dot := path.LastDelimiter('.');
  if dot < 0 then Exit;
  ext := LowerCase(path.Substring(dot));
  for i := 0 to High(IMAGE_EXTS) do
    if SameText(ext, IMAGE_EXTS[i]) then
    begin
      Result := ext;
      Exit;
    end;
end;

function SearchOpenverse(const AQuery: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
var
  URL, Body: string;
begin
  Result := False;
  SetLength(Results, 0);
  URL := OPENVERSE_API + '?q=' + URLEncode(AQuery) + '&page_size=20';
  if not HttpGetString(URL, Body, ErrMsg) then Exit;
  Result := ParseOpenverseResults(Body, Results, ErrMsg);
end;

function ParseOpenverseResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
var
  data, res: TJSONData;
  arr: TJSONArray;
  i, n: integer;
  el: TJSONObject;
  r: TSearchResult;
begin
  Result := False;
  SetLength(Results, 0);
  ErrMsg := '';
  data := nil;
  try
    try
      data := GetJSON(JSON);
    except
      on E: Exception do
      begin
        ErrMsg := 'Invalid JSON: ' + E.Message;
        Exit;
      end;
    end;
    res := data.FindPath('results');
    arr := AsArr(res);
    if arr = nil then
    begin
      ErrMsg := 'No "results" array in response';
      Exit;
    end;
    SetLength(Results, arr.Count);
    n := 0;
    for i := 0 to arr.Count - 1 do
    begin
      el := AsObj(arr.Items[i]);
      if el = nil then Continue;
      r.Title := JStr(el, 'title', '(untitled)');
      r.FullURL := JStr(el, 'url', '');
      r.ThumbURL := JStr(el, 'thumbnail', '');
      if r.ThumbURL = '' then
        r.ThumbURL := r.FullURL;
      r.PageURL := JStr(el, 'foreign_landing_url', '');
      r.License := JStr(el, 'license', '');
      r.Ext := GuessExtFromURL(r.FullURL);
      if r.FullURL <> '' then
      begin
        Results[n] := r;
        Inc(n);
      end;
    end;
    SetLength(Results, n);
    Result := True;
  finally
    data.Free;
  end;
end;

function SearchWikimedia(const AQuery: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
var
  URL, Body: string;
begin
  Result := False;
  SetLength(Results, 0);
  URL := WIKIMEDIA_API +
    '?action=query&generator=search&gsrsearch=' + URLEncode(AQuery) +
    '&gsrnamespace=6&gsrlimit=20&prop=imageinfo' +
    '&iiprop=url%7Cextmetadata%7Cmime&iiurlwidth=320&format=json';
  if not HttpGetString(URL, Body, ErrMsg) then Exit;
  Result := ParseWikimediaResults(Body, Results, ErrMsg);
end;

function ParseWikimediaResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
var
  data, pages, page, ii, em, lic: TJSONData;
  im: TJSONObject;
  po: TJSONObject;
  arr: TJSONArray;
  i, n: integer;
  r: TSearchResult;
begin
  Result := False;
  SetLength(Results, 0);
  ErrMsg := '';
  data := nil;
  try
    try
      data := GetJSON(JSON);
    except
      on E: Exception do
      begin
        ErrMsg := 'Invalid JSON: ' + E.Message;
        Exit;
      end;
    end;
    pages := data.FindPath('query.pages');
    po := AsObj(pages);
    if po = nil then
    begin
      ErrMsg := 'No "query.pages" in response';
      Exit;
    end;
    SetLength(Results, po.Count);
    n := 0;
    for i := 0 to po.Count - 1 do
    begin
      page := po.Items[i];
      if not (page is TJSONObject) then Continue;
      ii := TJSONObject(page).Find('imageinfo');
      arr := AsArr(ii);
      if (arr = nil) or (arr.Count = 0) then Continue;
      im := AsObj(arr.Items[0]);
      if im = nil then Continue;

      r.Title := JStr(TJSONObject(page), 'title', '(untitled)');
      r.FullURL := JStr(im, 'url', '');
      r.ThumbURL := JStr(im, 'thumburl', r.FullURL);
      r.PageURL := r.FullURL;
      r.Ext := GuessExtFromURL(r.FullURL);
      r.License := '';
      em := im.Find('extmetadata');
      if AsObj(em) <> nil then
      begin
        lic := AsObj(em).Find('License');
        if AsObj(lic) <> nil then
          r.License := JStr(TJSONObject(lic), 'value', '');
      end;
      if r.FullURL <> '' then
      begin
        Results[n] := r;
        Inc(n);
      end;
    end;
    SetLength(Results, n);
    Result := True;
  finally
    data.Free;
  end;
end;

function SearchImages(const AQuery: string; AProvider: TImageSearchProvider;
  out Results: TSearchResults; out ErrMsg: string): boolean;
var
  q: string;
begin
  ErrMsg := '';
  SetLength(Results, 0);
  q := Trim(AQuery);
  if q = '' then
  begin
    ErrMsg := 'Enter search terms';
    Result := False;
    Exit;
  end;
  case AProvider of
    ispOpenverse:
      Result := SearchOpenverse(q, Results, ErrMsg);
    ispWikimedia:
      Result := SearchWikimedia(q, Results, ErrMsg);
    ispUrl:
      begin
        if not (StartsText('http://', q) or StartsText('https://', q)) then
        begin
          ErrMsg := 'Enter a valid http(s) image URL';
          Result := False;
          Exit;
        end;
        SetLength(Results, 1);
        Results[0].Title := q;
        Results[0].FullURL := q;
        Results[0].ThumbURL := q;
        Results[0].PageURL := q;
        Results[0].License := '';
        Results[0].Ext := GuessExtFromURL(q);
        Result := True;
      end;
  end;
end;

end.
