unit main;

{
  =============================================================================
  CBZ Manager — Main Form Unit
  =============================================================================

  This unit implements TfrmMain, the central hub of the CBZ Manager application.
  CBZ Manager is a desktop tool for managing comic book archive (.cbz) files.
  A .cbz file is a ZIP archive containing sequentially named image pages (PNG,
  JPEG, WebP, etc.).

  Architecture overview
  ---------------------
  The UI is split into two panes controlled by a TSplitter:

  1. Left pane (LVFiles) — File browser
     Lists every .cbz file found in the currently open directory.  Each item
     shows a thumbnail of the first page so the user can visually identify
     the comic at a glance.

  2. Right pane (LVPages) — Page preview & editor
     Opens when the user double-clicks a file.  Displays every page inside
     that .cbz as thumbnails.  The user can delete, reorder, sort, reverse,
     renumber, or drag-and-drop pages.  Edits are staged (not written to disk
     immediately) and can be reverted or committed via a stage bar.

  Threading model
  ---------------
  All heavy I/O runs on background threads so the UI never blocks:

  • TLoadThread (uloaderthread)   — scans a directory, extracts the first page
    of every .cbz, and populates LVFiles.
  • TPagesThread (uloaderthread)  — opens a single .cbz and extracts every
    page into LVPages.
  • TSaveChangesThread (uPageEditModel) — writes staged page edits back to the
    .cbz (delete + reorder + rename), creating a _OLD.cbz backup first.
  • TServiceThread descendants (uthreadservice) — validation, WebP conversion,
    chapter merge, ComicInfo.xml removal, and batch page deletion.  Each
    carries its own result record and communicates progress via TThread.Queue.

  Thread results are consumed in OnTerminate handlers that run on the main
  thread (safe for UI access).  The form disables the relevant menu item while
  a service thread is running to prevent overlapping operations.

  Page editing model (in-memory, staging)
  ---------------------------------------
  When a .cbz is opened for preview the form builds three data structures:

  • FPages    — the current (working) state: TPageStates[0..N-1].
    Each TPageState holds Name, OrigName, Image (thumbnail), Gone flag,
    and OrigIndex.
  • FBaseline — a copy of FPages at open time, used for "revert".
  • FChanges  — a linear log of every delete/move since the last save.

  The stage bar (PanelStageBar) becomes visible as soon as FChanges is
  non-empty.  "Save" launches TSaveChangesThread; "Revert" restores FPages
  from FBaseline and clears FChanges.

  The FRenumber flag controls whether pages are sequentially renamed (e.g.
  "0001.jpg", "0002.jpg", …) when the .cbz is rewritten.  It defaults to True
  and is set whenever the user performs a delete, sort, or explicit renumber.

  Coordinate system & zoom
  ------------------------
  Thumbnails are stored at CacheW×CacheH (320×400) resolution in
  TLazIntfImageList instances (FFirstPages for the file list, FPagePreviews
  for the page list).  The zoom slider (ZoomScroll) rebuilds the TImageList
  icons on-the-fly via RebuildThumbs.  A debounce timer (TimerDebounceZoom)
  prevents rapid rebuilds while the user drags the slider.

  Keyboard shortcuts
  ------------------
  F4          — toggle preview pane
  F5          — reload current directory
  F8          — validate all .cbz files
  Ctrl+S      — save staged changes
  Ctrl+A      — select all items in the active list
  Esc         — close preview pane
  Del         — delete selected page(s)
}
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
  uloaderthread,
  uPageEditModel,
  ufrmjobmonitor;

