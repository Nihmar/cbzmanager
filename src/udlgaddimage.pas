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
    function CurrentProvider: TImageSearchProvider;
    procedure ClearPreview;
    procedure ShowInfo(const Msg: string; IsError: boolean);
    procedure DoSearch;
    procedure SelectResult(Idx: integer);
    procedure AddFromURL;
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

procedure TdlgAddImage.DoSearch;
var
  ErrMsg: string;
  i: integer;
begin
  ClearPreview;
  BtnAdd.Enabled := False;
  LstResults.Clear;
  FResults := nil;
  FSelected := -1;

  Screen.Cursor := crHourGlass;
  try
    if not SearchImages(EdQuery.Text, CurrentProvider, FResults, ErrMsg) then
    begin
      ShowInfo(ErrMsg, True);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;

  if Length(FResults) = 0 then
  begin
    ShowInfo('No images found.', False);
    Exit;
  end;

  for i := 0 to High(FResults) do
    LstResults.Items.Add(FResults[i].Title);
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
  Stream: TMemoryStream;
  Img: TLazIntfImage;
  Bmp: TBitmap;
  ErrMsg: string;
begin
  if (Idx < 0) or (Idx > High(FResults)) then Exit;
  r := FResults[Idx];
  if r.ThumbURL = '' then
  begin
    ShowInfo('This result has no downloadable image.', True);
    Exit;
  end;

  ClearPreview;
  FSelected := Idx;

  Screen.Cursor := crHourGlass;
  try
    if not DownloadImage(r.ThumbURL, Stream, ErrMsg) then
    begin
      ShowInfo('Could not load preview: ' + ErrMsg, True);
      FSelected := -1;
      Exit;
    end;
    Img := DecodeImage(Stream, r.Ext, 640, 640);
  finally
    Screen.Cursor := crDefault;
  end;

  if Img = nil then
  begin
    FreeAndNil(Stream);
    ShowInfo('Unsupported or corrupt preview image.', True);
    FSelected := -1;
    Exit;
  end;

  Bmp := IntfToBitmap(Img);
  try
    ImgPreview.Picture.Assign(Bmp);
  finally
    Bmp.Free;
  end;
  Img.Free;

  FPreviewStream := Stream;
  FPreviewURL := r.ThumbURL;
  LabelLicense.Caption := 'License: ' + r.License;
  if r.PageURL <> '' then
    LabelLicense.Hint := r.PageURL;
  BtnAdd.Enabled := True;
end;

procedure TdlgAddImage.AddFromURL;
var
  r: TSearchResult;
  Stream: TMemoryStream;
  ErrMsg: string;
begin
  r := FResults[FSelected];
  if SameText(r.FullURL, FPreviewURL) and (FPreviewStream <> nil) then
  begin
    { Reuse the already-downloaded (URL-mode) bytes. }
    FImageStream := FPreviewStream;
    FPreviewStream := nil;
    ModalResult := mrOk;
    Exit;
  end;

  Screen.Cursor := crHourGlass;
  try
    if not DownloadImage(r.FullURL, Stream, ErrMsg) then
    begin
      ShowInfo('Could not download image: ' + ErrMsg, True);
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  FImageStream := Stream;
  ModalResult := mrOk;
end;

procedure TdlgAddImage.BtnAddClick(Sender: TObject);
begin
  if FSelected < 0 then
  begin
    ShowInfo('Select an image first.', True);
    Exit;
  end;
  AddFromURL;
end;

procedure TdlgAddImage.FormCloseQuery(Sender: TObject; var CanClose: boolean);
begin
  if ModalResult = mrOk then
    CanClose := Assigned(FImageStream)
  else
    CanClose := True;
end;

function TdlgAddImage.ReleaseImageStream: TMemoryStream;
begin
  Result := FImageStream;
  FImageStream := nil;
end;

destructor TdlgAddImage.Destroy;
begin
  FreeAndNil(FPreviewStream);
  FreeAndNil(FImageStream);
  inherited Destroy;
end;

end.
