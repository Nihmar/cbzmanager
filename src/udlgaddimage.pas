unit udlgaddimage;

{$mode ObjFPC}{$H+}

{
  udlgaddimage.pas - Add image from internet dialog.

  Lets the user search a free, key-less image source (Openverse, Wikimedia
  Commons) or paste a direct image URL, pick one result, preview it, and
  hand the raw bytes back to the main form.  The main form then stages the
  image as the new first page of the open CBZ (nothing is written until the
  user saves via the stage bar).

  Threading
  ---------
  Every network operation runs on a worker thread, following the same
  fire-and-forget pattern as TPagesThread in main.pas: FreeOnTerminate =
  True, an OnTerminate handler that re-enables the UI, and a
  "Sender = F<x>Thread" guard so a superseded worker's result is ignored.
  A worker that is no longer wanted (the user searched again, picked another
  result, or closed the dialog) is detached with
  OnTerminate := nil; Terminate; F<x>Thread := nil.  A search can run several
  providers at once, so its workers are tracked in FSearchThreads and guarded
  by FSearchEpoch instead of by pointer identity: a worker stamped with an
  older epoch has been superseded and its results are dropped.
  Terminate is honoured mid-transfer via the TAbortQuery handed down to
  uimgsrc, so a detached worker abandons its download at the next transfer
  callback instead of running a 20 MB body to completion.

  Usage:
    dlg := TdlgAddImage.Create(Self);
    try
      if dlg.ShowModal = mrOk then
        Stream := dlg.ReleaseImageStream;   // caller owns the stream
    finally
      dlg.Free;
    end;
}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, ExtCtrls, StdCtrls,
  IntfGraphics, udlgbase, usettings, uimgsrc, uzipeditor, uimgutil;