type
  {
    TfrmMain — Application main form.

    Owns two TLazIntfImageList instances (FFirstPages, FPagePreviews) that
    cache decoded page images at CacheW×CacheH resolution.  All thumbnail
    rendering in the TListViews reads from these caches, so zoom changes never
    re-read ZIP archives.

    The form manages at most one TLoadThread and one TPagesThread at a time.
    Service threads (validate / convert / merge / delete-rows) are fire-and-
    forget with FreeOnTerminate = True; the form only needs to re-enable UI
    controls in their OnTerminate callbacks.
  }
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
    MnuClear: TMenuItem;
    SepFile3: TMenuItem;
    MnuExit: TMenuItem;
    MnuArchive: TMenuItem;
    MnuManageComicInfo: TMenuItem;
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
    LblFolderName: TLabel;
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
    BtnPgAddFront: TButton;
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
    CbBackup: TCheckBox;
    BtnStageRevert: TButton;
    BtnStageSave: TButton;
    LVPages: TListView;
    { Dialogs }
    SelectDialog: TSelectDirectoryDialog;
    OpenDialog: TOpenDialog;
    { Image lists }
    ILFilesFirstPages: TImageList;
    ILPages: TImageList;
    ILToolbar: TImageList;
    { Popup menus }
    PMFiles: TPopupMenu;
    MnuCtxOpenFile: TMenuItem;
    MnuCtxRenameFile: TMenuItem;
    MnuCtxDeleteFile: TMenuItem;
    SepCtxFile: TMenuItem;
    MnuCtxManageComicInfo: TMenuItem;
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
    procedure SaveChangesThreadTerminated(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
    procedure LVFilesDblClick(Sender: TObject);
    procedure LVFilesMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure LVPagesDragDrop(Sender, Source: TObject; X, Y: integer);
    procedure LVPagesDragOver(Sender, Source: TObject; X, Y: integer;
      State: TDragState; var Accept: boolean);
    procedure MnuCtxRenameFileClick(Sender: TObject);
    procedure MnuCtxDeleteFileClick(Sender: TObject);
    procedure MnuConvertWebPClick(Sender: TObject);
    procedure ConvertThreadTerminated(Sender: TObject);

    procedure MnuDeleteRowsClick(Sender: TObject);
    procedure DeleteRowsThreadTerminated(Sender: TObject);
    procedure MnuExitClick(Sender: TObject);

    procedure MnuMergeClick(Sender: TObject);
    procedure MergeThreadTerminated(Sender: TObject);
    procedure MnuClearClick(Sender: TObject);
    procedure MnuOpenFileClick(Sender: TObject);
    procedure MnuPageDeleteClick(Sender: TObject);
    procedure MnuPageMoveDownClick(Sender: TObject);
    procedure MnuPageMoveEndClick(Sender: TObject);
    procedure MnuPageMoveStartClick(Sender: TObject);
    procedure MnuPageMoveUpClick(Sender: TObject);
    procedure MnuPageRenumberClick(Sender: TObject);
    procedure MnuPageAddFrontClick(Sender: TObject);
    procedure MnuPageReverseClick(Sender: TObject);
    procedure MnuPageSortClick(Sender: TObject);
    procedure MnuReloadClick(Sender: TObject);
    procedure MnuManageComicInfoClick(Sender: TObject);
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
    { 16×16 badge overlay for ComicInfo indicator on LVFiles items }
    ILComicInfoBadge: TImageList;
    { Currently open directory (the one shown in LVFiles). }
    FDir: string;
    { Background thread that scans FDir and loads first-page thumbnails. }
    FLoadThread: TLoadThread;
    { Background thread that opens a single .cbz for page preview. }
    FPagesThread: TPagesThread;
    { Full-resolution cached images for the file-list pane (one per .cbz). }
    FFirstPages: TLazIntfImageList;
    { Full-resolution cached images for the page-preview pane (all pages of one .cbz). }
    FPagePreviews: TLazIntfImageList;
    { In-memory editing model }
    FPages: TPageStates;
    FBaseline: TPageStates;
    FChanges: TChanges;
    FRenumber: boolean;
    FPageFile: string;  // currently open CBZ file path
    FJobMonitor: TfrmJobMonitor;  // non-modal job progress window
    procedure ThreadTerminated(Sender: TObject);
    procedure PagesThreadTerminated(Sender: TObject);
    procedure ClearThumbnails;
    procedure SetStatus(const AMsg: string);
    procedure SetFolderOpsEnabled(AEnabled: boolean);
    procedure SetPageOpsEnabled(AEnabled: boolean);
    { Wires OnTerminate, disables the triggering controls, shows the progress
      indicator, and starts an already-constructed service thread. }
    procedure BeginServiceThread(AThread: TThread; const AStatus: string;
      ATerminate: TNotifyEvent; AToolButton: TToolButton; AMenuItem: TMenuItem);
    { Re-enables the triggering controls and hides the progress indicator.
      Called at the top of every service OnTerminate handler. }
    procedure FinishServiceThread(AToolButton: TToolButton; AMenuItem: TMenuItem);
    procedure UpdateStageBar;
    procedure AddChange(AKind: TChangeKind; const APageName: string);
    function GetSelectedPageIndices: TIntegerDynArray;
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
    { Return the full filename for an LVFiles item — reads the original
      filename stored in SubItems[0] (set by SyncAddThumbs), falling back
      to the visible Caption for backward compatibility. }
    function ItemFileName(AItem: TListItem): string;
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
  uWebp,
  uzipcore,
  uZipEditor,
  userviceconvert,
  uservicemerge,
  udlgrows,
  udlgvalidate,
  udlgcomicinfo,
  udlgwebp,
  udlgmerge,
  udlgconvertresults,
  udlgcomicinfoeditor,
  ucomicinfo,
  uservicecomicinfo,
  uthreadservice;

  {$R *.lfm}

const
  { Thumbnail height-to-width ratio: comic pages are taller than wide, so a
    thumbnail of width W is given height Round(W * PAGE_ASPECT_RATIO). }
  PAGE_ASPECT_RATIO = 1.25;

  { Zoom / thumbnail sizing.  The zoom slider value is the thumbnail width in
    pixels; height is derived via PAGE_ASPECT_RATIO. }
  THUMB_DEFAULT_SIZE = 128;   // initial thumbnail width and default zoom
  THUMB_MIN_SIZE = 48;        // smallest width the zoom slider allows
  THUMB_RENDER_FLOOR = 16;    // absolute lower bound when rendering thumbs
  ZOOM_STEP = 32;             // width change per zoom-in / zoom-out step

  { TfrmMain }

{
  FormCreate
  ----------
  Initialises the form on startup.
  - Creates the two TLazIntfImageList caches (FFirstPages, FPagePreviews) with
    ownership (True) so images are freed automatically.
  - Sets thumbnail dimensions and the initial zoom position (128, mid-range).
  - Configures both TListViews in vsIcon mode with double-buffering.
  - Hides the preview pane on startup.  If a directory was passed as a command-
    line argument it is loaded immediately.
}
procedure TfrmMain.FormCreate(Sender: TObject);
var
  Badge: TBitmap;
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
  ILFilesFirstPages.Width := THUMB_DEFAULT_SIZE;
  ILFilesFirstPages.Height := Round(THUMB_DEFAULT_SIZE * PAGE_ASPECT_RATIO);
  ILPages.Width := THUMB_DEFAULT_SIZE;
  ILPages.Height := Round(THUMB_DEFAULT_SIZE * PAGE_ASPECT_RATIO);
  LVFiles.DoubleBuffered := True;
  LVFiles.ReadOnly := True;
  LVFiles.ViewStyle := vsIcon;
  LVFiles.LargeImages := ILFilesFirstPages;
  LVPages.DoubleBuffered := True;
  LVPages.ReadOnly := True;
  LVPages.ViewStyle := vsIcon;
  LVPages.LargeImages := ILPages;

  { ComicInfo badge — small green circle indicator for StateImages overlay }
  ILComicInfoBadge := TImageList.Create(nil);
  ILComicInfoBadge.Width := 16;
  ILComicInfoBadge.Height := 16;
  LVFiles.StateImages := ILComicInfoBadge;
  begin
    Badge := TBitmap.Create;
    try
      Badge.SetSize(16, 16);
      Badge.PixelFormat := pf32bit;
      Badge.Transparent := True;
      Badge.TransparentColor := clNone;
      Badge.Canvas.Brush.Color := clNone;
      Badge.Canvas.FillRect(0, 0, 16, 16);
      { Green filled circle }
      Badge.Canvas.Brush.Color := clLime;
      Badge.Canvas.Pen.Color := clGreen;
      Badge.Canvas.Ellipse(1, 1, 15, 15);
      ILComicInfoBadge.Add(Badge, nil);
    finally
      Badge.Free;
    end;
  end;

  ZoomScroll.Min := THUMB_MIN_SIZE;
  ZoomScroll.Max := CacheW;
  ZoomScroll.Position := THUMB_DEFAULT_SIZE;
  HidePreview;
  SetFolderOpsEnabled(False);
  SetStatus('Ready');

  { Folder name label — sits above EditDir in PanelTop }
  LblFolderName := TLabel.Create(Self);
  LblFolderName.Parent := PanelTop;
  LblFolderName.Align := alTop;
  LblFolderName.Height := 22;
  LblFolderName.BorderSpacing.Around := 4;
  LblFolderName.Font.Style := [fsBold];
  LblFolderName.Caption := '';
  PanelTop.Height := 60;
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

{
  FormDestroy
  -----------
  Gracefully shuts down any running background threads before the form is
  destroyed.  Terminate + WaitFor ensures the thread exits its Execute loop
  cleanly.  The two TLazIntfImageList caches are freed explicitly (they are
  not owned by the form).
}
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
  ILComicInfoBadge.Free;
end;

{
  FormKeyDown
  -----------
  Central keyboard-shortcut dispatcher.  Key is set to 0 after handling to
  prevent the LCL from forwarding it further (e.g. to menu accelerators).

  Shortcuts:
    Esc          — close preview pane
    Del          — delete selected page(s) (preview must be visible)
    F4           — toggle preview
    F5           — reload current directory
    F8           — validate all .cbz files
    Ctrl+S       — save staged changes
    Ctrl+A       — select all in the currently-focused list view
}
procedure TfrmMain.FormKeyDown(Sender: TObject; var Key: word; Shift: TShiftState);
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

{
  SetStatus
  ---------
  Updates the status-bar label.  All user-visible messages flow through here
  so the status bar acts as a single point of feedback.
}
procedure TfrmMain.SetStatus(const AMsg: string);
begin
  LblStatus.Caption := AMsg;
end;

procedure TfrmMain.SetFolderOpsEnabled(AEnabled: boolean);
begin
  TbValidate.Enabled := AEnabled;
  TbConvertWebP.Enabled := AEnabled;
  TbMerge.Enabled := AEnabled;
  MnuValidate.Enabled := AEnabled;
  MnuConvertWebP.Enabled := AEnabled;
  MnuMerge.Enabled := AEnabled;
  MnuManageComicInfo.Enabled := AEnabled;
  MnuRemoveComicInfo.Enabled := AEnabled;
  MnuDeleteRows.Enabled := AEnabled;
end;

procedure TfrmMain.SetPageOpsEnabled(AEnabled: boolean);
begin
  PanelPageTools.Enabled := AEnabled;
  MnuPageDelete.Enabled := AEnabled;
  MnuPageDeleteRows.Enabled := AEnabled;
  MnuPageMoveUp.Enabled := AEnabled;
  MnuPageMoveDown.Enabled := AEnabled;
  MnuPageMoveStart.Enabled := AEnabled;
  MnuPageMoveEnd.Enabled := AEnabled;
  MnuPageSort.Enabled := AEnabled;
  MnuPageReverse.Enabled := AEnabled;
  MnuPageRenumber.Enabled := AEnabled;
end;

procedure TfrmMain.BeginServiceThread(AThread: TThread; const AStatus: string;
  ATerminate: TNotifyEvent; AToolButton: TToolButton; AMenuItem: TMenuItem);
begin
  SetStatus(AStatus);
  StatusProgress.Visible := True;
  if AToolButton <> nil then AToolButton.Enabled := False;
  if AMenuItem <> nil then AMenuItem.Enabled := False;
  AThread.OnTerminate := ATerminate;
  AThread.Start;
  { Create and show the job monitor window }
  if FJobMonitor = nil then
    FJobMonitor := TfrmJobMonitor.Create(Application);
  FJobMonitor.StartJob(AStatus);
end;

procedure TfrmMain.FinishServiceThread(AToolButton: TToolButton;
  AMenuItem: TMenuItem);
begin
  StatusProgress.Visible := False;
  if AToolButton <> nil then AToolButton.Enabled := True;
  if AMenuItem <> nil then AMenuItem.Enabled := True;
  if FJobMonitor <> nil then
    FJobMonitor.FinishJob;
end;

{
  RebuildThumbs
  -------------
  Re-creates thumbnails for a given TListView + TImageList pair at the
  requested size.  Used by the zoom debounce timer.

  The procedure:
  1. Detaches LargeImages from the ListView (otherwise the image list refuses
     to clear while it is assigned).
  2. Clears and resizes the TImageList.
  3. Iterates the TLazIntfImageList, calls MakeThumb to produce a TBitmap at
     the target size, adds it to the TImageList, then frees the bitmap.
  4. Reattaches LargeImages.

  BeginUpdate / EndUpdate suppress per-item repaints for performance.
}
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
    AIL.Height := Round(ASize * PAGE_ASPECT_RATIO);
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

{
  RenderPages
  -----------
  Rebuilds the LVPages content from the in-memory FPages array, skipping
  entries marked as Gone.  This is the only way the page-preview ListView is
  repopulated after edits — there is no separate "model → view" binding.

  Each surviving page gets a new thumbnail built from its cached TLazIntfImage
  (FPages[i].Image), resized to the current zoom level.  The page count label
  is updated to reflect the number of visible pages.
}
procedure TfrmMain.RenderPages;
var
  i: integer;
  Thumb: TBitmap;
  It: TListItem;
  Sz: integer;
begin
  LVPages.BeginUpdate;
  try
    LVPages.Items.Clear;
    LVPages.LargeImages := nil;
    ILPages.Clear;
    Sz := Max(THUMB_RENDER_FLOOR, ZoomScroll.Position);
    ILPages.Width := Sz;
    ILPages.Height := Round(Sz * PAGE_ASPECT_RATIO);
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

{
  FreePageImages
  --------------
  Nils out the Image references in both FPages and FBaseline without freeing
  the underlying TLazIntfImage objects.  This is called from ClearPreview
  before the arrays are discarded, because the actual image objects are owned
  by FPagePreviews (a TLazIntfImageList with OwnsObjects=True).  If we left
  dangling references the list would double-free them.
}
procedure TfrmMain.FreePageImages;
var
  i: integer;
begin
  for i := 0 to High(FPages) do
    FPages[i].Image := nil;
  for i := 0 to High(FBaseline) do
    FBaseline[i].Image := nil;
end;

{
  UpdateStageBar
  --------------
  Counts deletions and moves in FChanges and shows/hides the stage bar
  (PanelStageBar) accordingly.  Called by AddChange after every mutation.
  The stage bar is the coloured strip at the top of the preview pane that
  warns the user of unsaved edits and offers Save / Revert buttons.
}
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

{
  AddChange
  ---------
  Appends a change record to FChanges and refreshes the stage bar.
  This is the single entry point for recording mutations to the page model.
}
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

function TfrmMain.GetSelectedPageIndices: TIntegerDynArray;
var
  i, n: integer;
begin
  Result := nil;
  n := 0;
  for i := 0 to LVPages.Items.Count - 1 do
    if LVPages.Items[i].Selected then
    begin
      SetLength(Result, n + 1);
      Result[n] := i;
      Inc(n);
    end;
end;

{
  TimerDebounceZoomTimer
  ----------------------
  Debounce timer tick handler.  When the user drags the zoom slider we
  restart the timer on every Change event; only when the slider stops moving
  for ~300 ms does the timer fire and rebuild both thumbnail sets at the new
  size.  This avoids dozens of expensive RebuildThumbs calls during a drag.
}
procedure TfrmMain.TimerDebounceZoomTimer(Sender: TObject);
var
  Sz: integer;
begin
  TimerDebounceZoom.Enabled := False;
  Sz := Max(THUMB_RENDER_FLOOR, ZoomScroll.Position);
  RebuildThumbs(LVFiles, ILFilesFirstPages, FFirstPages, Sz);
  if PanelSingleFile.Visible then
    RebuildThumbs(LVPages, ILPages, FPagePreviews, Sz);
  LblZoomVal.Caption := IntToStr(ZoomScroll.Position);
end;

{
  ZoomScrollChange
  ----------------
  Restarts the debounce timer every time the zoom slider position changes.
  The label is updated immediately for snappy feedback even though the actual
  thumbnail rebuild is deferred.
}
procedure TfrmMain.ZoomScrollChange(Sender: TObject);
begin
  TimerDebounceZoom.Enabled := False;
  TimerDebounceZoom.Enabled := True;
  LblZoomVal.Caption := IntToStr(ZoomScroll.Position);
end;

{
  ZoomScrollMouseWheel
  --------------------
  Allows the mouse wheel to change the zoom slider in discrete steps equal to
  the slider's Frequency property.
}
procedure TfrmMain.ZoomScrollMouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: integer; MousePos: TPoint; var Handled: boolean);
begin
  if WheelDelta > 0 then
    ZoomScroll.Position := ZoomScroll.Position + ZoomScroll.Frequency
  else
    ZoomScroll.Position := ZoomScroll.Position - ZoomScroll.Frequency;
