unit main;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Generics.Collections, Math, IntfGraphics;

const
  THUMB_SPACING = 4;
  LABEL_HEIGHT = 24;
  CHECKBOX_H = 20;

type
  TThumbPanel = class(TPanel)
  private
    FCheckBox: TCheckBox;
    FImage: TImage;
    FLabel: TLabel;
    FSelected: boolean;
    procedure DoCheck(Sender: TObject);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetSelected(AValue: boolean);
    procedure SetThumbSize(AW, AH: integer);
    property ThumbCheckBox: TCheckBox read FCheckBox;
    property ThumbImage: TImage read FImage;
    property ThumbLabel: TLabel read FLabel;
    property Selected: boolean read FSelected;
  end;

  TLoadedItem = record
    Name: string;
    Image: TLazIntfImage;
  end;
  TLoadedItems = array of TLoadedItem;

  { TLoadThread }

  TLoadThread = class(TThread)
  private
    FDir: string;
    FFileNames: TStringList;
    FItems: TLoadedItems;
    FCount: integer;
    procedure SyncAddThumbs;
  protected
    procedure Execute; override;
  public
    constructor Create(const ADir: string);
    destructor Destroy; override;
  end;

  { TfrmMain }

  TfrmMain = class(TForm)
    ILFilesFirstPages: TImageList;
    LVFiles: TListView;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    EditDir: TEdit;
    BtnBrowse: TButton;
    SelectDialog: TSelectDirectoryDialog;
    ZoomScroll: TTrackBar;
    procedure BtnBrowseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure ZoomScrollChange(Sender: TObject);
  private
    FSelected: array of boolean;
    FLastClicked: integer;
    FLoadThread: TLoadThread;
    FThumbW: integer;
    FThumbH: integer;
    FFirstPages: specialize TObjectList<TLazIntfImage>;
    procedure ThreadTerminated(Sender: TObject);
    procedure ClearThumbnails;
    procedure LoadDirectory(const ADir: string);
    procedure ThumbMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure SelectRange(AFrom, ATo: integer);
    procedure LayoutFlowPanel;
  end;

var
  frmMain: TfrmMain;

implementation

uses
  uZipEditor, uImgUtil, uLog;

{ SOLO MAIN THREAD: IntfToBitmap e Canvas toccano il widgetset. }
function MakeThumb(Src: TLazIntfImage; W, H: integer): TBitmap;
var
  F: double;
  DW, DH: integer;
  Full: TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(W, H);
  Result.Canvas.Brush.Color := clWindow;
  Result.Canvas.FillRect(0, 0, W, H);
  if (Src = nil) or (Src.Width <= 0) or (Src.Height <= 0) then Exit;

  Full := IntfToBitmap(Src);
  if Full = nil then Exit;
  try
    F := Min(W / Full.Width, H / Full.Height);
    DW := Max(1, Round(Full.Width * F));
    DH := Max(1, Round(Full.Height * F));
    Result.Canvas.AntialiasingMode := amOn;
    Result.Canvas.StretchDraw(
      Rect((W - DW) div 2, (H - DH) div 2, (W - DW) div 2 + DW,
      (H - DH) div 2 + DH), Full);
  finally
    Full.Free;
  end;
end;
{$R *.lfm}

{ TThumbPanel }

constructor TThumbPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  BorderStyle := bsSingle;
  BorderSpacing.Around := THUMB_SPACING;

  FCheckBox := TCheckBox.Create(Self);
  FCheckBox.Parent := Self;
  FCheckBox.Align := alTop;
  FCheckBox.Height := CHECKBOX_H;
  FCheckBox.Caption := '';
  FCheckBox.OnClick := @DoCheck;

  FImage := TImage.Create(Self);
  FImage.Parent := Self;
  FImage.Align := alClient;
  FImage.Stretch := True;
  FImage.Proportional := True;
  FImage.Center := True;

  FLabel := TLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.Align := alBottom;
  FLabel.AutoSize := False;
  FLabel.Height := LABEL_HEIGHT;
  FLabel.Layout := tlCenter;
  FLabel.Alignment := taCenter;
  FLabel.WordWrap := True;
end;

procedure TThumbPanel.SetThumbSize(AW, AH: integer);
begin
  Width := AW;
  Height := AH;
end;

procedure TThumbPanel.DoCheck(Sender: TObject);
var
  Idx: integer;
begin
  Idx := Tag;
  if (Idx >= 0) and (Idx <= High(frmMain.FSelected)) then
  begin
    frmMain.FSelected[Idx] := FCheckBox.Checked;
    FSelected := FCheckBox.Checked;
    Invalidate;
  end;
