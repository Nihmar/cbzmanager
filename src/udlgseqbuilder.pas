unit udlgseqbuilder;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  IntfGraphics, uloaderthread, uimgutil, uservicemerge, udlgbase,
  upreviewloader, Types;

type
  { TdlgSeqBuilder }

  TdlgSeqBuilder = class(TForm)
    BtnAddVolume: TButton;
    BtnUndo: TButton;
    BtnCancel: TButton;
    BtnConfirm: TButton;
    BtnPrevPage: TButton;
    BtnNextPage: TButton;
    CbSequence: TComboBox;
    ILChapters: TImageList;
    ImgPreview: TImage;
    LblPreviewPage: TLabel;
    LblPreviewTitle: TLabel;
    LblZoomVal: TLabel;
    LblStatus: TLabel;
    LVChapters: TListView;
    PanelZoomBar: TPanel;
    PanelPreviewNav: TPanel;
    PanelPreview: TPanel;
    PanelMiddle: TPanel;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    ScrollBoxPreview: TScrollBox;
    ZoomScroll: TTrackBar;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure LVChaptersDblClick(Sender: TObject);
    procedure LVChaptersSelectItem(Sender: TObject; Item: TListItem;
      Selected: boolean);
    procedure BtnAddVolumeClick(Sender: TObject);
    procedure BtnUndoClick(Sender: TObject);
    procedure BtnPrevPageClick(Sender: TObject);
    procedure BtnNextPageClick(Sender: TObject);
    procedure ZoomScrollChange(Sender: TObject);
    procedure ZoomScrollMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
    procedure PreviewLoaderTerminated(Sender: TObject);
    procedure PreviewMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
  private
    { Chapter thumbnail zoom }
    FDir: string;
    FFiles: TStringArray;
    FImages: TLazIntfImageList;
    FVolumes: TIntArray;
    FRemovedCount: integer;

    FPreviewLoader: TPreviewLoader;
    FPreviewPages: TLazIntfImageList;
    FPreviewIndex: integer;
    FZoomLevel: double;

    procedure ApplyZoom;
    procedure RebuildGrid;
    procedure RefreshStatus;
    procedure ShowPreviewPage;
    procedure StartPreview(AFileIndex: integer);
    procedure ClearPreview;
    procedure StopPreviewLoader;
    function SelectedCount: integer;
  public
    procedure LoadChapters(const AFiles: TStringArray;
      AImages: TLazIntfImageList; const ADir: string);
    function GetSequence: TIntArray;
  end;

implementation

{$R *.lfm}

uses
  LCLIntf,
  LCLType;

const
  LVM_SETICONSPACING = $1000 + 53;
  LVM_ARRANGE = $1000 + 22;

{ TdlgSeqBuilder }

procedure TdlgSeqBuilder.FormCreate(Sender: TObject);
begin
  { Zoom controls for chapter thumbnails }
  FRemovedCount := 0;
  FVolumes := nil;
  FPreviewPages := nil;
  FPreviewLoader := nil;
  FPreviewIndex := 0;
  FZoomLevel := 1.0;

  RebuildGrid;
end;

procedure TdlgSeqBuilder.FormDestroy(Sender: TObject);
begin
  StopPreviewLoader;
  FreeAndNil(FPreviewPages);
end;

procedure TdlgSeqBuilder.FormKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (ssCtrl in Shift) then
  begin
    if BtnAddVolume.Enabled then
    begin
      BtnAddVolumeClick(Self);
      Key := 0;
    end;
    Exit;
  end;
  if (Key = VK_Z) and (ssCtrl in Shift) and not (ssAlt in Shift) then
  begin
    if BtnUndo.Enabled then
    begin
      BtnUndoClick(Self);
      Key := 0;
    end;
    Exit;
  end;
  if (Key = VK_LEFT) and (Shift = []) then
  begin
    if BtnPrevPage.Enabled then
    begin
      BtnPrevPageClick(Self);
      Key := 0;
    end;
    Exit;
  end;
  if (Key = VK_RIGHT) and (Shift = []) then
  begin
    if BtnNextPage.Enabled then
    begin
      BtnNextPageClick(Self);
      Key := 0;
    end;
    Exit;
  end;