end;

{
  ClearThumbnails
  ---------------
  Terminates the running TLoadThread (if any) and clears the file-list view
  and its associated caches.  Called before loading a new directory, so the
  old content is discarded before the new scan starts.

  The thread is waited on (WaitFor) so its memory can be freed safely.
}
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

{
  BtnBrowseClick
  --------------
  Opens a directory-selection dialog.  On OK the edit box is updated and
  LoadDirectory is called to scan the chosen folder.
}
procedure TfrmMain.BtnBrowseClick(Sender: TObject);
begin
  if SelectDialog.Execute then
  begin
    EditDir.Text := SelectDialog.FileName;
    LoadDirectory(SelectDialog.FileName);
  end;
end;

{
  ClearPreview
  ------------
  Tears down everything related to the page-preview pane:
  - Terminates any running TPagesThread.
  - Nils out image references (FreePageImages) so the TLazIntfImageList can
    safely free the actual objects.
  - Discards FPages, FBaseline, FChanges.
  - Clears the LVPages ListView, its TImageList, and the FPagePreviews cache.
  - Resets the stage bar and the preview-file label.
}
procedure TfrmMain.ClearPreview;
var
  i: integer;
begin
  if FPagesThread <> nil then
  begin
    FPagesThread.Terminate;
    FPagesThread.WaitFor;
    FreeAndNil(FPagesThread);
  end;
  FreePageImages;
  for i := 0 to High(FPages) do
    FPages[i].Data.Free;
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