type
  TProviderList = array of TImageSearchProvider;

  { Background worker that runs a provider search off the main thread. }
  TSearchThread = class(TThread)
  private
    FQuery: string;
    FProvider: TImageSearchProvider;
    FEpoch: integer;
    FResults: TSearchResults;
    FErrMsg: string;
    FOk: boolean;
    { Polled by uimgsrc during the transfer so Terminate takes effect. }
    function IsAborted: boolean;
  public
    constructor Create(const AQuery: string; AProvider: TImageSearchProvider;
      AEpoch: integer);
    procedure Execute; override;
    property Ok: boolean read FOk;
    property Epoch: integer read FEpoch;
    property Provider: TImageSearchProvider read FProvider;
    property Results: TSearchResults read FResults;
    property ErrMsg: string read FErrMsg;
  end;

  { Background worker that downloads + decodes a result thumbnail. }
  TPreviewThread = class(TThread)
  private
    FUrl, FExt, FLicense, FPageURL: string;
    FIdx: integer;
    FImg: TLazIntfImage;
    FStream: TMemoryStream;
    FOk: boolean;
    function IsAborted: boolean;
  public
    constructor Create(const AResult: TSearchResult; AIdx: integer);
    destructor Destroy; override;
    procedure Execute; override;
    { Hand the decoded image / raw bytes to the caller, who then owns them. }
    function ReleaseImg: TLazIntfImage;
    function ReleaseStream: TMemoryStream;
    property Ok: boolean read FOk;
    property Img: TLazIntfImage read FImg;
    property Url: string read FUrl;
    property License: string read FLicense;
    property PageURL: string read FPageURL;
    property Idx: integer read FIdx;
  end;

  { Background worker that downloads the full-resolution image to add. }
  TFetchThread = class(TThread)
  private
    FUrl: string;
    FStream: TMemoryStream;
    FErrMsg: string;
    FOk: boolean;
    function IsAborted: boolean;
  public
    constructor Create(const AResult: TSearchResult);
    destructor Destroy; override;
    procedure Execute; override;
    function ReleaseStream: TMemoryStream;
    property Ok: boolean read FOk;
    property ErrMsg: string read FErrMsg;
  end;

  { TdlgAddImage - search + pick dialog for an internet image. }
  TdlgAddImage = class(TSettingsDialog)
    BtnAdd: TButton;
    BtnCancel: TButton;
    BtnSearch: TButton;
    CbProvider: TComboBox;
    EdQuery: TEdit;
    ImgPreview: TImage;
    LabelInfo: TLabel;
    LabelLicense: TLabel;
    LabelQuery: TLabel;
    LstResults: TListBox;
    PanelBottom: TPanel;
    procedure BtnAddClick(Sender: TObject);
    procedure BtnSearchClick(Sender: TObject);
    procedure CbProviderChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: boolean);
    procedure LstResultsClick(Sender: TObject);
  private
    FResults: TSearchResults;
    FSelected: integer;
    FPreviewStream: TMemoryStream;
    FPreviewURL: string;
    FImageStream: TMemoryStream;
    { Workers of the current search, one per queried provider. }
    FSearchThreads: array of TSearchThread;
    { Bumped by every new search; a worker stamped with an older value has
      been superseded and its results are discarded. }
    FSearchEpoch: integer;
    FSearchPending: integer;
    FSearchErrors: string;
    FMultiSource: boolean;
    FPreviewThread: TPreviewThread;
    FFetchThread: TFetchThread;
    { The providers the current combo entry queries (empty for URL mode). }
    function ScopeProviders: TProviderList;
    function ScopeIsUrl: boolean;
    { True when FullURL is already in FResults - providers overlap. }
    function AlreadyListed(const AUrl: string): boolean;
    procedure AppendResult(const AResult: TSearchResult);
    procedure DetachSearches;
    procedure RemoveSearchThread(AThread: TSearchThread);
    procedure ClearPreview;
    procedure ShowInfo(const Msg: string; IsError: boolean);
    procedure DoSearch;
    procedure SelectResult(Idx: integer);
    procedure SearchDone(Sender: TObject);
    procedure PreviewDone(Sender: TObject);
    procedure FetchDone(Sender: TObject);
    procedure SetBusy(ABusy: boolean);
    { Detach every still-running worker so its OnTerminate can no longer
      reach this form, and ask it to abandon its transfer. }
    procedure DetachThreads;
    procedure LoadSettings; override;
    procedure SaveSettings; override;
  public
    { Returns the downloaded image stream and transfers ownership to the
      caller (the dialog no longer frees it).  Call only after ShowModal
      returns mrOk; returns nil otherwise. }
    function ReleaseImageStream: TMemoryStream;
    destructor Destroy; override;
  end;

implementation

{$R *.lfm}

{ TSearchThread }

constructor TSearchThread.Create(const AQuery: string;
  AProvider: TImageSearchProvider; AEpoch: integer);
begin
  inherited Create(True);
  FQuery := AQuery;
  FProvider := AProvider;
  FEpoch := AEpoch;
  SetLength(FResults, 0);
  FErrMsg := '';
  FOk := False;
  FreeOnTerminate := True;
end;

function TSearchThread.IsAborted: boolean;
begin
  Result := Terminated;
end;

procedure TSearchThread.Execute;
begin
  FOk := SearchImages(FQuery, FProvider, FResults, FErrMsg, @Self.IsAborted);
end;

{ TPreviewThread }

constructor TPreviewThread.Create(const AResult: TSearchResult; AIdx: integer);
begin
  inherited Create(True);
  FUrl := AResult.ThumbURL;
  FExt := AResult.Ext;
  FLicense := AResult.License;
  FPageURL := AResult.PageURL;
  FIdx := AIdx;
  FImg := nil;
  FStream := nil;
  FOk := False;
  FreeOnTerminate := True;
end;

destructor TPreviewThread.Destroy;
begin
  FStream.Free;
  FImg.Free;
  inherited Destroy;
end;

function TPreviewThread.IsAborted: boolean;
begin
  Result := Terminated;