end;

procedure TdlgSeqBuilder.FormShow(Sender: TObject);
begin
  RebuildGrid;
end;

procedure TdlgSeqBuilder.LVChaptersSelectItem(Sender: TObject;
  Item: TListItem; Selected: boolean);
var
  N: integer;
begin
  N := SelectedCount;
  if N > 0 then
  begin
    BtnAddVolume.Enabled := True;
    BtnAddVolume.Caption := Format('Add volume (%d ch.)', [N]);
  end
  else
  begin
    BtnAddVolume.Enabled := False;
    BtnAddVolume.Caption := 'Add volume (0 ch.)';
  end;
end;

function TdlgSeqBuilder.SelectedCount: integer;
var
  i: integer;
begin
  Result := 0;
  for i := 0 to LVChapters.Items.Count - 1 do
    if LVChapters.Items[i].Selected then
      Inc(Result);
end;

procedure TdlgSeqBuilder.BtnAddVolumeClick(Sender: TObject);
var
  N: integer;
begin
  N := SelectedCount;
  if N = 0 then Exit;

  SetLength(FVolumes, Length(FVolumes) + 1);
  FVolumes[High(FVolumes)] := N;
  Inc(FRemovedCount, N);

  ClearPreview;
  RebuildGrid;
  RefreshStatus;
  BtnUndo.Enabled := True;
end;

procedure TdlgSeqBuilder.BtnUndoClick(Sender: TObject);
begin
  if Length(FVolumes) = 0 then Exit;

  Dec(FRemovedCount, FVolumes[High(FVolumes)]);
  SetLength(FVolumes, Length(FVolumes) - 1);

  ClearPreview;
  RebuildGrid;
  RefreshStatus;
  BtnUndo.Enabled := Length(FVolumes) > 0;
end;

procedure TdlgSeqBuilder.LVChaptersDblClick(Sender: TObject);
var
  Item: TListItem;
begin
  Item := LVChapters.Selected;
  if Item = nil then Exit;
  StartPreview(FRemovedCount + Item.Index);
end;

procedure TdlgSeqBuilder.StartPreview(AFileIndex: integer);
var
  FilePath: string;
begin
  if (AFileIndex < 0) or (AFileIndex > High(FFiles)) then Exit;

  StopPreviewLoader;
  FreeAndNil(FPreviewPages);
  FPreviewIndex := 0;
  FZoomLevel := 1.0;

  FilePath := IncludeTrailingPathDelimiter(FDir) + FFiles[AFileIndex];
  LblPreviewTitle.Caption := ChangeFileExt(FFiles[AFileIndex], '');
  LblPreviewPage.Caption := 'Loading...';
  ImgPreview.Picture.Clear;
  BtnPrevPage.Enabled := False;
  BtnNextPage.Enabled := False;

  FPreviewLoader := TPreviewLoader.Create(FilePath);
  FPreviewLoader.OnTerminate := @PreviewLoaderTerminated;
  FPreviewLoader.Start;
end;

procedure TdlgSeqBuilder.PreviewLoaderTerminated(Sender: TObject);
begin
  if (FPreviewLoader.FatalException <> nil) or (FPreviewLoader.Pages.Count = 0) then
  begin
    LblPreviewPage.Caption := 'No pages';
    FreeAndNil(FPreviewLoader);
    Exit;
  end;

  FPreviewPages := FPreviewLoader.ExtractPages;
  FreeAndNil(FPreviewLoader);

  FPreviewIndex := 0;
  ShowPreviewPage;
end;

procedure TdlgSeqBuilder.ShowPreviewPage;
var
  Bmp: TBitmap;
