unit udlgaddimage;

{$mode ObjFPC}{$H+}

{
  udlgaddimage.pas - Add image from internet dialog.

  Lets the user search a free, key-less image source (Openverse, Wikimedia
  Commons) or paste a direct image URL, pick one result, preview it, and
  hand the raw bytes back to the main form.  The main form then stages the
  image as the new first page of the open CBZ (nothing is written until the
  user saves via the stage bar).

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
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, IntfGraphics, udlgbase, usettings, uimgsrc, uzipeditor, uimgutil;

type
  { Background worker that runs a provider search off the main thread. }
  TSearchThread = class(TThread)
  private
    FQuery: string;
    FProvider: TImageSearchProvider;
    FResults: TSearchResults;
    FErrMsg: string;
    FOk: boolean;
  public
    constructor Create(const AQuery: string; AProvider: TImageSearchProvider);
    procedure Execute; override;
    property Ok: boolean read FOk;
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
  public
    constructor Create(const AResult: TSearchResult; AIdx: integer);
    destructor Destroy; override;
    procedure Execute; override;
    property Ok: boolean read FOk;
    property Img: TLazIntfImage read FImg;
    property Stream: TMemoryStream read FStream;
    property Url: string read FUrl;
    property License: string read FLicense;
    property PageURL: string read FPageURL;
    property Idx: integer read FIdx;
  end;

  { Background worker that downloads the full-resolution image to add. }
  TFetchThread = class(TThread)
  private
    FUrl, FExt, FLicense, FPageURL: string;
    FStream: TMemoryStream;
    FErrMsg: string;
    FOk: boolean;
  public
    constructor Create(const AResult: TSearchResult);
    destructor Destroy; override;
    procedure Execute; override;
    property Ok: boolean read FOk;
    property Stream: TMemoryStream read FStream;
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
    FSearchThread: TSearchThread;
    FPreviewThread: TPreviewThread;
    FFetchThread: TFetchThread;
    function CurrentProvider: TImageSearchProvider;
    procedure ClearPreview;
    procedure ShowInfo(const Msg: string; IsError: boolean);
    procedure DoSearch;
    procedure SelectResult(Idx: integer);
    procedure SearchDone(Sender: TObject);
    procedure PreviewDone(Sender: TObject);
    procedure FetchDone(Sender: TObject);
    procedure SetBusy(ABusy: boolean);
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
  AProvider: TImageSearchProvider);
begin
  inherited Create(True);
  FQuery := AQuery;
  FProvider := AProvider;
  SetLength(FResults, 0);
  FErrMsg := '';
  FOk := False;
  FreeOnTerminate := False;
end;

procedure TSearchThread.Execute;
begin
  FOk := SearchImages(FQuery, FProvider, FResults, FErrMsg);
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
  FreeOnTerminate := False;
end;

destructor TPreviewThread.Destroy;
begin
  FStream.Free;
  FImg.Free;
  inherited Destroy;
end;

procedure TPreviewThread.Execute;
var
  Err: string;
begin
  FOk := DownloadImage(FUrl, FStream, Err);
  if FOk then
  begin
    FImg := DecodeImage(FStream, FExt, 640, 640);
    if FImg = nil then
    begin
      FOk := False;
      FreeAndNil(FStream);
    end;
  end
  else
    FreeAndNil(FStream);
end;

{ TFetchThread }

constructor TFetchThread.Create(const AResult: TSearchResult);
begin
  inherited Create(True);
  FUrl := AResult.FullURL;
  FExt := AResult.Ext;
  FLicense := AResult.License;
  FPageURL := AResult.PageURL;
  FStream := nil;
  FErrMsg := '';
  FOk := False;
  FreeOnTerminate := False;
end;

destructor TFetchThread.Destroy;
begin
  FStream.Free;
  inherited Destroy;
end;

procedure TFetchThread.Execute;
begin
  FOk := DownloadImage(FUrl, FStream, FErrMsg);
end;

{ TdlgAddImage }

function TdlgAddImage.CurrentProvider: TImageSearchProvider;
begin
  if (CbProvider.ItemIndex >= 0) and
     (CbProvider.ItemIndex <= Ord(High(TImageSearchProvider))) then
    Result := TImageSearchProvider(CbProvider.ItemIndex)
  else
    Result := ispOpenverse;
end;

