unit udlgseqbuilder;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, ComCtrls,
  IntfGraphics, uloaderthread, uimgutil, uservicemerge;

type
  TPreviewLoader = class(TThread)
  private
    FFile: string;
    FPages: TLazIntfImageList;
    procedure HandlePage(const AName: string; AImage: TLazIntfImage;
      var ACancel: boolean);
  protected
    procedure Execute; override;
  public
    constructor Create(const AFile: string);
    destructor Destroy; override;
    function ExtractPages: TLazIntfImageList;
    property Pages: TLazIntfImageList read FPages;
  end;

  TdlgSeqBuilder = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    PanelTop: TPanel;
    PanelBottom: TPanel;
    PanelPreview: TPanel;
    PanelPreviewNav: TPanel;
    LVChapters: TListView;
    ILChapters: TImageList;
    ScrollBoxPreview: TScrollBox;
    ImgPreview: TImage;
    LblStatus: TLabel;
    LblSequence: TLabel;
    LblPreviewTitle: TLabel;
    LblPreviewPage: TLabel;
    BtnPrevPage: TButton;
    BtnNextPage: TButton;
    BtnAddVolume: TButton;
    BtnUndo: TButton;
    BtnConfirm: TButton;
    BtnCancel: TButton;

    FDir: string;
    FFiles: TStringArray;
    FImages: TLazIntfImageList;
    FVolumes: TIntArray;
    FRemovedCount: integer;

    FPreviewLoader: TPreviewLoader;
    FPreviewPages: TLazIntfImageList;
    FPreviewIndex: integer;
    FZoomLevel: double;

    procedure LVChaptersDblClick(Sender: TObject);
    procedure LVChaptersSelectItem(Sender: TObject; Item: TListItem;
      Selected: boolean);
    procedure BtnAddVolumeClick(Sender: TObject);
    procedure BtnUndoClick(Sender: TObject);
    procedure BtnPrevPageClick(Sender: TObject);
    procedure BtnNextPageClick(Sender: TObject);
    procedure PreviewLoaderTerminated(Sender: TObject);
    procedure PreviewMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
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
  uzipeditor, LCLIntf, LCLType;

const
  ThumbW = 64;
  ThumbH = 80;
  LVM_SETICONSPACING = $1000 + 53;
  LVM_ARRANGE = $1000 + 22;

{ TPreviewLoader }

