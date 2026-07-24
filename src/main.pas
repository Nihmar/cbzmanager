unit main;

{$mode ObjFPC}{$H+}

interface

uses
  Classes,
  SysUtils,
  Forms,
  Controls,
  Graphics,
  Dialogs,
  StdCtrls,
  ExtCtrls,
  ComCtrls,
  Menus,
  Math,
  IntfGraphics,
  Types,
  uloaderthread;

type
  { TfrmMain }

  TfrmMain = class(TForm)
    BtnClosePreview: TButton;
    ILFilesFirstPages: TImageList;
    ILPages: TImageList;
    LblPreviewFile: TLabel;
    LVFiles: TListView;
    LVPages: TListView;
    MnuOpenFile: TMenuItem;
    PanelPreviewTop: TPanel;
    PanelSingleFile: TPanel;
    PanelMiddle: TPanel;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    EditDir: TEdit;
    BtnBrowse: TButton;
    PMFiles: TPopupMenu;
    SelectDialog: TSelectDirectoryDialog;
    SplitterPreview: TSplitter;
    TimerDebounceZoom: TTimer;
    ZoomScroll: TTrackBar;
    procedure BtnBrowseClick(Sender: TObject);
    procedure BtnClosePreviewClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure FormResize(Sender: TObject);
    procedure LVFilesDblClick(Sender: TObject);
    procedure LVFilesMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure MnuOpenFileClick(Sender: TObject);
    procedure PMFilesPopup(Sender: TObject);
    procedure TimerDebounceZoomTimer(Sender: TObject);
    procedure ZoomScrollChange(Sender: TObject);
    procedure ZoomScrollMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
  private
    FSelected: array of boolean;
    FLastClicked: integer;
    FDir: string;
    FLoadThread: TLoadThread;
    FPagesThread: TPagesThread;
    FThumbW: integer;
    FThumbH: integer;
    FFirstPages: TLazIntfImageList;
    FPagePreviews: TLazIntfImageList;
    procedure ThreadTerminated(Sender: TObject);
    procedure PagesThreadTerminated(Sender: TObject);
    procedure ClearThumbnails;
    procedure LoadDirectory(const ADir: string);
    procedure OpenPreview(AItem: TListItem);
    procedure ClearPreview;
    procedure HidePreview;
    procedure RebuildThumbs(ALV: TListView; AIL: TImageList;
      APages: TLazIntfImageList; ASize: integer);
    procedure ThumbMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure SelectRange(AFrom, ATo: integer);
    procedure LayoutFlowPanel;
  end;

var
  frmMain: TfrmMain;

implementation

uses
  LCLType,
  uImgUtil,
  uLog;

  {$R *.lfm}

  { TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'CBZ Manager';
  FFirstPages := TLazIntfImageList.Create(True);
  FPagePreviews := TLazIntfImageList.Create(True);
  FLastClicked := -1;
  FLoadThread := nil;
  FPagesThread := nil;
  FThumbW := 150;
  FThumbH := 180;
  ILFilesFirstPages.Width := 128;
  ILFilesFirstPages.Height := 160;
  ILPages.Width := 128;
  ILPages.Height := 160;
  LVFiles.DoubleBuffered := True;
  LVFiles.ViewStyle := vsIcon;
  LVFiles.LargeImages := ILFilesFirstPages;
  LVPages.DoubleBuffered := True;
  LVPages.ViewStyle := vsIcon;
  LVPages.LargeImages := ILPages;
  ZoomScroll.Min := 48;
  ZoomScroll.Max := CacheW;
  ZoomScroll.Position := 128;
  HidePreview;
  Log('=== Avvio, log in %s ===', [LogFileName]);
  Log('exe dir: %s', [ExtractFilePath(ParamStr(0))]);
  if ParamCount > 0 then
    LoadDirectory(ParamStr(1));
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  { i thread si autodistruggono: basta impedire loro di toccare i controlli }
  if FLoadThread <> nil then
    FLoadThread.Terminate;
  if FPagesThread <> nil then
    FPagesThread.Terminate;
  FLoadThread := nil;
  FPagesThread := nil;
  FFirstPages.Free;
  FPagePreviews.Free;
end;

procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: word;
  Shift: TShiftState);
begin
  if (Key = VK_ESCAPE) and PanelSingleFile.Visible then
  begin
    HidePreview;
    Key := 0;
  end;
end;

procedure TfrmMain.FormResize(Sender: TObject);
begin
  LayoutFlowPanel;
end;

procedure TfrmMain.RebuildThumbs(ALV: TListView; AIL: TImageList;
  APages: TLazIntfImageList; ASize: integer);
var
  i: integer;
  Thumb: TBitmap;
begin
  ALV.BeginUpdate;
  try
    ALV.LargeImages := nil;
    AIL.Clear;
    AIL.Width := ASize;
    AIL.Height := Round(ASize * 1.25);
    for i := 0 to APages.Count - 1 do
    begin
      Thumb := MakeThumb(APages[i], AIL.Width, AIL.Height);
      try
        AIL.Add(Thumb, nil);
      finally
        Thumb.Free;
      end;
    end;
    ALV.LargeImages := AIL;
  finally
    ALV.EndUpdate;
  end;