end;

function TPreviewThread.ReleaseImg: TLazIntfImage;
begin
  Result := FImg;
  FImg := nil;
end;

function TPreviewThread.ReleaseStream: TMemoryStream;
begin
  Result := FStream;
  FStream := nil;
end;

procedure TPreviewThread.Execute;
var
  Err: string;
begin
  FOk := DownloadImage(FUrl, FStream, Err, @Self.IsAborted);
  { Decoding a big thumbnail is not free — skip it if we were cancelled
    while the bytes were coming in. }
  if FOk and not Terminated then
  begin
    FImg := DecodeImage(FStream, FExt, 640, 640);
    if FImg = nil then
    begin
      FOk := False;
      FreeAndNil(FStream);
    end;
  end
  else
  begin
    FOk := False;
    FreeAndNil(FStream);
  end;
end;

{ TFetchThread }

constructor TFetchThread.Create(const AResult: TSearchResult);
begin
  inherited Create(True);
  FUrl := AResult.FullURL;
  FStream := nil;
  FErrMsg := '';
  FOk := False;
  FreeOnTerminate := True;
end;

destructor TFetchThread.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

function TFetchThread.IsAborted: boolean;
begin
  Result := Terminated;
end;

function TFetchThread.ReleaseStream: TMemoryStream;
begin
  Result := FStream;
  FStream := nil;
end;

procedure TFetchThread.Execute;
begin
  FOk := DownloadImage(FUrl, FStream, FErrMsg, @Self.IsAborted);
end;

{ TdlgAddImage }

{ Combo entries, in LFM order:
    0 All sources   1 Openverse   2 Wikimedia Commons   3 Image URL }
function TdlgAddImage.ScopeProviders: TProviderList;
begin
  case CbProvider.ItemIndex of
    1: begin
         SetLength(Result, 1);
         Result[0] := ispOpenverse;
       end;
    2: begin
         SetLength(Result, 1);
         Result[0] := ispWikimedia;
       end;
    3: SetLength(Result, 0);   { URL mode issues no search }
    else
      begin
        SetLength(Result, 2);
        Result[0] := ispOpenverse;
        Result[1] := ispWikimedia;
      end;
  end;
end;

function TdlgAddImage.ScopeIsUrl: boolean;
begin
  Result := CbProvider.ItemIndex = 3;
end;

function TdlgAddImage.AlreadyListed(const AUrl: string): boolean;
var
  i: integer;
begin
  Result := False;
  if AUrl = '' then Exit;
  for i := 0 to High(FResults) do
    if SameText(FResults[i].FullURL, AUrl) then
      Exit(True);
end;

{ Appends one hit to the model and to the list box, keeping the two index
  aligned - SelectResult and BtnAddClick both index FResults by row. }
procedure TdlgAddImage.AppendResult(const AResult: TSearchResult);
var
  n: integer;
  Row: string;
begin
  n := Length(FResults);
  SetLength(FResults, n + 1);
  FResults[n] := AResult;
  Row := AResult.Title;
  { Only worth the noise when more than one backend can appear in the list. }
  if FMultiSource then
    Row := '[' + ProviderToName(AResult.Source) + '] ' + Row;
  LstResults.Items.Add(Row);
end;

procedure TdlgAddImage.RemoveSearchThread(AThread: TSearchThread);
var
  i, j: integer;
begin
  for i := 0 to High(FSearchThreads) do
    if FSearchThreads[i] = AThread then
    begin
      for j := i to High(FSearchThreads) - 1 do
        FSearchThreads[j] := FSearchThreads[j + 1];
      SetLength(FSearchThreads, Length(FSearchThreads) - 1);
      Exit;
    end;
end;

{ Detaches every worker of the current search.  Bumping the epoch is what
  actually invalidates them: a worker already past its abort check still
  reaches SearchDone, which drops it on the epoch test. }