constructor TPreviewLoader.Create(const AFile: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FFile := AFile;
  FPages := TLazIntfImageList.Create(True);
end;

destructor TPreviewLoader.Destroy;
begin
  FPages.Free;
  inherited;
end;

function TPreviewLoader.ExtractPages: TLazIntfImageList;
begin
  Result := FPages;
  FPages := nil;
end;

procedure TPreviewLoader.Execute;
begin
  ForEachImage(FFile, @HandlePage);
end;

procedure TPreviewLoader.HandlePage(const AName: string;
  AImage: TLazIntfImage; var ACancel: boolean);
var
  Small: TLazIntfImage;
begin
  Small := ScaleIntfImage(AImage, CacheW, CacheH);
  AImage.Free;
  FPages.Add(Small);
  ACancel := Terminated;
end;

{ TdlgSeqBuilder }

procedure TdlgSeqBuilder.FormCreate(Sender: TObject);
var
  PanelBtns: TPanel;
begin
  BorderStyle := bsDialog;
  BorderIcons := [biSystemMenu];
  OnShow := @FormShow;

  PanelTop := TPanel.Create(Self);
  PanelTop.Parent := Self;
  PanelTop.Align := alTop;
  PanelTop.Height := 52;
  PanelTop.BevelOuter := bvNone;

  LblStatus := TLabel.Create(Self);
  LblStatus.Parent := PanelTop;
  LblStatus.Left := 12;
  LblStatus.Top := 8;
  LblStatus.Width := 760;
  LblStatus.Font.Height := -13;
  LblStatus.Font.Style := [fsBold];
  LblStatus.Caption := 'Volume 1';

  LblSequence := TLabel.Create(Self);
  LblSequence.Parent := PanelTop;
  LblSequence.Left := 12;
  LblSequence.Top := 30;
  LblSequence.AutoSize := False;
  LblSequence.Width := 760;
  LblSequence.Font.Style := [fsBold];
  LblSequence.Caption := 'Sequence: (none yet)';

  PanelBottom := TPanel.Create(Self);
  PanelBottom.Parent := Self;
  PanelBottom.Align := alBottom;
  PanelBottom.Height := 44;
  PanelBottom.BevelOuter := bvNone;

  BtnAddVolume := TButton.Create(Self);
  BtnAddVolume.Parent := PanelBottom;
  BtnAddVolume.Left := 12;
  BtnAddVolume.Top := 7;
  BtnAddVolume.Width := 150;
  BtnAddVolume.Height := 30;
  BtnAddVolume.Caption := 'Add volume (0 ch.)';
  BtnAddVolume.Enabled := False;
  BtnAddVolume.OnClick := @BtnAddVolumeClick;

  BtnUndo := TButton.Create(Self);
  BtnUndo.Parent := PanelBottom;
  BtnUndo.Left := 170;
  BtnUndo.Top := 7;
  BtnUndo.Width := 90;
  BtnUndo.Height := 30;
  BtnUndo.Caption := 'Undo last';
  BtnUndo.Enabled := False;
  BtnUndo.OnClick := @BtnUndoClick;

  PanelBtns := TPanel.Create(Self);
  PanelBtns.Parent := PanelBottom;
  PanelBtns.Align := alRight;
  PanelBtns.Width := 176;
  PanelBtns.BevelOuter := bvNone;

  BtnConfirm := TButton.Create(Self);
  BtnConfirm.Parent := PanelBtns;
  BtnConfirm.Left := 4;
  BtnConfirm.Top := 7;
  BtnConfirm.Width := 80;
  BtnConfirm.Height := 30;
  BtnConfirm.Caption := 'Confirm';
  BtnConfirm.Default := True;
  BtnConfirm.ModalResult := mrOK;

  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := PanelBtns;
  BtnCancel.Left := 92;
  BtnCancel.Top := 7;
  BtnCancel.Width := 80;
  BtnCancel.Height := 30;
  BtnCancel.Caption := 'Cancel';
  BtnCancel.Cancel := True;
  BtnCancel.ModalResult := mrCancel;

  PanelPreview := TPanel.Create(Self);
  PanelPreview.Parent := Self;
  PanelPreview.Align := alRight;
  PanelPreview.Width := 224;
  PanelPreview.BevelOuter := bvLowered;

  LblPreviewTitle := TLabel.Create(Self);
  LblPreviewTitle.Parent := PanelPreview;
  LblPreviewTitle.Align := alTop;
  LblPreviewTitle.Height := 26;
  LblPreviewTitle.Layout := tlCenter;
  LblPreviewTitle.Alignment := taCenter;
  LblPreviewTitle.Caption := 'Double-click to preview';
  LblPreviewTitle.Font.Height := -12;

  PanelPreviewNav := TPanel.Create(Self);
  PanelPreviewNav.Parent := PanelPreview;
  PanelPreviewNav.Align := alBottom;
  PanelPreviewNav.Height := 36;
  PanelPreviewNav.BevelOuter := bvNone;

  BtnPrevPage := TButton.Create(Self);
  BtnPrevPage.Parent := PanelPreviewNav;
  BtnPrevPage.Left := 20;
  BtnPrevPage.Top := 4;
  BtnPrevPage.Width := 50;
  BtnPrevPage.Height := 28;
  BtnPrevPage.Caption := '<';
  BtnPrevPage.Enabled := False;
  BtnPrevPage.OnClick := @BtnPrevPageClick;

  LblPreviewPage := TLabel.Create(Self);
  LblPreviewPage.Parent := PanelPreviewNav;
  LblPreviewPage.Left := 78;
  LblPreviewPage.Top := 10;
  LblPreviewPage.Width := 68;
  LblPreviewPage.Alignment := taCenter;
  LblPreviewPage.Caption := '';

  BtnNextPage := TButton.Create(Self);
  BtnNextPage.Parent := PanelPreviewNav;
  BtnNextPage.Left := 154;
  BtnNextPage.Top := 4;
  BtnNextPage.Width := 50;
  BtnNextPage.Height := 28;
  BtnNextPage.Caption := '>';
  BtnNextPage.Enabled := False;
  BtnNextPage.OnClick := @BtnNextPageClick;

  ScrollBoxPreview := TScrollBox.Create(Self);
  ScrollBoxPreview.Parent := PanelPreview;
  ScrollBoxPreview.Align := alClient;
  ScrollBoxPreview.BorderStyle := bsNone;
  ScrollBoxPreview.OnMouseWheel := @PreviewMouseWheel;

  ImgPreview := TImage.Create(Self);
  ImgPreview.Parent := ScrollBoxPreview;
  ImgPreview.Align := alClient;
  ImgPreview.Stretch := True;
  ImgPreview.Proportional := True;
  ImgPreview.Center := True;
  ImgPreview.BorderSpacing.Around := 4;
  ImgPreview.OnMouseWheel := @PreviewMouseWheel;

  ILChapters := TImageList.Create(Self);
  ILChapters.Width := ThumbW;
  ILChapters.Height := ThumbH;

  LVChapters := TListView.Create(Self);
  LVChapters.Parent := Self;
  LVChapters.Align := alClient;
  LVChapters.BorderSpacing.Around := 4;
  LVChapters.ViewStyle := vsIcon;
  LVChapters.MultiSelect := True;
  LVChapters.ReadOnly := True;
  LVChapters.LargeImages := ILChapters;
  LVChapters.OnDblClick := @LVChaptersDblClick;
  LVChapters.OnSelectItem := @LVChaptersSelectItem;
  LVChapters.IconOptions.Arrangement := iaTop;
  LVChapters.IconOptions.AutoArrange := True;
  LVChapters.IconOptions.WrapText := False;

  FRemovedCount := 0;
  FVolumes := nil;
  FPreviewPages := nil;
  FPreviewLoader := nil;
  FPreviewIndex := 0;
  FZoomLevel := 1.0;
end;

procedure TdlgSeqBuilder.FormDestroy(Sender: TObject);
begin
  StopPreviewLoader;
  FreeAndNil(FPreviewPages);
end;

procedure TdlgSeqBuilder.FormShow(Sender: TObject);
begin
  SendMessage(LVChapters.Handle, LVM_SETICONSPACING, 0,
    LParam((ThumbW + 40) or ((ThumbH + 32) shl 16)));
  SendMessage(LVChapters.Handle, LVM_ARRANGE, 0, 0);
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
  if (FPreviewLoader.FatalException <> nil) or
    (FPreviewLoader.Pages.Count = 0) then
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

  LblPreviewPage.Caption := Format('%d / %d',
    [FPreviewIndex + 1, FPreviewPages.Count]);
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
  if (FPreviewPages <> nil) and
    (FPreviewIndex < FPreviewPages.Count - 1) then
  begin
    Inc(FPreviewIndex);
    ShowPreviewPage;
  end;
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

procedure TdlgSeqBuilder.PreviewMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: integer; MousePos: TPoint;
  var Handled: boolean);
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
  i, Idx: integer;
  Thumb: TBitmap;
  It: TListItem;