{
  HidePreview
  -----------
  Hides the entire preview pane (PanelSingleFile + Splitter), calling
  ClearPreview first to release resources.  The file-list pane then expands
  to fill the window.
}
procedure TfrmMain.HidePreview;
begin
  ClearPreview;
  PanelSingleFile.Visible := False;
  SplitterPreview.Visible := False;
end;

{
  OpenPreview
  -----------
  Opens the given CBZ file in the page-preview pane.

  1. Clears any previous preview state.
  2. Makes the preview panel and splitter visible.
  3. Derives the full file path from FDir + the item caption.
  4. Creates a TPagesThread to extract every page in the background.
     The thread populates LVPages and FPagePreviews; when it finishes
     PagesThreadTerminated builds the FPages/FBaseline model.

  The ListView image list is pre-sized to the current zoom level before
  starting the thread so items appear at the right size as they arrive.
}
procedure TfrmMain.OpenPreview(AItem: TListItem);
var
  Sz: integer;
begin
  if AItem = nil then Exit;
  ClearPreview;

  Sz := Max(THUMB_RENDER_FLOOR, ZoomScroll.Position);
  LblPreviewFile.Caption := ItemFileName(AItem);
  PanelSingleFile.Visible := True;
  SplitterPreview.Visible := True;

  LVPages.LargeImages := nil;
  ILPages.Width := Sz;
  ILPages.Height := Round(Sz * PAGE_ASPECT_RATIO);
  LVPages.LargeImages := ILPages;

  FPageFile := IncludeTrailingPathDelimiter(FDir) + ItemFileName(AItem);
  SetPageOpsEnabled(False);
  FPagesThread := TPagesThread.Create(FPageFile);
  FPagesThread.OnTerminate := @PagesThreadTerminated;
  FPagesThread.ListView := LVPages;
  FPagesThread.Images := ILPages;
  FPagesThread.Pages := FPagePreviews;
  FPagesThread.Start;
end;

{
  LVFilesDblClick
  ---------------
  Opens the currently selected file in the preview pane on double-click.
}
procedure TfrmMain.LVFilesDblClick(Sender: TObject);
begin
  OpenPreview(LVFiles.Selected);
end;

{
  LVFilesMouseDown
  ----------------
  Ensures the right-clicked item is selected before the popup menu appears.
  With ReadOnly=True the first left click may only focus the control without
  selecting an item, so we force selection on left-click as well (unless
  Ctrl/Shift are held for multi-select).
}
procedure TfrmMain.LVFilesMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  It: TListItem;
begin
  It := LVFiles.GetItemAt(X, Y);
  if It = nil then Exit;

  if Button = mbRight then
  begin
    { il tasto destro non sposta la selezione da solo: il menu deve pero'
      agire sulla voce effettivamente cliccata }
    if not It.Selected then
      LVFiles.Selected := It;
  end
  else if (Button = mbLeft) and not (ssCtrl in Shift) and not (ssShift in Shift) then
  begin
    { With ReadOnly=True the first click may only give focus without selecting;
      force selection so DblClick sees LVFiles.Selected. }
    LVFiles.Selected := It;
  end;
end;

{
  PMFilesPopup
  ------------
  Enables/disables context-menu items just before the popup appears.
  Currently only gates MnuOpenFile on whether a file is selected.
}
procedure TfrmMain.PMFilesPopup(Sender: TObject);
var
  Ready: boolean;
begin
  Ready := FLoadThread = nil;
  MnuOpenFile.Enabled := (LVFiles.Selected <> nil) and Ready;
  MnuCtxRenameFile.Enabled := (LVFiles.Selected <> nil) and Ready;
  MnuCtxDeleteFile.Enabled := (LVFiles.Selected <> nil) and Ready;
  MnuCtxValidate.Enabled := Ready and MnuValidate.Enabled;
  MnuCtxConvertWebP.Enabled := Ready and MnuConvertWebP.Enabled;
  MnuCtxMerge.Enabled := Ready and MnuMerge.Enabled;
  MnuCtxManageComicInfo.Enabled := (LVFiles.Selected <> nil) and Ready;
  MnuCtxRemoveComicInfo.Enabled := Ready and MnuRemoveComicInfo.Enabled;
  MnuCtxDeleteRows.Enabled := Ready and MnuDeleteRows.Enabled;
  MnuCtxReorder.Enabled := Ready;
end;

{
  PMPagesPopup
  ------------
  Adjusts the page context menu caption before it pops up.
}
procedure TfrmMain.PMPagesPopup(Sender: TObject);
begin
  MnuPgDelete.Caption := 'Delete page(s)';
end;

{
  MnuOpenFileClick
  ----------------
  Opens the selected file in the preview pane (same as double-click).
}
procedure TfrmMain.MnuOpenFileClick(Sender: TObject);
begin
  OpenPreview(LVFiles.Selected);
end;

{
  BtnClosePreviewClick
  --------------------
  Closes the preview pane and returns to the file-list-only layout.
}
procedure TfrmMain.BtnClosePreviewClick(Sender: TObject);
begin
  HidePreview;
end;

{ Menu stubs }

{
  MnuExitClick
  ------------
  Closes the application.  FormDestroy handles thread cleanup.
}
procedure TfrmMain.MnuExitClick(Sender: TObject);
begin
  Close;
end;

{
  MnuReloadClick
  --------------
  Re-scans the current directory.  Useful after external changes (e.g. the
  user added or removed .cbz files in the file manager).
}
procedure TfrmMain.MnuReloadClick(Sender: TObject);
begin
  if FDir <> '' then
    LoadDirectory(FDir);
end;

{
  MnuClearClick
  -------------
  Clears the currently loaded directory: empties the file list, hides the
  preview pane, resets the status bar to "Ready", and disables toolbar
  buttons that require a loaded directory.
}
procedure TfrmMain.MnuClearClick(Sender: TObject);
begin
  FDir := '';
  EditDir.Text := '';
  LblFolderName.Caption := '';
  HidePreview;
  ClearThumbnails;
  SetStatus('Ready');
  SetFolderOpsEnabled(False);
end;

{
  MnuValidateClick
  ----------------
  Validates all selected (or all, if none selected) .cbz files in the current
  directory.  Launches a TValidateThread that checks archive integrity and
  reports issues.  Results are shown in a TdlgValidate dialog when the thread
  finishes.
}
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

  Thread := TValidateThread.Create(Files, FDir, @UpdateProgress);
  BeginServiceThread(Thread, 'Validating...', @ValidateThreadTerminated,
    TbValidate, MnuValidate);