procedure TdlgAddImage.DetachSearches;
var
  i: integer;
begin
  Inc(FSearchEpoch);
  for i := 0 to High(FSearchThreads) do
  begin
    FSearchThreads[i].OnTerminate := nil;
    FSearchThreads[i].Terminate;
  end;
  SetLength(FSearchThreads, 0);
  FSearchPending := 0;
end;

procedure TdlgAddImage.DetachThreads;
begin
  DetachSearches;
  if Assigned(FPreviewThread) then
  begin
    FPreviewThread.OnTerminate := nil;
    FPreviewThread.Terminate;
    FPreviewThread := nil;
  end;
  if Assigned(FFetchThread) then
  begin
    FFetchThread.OnTerminate := nil;
    FFetchThread.Terminate;
    FFetchThread := nil;
  end;
end;

procedure TdlgAddImage.ClearPreview;
begin
  FreeAndNil(FPreviewStream);
  FPreviewURL := '';
  ImgPreview.Picture.Clear;
  LabelLicense.Caption := '';
  LabelLicense.Hint := '';
end;

procedure TdlgAddImage.ShowInfo(const Msg: string; IsError: boolean);
begin
  LabelInfo.Caption := Msg;
  if IsError then
    LabelInfo.Font.Color := clRed
  else
    LabelInfo.Font.Color := clWindowText;
end;

procedure TdlgAddImage.FormCreate(Sender: TObject);
begin
  FResults := nil;
  FSelected := -1;
  FPreviewStream := nil;
  FPreviewURL := '';
  FImageStream := nil;
  FSearchEpoch := 0;
  FSearchPending := 0;
  FSearchErrors := '';
  FMultiSource := False;
  BtnAdd.Enabled := False;
  InitSettingsPersistence;
  CbProviderChange(nil);
end;

procedure TdlgAddImage.LoadSettings;
begin
  { Key renamed from 'Provider': the combo gained an "All sources" entry at
    index 0, so old stored indices no longer mean the same thing. }
  CbProvider.ItemIndex := AppSettings.ReadInteger('AddImage', 'Source', 0);
  if (CbProvider.ItemIndex < 0) or
     (CbProvider.ItemIndex >= CbProvider.Items.Count) then
    CbProvider.ItemIndex := 0;
  EdQuery.Text := AppSettings.ReadString('AddImage', 'Query', '');
end;

procedure TdlgAddImage.SaveSettings;
begin
  AppSettings.WriteInteger('AddImage', 'Source', CbProvider.ItemIndex);
  AppSettings.WriteString('AddImage', 'Query', EdQuery.Text);
end;

procedure TdlgAddImage.CbProviderChange(Sender: TObject);
begin
  if ScopeIsUrl then
    BtnSearch.Caption := 'Fetch'
  else
    BtnSearch.Caption := 'Search';
end;

procedure TdlgAddImage.BtnSearchClick(Sender: TObject);
begin
  DoSearch;
end;

procedure TdlgAddImage.SetBusy(ABusy: boolean);
begin
  EdQuery.Enabled := not ABusy;
  BtnSearch.Enabled := not ABusy;
  LstResults.Enabled := not ABusy;
  { Also frozen while busy: changing the provider mid-search would label the
    incoming results with the wrong source, and a second Add would start a
    competing download. }
  CbProvider.Enabled := not ABusy;
  if ABusy then
  begin
    BtnAdd.Enabled := False;
    Screen.Cursor := crHourGlass;
  end
  else
    Screen.Cursor := crDefault;
end;

procedure TdlgAddImage.DoSearch;
var
  Provs: TProviderList;
  i: integer;