end;

procedure TfrmMain.TimerDebounceZoomTimer(Sender: TObject);
var
  Sz: integer;
begin
  TimerDebounceZoom.Enabled := False;
  Sz := Max(16, ZoomScroll.Position);
  RebuildThumbs(LVFiles, ILFilesFirstPages, FFirstPages, Sz);
  if PanelSingleFile.Visible then
    RebuildThumbs(LVPages, ILPages, FPagePreviews, Sz);
end;

procedure TfrmMain.ZoomScrollChange(Sender: TObject);
begin
  TimerDebounceZoom.Enabled := False;
  TimerDebounceZoom.Enabled := True;
end;

procedure TfrmMain.ZoomScrollMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
begin
  if WheelDelta > 0 then
    ZoomScroll.Position := ZoomScroll.Position + ZoomScroll.Frequency
  else
    ZoomScroll.Position := ZoomScroll.Position - ZoomScroll.Frequency;
end;

procedure TfrmMain.LayoutFlowPanel;
begin
end;

procedure TfrmMain.ClearThumbnails;
begin
  if FLoadThread <> nil then
  begin
    FLoadThread.Terminate;
    FLoadThread := nil;
  end;
  LVFiles.Clear;
  ILFilesFirstPages.Clear;
  FFirstPages.Clear;
end;

procedure TfrmMain.BtnBrowseClick(Sender: TObject);
begin
  if SelectDialog.Execute then
  begin
    EditDir.Text := SelectDialog.FileName;
    LoadDirectory(SelectDialog.FileName);
  end;
end;

procedure TfrmMain.ClearPreview;
begin
  if FPagesThread <> nil then
  begin
    { FreeOnTerminate: si autodistrugge, e Terminated gli impedisce di
      pubblicare altre pagine su LVPages }
    FPagesThread.Terminate;
    FPagesThread := nil;
  end;
  LVPages.Clear;
  ILPages.Clear;
  FPagePreviews.Clear;
  LblPreviewFile.Caption := ' ';
end;

procedure TfrmMain.HidePreview;
begin
  ClearPreview;
  PanelSingleFile.Visible := False;
  SplitterPreview.Visible := False;
end;

procedure TfrmMain.OpenPreview(AItem: TListItem);
var
  Sz: integer;
begin
  if AItem = nil then Exit;
  ClearPreview;

  Sz := Max(16, ZoomScroll.Position);
  LblPreviewFile.Caption := AItem.Caption;
  PanelSingleFile.Visible := True;
  SplitterPreview.Visible := True;

  LVPages.LargeImages := nil;
  ILPages.Width := Sz;
  ILPages.Height := Round(Sz * 1.25);
  LVPages.LargeImages := ILPages;

  FPagesThread := TPagesThread.Create(
    IncludeTrailingPathDelimiter(FDir) + AItem.Caption);
  FPagesThread.OnTerminate := @PagesThreadTerminated;
  FPagesThread.ListView := LVPages;
  FPagesThread.Images := ILPages;
  FPagesThread.Pages := FPagePreviews;
  FPagesThread.Start;
end;

procedure TfrmMain.LVFilesDblClick(Sender: TObject);
begin
  OpenPreview(LVFiles.Selected);
end;

procedure TfrmMain.LVFilesMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  It: TListItem;
begin
  { il tasto destro non sposta la selezione da solo: il menu deve pero'
    agire sulla voce effettivamente cliccata }
  if Button <> mbRight then Exit;
  It := LVFiles.GetItemAt(X, Y);
  if (It <> nil) and not It.Selected then
    LVFiles.Selected := It;
end;

procedure TfrmMain.PMFilesPopup(Sender: TObject);
begin
  MnuOpenFile.Enabled := LVFiles.Selected <> nil;
end;

procedure TfrmMain.MnuOpenFileClick(Sender: TObject);
begin
  OpenPreview(LVFiles.Selected);
end;

procedure TfrmMain.BtnClosePreviewClick(Sender: TObject);
begin
  HidePreview;
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
  FDir := ADir;
  HidePreview;
  ClearThumbnails;
  FLoadThread := TLoadThread.Create(ADir);
  FLoadThread.OnTerminate := @ThreadTerminated;
  FLoadThread.ListView := LVFiles;
  FLoadThread.Images := ILFilesFirstPages;
  FLoadThread.Pages := FFirstPages;
  FLoadThread.Start;
end;

procedure TfrmMain.ThreadTerminated(Sender: TObject);
begin
  { puo' arrivare da un thread gia' sostituito: non azzerare quello corrente }
  if Sender = FLoadThread then
    FLoadThread := nil;
end;

procedure TfrmMain.PagesThreadTerminated(Sender: TObject);
begin
  if Sender = FPagesThread then
    FPagesThread := nil;
end;

end.
