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
  uPageEditModel;

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
    procedure MnuConvertWebPClick(Sender: TObject);
    procedure ConvertThreadTerminated(Sender: TObject);

    procedure MnuDeleteRowsClick(Sender: TObject);
    procedure DeleteRowsThreadTerminated(Sender: TObject);
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
    { Currently open directory (the one shown in LVFiles). }
    FDir: string;
    { Background thread that scans FDir and loads first-page thumbnails. }
    FLoadThread: TLoadThread;
    { Background thread that opens a single .cbz for page preview. }
    FPagesThread: TPagesThread;
    { Default thumbnail dimensions (unscaled). }
    FThumbW: integer;
    FThumbH: integer;
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
  LVFiles.ReadOnly := True;
  LVFiles.ViewStyle := vsIcon;
  LVFiles.LargeImages := ILFilesFirstPages;
  LVPages.DoubleBuffered := True;
  LVPages.ReadOnly := True;
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
  Sz := Max(16, ZoomScroll.Position);
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

  Sz := Max(16, ZoomScroll.Position);
  LblPreviewFile.Caption := AItem.Caption;
  PanelSingleFile.Visible := True;
  SplitterPreview.Visible := True;

  LVPages.LargeImages := nil;
  ILPages.Width := Sz;
  ILPages.Height := Round(Sz * 1.25);
  LVPages.LargeImages := ILPages;

  FPageFile := IncludeTrailingPathDelimiter(FDir) + AItem.Caption;
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
begin
  MnuOpenFile.Enabled := LVFiles.Selected <> nil;
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

  SetStatus('Validating...');
  StatusProgress.Visible := True;
  TbValidate.Enabled := False;
  MnuValidate.Enabled := False;
  Thread := TValidateThread.Create(Files, FDir, @UpdateProgress);
  Thread.OnTerminate := @ValidateThreadTerminated;
  Thread.Start;
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
  Dlg := TdlgValidate.Create(Self);
  Dlg.ShowResults(Thread.Result);
  Dlg.ShowModal;
  Dlg.Free;
  StatusProgress.Visible := False;
  TbValidate.Enabled := True;
  MnuValidate.Enabled := True;
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
  SetStatus('WebP conversion started...');
  StatusProgress.Visible := True;
  TbConvertWebP.Enabled := False;
  MnuConvertWebP.Enabled := False;
  Thread := TConvertThread.Create(Files, FDir, Options, @UpdateProgress);
  Thread.OnTerminate := @ConvertThreadTerminated;
  Thread.Start;
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
  i: integer;
begin
  Thread := Sender as TConvertThread;
  for i := 0 to High(Thread.Result) do
  begin
    if Thread.Result[i].Success then
      SetStatus(Format('Converted %s: %d pages to WebP',
        [Thread.Result[i].FileName, Thread.Result[i].PagesConverted]))
    else
      SetStatus(Format('%s: %s', [Thread.Result[i].FileName,
        Thread.Result[i].ErrorMsg]));
  end;
  LoadDirectory(FDir);
  StatusProgress.Visible := False;
  TbConvertWebP.Enabled := True;
  MnuConvertWebP.Enabled := True;
  SetStatus(Format('WebP conversion complete: %d files', [Length(Thread.Result)]));
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
  StatusProgress.Visible := False;
  TbMerge.Enabled := True;
  MnuMerge.Enabled := True;
end;


{
  MnuRemoveComicInfoClick
  -----------------------
  Scans selected .cbz files for ComicInfo.xml metadata and presents a dialog
  where the user can inspect and optionally remove it.  The dialog itself
  handles the removal (no background thread needed — it's interactive).
}
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
  StatusProgress.Visible := False;
  MnuDeleteRows.Enabled := True;
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
      if Dlg.CbBatchAll.Checked and (FDir <> '') then
      begin
        { Batch mode: delegate to background thread }
        Files := GetFileList;
        if Length(Files) > 0 then
        begin
          StatusProgress.Visible := True;
          MnuDeleteRows.Enabled := False;
          Thread := TDeletePagesThread.Create(Files, FDir, Dlg.Selected,
            Dlg.CbRenumber.Checked, Dlg.CbDeletePerm.Checked, @UpdateProgress);
          Thread.OnTerminate := @DeleteRowsThreadTerminated;
          Thread.Start;
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
  Increases zoom by 32 units (clamped to ZoomScroll.Max).
}
procedure TfrmMain.MnuZoomInClick(Sender: TObject);
begin
  ZoomScroll.Position := Min(ZoomScroll.Max, ZoomScroll.Position + 32);
end;

{
  MnuZoomOutClick
  ---------------
  Decreases zoom by 32 units (clamped to ZoomScroll.Min).
}
procedure TfrmMain.MnuZoomOutClick(Sender: TObject);
begin
  ZoomScroll.Position := Max(ZoomScroll.Min, ZoomScroll.Position - 32);
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
  i, n: integer;
  Sel: array of integer;
begin
  if not PanelSingleFile.Visible then Exit;
  Sel := nil;
  { Collect selected indices }
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

{
  MnuPageMoveUpClick
  ------------------
  Moves each selected page up by one position (swap with predecessor).
  Processed in index order so contiguous selections shift correctly.
}
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
    begin
      SetLength(Sel, Length(Sel) + 1);
      Sel[High(Sel)] := i;
    end;
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

{
  MnuPageMoveDownClick
  --------------------
  Moves each selected page down by one position.  Processed in reverse index
  order so contiguous selections shift correctly without interfering with
  each other.
}
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
    begin
      SetLength(Sel, Length(Sel) + 1);
      Sel[High(Sel)] := i;
    end;
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

{
  MnuPageMoveStartClick
  ---------------------
  Moves the single selected page to position 0 (the start of the list).
  All items between index 0 and the selected index shift right by one.
}
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

{
  MnuPageMoveEndClick
  -------------------
  Moves the single selected page to the last position.  All items between
  the selected index and the end shift left by one.
}
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

{
  MnuPageSortClick
  ----------------
  Sorts pages alphabetically by file name using a TStringList (which provides
  an O(n log n) in-place sort).  The original indices are stored as TObject
  cast to PtrInt so we can rebuild FPages in sorted order without losing the
  associated TLazIntfImage references.
}
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

{
  MnuPageReverseClick
  -------------------
  Reverses the page order in-place using two-pointer swap (O(n/2)).
}
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
begin
  if Length(FChanges) = 0 then Exit;
  if FPageFile = '' then Exit;

  if MessageDlg('Save changes',
    Format('Save %d pending changes? The original will be backed up as _OLD.cbz.',
    [Length(FChanges)]), mtConfirmation, mbYesNo, 0) <> mrYes then Exit;

  { Take a snapshot of the page state for the background thread }
  SetLength(Snapshot, Length(FPages));
  for i := 0 to High(FPages) do
  begin
    Snapshot[i].Name := FPages[i].Name;
    Snapshot[i].OrigName := FPages[i].OrigName;
    Snapshot[i].Gone := FPages[i].Gone;
  end;

  { Disable stage bar during save }
  BtnStageSave.Enabled := False;
  BtnStageRevert.Enabled := False;
  LblStageMsg.Caption := 'Saving...';
  StatusProgress.Visible := True;

  Thread := TSaveChangesThread.Create(FPageFile, Snapshot, FRenumber, @UpdateProgress);
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
  Accept := Source = LVPages;
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
      Result[n] := LVFiles.Items[i].Caption;
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
  { puo' arrivare da un thread gia' sostituito: non azzerare quello corrente }
  if Sender = FLoadThread then
  begin
    FLoadThread := nil;
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