begin
  { Any search still running keeps going until its next transfer callback
    notices Terminated; the epoch bump makes its results irrelevant. }
  DetachSearches;
  ClearPreview;
  BtnAdd.Enabled := False;
  LstResults.Clear;
  FResults := nil;
  FSelected := -1;
  FSearchErrors := '';

  if Trim(EdQuery.Text) = '' then
  begin
    if ScopeIsUrl then
      ShowInfo('Paste an image URL first.', True)
    else
      ShowInfo('Enter search terms.', True);
    Exit;
  end;

  if ScopeIsUrl then
  begin
    SetLength(Provs, 1);
    Provs[0] := ispUrl;
  end
  else
    Provs := ScopeProviders;
  if Length(Provs) = 0 then
  begin
    ShowInfo('No source selected.', True);
    Exit;
  end;
  FMultiSource := Length(Provs) > 1;

  SetBusy(True);
  if FMultiSource then
    ShowInfo(Format('Searching %d sources…', [Length(Provs)]), False)
  else
    ShowInfo('Searching…', False);

  { Create every worker before starting any, so FSearchPending is already
    final when the first one finishes. }
  SetLength(FSearchThreads, Length(Provs));
  FSearchPending := Length(Provs);
  for i := 0 to High(Provs) do
  begin
    FSearchThreads[i] := TSearchThread.Create(EdQuery.Text, Provs[i],
      FSearchEpoch);
    FSearchThreads[i].OnTerminate := @SearchDone;
  end;
  for i := 0 to High(FSearchThreads) do
    FSearchThreads[i].Start;
end;

procedure TdlgAddImage.SearchDone(Sender: TObject);
var
  th: TSearchThread;
  i: integer;
  WasUrl: boolean;
begin
  th := TSearchThread(Sender);
  { Superseded by a newer search, or detached at close. }
  if th.Epoch <> FSearchEpoch then Exit;
  RemoveSearchThread(th);
  if FSearchPending > 0 then
    Dec(FSearchPending);
  WasUrl := th.Provider = ispUrl;

  if th.Ok then
  begin
    { Providers overlap (Wikimedia images resurface through Openverse), so
      merge on FullURL rather than concatenating blindly. }
    for i := 0 to High(th.Results) do
      if not AlreadyListed(th.Results[i].FullURL) then
        AppendResult(th.Results[i]);
  end
  else if th.ErrMsg <> '' then
  begin
    if FSearchErrors <> '' then
      FSearchErrors := FSearchErrors + '; ';
    FSearchErrors := FSearchErrors +
      ProviderToName(th.Provider) + ': ' + th.ErrMsg;
  end;

  { Wait for every provider before settling the UI. }
  if FSearchPending > 0 then
  begin
    ShowInfo(Format('%d image(s) so far, %d source(s) still searching…',
      [Length(FResults), FSearchPending]), False);
    Exit;
  end;

  SetBusy(False);
  if Length(FResults) = 0 then
  begin
    if FSearchErrors <> '' then
      ShowInfo(FSearchErrors, True)
    else
      ShowInfo('No images found.', False);
    Exit;
  end;

  if WasUrl and (Length(FResults) = 1) then
  begin
    { A pasted URL yields exactly one hit — preview it straight away
      instead of making the user click the single row. }
    LstResults.ItemIndex := 0;
    SelectResult(0);
    Exit;
  end;

  if FSearchErrors <> '' then
    { Partial success: say so rather than silently showing a short list. }
    ShowInfo(Format('%d image(s) found. Some sources failed — %s',
      [Length(FResults), FSearchErrors]), True)
  else
    ShowInfo(Format('%d image(s) found. Pick one and press Add.',
      [Length(FResults)]), False);
end;

procedure TdlgAddImage.LstResultsClick(Sender: TObject);
begin
  SelectResult(LstResults.ItemIndex);
end;

procedure TdlgAddImage.SelectResult(Idx: integer);
var
  r: TSearchResult;