end;

{
  ValidateThreadTerminated
  ------------------------
  OnTerminate handler for TValidateThread.  Shows results in a modal dialog,
  then re-enables the UI controls and refreshes the status bar.
}
procedure TfrmMain.ValidateThreadTerminated(Sender: TObject);
var
  Thread: TValidateThread;
  Dlg: TdlgValidate;
begin
  Thread := Sender as TValidateThread;
  FinishServiceThread(TbValidate, MnuValidate);
  if Thread.FatalException <> nil then
  begin
    SetStatus('Validation failed: ' + Exception(Thread.FatalException).Message);
    Exit;
  end;
  Dlg := TdlgValidate.Create(Self);
  Dlg.ShowResults(Thread.Result);
  Dlg.ShowModal;
  Dlg.Free;
  SetStatus(Format('Validation complete: %d files', [Length(Thread.Result)]));
end;

{
  MnuConvertWebPClick
  -------------------
  Opens the WebP conversion dialog, collects user options (quality, whether to
  replace only if smaller, skip existing WebP, etc.), then launches a
  TConvertThread to perform the conversion in the background.
}
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
  Thread := TConvertThread.Create(Files, FDir, Options, @UpdateProgress);
  BeginServiceThread(Thread, 'WebP conversion started...',
    @ConvertThreadTerminated, TbConvertWebP, MnuConvertWebP);
end;

{
  ConvertThreadTerminated
  -----------------------
  OnTerminate handler for TConvertThread.  Iterates per-file results, logs
  outcomes, reloads the directory to pick up any renamed/regenerated files,
  and re-enables UI controls.
}
procedure TfrmMain.ConvertThreadTerminated(Sender: TObject);
var
  Thread: TConvertThread;
  Dlg: TdlgConvertResults;
begin
  Thread := Sender as TConvertThread;
  LoadDirectory(FDir);
  FinishServiceThread(TbConvertWebP, MnuConvertWebP);

  if Thread.FatalException <> nil then
  begin
    SetStatus('WebP conversion failed: ' +
      Exception(Thread.FatalException).Message);
    Exit;
  end;
  SetStatus(Format('WebP conversion complete: %d files', [Length(Thread.Result)]));

  Dlg := TdlgConvertResults.Create(Self);
  try
    Dlg.ShowResults(Thread.Result);
    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

{
  MnuMergeClick
  -------------
  Opens the merge dialog for combining multiple .cbz chapters into volumes.
  Auto-detects a series name from file names, lets the user configure chapter
  ranges and chapters-per-volume, then launches TMergeThread in the background.

  When Options.ChaptersPerVolume = 0 the service auto-calculates the split
  points to keep volumes under a target size.
}
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
    Dlg.Images := FFirstPages;
    if Dlg.ShowModal <> mrOk then Exit;

    Options.SeriesName := Dlg.EditSeries.Text;
    Options.ChapterStart := Dlg.EditChapterStart.Value;
    Options.ChapterEnd := Dlg.EditChapterEnd.Value;
    Options.ChaptersList := Dlg.ChaptersList;
    if (Length(Options.ChaptersList) = 0) and Dlg.CbManualCPV.Checked then
      Options.ChaptersPerVolume := Dlg.EditCPV.Value
    else
      Options.ChaptersPerVolume := 0;
    Options.Force := Dlg.CbForce.Checked;
    Options.Delete := Dlg.CbDelete.Checked;
    Options.GenerateComicInfo := Dlg.GenerateComicInfo;
  finally
    Dlg.Free;
  end;

  { Run merge in background thread }
  Thread := TMergeThread.Create(Files, FDir, Options, @UpdateProgress);
  BeginServiceThread(Thread, 'Merge started...', @MergeThreadTerminated,
    TbMerge, MnuMerge);
end;

{
  MergeThreadTerminated
  ---------------------
  OnTerminate handler for TMergeThread.  Reloads the directory so the newly
  created volume files appear, re-enables UI, and reports outcome.
}
procedure TfrmMain.MergeThreadTerminated(Sender: TObject);
var
  Thread: TMergeThread;
begin
  Thread := Sender as TMergeThread;
  if Thread.Result.Success then
    SetStatus(Format('Merge complete: %d volumes created',
      [Thread.Result.VolumesCreated]))
  else
    SetStatus(Format('Merge failed: %s', [Thread.Result.ErrorMsg]));
  LoadDirectory(FDir);
  FinishServiceThread(TbMerge, MnuMerge);
end;


procedure TfrmMain.MnuCtxRenameFileClick(Sender: TObject);
var
  OldName, NewName, OldPath, NewPath: string;
begin
  if (FDir = '') or (LVFiles.Selected = nil) then Exit;
  OldName := ItemFileName(LVFiles.Selected);
  NewName := ChangeFileExt(OldName, '');
  if not InputQuery('Rename file', 'New name:', NewName) then Exit;
  NewName := Trim(NewName);
  if NewName = '' then Exit;
  if ExtractFileExt(NewName) = '' then
    NewName := NewName + '.cbz';
  if NewName = OldName then Exit;
  OldPath := IncludeTrailingPathDelimiter(FDir) + OldName;
  NewPath := IncludeTrailingPathDelimiter(FDir) + NewName;
  if FileExists(NewPath) then
  begin
    SetStatus('A file with that name already exists');
    Exit;
  end;
  if not RenameFile(OldPath, NewPath) then
  begin
    SetStatus('Rename failed');
    Exit;
  end;
  HidePreview;
  LoadDirectory(FDir);
  SetStatus(Format('Renamed: %s -> %s', [OldName, NewName]));
end;

procedure TfrmMain.MnuCtxDeleteFileClick(Sender: TObject);
var
  FileName, FilePath: string;