begin
  if (FPreviewPages = nil) or (FPreviewPages.Count = 0) then
  begin
    ImgPreview.Picture.Clear;
    LblPreviewPage.Caption := '';
    BtnPrevPage.Enabled := False;
    BtnNextPage.Enabled := False;
    Exit;
  end;

  if FPreviewIndex < 0 then FPreviewIndex := 0;
  if FPreviewIndex >= FPreviewPages.Count then
    FPreviewIndex := FPreviewPages.Count - 1;

  Bmp := IntfToBitmap(FPreviewPages[FPreviewIndex]);
  if Bmp <> nil then
  begin
    try
      ImgPreview.Picture.Assign(Bmp);
    finally
      Bmp.Free;
    end;
  end;

  LblPreviewPage.Caption := Format('%d / %d', [FPreviewIndex + 1,
    FPreviewPages.Count]);
  BtnPrevPage.Enabled := FPreviewIndex > 0;
  BtnNextPage.Enabled := FPreviewIndex < FPreviewPages.Count - 1;
  ApplyZoom;
end;

procedure TdlgSeqBuilder.BtnPrevPageClick(Sender: TObject);
begin
  if FPreviewIndex > 0 then
  begin
    Dec(FPreviewIndex);
    ShowPreviewPage;
  end;
end;

procedure TdlgSeqBuilder.BtnNextPageClick(Sender: TObject);
begin
  if (FPreviewPages <> nil) and (FPreviewIndex < FPreviewPages.Count - 1) then
  begin
    Inc(FPreviewIndex);
    ShowPreviewPage;
  end;
end;

procedure TdlgSeqBuilder.ZoomScrollChange(Sender: TObject);
begin
  LblZoomVal.Caption := IntToStr(ZoomScroll.Position);
  RebuildGrid;
end;

procedure TdlgSeqBuilder.ZoomScrollMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
begin
  if WheelDelta > 0 then
    ZoomScroll.Position := ZoomScroll.Position + ZoomScroll.Frequency
  else
    ZoomScroll.Position := ZoomScroll.Position - ZoomScroll.Frequency;
  Handled := True;
end;

procedure TdlgSeqBuilder.StopPreviewLoader;
begin
  if FPreviewLoader <> nil then
  begin
    FPreviewLoader.Terminate;
    FPreviewLoader.WaitFor;
    FreeAndNil(FPreviewLoader);
  end;
end;

procedure TdlgSeqBuilder.ClearPreview;
begin
  StopPreviewLoader;
  FreeAndNil(FPreviewPages);
  FPreviewIndex := 0;
  FZoomLevel := 1.0;
  ImgPreview.Picture.Clear;
  LblPreviewTitle.Caption := 'Double-click to preview';
  LblPreviewPage.Caption := '';
  BtnPrevPage.Enabled := False;
  BtnNextPage.Enabled := False;
end;

procedure TdlgSeqBuilder.PreviewMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
begin
  if not (ssCtrl in Shift) then Exit;
  if (FPreviewPages = nil) or (FPreviewPages.Count = 0) then Exit;
  if WheelDelta > 0 then
    FZoomLevel := FZoomLevel + 0.15
  else
    FZoomLevel := FZoomLevel - 0.15;
  if FZoomLevel < 1.0 then FZoomLevel := 1.0;
  if FZoomLevel > 5.0 then FZoomLevel := 5.0;
  ApplyZoom;
  Handled := True;
end;

procedure TdlgSeqBuilder.ApplyZoom;
var
  SrcW, SrcH, AreaW, AreaH: integer;
  Ratio: double;
