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
  Math,
  IntfGraphics,
  Types,
  uloaderthread;

type
  { TfrmMain }

  TfrmMain = class(TForm)
    ILFilesFirstPages: TImageList;
    LVFiles: TListView;
    PanelSingleFile: TPanel;
    PanelMiddle: TPanel;
    PanelBottom: TPanel;
    PanelTop: TPanel;
    EditDir: TEdit;
    BtnBrowse: TButton;
    SelectDialog: TSelectDirectoryDialog;
    TimerDebounceZoom: TTimer;
    ZoomScroll: TTrackBar;
    procedure BtnBrowseClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure TimerDebounceZoomTimer(Sender: TObject);
    procedure ZoomScrollChange(Sender: TObject);
    procedure ZoomScrollMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
  private
    FSelected: array of boolean;
    FLastClicked: integer;
    FLoadThread: TLoadThread;
    FThumbW: integer;
    FThumbH: integer;
    FFirstPages: TLazIntfImageList;
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
  uImgUtil,
  uLog;

  {$R *.lfm}

  { TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'CBZ Manager';
  FFirstPages := TLazIntfImageList.Create(True);
  FLastClicked := -1;
  FLoadThread := nil;
  FThumbW := 150;
  FThumbH := 180;
  ILFilesFirstPages.Width := 128;
  ILFilesFirstPages.Height := 160;
  LVFiles.DoubleBuffered := True;
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

procedure TfrmMain.TimerDebounceZoomTimer(Sender: TObject);
var
  i, Sz: integer;
  Thumb: TBitmap;
begin
  TimerDebounceZoom.Enabled := False;
  Sz := Max(16, ZoomScroll.Position);

  LVFiles.BeginUpdate;
  try
    LVFiles.LargeImages := nil;
    ILFilesFirstPages.Clear;
    ILFilesFirstPages.Width := Sz;
    ILFilesFirstPages.Height := Round(Sz * 1.25);
    for i := 0 to FFirstPages.Count - 1 do
    begin
      Thumb := MakeThumb(FFirstPages[i], Sz, Round(Sz * 1.25));
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
  FLoadThread.ListView := LVFiles;             
  FLoadThread.Images := ILFilesFirstPages;
  FLoadThread.Pages := FFirstPages;
  FLoadThread.Start;
end;

procedure TfrmMain.ThreadTerminated(Sender: TObject);
begin
  FLoadThread := nil;
end;

end.