procedure TdlgAddImage.ClearPreview;
begin
  FreeAndNil(FPreviewStream);
  FPreviewURL := '';
  ImgPreview.Picture := nil;
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
  BtnAdd.Enabled := False;
  InitSettingsPersistence;
  CbProviderChange(nil);
end;

procedure TdlgAddImage.LoadSettings;
begin
  CbProvider.ItemIndex := AppSettings.ReadInteger('AddImage', 'Provider', 0);
  if (CbProvider.ItemIndex < 0) or
     (CbProvider.ItemIndex > Ord(High(TImageSearchProvider))) then
    CbProvider.ItemIndex := 0;
  EdQuery.Text := AppSettings.ReadString('AddImage', 'Query', '');
end;

procedure TdlgAddImage.SaveSettings;
begin
  AppSettings.WriteInteger('AddImage', 'Provider', CbProvider.ItemIndex);
  AppSettings.WriteString('AddImage', 'Query', EdQuery.Text);
end;

procedure TdlgAddImage.CbProviderChange(Sender: TObject);
begin
  if CurrentProvider = ispUrl then
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
  if ABusy then
    Screen.Cursor := crHourGlass
  else
    Screen.Cursor := crDefault;
end;

procedure TdlgAddImage.DetachThreads;
begin
  if Assigned(FSearchThread) then
  begin
    FSearchThread.OnTerminate := nil;
    FSearchThread.Terminate;
    FSearchThread := nil;
  end;
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

procedure TdlgAddImage.DoSearch;
begin
  if Assigned(FSearchThread) then
  begin
    FSearchThread.OnTerminate := nil;
    FSearchThread.Terminate;
    FSearchThread := nil;
  end;
  ClearPreview;
  BtnAdd.Enabled := False;
  LstResults.Clear;
  FResults := nil;
  FSelected := -1;

  SetBusy(True);
  ShowInfo('Searching…', False);
  FSearchThread := TSearchThread.Create(EdQuery.Text, CurrentProvider);
  FSearchThread.OnTerminate := @SearchDone;
  FSearchThread.FreeOnTerminate := True;
  FSearchThread.Start;
end;

procedure TdlgAddImage.SearchDone(Sender: TObject);
var
  th: TSearchThread;
  i: integer;
begin
  th := TSearchThread(Sender);
  FSearchThread := nil;
  SetBusy(False);
  if th.FOk then
  begin
    FResults := th.Results;
    if Length(FResults) = 0 then
      ShowInfo('No images found.', False)
    else
    begin
      for i := 0 to High(FResults) do
        LstResults.Items.Add(FResults[i].Title);
      ShowInfo(Format('%d image(s) found. Pick one and press Add.',
        [Length(FResults)]), False);
    end;
  end
  else
    ShowInfo(th.ErrMsg, True);
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
  FPreviewThread.FreeOnTerminate := True;
  FPreviewThread.Start;
end;

procedure TdlgAddImage.PreviewDone(Sender: TObject);
var
  th: TPreviewThread;
  Bmp: TBitmap;
begin
  th := TPreviewThread(Sender);
  FPreviewThread := nil;
  SetBusy(False);
  if not th.Ok or (th.Img = nil) then
  begin
    ShowInfo('Unsupported or corrupt preview image.', True);
    Exit;
  end;

  Bmp := IntfToBitmap(th.Img);
  try
    ImgPreview.Picture.Assign(Bmp);
  finally
    Bmp.Free;
    th.Img.Free;
    th.FImg := nil;
  end;

  FPreviewStream := th.Stream;
  th.FStream := nil;
  FPreviewURL := th.Url;
  FSelected := th.Idx;
  LabelLicense.Caption := 'License: ' + th.License;
  if th.PageURL <> '' then
    LabelLicense.Hint := th.PageURL;
  BtnAdd.Enabled := True;
end;

procedure TdlgAddImage.BtnAddClick(Sender: TObject);
var
  r: TSearchResult;
begin
  if FSelected < 0 then
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
  FFetchThread.FreeOnTerminate := True;
  FFetchThread.Start;
end;

procedure TdlgAddImage.FetchDone(Sender: TObject);
var
  th: TFetchThread;
begin
  th := TFetchThread(Sender);
  FFetchThread := nil;
  SetBusy(False);
  if th.Ok then
  begin
    FImageStream := th.Stream;
    th.FStream := nil;
    ModalResult := mrOk;
  end
  else
    ShowInfo('Could not download image: ' + th.ErrMsg, True);
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
