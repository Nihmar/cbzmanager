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
  { In-memory page state for the editing model }
  TPageState = record
    Name: string;          // current entry name inside CBZ
    OrigName: string;      // original entry name at open time
    Image: TLazIntfImage;  // cached thumbnail (writable copy)
    Gone: boolean;         // marked for deletion
    OrigIndex: integer;    // original position at open time
  end;
  TPageStates = array of TPageState;

  TChangeKind = (ckDeleted, ckMoved);

  TChange = record
    Kind: TChangeKind;
    PageName: string;
  end;
  TChanges = array of TChange;

  { TfrmMain }

  TfrmMain = class(TForm)
    { Menu }
    MainMenu: TMainMenu;
    MnuFile: TMenuItem;
    MnuOpenFile: TMenuItem;
    MnuBrowse: TMenuItem;
    SepFile1: TMenuItem;
    MnuValidate: TMenuItem;
    MnuConvertWebP: TMenuItem;
    MnuMerge: TMenuItem;

    SepFile2: TMenuItem;
    MnuExit: TMenuItem;
    MnuArchive: TMenuItem;
    MnuRemoveComicInfo: TMenuItem;
    MnuDeleteRows: TMenuItem;

    SepArch1: TMenuItem;
    MnuReload: TMenuItem;
    MnuPages: TMenuItem;
    MnuPageDelete: TMenuItem;
    MnuPageDeleteRows: TMenuItem;
    SepPag1: TMenuItem;
    MnuPageMoveUp: TMenuItem;
    MnuPageMoveDown: TMenuItem;
    MnuPageMoveStart: TMenuItem;
    MnuPageMoveEnd: TMenuItem;
    SepPag2: TMenuItem;
    MnuPageSort: TMenuItem;
    MnuPageReverse: TMenuItem;
    SepPag3: TMenuItem;
    MnuPageRenumber: TMenuItem;
    MnuView: TMenuItem;
    MnuTogglePreview: TMenuItem;
    SepView1: TMenuItem;
    MnuZoomIn: TMenuItem;
    MnuZoomOut: TMenuItem;
    { Toolbar }
    ToolBar: TToolBar;
    TbBrowse: TToolButton;
    TbSep1: TToolButton;
    TbValidate: TToolButton;
    TbConvertWebP: TToolButton;
    TbMerge: TToolButton;

    TbSep2: TToolButton;
    TbTogglePreview: TToolButton;
    { Path row }
    PanelTop: TPanel;
    EditDir: TEdit;
    BtnBrowse: TButton;
    { Status bar }
    PanelBottom: TPanel;
    LblZoomVal: TLabel;
    ZoomScroll: TTrackBar;
    StatusProgress: TProgressBar;
    LblStatus: TLabel;
    { Client area }
    PanelMiddle: TPanel;
    LVFiles: TListView;
    PanelSingleFile: TPanel;
    SplitterPreview: TSplitter;
    { Preview pane }
    PanelPreviewTop: TPanel;
    LblPreviewFile: TLabel;
    LblPageCount: TLabel;
    BtnClosePreview: TButton;
    PanelPageTools: TPanel;
    BtnPgDelete: TButton;
    BtnPgDeleteRows: TButton;
    SepPt1: TPanel;
    BtnPgMoveUp: TButton;
    BtnPgMoveDown: TButton;
    BtnPgMoveStart: TButton;
    BtnPgMoveEnd: TButton;
    SepPt2: TPanel;
    BtnPgSort: TButton;
    BtnPgReverse: TButton;
    PanelStageBar: TPanel;
    ShapeStageDot: TShape;
    LblStageMsg: TLabel;
    BtnStageRevert: TButton;
    BtnStageSave: TButton;
    LVPages: TListView;
    { Dialogs }
    SelectDialog: TSelectDirectoryDialog;
    { Image lists }
    ILFilesFirstPages: TImageList;
    ILPages: TImageList;
    ILToolbar: TImageList;
    { Popup menus }
    PMFiles: TPopupMenu;
    MnuCtxOpenFile: TMenuItem;
    MnuCtxRemoveComicInfo: TMenuItem;
    MnuCtxDeleteRows: TMenuItem;
    MnuCtxReorder: TMenuItem;
    SepCtx1: TMenuItem;
    MnuCtxValidate: TMenuItem;
    MnuCtxConvertWebP: TMenuItem;
    MnuCtxMerge: TMenuItem;

    PMPages: TPopupMenu;
    MnuPgDelete: TMenuItem;
    MnuPgDeleteRows: TMenuItem;
    SepPg1: TMenuItem;
    MnuPgMoveUp: TMenuItem;
    MnuPgMoveDown: TMenuItem;
    MnuPgMoveStart: TMenuItem;
    MnuPgMoveEnd: TMenuItem;
    { Timers }
    TimerDebounceZoom: TTimer;
    { Event handlers }
    procedure BtnBrowseClick(Sender: TObject);
    procedure BtnClosePreviewClick(Sender: TObject);
    procedure BtnStageRevertClick(Sender: TObject);
    procedure BtnStageSaveClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure LVFilesDblClick(Sender: TObject);
    procedure LVFilesMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure LVPagesDragDrop(Sender, Source: TObject; X, Y: integer);
    procedure LVPagesDragOver(Sender, Source: TObject; X, Y: integer;
      State: TDragState; var Accept: boolean);
    procedure MnuConvertWebPClick(Sender: TObject);
    procedure ConvertThreadTerminated(Sender: TObject);

    procedure MnuDeleteRowsClick(Sender: TObject);
    procedure MnuExitClick(Sender: TObject);

    procedure MnuMergeClick(Sender: TObject);
    procedure MergeThreadTerminated(Sender: TObject);
    procedure MnuOpenFileClick(Sender: TObject);
    procedure MnuPageDeleteClick(Sender: TObject);
    procedure MnuPageMoveDownClick(Sender: TObject);
    procedure MnuPageMoveEndClick(Sender: TObject);
    procedure MnuPageMoveStartClick(Sender: TObject);
    procedure MnuPageMoveUpClick(Sender: TObject);
    procedure MnuPageRenumberClick(Sender: TObject);
    procedure MnuPageReverseClick(Sender: TObject);
    procedure MnuPageSortClick(Sender: TObject);
    procedure MnuReloadClick(Sender: TObject);
    procedure MnuRemoveComicInfoClick(Sender: TObject);
    procedure MnuTogglePreviewClick(Sender: TObject);
    procedure MnuValidateClick(Sender: TObject);
    procedure ValidateThreadTerminated(Sender: TObject);
    procedure MnuZoomInClick(Sender: TObject);
    procedure MnuZoomOutClick(Sender: TObject);
    procedure PMFilesPopup(Sender: TObject);
    procedure PMPagesPopup(Sender: TObject);
    procedure TimerDebounceZoomTimer(Sender: TObject);
    procedure ZoomScrollChange(Sender: TObject);
    procedure ZoomScrollMouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
  private
    FDir: string;
    FLoadThread: TLoadThread;
    FPagesThread: TPagesThread;
    FThumbW: integer;
    FThumbH: integer;
    FFirstPages: TLazIntfImageList;
    FPagePreviews: TLazIntfImageList;
    { In-memory editing model }
    FPages: TPageStates;
    FBaseline: TPageStates;
    FChanges: TChanges;
    FRenumber: boolean;
    FPageFile: string;  // currently open CBZ file path
    procedure ThreadTerminated(Sender: TObject);
    procedure PagesThreadTerminated(Sender: TObject);
    procedure ClearThumbnails;
    procedure SetStatus(const AMsg: string);
    procedure UpdateStageBar;
    procedure AddChange(AKind: TChangeKind; const APageName: string);
    procedure FreePageImages;
    procedure LoadDirectory(const ADir: string);
    procedure OpenPreview(AItem: TListItem);
    procedure ClearPreview;
    procedure HidePreview;
    procedure RenderPages;
    procedure RebuildThumbs(ALV: TListView; AIL: TImageList;
      APages: TLazIntfImageList; ASize: integer);
    { Collect file names from LvFiles. When AAll=True returns every file;
      otherwise returns selected files, or all files if none selected. }
    function GetFileList(AAll: boolean = False): TStringArray;
    { Progress callback for service operations: updates StatusProgress + LblStatus }
    procedure UpdateProgress(APercent: integer; const AMsg: string);
  end;