end;

procedure TThumbPanel.SetSelected(AValue: boolean);
begin
  if FSelected = AValue then Exit;
  FSelected := AValue;
  FCheckBox.Checked := AValue;
  Invalidate;
end;

procedure TThumbPanel.Paint;
var
  R: TRect;
begin
  inherited Paint;
  if FSelected then
  begin
    R := ClientRect;
    Canvas.Pen.Color := clHighlight;
    Canvas.Pen.Width := 2;
    Canvas.Pen.Style := psSolid;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
  end;
end;

{ TLoadThread }

constructor TLoadThread.Create(const ADir: string);
begin
  inherited Create(True);
  FreeOnTerminate := True;
  FDir := ADir;
  FFileNames := TStringList.Create;
  FCount := 0;
  SetLength(FItems, 0);
end;

destructor TLoadThread.Destroy;
begin
  FFileNames.Free;
  inherited Destroy;
end;

procedure TLoadThread.Execute;
var
  Dir: string;
  SearchRec: TSearchRec;
  FileNames: TStringList;
  i, j: integer;
  FilePath: string;
  Img: TLazIntfImage;
  Batch: TLoadedItems;
  BatchCount: integer;
begin
  try
  Dir := IncludeTrailingPathDelimiter(FDir);

  FileNames := TStringList.Create;
  try
    if FindFirst(Dir + '*.cbz', faAnyFile, SearchRec) = 0 then
    begin
      repeat
        FileNames.Add(SearchRec.Name);
      until FindNext(SearchRec) <> 0;
      FindClose(SearchRec);
    end;
    FileNames.Sort;
    Log('Thread: %d file .cbz trovati in %s', [FileNames.Count, Dir]);

    BatchCount := 0;
    SetLength(Batch, 0);

    for i := 0 to FileNames.Count - 1 do
    begin
      if Terminated then Exit;

      FilePath := Dir + FileNames[i];
      Img := nil;
      try
        Img := GetFirstImageAsIntfImage(FilePath);
      except
        on E: Exception do
        begin
          Log('Thread: eccezione su %s: %s: %s',
            [FileNames[i], E.ClassName, E.Message]);
          Img := nil;
        end;
      end;

      Inc(BatchCount);
      SetLength(Batch, BatchCount);
      Batch[BatchCount - 1].Name := FileNames[i];
      Batch[BatchCount - 1].Image := Img;
      Log('Thread: %d/%d elaborato, batch=%d',
        [i + 1, FileNames.Count, BatchCount]);

      if BatchCount >= 4 then
      begin
        FItems := Batch;
        FCount := BatchCount;
        FFileNames.Clear;
        for j := 0 to BatchCount - 1 do
          FFileNames.Add(Batch[j].Name);
        Log('Thread: Synchronize batch di %d...', [FCount]);
        TThread.Synchronize(nil, @SyncAddThumbs);
        Log('Thread: Synchronize rientrato');
        BatchCount := 0;
        SetLength(Batch, 0);
      end;
    end;

    if BatchCount > 0 then
    begin
      FItems := Batch;
      FCount := BatchCount;
      FFileNames.Clear;
      for j := 0 to BatchCount - 1 do
        FFileNames.Add(Batch[j].Name);
      TThread.Synchronize(nil, @SyncAddThumbs);
    end;
  finally
    FileNames.Free;
  end;
  Log('Thread: terminato regolarmente');
  except
    on E: Exception do
      Log('Thread: ECCEZIONE NON GESTITA %s: %s', [E.ClassName, E.Message]);
  end;
end;

procedure TLoadThread.SyncAddThumbs;
var
  i, Idx, ILIdx: integer;
  Thumb: TBitmap;
  It: TListItem;