begin
  if (FPreviewPages = nil) or (FPreviewIndex < 0) or
    (FPreviewIndex >= FPreviewPages.Count) then Exit;
  if FZoomLevel <= 1.0 then
  begin
    ImgPreview.Align := alClient;
    ImgPreview.Stretch := True;
    ImgPreview.Proportional := True;
    ImgPreview.Center := True;
  end
  else
  begin
    SrcW := FPreviewPages[FPreviewIndex].Width;
    SrcH := FPreviewPages[FPreviewIndex].Height;
    AreaW := ScrollBoxPreview.ClientWidth;
    AreaH := ScrollBoxPreview.ClientHeight;
    if (SrcW = 0) or (SrcH = 0) then Exit;
    Ratio := AreaW / SrcW;
    if AreaH / SrcH < Ratio then
      Ratio := AreaH / SrcH;
    ImgPreview.Align := alNone;
    ImgPreview.Stretch := True;
    ImgPreview.Proportional := False;
    ImgPreview.Center := False;
    ImgPreview.Left := 0;
    ImgPreview.Top := 0;
    ImgPreview.Width := Round(SrcW * Ratio * FZoomLevel);
    ImgPreview.Height := Round(SrcH * Ratio * FZoomLevel);
  end;
end;

procedure TdlgSeqBuilder.RebuildGrid;
var
  i, Idx, TW, TH, SpacingX, SpacingY: integer;
  It: TListItem;
begin
  TW := ZoomScroll.Position;
  TH := ThumbHeight(TW);

  ILChapters.Clear;
  ILChapters.Width := TW;
  ILChapters.Height := TH;

  LVChapters.BeginUpdate;
  try
    LVChapters.LargeImages := nil;
    LVChapters.Items.Clear;

    for i := FRemovedCount to High(FFiles) do
    begin
      if i < FImages.Count then
        Idx := AppendThumb(ILChapters, FImages[i])
      else
        Idx := -1;

      It := LVChapters.Items.Add;
      It.Caption := ChangeFileExt(FFiles[i], '');
      It.ImageIndex := Idx;
    end;

    LVChapters.LargeImages := ILChapters;
  finally
    LVChapters.EndUpdate;
  end;

  if LVChapters.HandleAllocated then
  begin
    SpacingX := TW + 40;
    SpacingY := TH + 32;
    SendMessage(LVChapters.Handle, LVM_SETICONSPACING, 0,
      LParam(SpacingX or (SpacingY shl 16)));
    SendMessage(LVChapters.Handle, LVM_ARRANGE, 0, 0);
  end;

  BtnAddVolume.Enabled := False;
  BtnAddVolume.Caption := 'Add volume (0 ch.)';
end;

procedure TdlgSeqBuilder.RefreshStatus;
var
  i, Remaining: integer;
begin
  LblStatus.Caption := Format('Volume %d | Select chapters, then press "Add volume"',
    [Length(FVolumes) + 1]);

  Remaining := Length(FFiles) - FRemovedCount;

  CbSequence.Items.BeginUpdate;
  try
    CbSequence.Items.Clear;
    if Length(FVolumes) = 0 then
    begin
      CbSequence.Items.Add('Sequence: (none yet)');
    end
    else
    begin
      for i := 0 to High(FVolumes) do
        CbSequence.Items.Add(Format('Vol.%d: %d ch.', [i + 1, FVolumes[i]]));
      if Remaining = 0 then
        CbSequence.Items.Add('  (all assigned)')
      else
        CbSequence.Items.Add(Format('  %d remaining', [Remaining]));
      CbSequence.ItemIndex := High(FVolumes);  { select last volume }
    end;
  finally
    CbSequence.Items.EndUpdate;
  end;
end;

procedure TdlgSeqBuilder.LoadChapters(const AFiles: TStringArray;
  AImages: TLazIntfImageList; const ADir: string);
begin
  FFiles := AFiles;
  FImages := AImages;
  FDir := ADir;
  FRemovedCount := 0;
  FVolumes := nil;
  RebuildGrid;
  RefreshStatus;
end;

function TdlgSeqBuilder.GetSequence: TIntArray;
begin
  Result := Copy(FVolumes, 0, Length(FVolumes));
end;

end.