begin
  if (FDir = '') or (LVFiles.Selected = nil) then Exit;
  FileName := ItemFileName(LVFiles.Selected);
  if MessageDlg('Delete file',
    Format('Permanently delete "%s"?', [FileName]),
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  FilePath := IncludeTrailingPathDelimiter(FDir) + FileName;
  if not DeleteFile(FilePath) then
  begin
    SetStatus('Delete failed');
    Exit;
  end;
  HidePreview;
  LoadDirectory(FDir);
  SetStatus(Format('Deleted: %s', [FileName]));
end;

procedure TfrmMain.MnuManageComicInfoClick(Sender: TObject);
var
  FileName, FilePath, SeriesName: string;
  Dlg: TdlgComicInfoEditor;
  Info: TComicInfo;
  PageCnt: integer;
  Files: TStringArray;
begin
  if FDir = '' then
  begin
    SetStatus('Open a folder first');
    Exit;
  end;
  if LVFiles.Selected = nil then
  begin
    SetStatus('Select a file first');
    Exit;
  end;
  FileName := ItemFileName(LVFiles.Selected);
  FilePath := IncludeTrailingPathDelimiter(FDir) + FileName;
  Files := GetFileList(True);
  SeriesName := TMergeService.DetectSeriesName(Files);
  PageCnt := GetImageCount(FilePath);
  Dlg := TdlgComicInfoEditor.Create(Self);
  try
    Dlg.LoadFile(FilePath, FileName, SeriesName, PageCnt);
    if Dlg.ShowModal = mrOK then
    begin
      if Dlg.Removed then
      begin
        TComicInfoService.Remove([FileName], FDir, Dlg.BackupEnabled);
        SetStatus('ComicInfo.xml removed from ' + FileName);
      end
      else
      begin
        Info := Dlg.GetData;
        WriteComicInfoToCBZ(FilePath, Info, Dlg.BackupEnabled);
        SetStatus('ComicInfo.xml saved to ' + FileName);
      end;
    end;
  finally
    Dlg.Free;
  end;
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

{
  DeleteRowsThreadTerminated
  --------------------------
  OnTerminate handler for the batch page-deletion thread (TDeletePagesThread).
  On success the directory is reloaded so the file list reflects any renamed
  files.  On failure the error message is displayed in the status bar.
}
procedure TfrmMain.DeleteRowsThreadTerminated(Sender: TObject);
var
  Thread: TDeletePagesThread;
begin
  Thread := Sender as TDeletePagesThread;
  FinishServiceThread(nil, MnuDeleteRows);
  if Thread.Result.Success then
  begin
    LoadDirectory(FDir);
    SetStatus(Format('Batch delete complete: %d files processed',
      [Thread.Result.Processed]));
  end
  else
    SetStatus(Format('Batch delete failed: %s', [Thread.Result.ErrorMsg]));
end;

{
  MnuDeleteRowsClick
  ------------------
  Opens the "delete rows" dialog (TdlgRows), which lets the user select page
  indices to remove.  Supports two modes:

  1. Single-file mode (preview pane open, batch unchecked):
     Marks pages as Gone in the in-memory model and adds ckDeleted changes.
     The actual .cbz is not modified until the user clicks "Save changes".

  2. Batch mode (batch checkbox checked):
     Launches TDeletePagesThread to apply the same page-index selection to
     *every* .cbz in the directory.  Each file is rewritten immediately in
     the background thread (not staged).
}
procedure TfrmMain.MnuDeleteRowsClick(Sender: TObject);
var
  Dlg: TdlgRows;
  i: integer;
  Files: TStringArray;
  Thread: TDeletePagesThread;
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
      if Dlg.BatchAll and (FDir <> '') then
      begin
        { Batch mode: delegate to background thread }
        Files := GetFileList;
        if Length(Files) > 0 then
        begin
          Thread := TDeletePagesThread.Create(Files, FDir, Dlg.Selected,
            Dlg.Renumber, Dlg.DeletePermanently, @UpdateProgress);
          BeginServiceThread(Thread, 'Deleting pages...',
            @DeleteRowsThreadTerminated, nil, MnuDeleteRows);
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
        if Dlg.Renumber then
          FRenumber := True;
        RenderPages;
        SetStatus(Format('%d pages deleted', [Length(FPages)]));
      end;
    end;
  finally
    Dlg.Free;
  end;
end;


{
  MnuTogglePreviewClick
  ---------------------
  Toggles the preview pane: if it is visible it is hidden; otherwise the
  currently selected file in LVFiles is opened for preview.
}
procedure TfrmMain.MnuTogglePreviewClick(Sender: TObject);
begin
  if PanelSingleFile.Visible then
    HidePreview
  else if LVFiles.Selected <> nil then
    OpenPreview(LVFiles.Selected);
end;

{
  MnuZoomInClick
  --------------
  Increases zoom by ZOOM_STEP units (clamped to ZoomScroll.Max).
}
procedure TfrmMain.MnuZoomInClick(Sender: TObject);
begin
  ZoomScroll.Position := Min(ZoomScroll.Max, ZoomScroll.Position + ZOOM_STEP);
end;

{
  MnuZoomOutClick
  ---------------
  Decreases zoom by ZOOM_STEP units (clamped to ZoomScroll.Min).
}
procedure TfrmMain.MnuZoomOutClick(Sender: TObject);
begin
  ZoomScroll.Position := Max(ZoomScroll.Min, ZoomScroll.Position - ZOOM_STEP);
end;

{ ---------------------------------------------------------------------------
  Page operations
  All of the following operate on the in-memory FPages array and record
  changes in FChanges.  They call RenderPages to refresh the ListView and
  set FRenumber := True where appropriate so pages will be renamed on save.
  --------------------------------------------------------------------------- }

{
  MnuPageDeleteClick
  ------------------
  Deletes all selected pages from the preview pane.  Selected indices are
  collected first, then Gone flags are set from highest to lowest index so
  that earlier deletions do not invalidate later indices.  Setting
  FRenumber := True ensures the remaining pages are renumbered on save.
}
procedure TfrmMain.MnuPageDeleteClick(Sender: TObject);
var
  Sel: TIntegerDynArray;
  Count: integer;
begin
  if not PanelSingleFile.Visible then Exit;
  Sel := GetSelectedPageIndices;
  if Length(Sel) = 0 then
  begin
    SetStatus('No pages selected');
    Exit;
  end;
  Count := PageDeleteSelected(FPages, FChanges, Sel);
  FRenumber := True;
  UpdateStageBar;
  RenderPages;
  SetStatus(Format('%d pages deleted', [Count]));
end;

{
  MnuPageMoveUpClick
  ------------------
  Moves each selected page up by one position (swap with predecessor).
  Processed in index order so contiguous selections shift correctly.
}
procedure TfrmMain.MnuPageMoveUpClick(Sender: TObject);
var
  Sel: TIntegerDynArray;
begin
  if not PanelSingleFile.Visible then Exit;
  Sel := GetSelectedPageIndices;
  if Length(Sel) = 0 then Exit;
  PageMoveUp(FPages, FChanges, Sel);
  UpdateStageBar;
  RenderPages;
end;

{
  MnuPageMoveDownClick
  --------------------
  Moves each selected page down by one position.  Processed in reverse index
  order so contiguous selections shift correctly without interfering with
  each other.
}
procedure TfrmMain.MnuPageMoveDownClick(Sender: TObject);
var
  Sel: TIntegerDynArray;
begin
  if not PanelSingleFile.Visible then Exit;
  Sel := GetSelectedPageIndices;
  if Length(Sel) = 0 then Exit;
  PageMoveDown(FPages, FChanges, Sel);
  UpdateStageBar;
  RenderPages;
end;

{
  MnuPageMoveStartClick
  ---------------------
  Moves the single selected page to position 0 (the start of the list).
  All items between index 0 and the selected index shift right by one.
}
procedure TfrmMain.MnuPageMoveStartClick(Sender: TObject);
begin
  if not PanelSingleFile.Visible then Exit;
  if LVPages.Selected = nil then Exit;
  PageMoveToStart(FPages, FChanges, LVPages.Selected.Index);
  UpdateStageBar;
  RenderPages;
end;

{
  MnuPageMoveEndClick
  -------------------
  Moves the single selected page to the last position.  All items between
  the selected index and the end shift left by one.
}
procedure TfrmMain.MnuPageMoveEndClick(Sender: TObject);
begin
  if not PanelSingleFile.Visible then Exit;
  if LVPages.Selected = nil then Exit;
  PageMoveToEnd(FPages, FChanges, LVPages.Selected.Index);
  UpdateStageBar;
  RenderPages;
end;

{
  MnuPageSortClick
  ----------------
  Sorts pages alphabetically by file name using a TStringList (which provides
  an O(n log n) in-place sort).  The original indices are stored as TObject
  cast to PtrInt so we can rebuild FPages in sorted order without losing the
  associated TLazIntfImage references.
}
procedure TfrmMain.MnuPageSortClick(Sender: TObject);
begin
  if not PanelSingleFile.Visible then Exit;
  PageSort(FPages, FChanges);
  UpdateStageBar;
  RenderPages;
  SetStatus('Pages sorted by name');
end;

{
  MnuPageReverseClick
  -------------------
  Reverses the page order in-place using two-pointer swap (O(n/2)).
}
procedure TfrmMain.MnuPageReverseClick(Sender: TObject);
begin
  if not PanelSingleFile.Visible then Exit;
  PageReverse(FPages, FChanges);
  UpdateStageBar;
  RenderPages;
  SetStatus('Order reversed');
end;

{
  MnuPageRenumberClick
  --------------------
  Renames every non-Gone page to a zero-padded sequential number with the
  original file extension preserved (e.g. "0001.jpg", "0002.png", …).
  The page names are updated in FPages but the .cbz is not touched until
  the user saves.  FRenumber is also set globally so the save thread will
  renumber again (idempotent).
}
procedure TfrmMain.MnuPageRenumberClick(Sender: TObject);
var
  Count: integer;
begin
  if not PanelSingleFile.Visible then Exit;
  FRenumber := True;
  Count := PageRenumber(FPages, FChanges);
  UpdateStageBar;
  RenderPages;
  SetStatus(Format('Pages renumbered (%d)', [Count]));
end;

{
  MnuPageAddFrontClick
  --------------------
  Lets the user select an image file from disk and inserts it as page 0
  (the first page) of the currently open CBZ.  The image is decoded,
  cached as a TLazIntfImage thumbnail, and the raw bytes are stored in
  a TMemoryStream attached to the new TPageState.  When saved, the new
  page will be written into the CBZ as the first entry.

  After insertion the stage bar appears; the user can then move the page
  elsewhere using the existing reorder buttons if desired.
}
procedure TfrmMain.MnuPageAddFrontClick(Sender: TObject);
var
  MemStream: TMemoryStream;
  Img: TLazIntfImage;
  PageExt, PageName: string;
  NewPage: TPageState;
begin
  if not PanelSingleFile.Visible then Exit;

  if not OpenDialog.Execute then Exit;

  { Load the entire file into a memory stream for decoding and later save }
  PageExt := ExtractFileExt(OpenDialog.FileName);
  MemStream := TMemoryStream.Create;
  try
    MemStream.LoadFromFile(OpenDialog.FileName);

    { Decode the image for the thumbnail cache }
    if SameText(PageExt, '.webp') then
      Img := WebPToIntfImage(MemStream.Memory, MemStream.Size)
    else
    begin
      MemStream.Position := 0;
      Img := StreamToIntfImage(MemStream, ReaderClassForExt(PageExt));
    end;

    if Img = nil then
    begin
      SetStatus(Format('Cannot decode image: %s', [ExtractFileName(OpenDialog.FileName)]));
      Exit;
    end;

    { Build a TPageState for the new front page.
      Raw bytes are stored in original format; use Convert to WebP later
      if WebP encoding is desired. }
    NewPage.Image := Img;
    NewPage.Gone := False;
    NewPage.OrigIndex := 0;
    PageName := 'frontispiece' + PageExt;
    NewPage.Data := TMemoryStream.Create;
    MemStream.Position := 0;
    NewPage.Data.CopyFrom(MemStream, MemStream.Size);

    NewPage.Name := PageName;
    NewPage.OrigName := PageName;

    { Insert at position 0 }
    PageInsertFront(FPages, FChanges, NewPage);
    FRenumber := True;
    UpdateStageBar;
    RenderPages;
    SetStatus(Format('Inserted %s as page 1', [ExtractFileName(OpenDialog.FileName)]));
  finally
    MemStream.Free;
  end;
end;

{ ---------------------------------------------------------------------------
  Stage bar — Save / Revert
  --------------------------------------------------------------------------- }

{
  SaveChangesThreadTerminated
  ---------------------------
  OnTerminate handler for TSaveChangesThread.  On success the in-memory model
  is compacted (Gone entries removed, renumber applied if requested) and the
  baseline is reset to match the new state.  On failure the error is shown in
  the status bar.  UI controls are re-enabled in both cases.
}
procedure TfrmMain.SaveChangesThreadTerminated(Sender: TObject);
var
  Thread: TSaveChangesThread;
  i, j, PageNum: integer;
  PageExt: string;
begin
  Thread := Sender as TSaveChangesThread;
  if Thread.Result.Success then
  begin
    { Free the Data streams of inserted pages — no longer needed after save }
    for i := 0 to High(FPages) do
      FreeAndNil(FPages[i].Data);

    { Step 4: Update model in-memory (same logic as original synchronous path) }
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
    RenderPages;
    SetStatus(Format('Changes saved: %d pages', [Length(FPages)]));
  end
  else
    SetStatus(Format('Save failed: %s', [Thread.Result.ErrorMsg]));
  StatusProgress.Visible := False;
  BtnStageSave.Enabled := True;
  BtnStageRevert.Enabled := True;
  CbBackup.Enabled := True;
end;

{
  BtnStageSaveClick
  -----------------
  Commits all staged changes to the .cbz file on disk.

  1. Confirms with the user (the original .cbz is renamed to _OLD.cbz as a
     safety backup).
  2. Takes a snapshot of the current FPages state (Name, OrigName, Gone) so
     the background thread can work on a stable copy while the user may
     continue interacting with the UI (though Save/Revert buttons are
     disabled to prevent concurrent edits).
  3. Creates and starts TSaveChangesThread.

  The snapshot does NOT include TLazIntfImage references — the thread only
  needs name and deletion metadata; it re-reads image data from the original
  ZIP.
}
procedure TfrmMain.BtnStageSaveClick(Sender: TObject);
var
  i: integer;
  Snapshot: TPageStates;
  Thread: TSaveChangesThread;
  BackupMsg: string;
begin
  if Length(FChanges) = 0 then Exit;
  if FPageFile = '' then Exit;

  if CbBackup.Checked then
    BackupMsg := ' The original will be backed up as _OLD.cbz.'
  else
    BackupMsg := ' No backup will be kept.';

  if MessageDlg('Save changes',
    Format('Save %d pending changes?%s', [Length(FChanges), BackupMsg]),
    mtConfirmation, mbYesNo, 0) <> mrYes then Exit;

  { Take a snapshot of the page state for the background thread }
  SetLength(Snapshot, Length(FPages));
  for i := 0 to High(FPages) do
  begin
    Snapshot[i].Name := FPages[i].Name;
    Snapshot[i].OrigName := FPages[i].OrigName;
    Snapshot[i].Gone := FPages[i].Gone;
    Snapshot[i].Data := FPages[i].Data;
  end;

  { Disable stage bar during save }
  BtnStageSave.Enabled := False;
  BtnStageRevert.Enabled := False;
  CbBackup.Enabled := False;
  LblStageMsg.Caption := 'Saving...';
  StatusProgress.Visible := True;

  Thread := TSaveChangesThread.Create(FPageFile, Snapshot, FRenumber,
    CbBackup.Checked, @UpdateProgress);
  Thread.OnTerminate := @SaveChangesThreadTerminated;
  Thread.Start;
end;

{
  BtnStageRevertClick
  -------------------
  Discards all pending changes and restores FPages from the baseline snapshot.
  The user is asked for confirmation because this action cannot be undone.
  After revert the stage bar is hidden and the preview is re-rendered.
}
procedure TfrmMain.BtnStageRevertClick(Sender: TObject);
var
  i: integer;
begin
  if Length(FChanges) = 0 then Exit;
  if MessageDlg('Discard changes',
    'Discard all pending changes? This cannot be undone.', mtConfirmation,
    mbYesNo, 0) <> mrYes then Exit;
  { Free any Data streams from inserted pages before restoring baseline }
  for i := 0 to High(FPages) do
    FreeAndNil(FPages[i].Data);

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

{ ---------------------------------------------------------------------------
  Drag and drop (page reordering)
  --------------------------------------------------------------------------- }

{
  LVPagesDragOver
  ---------------
  Accepts drag operations only when the source is LVPages itself (internal
  reorder, no external file drops).
}
procedure TfrmMain.LVPagesDragOver(Sender, Source: TObject; X, Y: integer;
  State: TDragState; var Accept: boolean);
begin
  Accept := (Source = LVPages) and (FPagesThread = nil);
end;

{
  LVPagesDragDrop
  ---------------
  Handles drag-and-drop reorder within the page list.  The selected page is
  moved to the drop target position.  The in-place shift uses a temporary
  variable to avoid issues with managed-string reference counting in the
  dynamic array — direct Swap or intermediate assignments could leave strings
  in an inconsistent state.
}
procedure TfrmMain.LVPagesDragDrop(Sender, Source: TObject; X, Y: integer);
var
  FromIdx, ToIdx: integer;
  Item: TListItem;
  MovedName: string;
begin
  if Source <> LVPages then Exit;
  if LVPages.Selected = nil then Exit;
  Item := LVPages.GetItemAt(X, Y);
  if Item = nil then Exit;
  FromIdx := LVPages.Selected.Index;
  ToIdx := Item.Index;
  if (FromIdx < 0) or (ToIdx < 0) or (FromIdx = ToIdx) then Exit;
  MovedName := FPages[FromIdx].Name;
  PageDragDrop(FPages, FChanges, FromIdx, ToIdx);
  UpdateStageBar;
  RenderPages;
  SetStatus(Format('%s moved to position %d', [MovedName, ToIdx + 1]));
end;

{ ---------------------------------------------------------------------------
  Thread callbacks and helpers
  --------------------------------------------------------------------------- }

{
  GetFileList
  -----------
  Collects file names from LVFiles into a TStringArray.

  When AAll = True: returns every file in the list.
  When AAll = False (default): returns selected files, or ALL files if
    nothing is selected (SelCount = 0).  This "all or selected" pattern is
    used by service operations so the user can either explicitly select a
    subset or apply the operation to the whole directory.

  The result array is tightly packed (no gaps).
}
function TfrmMain.ItemFileName(AItem: TListItem): string;
begin
  if (AItem <> nil) and (AItem.SubItems.Count > 0) and (AItem.SubItems[0] <> '') then
    Result := AItem.SubItems[0]
  else if AItem <> nil then
    Result := AItem.Caption
  else
    Result := '';
end;

{
  GetFileList
  -----------
  Collects file names from LvFiles.  When AAll=True returns every file;
  otherwise returns selected files, or all files if none selected.

  The returned names are the full original filenames (from SubItems[0]),
  so they can be used for actual file I/O.
}
function TfrmMain.GetFileList(AAll: boolean = False): TStringArray;
var
  i, n: integer;
begin
  n := 0;
  Result := nil;
  SetLength(Result, LVFiles.Items.Count);
  for i := 0 to LVFiles.Items.Count - 1 do
    if AAll or (LVFiles.SelCount = 0) or LVFiles.Items[i].Selected then
    begin
      Result[n] := ItemFileName(LVFiles.Items[i]);
      Inc(n);
    end;
  SetLength(Result, n);
end;

{
  UpdateProgress
  --------------
  Progress callback passed to service threads.  Updates the progress bar and
  status label on the main thread via TThread.Queue (the call is marshalled
  by the thread's SyncProgress → FOnProgress chain).  The progress bar is
  hidden when APercent reaches 100.
}
procedure TfrmMain.UpdateProgress(APercent: integer; const AMsg: string);
begin
  StatusProgress.Position := APercent;
  StatusProgress.Visible := APercent < 100;
  LblStatus.Caption := AMsg;
  if FJobMonitor <> nil then
    FJobMonitor.UpdateProgress(APercent, AMsg);
end;

{
  LoadDirectory
  -------------
  Starts loading a directory of .cbz files into the file-list pane.

  1. Logs the path.
  2. Saves FDir and hides any open preview.
  3. Clears previous thumbnails (terminating the old TLoadThread if needed).
  4. Creates a new TLoadThread and wires it to LVFiles / ILFilesFirstPages /
     FFirstPages.  The thread scans the directory, extracts the first page of
     each .cbz, and emits items in batches to the main thread via Synchronize.
  5. When the thread finishes, ThreadTerminated sets the status.

  This method returns immediately — loading proceeds asynchronously.
}
procedure TfrmMain.LoadDirectory(const ADir: string);
begin
  Log('LoadDirectory: %s', [ADir]);
  FDir := ADir;
  LblFolderName.Caption := ExtractFileName(ExcludeTrailingPathDelimiter(ADir));
  HidePreview;
  ClearThumbnails;
  SetFolderOpsEnabled(False);
  FLoadThread := TLoadThread.Create(ADir);
  FLoadThread.OnTerminate := @ThreadTerminated;
  FLoadThread.ListView := LVFiles;
  FLoadThread.Images := ILFilesFirstPages;
  FLoadThread.Pages := FFirstPages;
  FLoadThread.Start;
  SetStatus(Format('Loading: %s', [ADir]));
end;

{
  ThreadTerminated
  ----------------
  OnTerminate handler for TLoadThread.

  Guards against stale threads: if a new LoadDirectory call replaced
  FLoadThread before the old thread finished, the stale thread's OnTerminate
  will still fire, but Sender will not equal FLoadThread (which now points
  to the new thread or nil).  We only update the UI for the current thread.
}
procedure TfrmMain.ThreadTerminated(Sender: TObject);
begin
  if Sender = FLoadThread then
  begin
    FLoadThread := nil;
    SetFolderOpsEnabled(True);
    SetStatus(Format('%d .cbz files', [LVFiles.Items.Count]));
    LVFiles.SetFocus;
  end;
end;

{
  PagesThreadTerminated
  ---------------------
  OnTerminate handler for TPagesThread.

  When the background extraction of all pages from a single .cbz completes,
  this handler builds the in-memory editing model:

  - FPages[i] is initialised from the ListView item caption (entry name)
    and the cached TLazIntfImage from FPagePreviews[i].
  - FBaseline is set to an identical copy so "Revert" can restore this state.
  - FChanges is cleared and FRenumber is reset.

  Same stale-thread guard as ThreadTerminated — only acts if Sender matches
  the current FPagesThread.
}
procedure TfrmMain.PagesThreadTerminated(Sender: TObject);
var
  i: integer;
begin
  if Sender = FPagesThread then
  begin
    FPagesThread := nil;
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
    SetPageOpsEnabled(True);
    LblPageCount.Caption := Format('%d pages', [LVPages.Items.Count]);
    SetStatus(Format('%d pages in preview', [LVPages.Items.Count]));
  end;
end;

end.