begin
  if Terminated then
  begin
    { nessuno prendera' in carico le immagini del batch: evita il leak }
    for i := 0 to FCount - 1 do
      FItems[i].Image.Free;
    Exit;
  end;
  frmMain.LVFiles.BeginUpdate;
  try
    for i := 0 to FCount - 1 do
    begin
      Idx := frmMain.FFirstPages.Add(FItems[i].Image);   // originale, anche se nil
      Thumb := MakeThumb(FItems[i].Image, frmMain.ILFilesFirstPages.Width,
        frmMain.ILFilesFirstPages.Height);
      try
        ILIdx := frmMain.ILFilesFirstPages.Add(Thumb, nil);
      finally
        Thumb.Free;
      end;
      It := frmMain.LVFiles.Items.Add;
      It.Caption := FFileNames[i];
      It.ImageIndex := ILIdx;
      Log('Sync: %s img=%s listIdx=%d ilIdx=%d',
        [FFileNames[i], BoolToStr(FItems[i].Image <> nil, 'si', 'NO'),
        Idx, ILIdx]);
    end;
  finally
    frmMain.LVFiles.EndUpdate;
  end;
  Log('Sync: LVFiles.Items.Count=%d ImageList.Count=%d',
    [frmMain.LVFiles.Items.Count, frmMain.ILFilesFirstPages.Count]);
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'CBZ Manager'; 
  FFirstPages := specialize TObjectList<TLazIntfImage>.Create(True);
  FLastClicked := -1;
  FLoadThread := nil;
  FThumbW := 150;
  FThumbH := 180;
  ILFilesFirstPages.Width := 128;
  ILFilesFirstPages.Height := 160;
  LVFiles.ViewStyle := vsIcon;
  LVFiles.LargeImages := ILFilesFirstPages;
  ZoomScroll.Min := 48;
  ZoomScroll.Max := 320;
  ZoomScroll.Position := 128;
  Log('=== Avvio, log in %s ===', [LogFileName]);
  Log('exe dir: %s', [ExtractFilePath(ParamStr(0))]);
  if ParamCount > 0 then
    LoadDirectory(ParamStr(1));
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FFirstPages.Free;
end;

procedure TfrmMain.FormResize(Sender: TObject);
begin
  LayoutFlowPanel;
end;

procedure TfrmMain.ZoomScrollChange(Sender: TObject);
var
  i, Sz: integer;
  Thumb: TBitmap;
begin
  Sz := Max(16, ZoomScroll.Position);
  LVFiles.BeginUpdate;
  try
    LVFiles.LargeImages := nil;
    // niente ridisegni con indici temporaneamente invalidi
    ILFilesFirstPages.Clear;
    ILFilesFirstPages.Width := Sz;
    ILFilesFirstPages.Height := Round(Sz * 1.25);
    for i := 0 to FFirstPages.Count - 1 do
    begin
      Thumb := MakeThumb(FFirstPages[i], ILFilesFirstPages.Width,
        ILFilesFirstPages.Height);
      try
        ILFilesFirstPages.Add(Thumb, nil);
      finally
        Thumb.Free;
      end;
    end;
    LVFiles.LargeImages := ILFilesFirstPages;
  finally
    LVFiles.EndUpdate;
  end;
  LVFiles.Invalidate;
end;

procedure TfrmMain.LayoutFlowPanel;
begin
end;

procedure TfrmMain.ClearThumbnails;
begin
  if FFirstPages.Count > 0 then
    FFirstPages.Clear;
  ILFilesFirstPages.Clear;
  LVFiles.Clear;
end;

procedure TfrmMain.BtnBrowseClick(Sender: TObject);
begin
  if SelectDialog.Execute then
  begin
    EditDir.Text := SelectDialog.FileName;
    LoadDirectory(SelectDialog.FileName);
  end;
end;

procedure TfrmMain.ThumbMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  Idx: integer;
begin
  if Button <> mbLeft then Exit;
  if not (Sender is TControl) then Exit;
  Idx := TControl(Sender).Parent.Tag;
  if (Idx < 0) or (Idx > High(FSelected)) then Exit;

  if ssShift in Shift then
  begin
    if FLastClicked >= 0 then
      SelectRange(FLastClicked, Idx);
  end
  else if ssCtrl in Shift then
  begin
    FSelected[Idx] := not FSelected[Idx];
  end
  else
  begin
    FSelected[Idx] := True;
  end;
  FLastClicked := Idx;
end;

procedure TfrmMain.SelectRange(AFrom, ATo: integer);
var
  i, lo, hi: integer;
begin
  if AFrom < ATo then
  begin
    lo := AFrom;
    hi := ATo;
  end
  else
  begin
    lo := ATo;
    hi := AFrom;
  end;
  for i := lo to hi do
  begin
    FSelected[i] := True;
  end;
end;

procedure TfrmMain.LoadDirectory(const ADir: string);
begin
  Log('LoadDirectory: %s', [ADir]);
  ClearThumbnails;
  FLoadThread := TLoadThread.Create(ADir);
  FLoadThread.OnTerminate := @ThreadTerminated;
  FLoadThread.Start;
end;

procedure TfrmMain.ThreadTerminated(Sender: TObject);
begin
  FLoadThread := nil;
end;

end.