begin
  if (Idx < 0) or (Idx > High(FResults)) then Exit;
  r := FResults[Idx];
  if r.ThumbURL = '' then
  begin
    ShowInfo('This result has no downloadable image.', True);
    Exit;
  end;

  if Assigned(FPreviewThread) then
  begin
    FPreviewThread.OnTerminate := nil;
    FPreviewThread.Terminate;
    FPreviewThread := nil;
  end;

  ClearPreview;
  FSelected := -1;
  BtnAdd.Enabled := False;

  SetBusy(True);
  ShowInfo('Loading preview…', False);
  FPreviewThread := TPreviewThread.Create(r, Idx);
  FPreviewThread.OnTerminate := @PreviewDone;
  FPreviewThread.Start;
end;

procedure TdlgAddImage.PreviewDone(Sender: TObject);
var
  th: TPreviewThread;
  Img: TLazIntfImage;
  Bmp: TBitmap;
begin
  if Sender <> FPreviewThread then Exit;
  th := TPreviewThread(Sender);
  FPreviewThread := nil;
  SetBusy(False);
  if not th.Ok or (th.Img = nil) then
  begin
    ShowInfo('Unsupported or corrupt preview image.', True);
    Exit;
  end;

  Img := th.ReleaseImg;
  try
    Bmp := IntfToBitmap(Img);
    try
      if Bmp = nil then
      begin
        ShowInfo('Could not render the preview.', True);
        Exit;
      end;
      ImgPreview.Picture.Assign(Bmp);
    finally
      Bmp.Free;
    end;
  finally
    Img.Free;
  end;

  FPreviewStream := th.ReleaseStream;
  FPreviewURL := th.Url;
  FSelected := th.Idx;
  LabelLicense.Caption := 'License: ' + th.License;
  if th.PageURL <> '' then
    LabelLicense.Hint := th.PageURL;
  ShowInfo('Preview ready. Press Add to insert it as page 1.', False);
  BtnAdd.Enabled := True;
end;

procedure TdlgAddImage.BtnAddClick(Sender: TObject);
var
  r: TSearchResult;
begin
  if (FSelected < 0) or (FSelected > High(FResults)) then
  begin
    ShowInfo('Select an image first.', True);
    Exit;
  end;
  r := FResults[FSelected];
  if SameText(r.FullURL, FPreviewURL) and (FPreviewStream <> nil) then
  begin
    { Reuse the already-downloaded (URL-mode) bytes — no network needed. }
    FImageStream := FPreviewStream;
    FPreviewStream := nil;
    ModalResult := mrOk;
    Exit;
  end;

  if Assigned(FFetchThread) then
  begin
    FFetchThread.OnTerminate := nil;
    FFetchThread.Terminate;
    FFetchThread := nil;
  end;

  SetBusy(True);
  ShowInfo('Downloading image…', False);
  FFetchThread := TFetchThread.Create(r);
  FFetchThread.OnTerminate := @FetchDone;
  FFetchThread.Start;
end;

procedure TdlgAddImage.FetchDone(Sender: TObject);
var
  th: TFetchThread;
begin
  if Sender <> FFetchThread then Exit;
  th := TFetchThread(Sender);
  FFetchThread := nil;
  SetBusy(False);
  if th.Ok then
  begin
    FImageStream := th.ReleaseStream;
    ModalResult := mrOk;
  end
  else
  begin
    ShowInfo('Could not download image: ' + th.ErrMsg, True);
    { SetBusy(False) cleared it; the pick is still valid, so allow a retry. }
    BtnAdd.Enabled := FSelected >= 0;
  end;
end;

procedure TdlgAddImage.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  if ModalResult = mrOk then
    CanClose := Assigned(FImageStream)
  else
  begin
    DetachThreads;
    CanClose := True;
  end;
end;

function TdlgAddImage.ReleaseImageStream: TMemoryStream;
begin
  Result := FImageStream;
  FImageStream := nil;
end;

destructor TdlgAddImage.Destroy;
begin
  DetachThreads;
  FreeAndNil(FPreviewStream);
  FreeAndNil(FImageStream);
  inherited Destroy;
end;

end.
