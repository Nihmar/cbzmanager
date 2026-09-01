unit udlgseqbuilder;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  IntfGraphics, uloaderthread, uimgutil, uservicemerge, udlgbase,
  upreviewloader, Types, uselection;

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
    procedure FormKeyUp(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormDeactivate(Sender: TObject);
    procedure LVChaptersDblClick(Sender: TObject);
    procedure LVChaptersMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure LVChaptersMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
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
    { For each file in FFiles, its index into FImages (thumbnail); -1 when
      no thumbnail is available.  Lets the caller pass a chapter-only file
      list whose thumbnails live in a larger, full-directory image list. }
    FImageIdx: TIntArray;
    FVolumes: TIntArray;
    FRemovedCount: integer;

    FPreviewLoader: TPreviewLoader;
    FPreviewPages: TLazIntfImageList;
    FPreviewIndex: integer;
    FZoomLevel: double;
    { Explorer-style selection state for LVChapters. }
    FAnchor: integer;
    FSel: TIntegerDynArray;
    FPendingSel: TIntegerDynArray;
    FPendingFocus: integer;
    FPendingList: TListView;
    FReassertTicks: integer;
    FReassertStable: integer;
    { Live modifier-key state tracked via OnKeyDown / OnKeyUp. }
    FKeyShiftDown: boolean;
    FKeyCtrlDown: boolean;
    procedure AppIdle(Sender: TObject; var Done: boolean);

    procedure ApplyZoom(const AOldZoom: double);
    procedure RebuildGrid;
    function ChapterRangeStr(AStart, ACount: integer): string;
    procedure RefreshStatus;
    procedure ShowPreviewPage;
    procedure StartPreview(AFileIndex: integer);
    procedure ClearPreview;
    procedure StopPreviewLoader;
    function SelectedCount: integer;
    procedure ClearPendingSel;
    procedure SetPendingSel(AList: TListView; const A: array of integer;
      AFocus: integer);
    procedure ReassertPendingSelection(Data: PtrInt);
    function ItemAtPoint(ALV: TListView; X, Y: integer): TListItem;
  public
    { AFiles are the chapters in merge order; AImageIdx[i] is the index of
      AFiles[i]'s thumbnail inside AImages (may be -1). }
    procedure LoadChapters(const AFiles: TStringArray;
      AImages: TLazIntfImageList; const AImageIdx: TIntArray;
      const ADir: string);
    function GetSequence: TIntArray;

    { True when the selected set (booleans over the visible items) is
      exactly the first ACount items — the only selection the merge can
      honour, because volumes are assembled in list order. }
    function IsFrontBlockSelection(const ASelected: array of boolean;
      ACount: integer): boolean;

    { Adds a volume of the next N chapters (front-consumption), updating
      the grid, status and undo state. }
    procedure AddVolume(N: integer);
  end;

implementation

{$R *.lfm}

uses
  LCLIntf,
  LCLType,
  uLog;

const
  LVM_SETICONSPACING = $1000 + 53;
  LVM_ARRANGE = $1000 + 22;
  { Wheel-delta divisor for preview panning (~40 px per notch) }
  PreviewScrollStep = 3;

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
  FAnchor := -1;
  FPendingFocus := -1;
  FPendingList := nil;
  FKeyShiftDown := False;
  FKeyCtrlDown := False;
  Application.AddOnIdleHandler(@AppIdle);

  RebuildGrid;
end;

procedure TdlgSeqBuilder.FormDestroy(Sender: TObject);
begin
  Application.RemoveOnIdleHandler(@AppIdle);
  StopPreviewLoader;
  FreeAndNil(FPreviewPages);
end;

procedure TdlgSeqBuilder.AppIdle(Sender: TObject; var Done: boolean);
begin
  if (GetKeyState(VK_LBUTTON) < 0) or (GetKeyState(VK_RBUTTON) < 0) or
     (GetKeyState(VK_MBUTTON) < 0) then Exit;
  if GetKeyState(VK_SHIFT) >= 0 then
    FKeyShiftDown := False;
  if GetKeyState(VK_CONTROL) >= 0 then
    FKeyCtrlDown := False;
end;

procedure TdlgSeqBuilder.FormKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if Key = VK_SHIFT then FKeyShiftDown := True;
  if Key = VK_CONTROL then FKeyCtrlDown := True;

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

procedure TdlgSeqBuilder.FormKeyUp(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if Key = VK_SHIFT then FKeyShiftDown := False;
  if Key = VK_CONTROL then FKeyCtrlDown := False;
end;

procedure TdlgSeqBuilder.FormDeactivate(Sender: TObject);
begin
  FKeyShiftDown := False;
  FKeyCtrlDown := False;
end;

{
  LVChaptersMouseDown
  --------------------
  Explorer/Dolphin-style selection for the chapter list, matching the main
  form's LVFilesMouseDown semantics.
}
procedure TdlgSeqBuilder.LVChaptersMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  ALV: TListView;
  It: TListItem;
  Anchor: integer;
  Cur: TIntegerDynArray;
  ShiftDown, CtrlDown: boolean;
begin
  ALV := TListView(Sender);
  It := ItemAtPoint(ALV, X, Y);

  ShiftDown := FKeyShiftDown or (ssShift in Shift) or (GetKeyState(VK_SHIFT) < 0);
  CtrlDown := FKeyCtrlDown or (ssCtrl in Shift) or (GetKeyState(VK_CONTROL) < 0);

  if Button = mbRight then
  begin
    if (It <> nil) and not It.Selected then
    begin
      if not (ssDouble in Shift) then
        ClearPendingSel;
      SetPendingSel(ALV, [It.Index], It.Index);
    end;
    Exit;
  end;

  if Button <> mbLeft then Exit;

  if not (ssDouble in Shift) then
    ClearPendingSel;

  if It = nil then
  begin
    SetPendingSel(ALV, [], -1);
    FAnchor := -1;
    Exit;
  end;

  if ShiftDown then
  begin
    Anchor := FAnchor;
    if Anchor < 0 then
    begin
      if ALV.Selected <> nil then Anchor := ALV.Selected.Index
      else Anchor := It.Index;
    end;
    if CtrlDown then
    begin
      Cur := FSel;
      SetPendingSel(ALV, UnionSel(Cur, RangeSel(Anchor, It.Index)), It.Index);
    end
    else
      SetPendingSel(ALV, RangeSel(Anchor, It.Index), It.Index);
  end
  else if CtrlDown then
  begin
    Cur := FSel;
    SetPendingSel(ALV, ToggleSel(Cur, It.Index), It.Index);
    FAnchor := It.Index;
  end
  else
  begin
    SetPendingSel(ALV, [It.Index], It.Index);
    FAnchor := It.Index;
  end;
end;

procedure TdlgSeqBuilder.LVChaptersMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: integer);
begin
  if FPendingList = nil then Exit;
  FReassertTicks := 30;
  FReassertStable := 0;
  Application.QueueAsyncCall(@ReassertPendingSelection, 0);
end;

procedure TdlgSeqBuilder.ReassertPendingSelection(Data: PtrInt);
var
  LV: TListView;
begin
  if (FPendingList = nil) or (FPendingList.Items.Count = 0) then
  begin
    ClearPendingSel;
    Exit;
  end;
  LV := FPendingList;

  if SelectionMatches(LV, FPendingSel) then
    Inc(FReassertStable)
  else
  begin
    ApplySelection(LV, FPendingSel, FPendingFocus);
    FReassertStable := 0;
  end;

  if FReassertTicks > 0 then
    Dec(FReassertTicks);
  if (FReassertStable >= 2) or (FReassertTicks <= 0) then
    ClearPendingSel
  else
    Application.QueueAsyncCall(@ReassertPendingSelection, 0);
end;

procedure TdlgSeqBuilder.ClearPendingSel;
begin
  FPendingList := nil;
  FPendingSel := nil;
  FPendingFocus := -1;
  FReassertStable := 0;
  FReassertTicks := 0;
end;

procedure TdlgSeqBuilder.SetPendingSel(AList: TListView;
  const A: array of integer; AFocus: integer);
var
  i: integer;
begin
  FPendingList := AList;
  SetLength(FPendingSel, Length(A));
  for i := 0 to High(A) do FPendingSel[i] := A[i];
  FPendingFocus := AFocus;
  SetLength(FSel, Length(A));
  for i := 0 to High(A) do FSel[i] := A[i];
end;

function TdlgSeqBuilder.ItemAtPoint(ALV: TListView; X, Y: integer): TListItem;
var
  i: integer;
  R: TRect;
  Pt: TPoint;
begin
  Result := ALV.GetItemAt(X, Y);
  if Result <> nil then Exit;
  Pt := Point(X, Y);
  for i := 0 to ALV.Items.Count - 1 do
  begin
    R := ALV.Items[i].DisplayRect(drBounds);
    if PtInRect(R, Pt) then
      Exit(ALV.Items[i]);
  end;
  Result := nil;
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

function TdlgSeqBuilder.IsFrontBlockSelection(const ASelected: array of boolean;
  ACount: integer): boolean;
var
  i: integer;
begin
  Result := False;
  if (ACount <= 0) or (Length(ASelected) < ACount) then Exit;
  for i := 0 to Length(ASelected) - 1 do
    if ASelected[i] <> (i < ACount) then Exit;
  Result := True;
end;

procedure TdlgSeqBuilder.AddVolume(N: integer);
begin
  if N <= 0 then Exit;
  SetLength(FVolumes, Length(FVolumes) + 1);
  FVolumes[High(FVolumes)] := N;
  Inc(FRemovedCount, N);
  ClearPreview;
  RebuildGrid;
  RefreshStatus;
  BtnUndo.Enabled := True;
end;

procedure TdlgSeqBuilder.BtnAddVolumeClick(Sender: TObject);
var
  N, i: integer;
  Selected: array of boolean;
begin
  N := SelectedCount;
  if N = 0 then Exit;

  { The merge assembles volumes in list order (the preview and the merge
    service both consume the chapters front-to-back), so the selection
    must be exactly the first N remaining chapters.  Arbitrary selections
    would make the volume contain different chapters than the user sees. }
  SetLength(Selected, LVChapters.Items.Count);
  for i := 0 to LVChapters.Items.Count - 1 do
    Selected[i] := LVChapters.Items[i].Selected;
  if not IsFrontBlockSelection(Selected, N) then
  begin
    LblStatus.Caption :=
      'Select chapters from the start (volumes are assembled in list order)';
    Exit;
  end;

  AddVolume(N);
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
  try
    StartPreview(FRemovedCount + Item.Index);
  except
    on E: Exception do
    begin
      { A failed preview must never crash the dialog: log the cause and
        degrade to the 'No pages' state instead of showing an exception
        dialog (e.g. range-check errors on unusual images). }
      Log('SeqBuilder preview failed: %s: %s', [E.ClassName, E.Message]);
      StopPreviewLoader;
      ClearPreview;
      LblPreviewPage.Caption := 'No pages';
    end;
  end;
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
  { Only the CURRENT loader may update the preview.  A superseded loader
    (replaced by a newer double-click, or the form closing while it was
    still running) must not touch the UI: StopPreviewLoader has already
    nilled FPreviewLoader, so Sender <> FPreviewLoader and we bail out.
    The thread frees itself (FreeOnTerminate). }
  if Sender <> FPreviewLoader then Exit;

  if (FPreviewLoader.FatalException <> nil) or (FPreviewLoader.Pages.Count = 0) then
  begin
    LblPreviewPage.Caption := 'No pages';
    FPreviewLoader := nil;
    Exit;
  end;

  FPreviewPages := FPreviewLoader.ExtractPages;
  FPreviewLoader := nil;

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
  ApplyZoom(FZoomLevel);
end;

procedure TdlgSeqBuilder.BtnPrevPageClick(Sender: TObject);
begin
  if FPreviewIndex > 0 then
  begin
    Dec(FPreviewIndex);
    FZoomLevel := 1.0;
    ShowPreviewPage;
  end;
end;

procedure TdlgSeqBuilder.BtnNextPageClick(Sender: TObject);
begin
  if (FPreviewPages <> nil) and (FPreviewIndex < FPreviewPages.Count - 1) then
  begin
    Inc(FPreviewIndex);
    FZoomLevel := 1.0;
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
    FPreviewLoader := nil;
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
var
  OldZoom: double;
begin
  if not (ssCtrl in Shift) then
  begin
    { Plain wheel pans the preview vertically (top to bottom);
      shift+wheel pans horizontally (left/right). }
    if (FPreviewPages = nil) or (FPreviewPages.Count = 0) then Exit;
    Handled := True;
    if ssShift in Shift then
      ScrollBoxPreview.HorzScrollBar.Position :=
        ScrollBoxPreview.HorzScrollBar.Position - WheelDelta div PreviewScrollStep
    else
      ScrollBoxPreview.VertScrollBar.Position :=
        ScrollBoxPreview.VertScrollBar.Position - WheelDelta div PreviewScrollStep;
    Exit;
  end;

  if (FPreviewPages = nil) or (FPreviewPages.Count = 0) then Exit;
  OldZoom := FZoomLevel;
  if WheelDelta > 0 then
    FZoomLevel := FZoomLevel + 0.15
  else
    FZoomLevel := FZoomLevel - 0.15;
  if FZoomLevel < 1.0 then FZoomLevel := 1.0;
  if FZoomLevel > 5.0 then FZoomLevel := 5.0;
  ApplyZoom(OldZoom);
  Handled := True;
end;

procedure TdlgSeqBuilder.ApplyZoom(const AOldZoom: double);
var
  SrcW, SrcH, AreaW, AreaH, OldCX, OldCY: integer;
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
    ScrollBoxPreview.HorzScrollBar.Position := 0;
    ScrollBoxPreview.VertScrollBar.Position := 0;
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

    { Anchor the zoom at the viewport centre: capture the content point
      under the centre, then keep it stationary while the image scales
      from the top-left. }
    OldCX := ScrollBoxPreview.HorzScrollBar.Position + AreaW div 2;
    OldCY := ScrollBoxPreview.VertScrollBar.Position + AreaH div 2;

    ImgPreview.Align := alNone;
    ImgPreview.Stretch := True;
    ImgPreview.Proportional := False;
    ImgPreview.Center := False;
    ImgPreview.Left := 0;
    ImgPreview.Top := 0;
    ImgPreview.Width := Round(SrcW * Ratio * FZoomLevel);
    ImgPreview.Height := Round(SrcH * Ratio * FZoomLevel);

    ScrollBoxPreview.HorzScrollBar.Position :=
      CenterAnchorScrollPos(OldCX, AOldZoom, FZoomLevel, AreaW, ImgPreview.Width);
    ScrollBoxPreview.VertScrollBar.Position :=
      CenterAnchorScrollPos(OldCY, AOldZoom, FZoomLevel, AreaH, ImgPreview.Height);
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

  { Discard stale selection state — item indices change after the rebuild. }
  ClearPendingSel;
  FAnchor := -1;
  FSel := nil;

  LVChapters.BeginUpdate;
  try
    LVChapters.LargeImages := nil;
    LVChapters.Items.Clear;

    for i := FRemovedCount to High(FFiles) do
    begin
      { Thumbnail via the index map: the chapter list may be a subset of
        the image list's directory, and some files may lack a thumbnail. }
      Idx := -1;
      if (i < Length(FImageIdx)) and (FImageIdx[i] >= 0) and
         (FImageIdx[i] < FImages.Count) then
        Idx := AppendThumb(ILChapters, FImages[FImageIdx[i]]);

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

{ Compact chapter list for a volume: "0001, 0002, 0003" or
  "0001 … 0008" for longer runs. }
function TdlgSeqBuilder.ChapterRangeStr(AStart, ACount: integer): string;
var
  i: integer;
begin
  if ACount <= 3 then
  begin
    Result := '';
    for i := AStart to AStart + ACount - 1 do
    begin
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + ChangeFileExt(FFiles[i], '');
    end;
  end
  else
    Result := ChangeFileExt(FFiles[AStart], '') + ' … ' +
      ChangeFileExt(FFiles[AStart + ACount - 1], '');
end;

procedure TdlgSeqBuilder.RefreshStatus;
var
  i, Remaining, Pos: integer;
begin
  LblStatus.Caption := Format(
    'Volume %d | Select the next chapters (in order), then press "Add volume"',
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
      Pos := 0;
      for i := 0 to High(FVolumes) do
      begin
        CbSequence.Items.Add(Format('Vol.%d: %d ch. (%s)',
          [i + 1, FVolumes[i], ChapterRangeStr(Pos, FVolumes[i])]));
        Inc(Pos, FVolumes[i]);
      end;
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
  AImages: TLazIntfImageList; const AImageIdx: TIntArray;
  const ADir: string);
begin
  FFiles := AFiles;
  FImages := AImages;
  FImageIdx := AImageIdx;
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
