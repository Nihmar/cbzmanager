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
  { Raised inside the transfer callback when the caller asks to stop.  Lets a
    worker thread abandon an in-flight download instead of running it to
    completion after TThread.Terminate. }
  EDownloadAborted = class(Exception);

  { Polled during a transfer; returning True aborts it.  A TThread passes a
    method returning its own Terminated flag. }
  TAbortQuery = function: boolean of object;

  { Search backends exposed in the UI.  ispUrl is not a backend: it wraps a
    URL the user pasted.  Order is presentation only - nothing maps a combo
    index onto these ordinals. }
  TImageSearchProvider = (ispOpenverse, ispWikimedia, ispOpenLibrary, ispUrl);

  { A single hit returned by a search.  ThumbURL is what the picker shows;
    FullURL is the actual image bytes that get inserted into the CBZ.
    Source records which backend produced it, so a merged multi-provider
    result set can still label and group its entries. }
  TSearchResult = record
    Source: TImageSearchProvider;
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
  ispUrl provider treats AQuery itself as the image URL (no network call).
  AAbort, when supplied, is polled during the transfer to cancel it early. }
function SearchImages(const AQuery: string; AProvider: TImageSearchProvider;
  out Results: TSearchResults; out ErrMsg: string;
  AAbort: TAbortQuery = nil): boolean;

{ Downloads the image at URL into a freshly created TMemoryStream (caller
  owns it).  Returns True on HTTP 200 with a non-empty body.  AAbort, when
  supplied, is polled during the transfer to cancel it early. }
function DownloadImage(const URL: string; out Stream: TMemoryStream;
  out ErrMsg: string; AAbort: TAbortQuery = nil): boolean;

{ Parses a raw provider JSON body into result records.  Exposed separately
  from the network layer so each one can be unit-tested offline. }
function ParseOpenverseResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
function ParseWikimediaResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
function ParseOpenLibraryResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;