var
  frmMain: TfrmMain;

implementation

uses
  LCLType,
  uImgUtil,
  uLog,
  uZipEditor,
  uservicebase,
  userviceconvert,
  uservicemerge,
  udlgrows,
  udlgvalidate,
  udlgcomicinfo,
  udlgwebp,
  udlgmerge,
  uthreadservice;

  {$R *.lfm}

  { TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
begin
  Caption := 'CBZ Manager';
  FFirstPages := TLazIntfImageList.Create(True);
  FPagePreviews := TLazIntfImageList.Create(True);
  FLoadThread := nil;
  FPagesThread := nil;
  FPages := nil;
  FBaseline := nil;
  FChanges := nil;
  FRenumber := True;
  FPageFile := '';
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
  SetStatus('Ready');
  Log('=== Avvio, log in %s ===', [LogFileName]);
  Log('exe dir: %s', [ExtractFilePath(ParamStr(0))]);
  if ParamCount > 0 then
    LoadDirectory(ParamStr(1));

  { Programmatic hints for icon-only buttons }
  BtnPgMoveUp.Hint := 'Move page up';
  BtnPgMoveDown.Hint := 'Move page down';
  BtnPgMoveStart.Hint := 'Move to start';
  BtnPgMoveEnd.Hint := 'Move to end';
  BtnPgSort.Hint := 'Sort by name';
  BtnPgReverse.Hint := 'Reverse order';
  BtnClosePreview.Hint := 'Close preview';
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  if FLoadThread <> nil then
  begin
    FLoadThread.Terminate;
    FLoadThread.WaitFor;
    FreeAndNil(FLoadThread);
  end;
  if FPagesThread <> nil then
  begin
    FPagesThread.Terminate;
    FPagesThread.WaitFor;
    FreeAndNil(FPagesThread);
  end;
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
  end
  else if (Key = VK_DELETE) and PanelSingleFile.Visible then
  begin
    MnuPageDeleteClick(Sender);
    Key := 0;
  end
  else if (Key = VK_F4) and (Shift = []) then
  begin
    MnuTogglePreviewClick(Sender);
    Key := 0;
  end
  else if (Key = VK_F5) and (Shift = []) then
  begin
    MnuReloadClick(Sender);
    Key := 0;
  end
  else if (Key = VK_F8) and (Shift = []) then
  begin
    MnuValidateClick(Sender);
    Key := 0;
  end
  else if (ssCtrl in Shift) and (Key = Ord('S')) then
  begin
    BtnStageSaveClick(Sender);
    Key := 0;
  end
  else if (ssCtrl in Shift) and (Key = Ord('A')) then
  begin
    if PanelSingleFile.Visible then
      LVPages.SelectAll
    else
      LVFiles.SelectAll;
    Key := 0;
  end;
end;

procedure TfrmMain.SetStatus(const AMsg: string);
begin
  LblStatus.Caption := AMsg;
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

procedure TfrmMain.RenderPages;
var
  i: integer;
  Thumb: TBitmap;
  It: TListItem;
  Sz: integer;
begin
  LVPages.BeginUpdate;
  try
    LVPages.LargeImages := nil;
    ILPages.Clear;
    Sz := Max(16, ZoomScroll.Position);
    ILPages.Width := Sz;
    ILPages.Height := Round(Sz * 1.25);
    for i := 0 to High(FPages) do
    begin
      if FPages[i].Gone then Continue;
      Thumb := MakeThumb(FPages[i].Image, ILPages.Width, ILPages.Height);
      try
        ILPages.Add(Thumb, nil);
      finally
        Thumb.Free;
      end;
      It := LVPages.Items.Add;
      It.Caption := FPages[i].Name;
      It.ImageIndex := ILPages.Count - 1;
    end;
    LVPages.LargeImages := ILPages;
  finally
    LVPages.EndUpdate;
  end;
  LblPageCount.Caption := Format('%d pages', [LVPages.Items.Count]);
end;

procedure TfrmMain.FreePageImages;
var
  i: integer;
begin
  for i := 0 to High(FPages) do
    FPages[i].Image := nil;
  for i := 0 to High(FBaseline) do
    FBaseline[i].Image := nil;
end;

procedure TfrmMain.UpdateStageBar;
var
  nDel, nMov, nTotal: integer;
  i: integer;
begin
  nDel := 0;
  nMov := 0;
  for i := 0 to High(FChanges) do
  begin
    case FChanges[i].Kind of
      ckDeleted: Inc(nDel);
      ckMoved: Inc(nMov);
    end;
  end;
  nTotal := Length(FChanges);
  PanelStageBar.Visible := nTotal > 0;
  if nTotal > 0 then
  begin
    LblStageMsg.Caption := Format('Pending changes: %d', [nTotal]);
  end;
end;

procedure TfrmMain.AddChange(AKind: TChangeKind; const APageName: string);
var
  n: integer;
begin
  n := Length(FChanges);
  SetLength(FChanges, n + 1);
  FChanges[n].Kind := AKind;
  FChanges[n].PageName := APageName;
  UpdateStageBar;
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
  LblZoomVal.Caption := IntToStr(ZoomScroll.Position);
end;

procedure TfrmMain.ZoomScrollChange(Sender: TObject);
begin
  TimerDebounceZoom.Enabled := False;
  TimerDebounceZoom.Enabled := True;
  LblZoomVal.Caption := IntToStr(ZoomScroll.Position);
end;

procedure TfrmMain.ZoomScrollMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
begin
  if WheelDelta > 0 then
    ZoomScroll.Position := ZoomScroll.Position + ZoomScroll.Frequency
  else
    ZoomScroll.Position := ZoomScroll.Position - ZoomScroll.Frequency;
end;

procedure TfrmMain.ClearThumbnails;
begin
  if FLoadThread <> nil then
  begin
    FLoadThread.Terminate;
    FLoadThread.WaitFor;
    FreeAndNil(FLoadThread);
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
    FPagesThread.Terminate;
    FPagesThread.WaitFor;
    FreeAndNil(FPagesThread);
  end;
  FreePageImages;
  FPages := nil;
  FBaseline := nil;
  FChanges := nil;
  FRenumber := True;
  FPageFile := '';
  PanelStageBar.Visible := False;
  LVPages.Clear;
  ILPages.Clear;
  FPagePreviews.Clear;
  LblPreviewFile.Caption := ' ';
  LblPageCount.Caption := '';
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

procedure TfrmMain.PMPagesPopup(Sender: TObject);
begin
  MnuPgDelete.Caption := 'Delete page(s)';
end;

procedure TfrmMain.MnuOpenFileClick(Sender: TObject);
begin
  OpenPreview(LVFiles.Selected);
end;

procedure TfrmMain.BtnClosePreviewClick(Sender: TObject);
begin
  HidePreview;
end;

{ Menu stubs }

procedure TfrmMain.MnuExitClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.MnuReloadClick(Sender: TObject);
begin
  if FDir <> '' then
    LoadDirectory(FDir);
end;

procedure TfrmMain.MnuValidateClick(Sender: TObject);
var
  Files: TStringArray;
  Thread: TValidateThread;
begin
  if FDir = '' then
  begin
    SetStatus('Open a folder first');
    Exit;
  end;
  Files := GetFileList;
  if Length(Files) = 0 then
  begin
    SetStatus('No CBZ files in folder');
    Exit;
  end;

  SetStatus('Validating...');
  StatusProgress.Visible := True;
  TbValidate.Enabled := False;
  MnuValidate.Enabled := False;
  Thread := TValidateThread.Create(Files, FDir, @UpdateProgress);
  Thread.OnTerminate := @ValidateThreadTerminated;
  Thread.Start;
end;

procedure TfrmMain.ValidateThreadTerminated(Sender: TObject);
var
  Thread: TValidateThread;
  Dlg: TdlgValidate;
begin
  Thread := Sender as TValidateThread;
  Dlg := TdlgValidate.Create(Self);
  Dlg.ShowResults(Thread.Result);
  Dlg.ShowModal;
  Dlg.Free;
  StatusProgress.Visible := False;
  TbValidate.Enabled := True;
  MnuValidate.Enabled := True;
  SetStatus(Format('Validation complete: %d files', [Length(Thread.Result)]));
end;

procedure TfrmMain.MnuConvertWebPClick(Sender: TObject);
var
  Dlg: TdlgWebp;
  Files: TStringArray;
  Options: TConvertOptions;
  Thread: TConvertThread;
begin
  if FDir = '' then
  begin
    SetStatus('Open a folder first');
    Exit;
  end;
  { Collect files }
  Files := GetFileList;
  if Length(Files) = 0 then Exit;

  Dlg := TdlgWebp.Create(Self);
  try
    if Dlg.ShowModal <> mrOk then Exit;
    Options.Quality := Dlg.Quality;
    Options.ReplaceOnlyIfSmaller := Dlg.ReplaceOnlyIfSmaller;
    Options.SkipExistingWebP := Dlg.SkipExistingWebP;
    Options.RemoveComicInfo := Dlg.RemoveComicInfo;
    Options.RenumberPages := Dlg.RenumberPages;
    Options.BackupOld := Dlg.BackupOld;
  finally
    Dlg.Free;
  end;

  { Run conversion in background thread }
  SetStatus('WebP conversion started...');
  StatusProgress.Visible := True;
  TbConvertWebP.Enabled := False;
  MnuConvertWebP.Enabled := False;
  Thread := TConvertThread.Create(Files, FDir, Options, @UpdateProgress);
  Thread.OnTerminate := @ConvertThreadTerminated;
  Thread.Start;
end;

procedure TfrmMain.ConvertThreadTerminated(Sender: TObject);
var
  Thread: TConvertThread;
  i: integer;
begin
  Thread := Sender as TConvertThread;
  for i := 0 to High(Thread.Result) do
  begin
    if Thread.Result[i].Success then
      SetStatus(Format('Converted %s: %d pages to WebP',
        [Thread.Result[i].FileName, Thread.Result[i].PagesConverted]))
    else
      SetStatus(Format('%s: %s', [Thread.Result[i].FileName, Thread.Result[i].ErrorMsg]));
  end;
  LoadDirectory(FDir);
  StatusProgress.Visible := False;
  TbConvertWebP.Enabled := True;
  MnuConvertWebP.Enabled := True;
  SetStatus(Format('WebP conversion complete: %d files', [Length(Thread.Result)]));
end;

procedure TfrmMain.MnuMergeClick(Sender: TObject);
var
  Dlg: TdlgMerge;
  Files: TStringArray;
  Options: TMergeOptions;
  SeriesName: string;
  Thread: TMergeThread;
begin
  if FDir = '' then
  begin
    SetStatus('Open a folder first');
    Exit;
  end;
  { Collect all CBZ files }
  Files := GetFileList(True);
  if Length(Files) = 0 then Exit;

  { Auto-detect series name }
  SeriesName := TMergeService.DetectSeriesName(Files);
  if SeriesName = '' then SeriesName := 'Unknown';

  Dlg := TdlgMerge.Create(Self);
  try
    Dlg.LoadChapters(Files, FDir, SeriesName);
    if Dlg.ShowModal <> mrOk then Exit;

    Options.SeriesName := Dlg.EditSeries.Text;
    Options.ChapterStart := Dlg.EditChapterStart.Value;
    Options.ChapterEnd := Dlg.EditChapterEnd.Value;
    if Dlg.CbManualCPV.Checked then
      Options.ChaptersPerVolume := Dlg.EditCPV.Value
    else
      Options.ChaptersPerVolume := 0;  { auto-calculate }
    Options.Force := Dlg.CbForce.Checked;
    Options.Delete := Dlg.CbDelete.Checked;
  finally
    Dlg.Free;
  end;

  { Run merge in background thread }
  SetStatus('Merge started...');
  StatusProgress.Visible := True;
  TbMerge.Enabled := False;
  MnuMerge.Enabled := False;
  Thread := TMergeThread.Create(Files, FDir, Options, @UpdateProgress);
  Thread.OnTerminate := @MergeThreadTerminated;
  Thread.Start;
end;

procedure TfrmMain.MergeThreadTerminated(Sender: TObject);
var
  Thread: TMergeThread;
begin
  Thread := Sender as TMergeThread;
  if Thread.Result.Success then
    SetStatus(Format('Merge complete: %d volumes created', [Thread.Result.VolumesCreated]))
  else
    SetStatus(Format('Merge failed: %s', [Thread.Result.ErrorMsg]));
  LoadDirectory(FDir);
  StatusProgress.Visible := False;
  TbMerge.Enabled := True;
  MnuMerge.Enabled := True;
end;


procedure TfrmMain.MnuRemoveComicInfoClick(Sender: TObject);
var
  Files: TStringArray;
  Dlg: TdlgComicInfo;
begin
  if FDir = '' then
  begin
    SetStatus('Open a folder first');
    Exit;
  end;
  { Collect files }
  Files := GetFileList;
  if Length(Files) = 0 then Exit;
  Dlg := TdlgComicInfo.Create(Self);
  try
    Dlg.ScanFiles(Files, FDir);
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
  LoadDirectory(FDir);
  SetStatus(Format('ComicInfo.xml: %d files processed', [Length(Files)]));
end;

procedure TfrmMain.MnuDeleteRowsClick(Sender: TObject);
var
  Dlg: TdlgRows;
  i: integer;
  Files: TStringArray;
  FullPath: string;
  Entries: TZipEntries;
begin
  if not PanelSingleFile.Visible or (FPageFile = '') then
  begin
    SetStatus('Open a file in preview first');
    Exit;
  end;
  Dlg := TdlgRows.Create(Self);
  try
    Dlg.PageCount := Length(FPages);
    Dlg.Directory := FDir;
    if Dlg.ShowModal = mrOk then
    begin
      if Dlg.CbBatchAll.Checked and (FDir <> '') then
      begin
        { Batch mode: process all CBZ files in directory }
        Files := GetFileList;
        if Length(Files) > 0 then
        begin
          StatusProgress.Visible := True;
          try
            for i := 0 to High(Files) do
            begin
              FullPath := IncludeTrailingPathDelimiter(FDir) + Files[i];
              UpdateProgress((i * 100) div Length(Files),
                Format('Deleting pages from %s (%d/%d)', [Files[i], i + 1, Length(Files)]));

              Entries := FilterPagesFromCBZ(FullPath, Dlg.Selected, Dlg.CbRenumber.Checked);
              try
                if Length(Entries) > 0 then
                begin
                  if Dlg.CbDeletePerm.Checked then
                  begin
                    { Write directly, no backup }
                    WriteZipFromEntriesDeflated(FullPath, Entries);
                  end
                  else
                  begin
                    { Write with backup via ReplaceCBZ }
                    ReplaceCBZ(FullPath, Entries);
                  end;
                end;
              finally
                FreeZipEntries(Entries);
              end;
            end;
          finally
            StatusProgress.Visible := False;
          end;
          LoadDirectory(FDir);
          SetStatus(Format('Batch delete complete: %d files processed', [Length(Files)]));
        end;
      end
      else
      begin
        { Single-file mode: operate on in-memory model }
        for i := 0 to High(Dlg.Selected) do
          if Dlg.Selected[i] and (i < Length(FPages)) and not FPages[i].Gone then
          begin
            FPages[i].Gone := True;
            AddChange(ckDeleted, FPages[i].Name);
          end;
        if Dlg.CbRenumber.Checked then
          FRenumber := True;
        RenderPages;
        SetStatus(Format('%d pages deleted', [Length(FPages)]));
      end;
    end;
  finally
    Dlg.Free;
  end;
end;


procedure TfrmMain.MnuTogglePreviewClick(Sender: TObject);
begin
  if PanelSingleFile.Visible then
    HidePreview
  else if LVFiles.Selected <> nil then
    OpenPreview(LVFiles.Selected);
end;

procedure TfrmMain.MnuZoomInClick(Sender: TObject);
begin
  ZoomScroll.Position := Min(ZoomScroll.Max, ZoomScroll.Position + 32);
end;

procedure TfrmMain.MnuZoomOutClick(Sender: TObject);
begin
  ZoomScroll.Position := Max(ZoomScroll.Min, ZoomScroll.Position - 32);
end;

{ Page operations }

procedure TfrmMain.MnuPageDeleteClick(Sender: TObject);
var
  i, n: integer;
  Sel: array of integer;
begin
  if not PanelSingleFile.Visible then Exit;
  Sel := nil;
  for i := 0 to LVPages.Items.Count - 1 do
    if LVPages.Items[i].Selected then
    begin
      SetLength(Sel, Length(Sel) + 1);
      Sel[High(Sel)] := i;
    end;
  if Length(Sel) = 0 then
  begin
    SetStatus('No pages selected');
    Exit;
  end;
  { Mark as Gone from highest index to lowest so indices stay valid }
  for i := High(Sel) downto 0 do
  begin
    n := Sel[i];
    if not FPages[n].Gone then
    begin
      FPages[n].Gone := True;
      AddChange(ckDeleted, FPages[n].Name);
    end;
  end;
  RenderPages;
  FRenumber := True;
  SetStatus(Format('%d pages deleted', [Length(Sel)]));
end;

procedure TfrmMain.MnuPageMoveUpClick(Sender: TObject);
var
  i, n: integer;
  Tmp: TPageState;
  Sel: array of integer;
begin
  if not PanelSingleFile.Visible then Exit;
  Sel := nil;
  for i := 0 to LVPages.Items.Count - 1 do
    if LVPages.Items[i].Selected then
      begin SetLength(Sel, Length(Sel) + 1); Sel[High(Sel)] := i; end;
  if Length(Sel) = 0 then Exit;
  { Move each selected page up by one (process in order) }
  for i := 0 to High(Sel) do
  begin
    n := Sel[i];
    if n > 0 then
    begin
      Tmp := FPages[n - 1];
      FPages[n - 1] := FPages[n];
      FPages[n] := Tmp;
      AddChange(ckMoved, FPages[n - 1].Name);
    end;
  end;
  RenderPages;
end;

procedure TfrmMain.MnuPageMoveDownClick(Sender: TObject);
var
  i, n: integer;
  Tmp: TPageState;
  Sel: array of integer;
begin
  if not PanelSingleFile.Visible then Exit;
  Sel := nil;
  for i := 0 to LVPages.Items.Count - 1 do
    if LVPages.Items[i].Selected then
      begin SetLength(Sel, Length(Sel) + 1); Sel[High(Sel)] := i; end;
  if Length(Sel) = 0 then Exit;
  { Move each selected page down by one (process in reverse) }
  for i := High(Sel) downto 0 do
  begin
    n := Sel[i];
    if n < High(FPages) then
    begin
      Tmp := FPages[n + 1];
      FPages[n + 1] := FPages[n];
      FPages[n] := Tmp;
      AddChange(ckMoved, FPages[n + 1].Name);
    end;
  end;
  RenderPages;
end;

procedure TfrmMain.MnuPageMoveStartClick(Sender: TObject);
var
  i, n: integer;
  Page: TPageState;
begin
  if not PanelSingleFile.Visible then Exit;
  if LVPages.Selected = nil then Exit;
  n := LVPages.Selected.Index;
  if n <= 0 then Exit;
  Page := FPages[n];
  for i := n downto 1 do
    FPages[i] := FPages[i - 1];
  FPages[0] := Page;
  AddChange(ckMoved, Page.Name);
  RenderPages;
end;

procedure TfrmMain.MnuPageMoveEndClick(Sender: TObject);
var
  i, n, Last: integer;
  Page: TPageState;
begin
  if not PanelSingleFile.Visible then Exit;
  if LVPages.Selected = nil then Exit;
  n := LVPages.Selected.Index;
  Last := High(FPages);
  if (n < 0) or (n >= Last) then Exit;
  Page := FPages[n];
  for i := n to Last - 1 do
    FPages[i] := FPages[i + 1];
  FPages[Last] := Page;
  AddChange(ckMoved, Page.Name);
  RenderPages;
end;

procedure TfrmMain.MnuPageSortClick(Sender: TObject);
var
  i: integer;
  SL: TStringList;
  NewPages: TPageStates;
  OldIdx: integer;
begin
  if not PanelSingleFile.Visible then Exit;
  SL := TStringList.Create;
  try
    { Build string list: key=Name, object=original index }
    for i := 0 to High(FPages) do
      SL.AddObject(FPages[i].Name, TObject(PtrInt(i)));
    SL.Sort;  { O(n log n) }
    { Rebuild FPages in sorted order }
    SetLength(NewPages, SL.Count);
    for i := 0 to SL.Count - 1 do
    begin
      OldIdx := PtrInt(SL.Objects[i]);
      NewPages[i] := FPages[OldIdx];
    end;
    FPages := NewPages;
  finally
    SL.Free;
  end;
  AddChange(ckMoved, 'sort');
  RenderPages;
  SetStatus('Pages sorted by name');
end;

procedure TfrmMain.MnuPageReverseClick(Sender: TObject);
var
  i, j: integer;
  Tmp: TPageState;
begin
  if not PanelSingleFile.Visible then Exit;
  i := 0;
  j := High(FPages);
  while i < j do
  begin
    Tmp := FPages[i];
    FPages[i] := FPages[j];
    FPages[j] := Tmp;
    Inc(i);
    Dec(j);
  end;
  AddChange(ckMoved, 'inversione');
  RenderPages;
  SetStatus('Order reversed');
end;

procedure TfrmMain.MnuPageRenumberClick(Sender: TObject);
var
  i, PageNum: integer;
  Ext: string;
begin
  if not PanelSingleFile.Visible then Exit;
  FRenumber := True;
  PageNum := 1;
  for i := 0 to High(FPages) do
  begin
    if FPages[i].Gone then Continue;
    Ext := ExtractFileExt(FPages[i].Name);
    FPages[i].Name := FormatPageName(PageNum, 4, Ext);
    Inc(PageNum);
  end;
  AddChange(ckMoved, 'renumber');
  RenderPages;
  SetStatus(Format('Pages renumbered (%d)', [PageNum - 1]));
end;

{ Stage bar }

procedure TfrmMain.BtnStageSaveClick(Sender: TObject);
var
  i, j, PageNum: integer;
  AllEntries, OutEntries: TZipEntries;
  NewName, PageExt: string;
begin
  if Length(FChanges) = 0 then Exit;
  if FPageFile = '' then Exit;

  if MessageDlg('Save changes',
    Format('Save %d pending changes? The original will be backed up as _OLD.cbz.',
      [Length(FChanges)]),
    mtConfirmation, mbYesNo, 0) <> mrYes then Exit;

  { Step 1: Read ALL original entries into RAM (no temp files) }
  AllEntries := CollectZipEntries(FPageFile);
  try
    { Step 2: Build the output entry list — keep only survivors }
    SetLength(OutEntries, 0);
    for i := 0 to High(FPages) do
    begin
      if FPages[i].Gone then Continue;

      { Find original data by OrigName }
      for j := 0 to High(AllEntries) do
        if SameText(AllEntries[j].Name, FPages[i].OrigName) then
        begin
          SetLength(OutEntries, Length(OutEntries) + 1);
          { Apply renumber to the output name }
          if FRenumber then
          begin
            PageNum := Length(OutEntries);
            PageExt := ExtractFileExt(FPages[i].Name);
            NewName := FormatPageName(PageNum, 4, PageExt);
          end
          else
            NewName := FPages[i].Name;

          OutEntries[High(OutEntries)].Name := NewName;
          OutEntries[High(OutEntries)].Data := TMemoryStream.Create;
          AllEntries[j].Data.Position := 0;
          OutEntries[High(OutEntries)].Data.CopyFrom(AllEntries[j].Data,
            AllEntries[j].Data.Size);
          Break;
        end;
    end;

    { Step 3: Replace file with backup }
    if not ReplaceCBZ(FPageFile, OutEntries) then
    begin
      SetStatus('Save failed — check disk space or file permissions');
      FreeZipEntries(OutEntries);
      Exit;
    end;

    { Step 4: Update model }
    j := 0;
    for i := 0 to High(FPages) do
      if not FPages[i].Gone then
      begin
        if i <> j then FPages[j] := FPages[i];
        if FRenumber then
        begin
          PageNum := j + 1;
          PageExt := ExtractFileExt(FPages[j].Name);
          FPages[j].Name := FormatPageName(PageNum, 4, PageExt);
        end;
        FPages[j].OrigName := FPages[j].Name;
        Inc(j);
      end;
    SetLength(FPages, j);
    SetLength(FBaseline, Length(FPages));
    for i := 0 to High(FPages) do
    begin
      FBaseline[i] := FPages[i];
      FBaseline[i].OrigIndex := i;
    end;
    FChanges := nil;
    FRenumber := True;
    PanelStageBar.Visible := False;
    FreeZipEntries(OutEntries);
    RenderPages;
    SetStatus(Format('Changes saved: %d pages', [Length(FPages)]));
  finally
    FreeZipEntries(AllEntries);
  end;
end;

procedure TfrmMain.BtnStageRevertClick(Sender: TObject);
var
  i: integer;
begin
  if Length(FChanges) = 0 then Exit;
  if MessageDlg('Discard changes',
    'Discard all pending changes? This cannot be undone.',
    mtConfirmation, mbYesNo, 0) <> mrYes then Exit;
  { Restore from baseline }
  SetLength(FPages, Length(FBaseline));
  for i := 0 to High(FBaseline) do
  begin
    FPages[i] := FBaseline[i];
    FPages[i].Image := FBaseline[i].Image;
    FPages[i].Gone := False;
  end;
  FChanges := nil;
  FRenumber := True;
  PanelStageBar.Visible := False;
  RenderPages;
  SetStatus('Changes discarded');
end;

{ Drag and drop }

procedure TfrmMain.LVPagesDragOver(Sender, Source: TObject; X, Y: integer;
  State: TDragState; var Accept: boolean);
begin
  Accept := Source = LVPages;
end;

procedure TfrmMain.LVPagesDragDrop(Sender, Source: TObject; X, Y: integer);
var
  FromIdx, ToIdx, d: integer;
  Item: TListItem;
  Tmp: TPageState;
begin
  if Source <> LVPages then Exit;
  if LVPages.Selected = nil then Exit;
  Item := LVPages.GetItemAt(X, Y);
  if Item = nil then Exit;
  FromIdx := LVPages.Selected.Index;
  ToIdx := Item.Index;
  if (FromIdx < 0) or (ToIdx < 0) or (FromIdx = ToIdx) then Exit;
  { Safe reorder using swaps (handles reference-counted strings correctly) }
  Tmp := FPages[FromIdx];
  if FromIdx < ToIdx then
    for d := FromIdx to ToIdx - 1 do
      FPages[d] := FPages[d + 1]
  else
    for d := FromIdx downto ToIdx + 1 do
      FPages[d] := FPages[d - 1];
  FPages[ToIdx] := Tmp;
  AddChange(ckMoved, Tmp.Name);
  RenderPages;
  SetStatus(Format('%s moved to position %d', [Tmp.Name, ToIdx + 1]));
end;

{ Thread callbacks }

{ File list helper }

function TfrmMain.GetFileList(AAll: boolean = False): TStringArray;
var
  i, n: integer;
begin
  n := 0;
  SetLength(Result, LVFiles.Items.Count);
  for i := 0 to LVFiles.Items.Count - 1 do
    if AAll or (LVFiles.SelCount = 0) or LVFiles.Items[i].Selected then
    begin
      Result[n] := LVFiles.Items[i].Caption;
      Inc(n);
    end;
  SetLength(Result, n);
end;

procedure TfrmMain.UpdateProgress(APercent: integer; const AMsg: string);
begin
  StatusProgress.Position := APercent;
  StatusProgress.Visible := APercent < 100;
  LblStatus.Caption := AMsg;
  StatusProgress.Update;
  Application.ProcessMessages;
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
  SetStatus(Format('Loading: %s', [ADir]));
end;

procedure TfrmMain.ThreadTerminated(Sender: TObject);
begin
  { puo' arrivare da un thread gia' sostituito: non azzerare quello corrente }
  if Sender = FLoadThread then
  begin
    FLoadThread := nil;
    SetStatus(Format('%d .cbz files', [LVFiles.Items.Count]));
  end;
end;

procedure TfrmMain.PagesThreadTerminated(Sender: TObject);
var
  i: integer;
begin
  if Sender = FPagesThread then
  begin
    FPagesThread := nil;
    { Populate the model from thread results }
    SetLength(FPages, FPagePreviews.Count);
    SetLength(FBaseline, FPagePreviews.Count);
    for i := 0 to FPagePreviews.Count - 1 do
    begin
      FPages[i].Name := LVPages.Items[i].Caption;
      FPages[i].OrigName := LVPages.Items[i].Caption;
      FPages[i].Image := FPagePreviews[i];
      FPages[i].Gone := False;
      FPages[i].OrigIndex := i;
      FBaseline[i] := FPages[i];
    end;
    FChanges := nil;
    FRenumber := True;
    LblPageCount.Caption := Format('%d pages', [LVPages.Items.Count]);
    SetStatus(Format('%d pages in preview', [LVPages.Items.Count]));
  end;
end;

end.