begin
  LVChapters.BeginUpdate;
  try
    LVChapters.LargeImages := nil;
    ILChapters.Clear;
    LVChapters.Items.Clear;

    for i := FRemovedCount to High(FFiles) do
    begin
      if i < FImages.Count then
      begin
        Thumb := MakeThumb(FImages[i], ThumbW, ThumbH);
        try
          Idx := ILChapters.Add(Thumb, nil);
        finally
          Thumb.Free;
        end;
      end
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
    SendMessage(LVChapters.Handle, LVM_SETICONSPACING, 0,
      LParam((ThumbW + 40) or ((ThumbH + 32) shl 16)));
    SendMessage(LVChapters.Handle, LVM_ARRANGE, 0, 0);
  end;

  BtnAddVolume.Enabled := False;
  BtnAddVolume.Caption := 'Add volume (0 ch.)';
end;

procedure TdlgSeqBuilder.RefreshStatus;
var
  i, Remaining: integer;
  S: string;
begin
  LblStatus.Caption := Format(
    'Volume %d | Select chapters, then press "Add volume"',
    [Length(FVolumes) + 1]);

  Remaining := Length(FFiles) - FRemovedCount;

  if Length(FVolumes) = 0 then
    S := 'Sequence: (none yet)'
  else
  begin
    S := 'Sequence:';
    for i := 0 to High(FVolumes) do
      S := S + Format(' Vol.%d: %d ch.', [i + 1, FVolumes[i]]);
  end;

  if Remaining = 0 then
    S := S + ' | All chapters assigned'
  else
    S := S + Format(' | %d remaining', [Remaining]);

  LblSequence.Caption := S;
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