{ Best-effort file extension (leading dot) inferred from a URL's path. }
function GuessExtFromURL(const URL: string): string;

{ Loads the OpenSSL interface up front.  MUST be called from the main thread
  before starting any worker that may issue an https request; see the note on
  the implementation for why.  Returns False (with ErrMsg) when no OpenSSL
  library is available at all. }
function PrepareSSL(out ErrMsg: string): boolean;

implementation

uses
  openssl{$IFDEF WINDOWS}, DynLibs{$ENDIF};

const
  { Wikimedia's User-Agent policy requires a descriptive agent carrying a
    contact URL; a bare product token is answered with 403. }
  USER_AGENT = 'cbzmanager/1.0 (+https://github.com/Nihmar/cbzmanager)';
  OPENVERSE_API = 'https://api.openverse.org/v1/images/';
  WIKIMEDIA_API = 'https://commons.wikimedia.org/w/api.php';
  OPENLIBRARY_API = 'https://openlibrary.org/search.json';
  { Covers are addressed by numeric cover id.  That form is exempt from the
    100-requests-per-5-minutes cap the covers API puts on ISBN/OCLC/LCCN
    lookups.  '?default=false' turns a missing cover into a 404 instead of a
    blank placeholder image. }
  OPENLIBRARY_COVER = 'https://covers.openlibrary.org/b/id/';
  OPENLIBRARY_WORK = 'https://openlibrary.org';
  IMAGE_EXTS: array[0..7] of string =
    ('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.tif', '.tiff');

{ Tiny object whose OnDataReceived callback enforces the download cap and
  polls the caller's abort query.  Heap-allocated; the TFPHTTPClient holds
  only a plain-method pointer. }
type
  TDownloadGuard = class
  private
    FAbort: TAbortQuery;
  public
    constructor Create(AAbort: TAbortQuery);
    procedure Check(Sender: TObject; const ContentLength, CurrentPos: Int64);
  end;

constructor TDownloadGuard.Create(AAbort: TAbortQuery);
begin
  inherited Create;
  FAbort := AAbort;
end;

procedure TDownloadGuard.Check(Sender: TObject; const ContentLength, CurrentPos: Int64);
begin
  { Refuse a server-declared oversize body before reading it, then keep
    checking the running total in case Content-Length lied or was absent. }
  if (ContentLength > MAX_DOWNLOAD_SIZE) or (CurrentPos > MAX_DOWNLOAD_SIZE) then
    raise EMaxDownloadSize.Create('Download exceeds 20 MB limit');
  if Assigned(FAbort) and FAbort() then
    raise EDownloadAborted.Create('Cancelled');
end;

{ opensslsockets surfaces a failed InitSSLInterface as a bare "Could not
  initialize OpenSSL library", which says nothing about the actual cause:
  no libssl/libcrypto under any of the names FPC 3.2.2 knows could be
  loaded.  Say what is missing instead. }
function ExplainNetError(const AMsg: string): string;
begin
  Result := AMsg;
  if Pos('openssl', LowerCase(AMsg)) > 0 then
    Result := AMsg + ' — HTTPS is unavailable: no OpenSSL library could be ' +
{$IFDEF WINDOWS}
      'loaded.  Windows ships none under the names FPC looks for; place ' +
      'libcrypto-3-x64.dll and libssl-3-x64.dll (or the 1.1 pair) next to ' +
      'cbzmanager.exe and restart.';
{$ELSE}
      'loaded.  Install the OpenSSL runtime and make sure libssl.so / ' +
      'libcrypto.so are on the loader path, then restart.';
{$ENDIF}
end;

{$IFDEF WINDOWS}
{ FPC 3.2.2's openssl unit only looks for the OpenSSL 1.0/1.1 DLL names
  (libeay32 / ssleay32 / libssl-1_1-x64), and Windows ships nothing under
  those — so InitSSLInterface fails outright and every HTTPS request dies
  before it starts.  Current Windows builds do carry a 3.x (and 4.x) pair in
  System32, and fpopenssl's default stAny path asks for TLS_method, which
  those export (SSLv23_method, the fallback, is gone in 3.x) — so binding
  them works.  DLLSSLName / DLLUtilName are plain vars, so point them at the
  first pair that actually loads.  If none do we change nothing, leaving
  FPC's own names to pick up a 1.1.1 pair shipped beside the executable. }
procedure BindSystemOpenSSL;
const
  {$IFDEF WIN64}
  ARCH_SUFFIX = '-x64';
  {$ELSE}
  ARCH_SUFFIX = '';
  {$ENDIF}
  { 3 first: it is the ubiquitous, well-understood ABI.  Some Windows
    installs also carry a "-4-" pair; take it only if no 3 is present. }
  MAJORS: array[0..1] of string = ('3', '4');
var
  i: integer;
  Ssl, Crypto: string;
  hSsl, hCrypto: TLibHandle;
begin
  for i := Low(MAJORS) to High(MAJORS) do
  begin
    Crypto := 'libcrypto-' + MAJORS[i] + ARCH_SUFFIX + '.dll';
    Ssl := 'libssl-' + MAJORS[i] + ARCH_SUFFIX + '.dll';
    hCrypto := DynLibs.LoadLibrary(Crypto);
    if hCrypto = NilHandle then Continue;
    hSsl := DynLibs.LoadLibrary(Ssl);
    if hSsl = NilHandle then
    begin
      UnloadLibrary(hCrypto);
      Continue;
    end;
    { Both resolve.  Drop the probe handles — the openssl unit loads them
      again through its own refcount when it initialises. }
    UnloadLibrary(hSsl);
    UnloadLibrary(hCrypto);
    DLLUtilName := Crypto;
    DLLSSLName := Ssl;
    Exit;
  end;
end;
{$ENDIF}

{ FPC 3.2.2's InitSSLInterface has a broken double-checked lock
  (openssl.pas): the thread that LOSES the race enters the critical section,
  finds SSLloaded already True and Exits — leaving Result at the False it was
  given before the lock.  opensslsockets.MaybeInitSSLInterface reads that
  False as a failure and raises "Could not initialize OpenSSL library", so
  firing several search workers at once makes all but the winner fail for no
  reason.  Loading once from the main thread means every worker's
  "if not IsSSLloaded" short-circuits and none of them ever enters the racy
  path. }
function PrepareSSL(out ErrMsg: string): boolean;
begin
  ErrMsg := '';
  Result := IsSSLloaded;
  if not Result then
    Result := InitSSLInterface;
  if not Result then
    ErrMsg := ExplainNetError('Could not initialize OpenSSL library');
end;

function ProviderToName(P: TImageSearchProvider): string;
begin
  case P of
    ispOpenverse:   Result := 'Openverse';
    ispWikimedia:   Result := 'Wikimedia Commons';
    ispOpenLibrary: Result := 'Open Library';
    ispUrl:         Result := 'Image URL';
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

function JInt(o: TJSONObject; const Key: string; Def: integer): integer;
var
  v: TJSONData;
begin
  Result := Def;
  if o = nil then Exit;
  v := o.Find(Key);
  if Assigned(v) and (v.JSONType = jtNumber) then
    Result := v.AsInteger;
end;

{ Single GET returning the body as a string.  Sets AllowRedirect and a
  descriptive User-Agent. }
function HttpGetString(const URL: string; out Body: string;
  out ErrMsg: string; AAbort: TAbortQuery): boolean;
var
  http: TFPHTTPClient;
  guard: TDownloadGuard;
begin
  Result := False;
  Body := '';
  ErrMsg := '';
  guard := TDownloadGuard.Create(AAbort);
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
        ErrMsg := ExplainNetError(E.Message);
    end;
  finally
    http.Free;
    guard.Free;
  end;
end;

function DownloadImage(const URL: string; out Stream: TMemoryStream;
  out ErrMsg: string; AAbort: TAbortQuery): boolean;
var
  http: TFPHTTPClient;
  guard: TDownloadGuard;
begin
  Result := False;
  Stream := nil;
  ErrMsg := '';
  guard := TDownloadGuard.Create(AAbort);
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
        ErrMsg := ExplainNetError(E.Message);
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
  out ErrMsg: string; AAbort: TAbortQuery): boolean;
var
  URL, Body: string;
begin
  Result := False;
  SetLength(Results, 0);
  URL := OPENVERSE_API + '?q=' + URLEncode(AQuery) + '&page_size=20';
  if not HttpGetString(URL, Body, ErrMsg, AAbort) then Exit;
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
      r.Source := ispOpenverse;
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
  out ErrMsg: string; AAbort: TAbortQuery): boolean;
