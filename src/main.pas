unit main;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Generics.Collections;

const
  THUMB_SPACING = 4;
  LABEL_HEIGHT  = 24;
  CHECKBOX_H    = 20;

type
  TThumbPanel = class(TPanel)
  private
    FCheckBox: TCheckBox;
    FImage: TImage;
    FLabel: TLabel;
    FSelected: Boolean;
    procedure DoCheck(Sender: TObject);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetSelected(AValue: Boolean);
    procedure SetThumbSize(AW, AH: Integer);
    property ThumbCheckBox: TCheckBox read FCheckBox;
    property ThumbImage: TImage read FImage;
    property ThumbLabel: TLabel read FLabel;
    property Selected: Boolean read FSelected;
  end;

  TLoadedItem = record
    Name: string;
    Bitmap: TBitmap;
  end;
  TLoadedItems = array of TLoadedItem;

  TLoadThread = class(TThread)
  private
    FDir: string;
    FFileNames: TStringList;
    FItems: TLoadedItems;
    FCount: Integer;
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
    procedure FormResize(Sender: TObject);
    procedure ZoomScrollChange(Sender: TObject);
  private
    FSelected: array of Boolean;
    FLastClicked: Integer;
    FLoadThread: TLoadThread;
    FThumbW: Integer;
    FThumbH: Integer;
    FFirstPages: specialize TObjectList<TBitmap>;
    procedure ThreadTerminated(Sender: TObject);
    procedure ClearThumbnails;
    procedure LoadDirectory(const ADir: string);
    procedure ThumbMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SelectRange(AFrom, ATo: Integer);
    procedure LayoutFlowPanel;
  end;

var
  frmMain: TfrmMain;

implementation

uses
  uZipEditor;

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

procedure TThumbPanel.SetThumbSize(AW, AH: Integer);
begin
  Width := AW;
  Height := AH;
end;

procedure TThumbPanel.DoCheck(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := Tag;
  if (Idx >= 0) and (Idx <= High(frmMain.FSelected)) then
  begin
    frmMain.FSelected[Idx] := FCheckBox.Checked;
    FSelected := FCheckBox.Checked;
    Invalidate;
  end;
end;

procedure TThumbPanel.SetSelected(AValue: Boolean);
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
  i, j: Integer;
  FilePath: string;
  Bmp: TBitmap;
  Batch: TLoadedItems;
  BatchCount: Integer;
begin
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

    BatchCount := 0;
    SetLength(Batch, 0);

    for i := 0 to FileNames.Count - 1 do
    begin
      if Terminated then Exit;

      FilePath := Dir + FileNames[i];
      Bmp := nil;
      try
        Bmp := GetFirstImageAsBitmap(FilePath);
      except
        Bmp := nil;
      end;

      Inc(BatchCount);
      SetLength(Batch, BatchCount);
      Batch[BatchCount - 1].Name := FileNames[i];
      Batch[BatchCount - 1].Bitmap := Bmp;

      if BatchCount >= 4 then
      begin
        FItems := Batch;
        FCount := BatchCount;
        FFileNames.Clear;
        for j := 0 to BatchCount - 1 do
          FFileNames.Add(Batch[j].Name);
        TThread.Synchronize(nil, @SyncAddThumbs);
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
end;

procedure TLoadThread.SyncAddThumbs;
var
  i, Idx: Integer;
  Thumb: TThumbPanel;
  LIndexFP, LIndexIL: Integer;
begin
  if Terminated then Exit;
  // Idx := Length(frmMain.FThumbs);
  for i := 0 to FCount - 1 do
  begin
    if Terminated then Exit;

    LIndexFP := frmMain.FFirstPages.Add(FItems[i].Bitmap);
    LIndexIL := frmMain.ILFilesFirstPages.Add(frmMain.FFirstPages[LIndexFP], nil);
    frmMain.LVFiles.AddItem(FFileNames[i], nil);
    frmMain.LVFiles.Items[frmMain.LVFiles.Items.Count - 1].ImageIndex := LIndexIL;

    {
    Thumb := TThumbPanel.Create(frmMain);
    Thumb.Parent := frmMain.FlowPanel;
    Thumb.HandleNeeded;
    Thumb.Tag := Idx;
    Thumb.SetThumbSize(frmMain.FThumbW, frmMain.FThumbH);
    Thumb.OnMouseDown := @frmMain.ThumbMouseDown;
    Thumb.ThumbImage.OnMouseDown := @frmMain.ThumbMouseDown;
    Thumb.ThumbLabel.OnMouseDown := @frmMain.ThumbMouseDown;

    SetLength(frmMain.FThumbs, Idx + 1);
    SetLength(frmMain.FSelected, Idx + 1);
    frmMain.FThumbs[Idx] := Thumb;
    frmMain.FSelected[Idx] := False;

    if FItems[i].Bitmap <> nil then
    begin
      Thumb.ThumbImage.Picture.Bitmap := FItems[i].Bitmap;
      FItems[i].Bitmap.Free;
    end;

    Thumb.ThumbLabel.Caption := FFileNames[i];
    Inc(Idx);
    }
  end;
  frmMain.LayoutFlowPanel;
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'CBZ Manager';
  FLastClicked := -1;
  FLoadThread := nil;
  FThumbW := 150;
  FThumbH := 180;
  if ParamCount > 0 then
    LoadDirectory(ParamStr(1));
  FFirstPages := specialize TObjectList<TBitmap>.Create(True);
end;

procedure TfrmMain.FormResize(Sender: TObject);
begin
  LayoutFlowPanel;
end;

procedure TfrmMain.ZoomScrollChange(Sender: TObject);
var
  LBitmap: TBitmap;
begin
  LVFiles.BeginUpdate;
  ILFilesFirstPages.Clear;
  ILFilesFirstPages.Height := ZoomScroll.Position;
  ILFilesFirstPages.Width := ZoomScroll.Position;
  for LBitmap in FFirstPages do
    begin
      ILFilesFirstPages.Add(LBitmap, nil);
    end;
  LVFiles.EndUpdate;
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
  Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
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

procedure TfrmMain.SelectRange(AFrom, ATo: Integer);
var
  i, lo, hi: Integer;
begin
  if AFrom < ATo then begin lo := AFrom; hi := ATo; end
  else begin lo := ATo; hi := AFrom; end;
  for i := lo to hi do
  begin
    FSelected[i] := True;
  end;
end;

procedure TfrmMain.LoadDirectory(const ADir: string);
begin
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