var
  URL, Body: string;
begin
  Result := False;
  SetLength(Results, 0);
  URL := WIKIMEDIA_API +
    '?action=query&generator=search&gsrsearch=' + URLEncode(AQuery) +
    '&gsrnamespace=6&gsrlimit=20&prop=imageinfo' +
    '&iiprop=url%7Cextmetadata%7Cmime&iiurlwidth=320&format=json';
  if not HttpGetString(URL, Body, ErrMsg, AAbort) then Exit;
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

      r.Source := ispWikimedia;
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

function SearchOpenLibrary(const AQuery: string; out Results: TSearchResults;
  out ErrMsg: string; AAbort: TAbortQuery): boolean;
var
  URL, Body: string;
begin
  Result := False;
  SetLength(Results, 0);
  { 'fields' keeps the response small: the default document carries dozens of
    arrays we would only throw away. }
  URL := OPENLIBRARY_API + '?q=' + URLEncode(AQuery) +
    '&limit=20&fields=key,title,author_name,cover_i,first_publish_year';
  if not HttpGetString(URL, Body, ErrMsg, AAbort) then Exit;
  Result := ParseOpenLibraryResults(Body, Results, ErrMsg);
end;

{ "Title (year) - First Author", skipping whichever parts are absent. }
function OpenLibraryTitle(el: TJSONObject): string;
var
  Year: integer;
  Authors: TJSONArray;
begin
  Result := JStr(el, 'title', '(untitled)');
  Year := JInt(el, 'first_publish_year', 0);
  if Year > 0 then
    Result := Result + ' (' + IntToStr(Year) + ')';
  Authors := AsArr(el.Find('author_name'));
  if (Authors <> nil) and (Authors.Count > 0) and
     (Authors.Items[0].JSONType = jtString) then
    Result := Result + ' — ' + Authors.Items[0].AsString;
end;

function ParseOpenLibraryResults(const JSON: string; out Results: TSearchResults;
  out ErrMsg: string): boolean;
var
  data, docs: TJSONData;
  arr: TJSONArray;
  i, n, Cover: integer;
  el: TJSONObject;
  Key: string;
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
    docs := data.FindPath('docs');
    arr := AsArr(docs);
    if arr = nil then
    begin
      ErrMsg := 'No "docs" array in response';
      Exit;
    end;
    SetLength(Results, arr.Count);
    n := 0;
    for i := 0 to arr.Count - 1 do
    begin
      el := AsObj(arr.Items[i]);
      if el = nil then Continue;
      { No cover id means the edition has no scanned cover — nothing to add. }
      Cover := JInt(el, 'cover_i', 0);
      if Cover <= 0 then Continue;
      r.Source := ispOpenLibrary;
      r.Title := OpenLibraryTitle(el);
      r.FullURL := OPENLIBRARY_COVER + IntToStr(Cover) + '-L.jpg?default=false';
      r.ThumbURL := OPENLIBRARY_COVER + IntToStr(Cover) + '-M.jpg?default=false';
      Key := JStr(el, 'key', '');
      if Key <> '' then
        r.PageURL := OPENLIBRARY_WORK + Key
      else
        r.PageURL := '';
      { Unlike the other two backends this is not a free-licence pool: the
        cover art belongs to whoever published the edition.  Say so rather
        than leaving the label blank, which would read as "unrestricted". }
      r.License := 'Cover art — rights vary by edition';
      r.Ext := '.jpg';
      Results[n] := r;
      Inc(n);
    end;
    SetLength(Results, n);
    Result := True;
  finally
    data.Free;
  end;
end;

function SearchImages(const AQuery: string; AProvider: TImageSearchProvider;
  out Results: TSearchResults; out ErrMsg: string;
  AAbort: TAbortQuery): boolean;
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
      Result := SearchOpenverse(q, Results, ErrMsg, AAbort);
    ispWikimedia:
      Result := SearchWikimedia(q, Results, ErrMsg, AAbort);
    ispOpenLibrary:
      Result := SearchOpenLibrary(q, Results, ErrMsg, AAbort);
    ispUrl:
      begin
        if not (StartsText('http://', q) or StartsText('https://', q)) then
        begin
          ErrMsg := 'Enter a valid http(s) image URL';
          Result := False;
          Exit;
        end;
        SetLength(Results, 1);
        Results[0].Source := ispUrl;
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

initialization
{$IFDEF WINDOWS}
  { Runs before any worker thread exists, so writing the two name vars here
    needs no locking. }
  BindSystemOpenSSL;
{$ENDIF}

end.
