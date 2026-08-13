unit uPageEditModel;

{ ============================================================================
  uPageEditModel – In-memory page editing model for the CBZ preview pane.

  Provides the data types (TPageState, TChange) and the background save thread
  (TSaveChangesThread) that persists in-memory edits back to the CBZ archive.
  This unit is pure data + I/O — it has no GUI dependencies and can be used
  from any context.

  Lifecycle:
    1. Populate a TPageStates array from a CBZ's entry list.
    2. The UI mutates TPageState records (rename, mark deleted, reorder).
    3. TSaveChangesThread writes the modified pages back to disk, optionally
       renumbering them.
  ============================================================================
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IntfGraphics, uzipcore, uservicebase;

type
  { ------------------------------------------------------------------------
    TPageState – In-memory state for a single page in the editing model.

    Each page stored inside a CBZ gets one TPageState record.  The UI mutates
    these records (rename, mark Gone, reorder by moving elements) and the
    background save thread writes the final state back to the archive.
    ------------------------------------------------------------------------ }
  TPageState = record
    Name: string;          // current entry name inside the CBZ (may differ from OrigName after rename)
    OrigName: string;      // original entry name at open time — used as the lookup key during save
    Image: TLazIntfImage;  // cached thumbnail image (writable copy owned by the preview pane)
    Gone: boolean;         // when True the page is marked for deletion and is skipped on save
    OrigIndex: integer;    // original 0-based position at open time (preserved for undo reference)
    Data: TMemoryStream;  // raw image data for inserted or edited pages (nil = unchanged archive page)
  end;

  { Dynamic array of TPageState — represents the entire page list of a CBZ. }
  TPageStates = array of TPageState;

  { ------------------------------------------------------------------------
    TChangeKind – Enumerates the types of changes tracked for undo/redo.
      - ckDeleted: the page was removed from the list.
      - ckMoved:   the page was reordered to a different position.
      - ckEdited:  the page's image content was replaced (resize / colour
                   adjust / split).  Counted by the stage bar so pending
                   edits trigger the Save/Revert flow like any other change.
    ------------------------------------------------------------------------ }
  TChangeKind = (ckDeleted, ckMoved, ckEdited);

  { ------------------------------------------------------------------------
    TChange – A single undo/redo change record.

    @field Kind     The type of change.
    @field PageName The entry name affected (matches TPageState.OrigName).
    ------------------------------------------------------------------------ }
  TChange = record
    Kind: TChangeKind;
    PageName: string;
  end;

  { Dynamic array of TChange — represents an undo/redo stack entry. }
  TChanges = array of TChange;

  { ------------------------------------------------------------------------
    TSaveChangesResult – Outcome of a background save operation.

    @field Success  True if the CBZ was rewritten without error.
    @field ErrorMsg Human-readable error description when Success is False.
    ------------------------------------------------------------------------ }
  TSaveChangesResult = record
    Success: boolean;
    ErrorMsg: string;
  end;

  { ------------------------------------------------------------------------
    TSaveChangesThread – Background thread that persists in-memory page edits
    back to the CBZ archive on disk.

    It takes a shallow copy (snapshot) of the TPageStates array at creation
    time so the main thread can continue mutating the original array while the
    save is in progress.  Image references (TLazIntfImage) are intentionally
    NOT copied — the thread works purely with entry names and streams.

    The Execute method:
      1. Reads the original CBZ entries into memory.
      2. Walks the snapshot, filtering out Gone pages.
      3. Optionally renumbers remaining pages (001, 002, …).
      4. Writes a replacement CBZ via ReplaceCBZ.

    Progress is reported to the main thread through TThread.Queue.
    ------------------------------------------------------------------------ }
  TSaveChangesThread = class(TThread)
  private
    FPageFile: string;               // full path to the CBZ file being saved
    FPages: TPageStates;             // snapshot copy of the page list (no Image refs)
    FRenumber: boolean;              // whether to re-sequence page names after save
    FBackupOld: boolean;             // when True use ReplaceCBZ (backup), otherwise direct write
    FResult: TSaveChangesResult;     // outcome populated by Execute
    FOnProgress: TServiceProgressEvent;     // callback for UI progress updates
    FPendingPct: integer;            // latest progress percentage (set by Execute, read by SyncProgress)
    FPendingMsg: string;             // latest progress message   (set by Execute, read by SyncProgress)
    procedure SyncProgress;          // called on the main thread via TThread.Queue
    procedure DoProgress(APercent: integer; const AMsg: string);  // posts a progress update to the queue
  protected
    procedure Execute; override;
  public
    { Create a suspended thread.  APages is snapshotted immediately.
      @param APageFile   Full path to the .cbz file.
      @param APages      Current page list (copied, Image refs dropped).
      @param ARenumber   If True, surviving pages are renamed 001…NNN.ext.
      @param ABackupOld  If True, create _OLD.cbz backup before writing.
      @param AOnProgress Optional progress callback (nil if not needed). }
    constructor Create(const APageFile: string; const APages: TPageStates;
      ARenumber: boolean; ABackupOld: boolean; AOnProgress: TServiceProgressEvent);
    { Read the result after the thread has terminated.  Call only from the
      OnTerminate handler or after WaitFor. }
    property Result: TSaveChangesResult read FResult;
  end;

procedure AppendChange(var AChanges: TChanges; AKind: TChangeKind;
  const APageName: string);
function PageDeleteSelected(var APages: TPageStates; var AChanges: TChanges;
  const ASel: array of integer): integer;
procedure PageMoveUp(var APages: TPageStates; var AChanges: TChanges;
  const ASel: array of integer);
procedure PageMoveDown(var APages: TPageStates; var AChanges: TChanges;
  const ASel: array of integer);
procedure PageMoveToStart(var APages: TPageStates; var AChanges: TChanges;
  AIndex: integer);
procedure PageMoveToEnd(var APages: TPageStates; var AChanges: TChanges;
  AIndex: integer);
procedure PageSort(var APages: TPageStates; var AChanges: TChanges);
procedure PageReverse(var APages: TPageStates; var AChanges: TChanges);
function PageRenumber(var APages: TPageStates; var AChanges: TChanges): integer;
procedure PageDragDrop(var APages: TPageStates; var AChanges: TChanges;
  AFromIdx, AToIdx: integer);
procedure PageInsertFront(var APages: TPageStates; var AChanges: TChanges;
  const APage: TPageState);
procedure PageInsertAt(var APages: TPageStates; var AChanges: TChanges;
  AIndex: integer; const APage: TPageState);

implementation

procedure AppendChange(var AChanges: TChanges; AKind: TChangeKind;
  const APageName: string);
var
  n: integer;
begin
  n := Length(AChanges);
  SetLength(AChanges, n + 1);
  AChanges[n].Kind := AKind;
  AChanges[n].PageName := APageName;
end;

function PageDeleteSelected(var APages: TPageStates; var AChanges: TChanges;
  const ASel: array of integer): integer;
var
  i, n: integer;
begin
  Result := 0;
  for i := High(ASel) downto 0 do
  begin
    n := ASel[i];
    if (n >= 0) and (n <= High(APages)) and not APages[n].Gone then
    begin
      APages[n].Gone := True;
      AppendChange(AChanges, ckDeleted, APages[n].Name);
      Inc(Result);
    end;
  end;
end;

procedure PageMoveUp(var APages: TPageStates; var AChanges: TChanges;
  const ASel: array of integer);
var
  i, n, p: integer;
  Tmp: TPageState;
begin
  for i := 0 to High(ASel) do
  begin
    n := ASel[i];
    if (n < 0) or (n > High(APages)) then Continue;
    { Swap with the previous VISIBLE page: skip staged-deleted (Gone)
      neighbours so a move-up after a delete is not a silent no-op. }
    p := n - 1;
    while (p >= 0) and APages[p].Gone do Dec(p);
    if p < 0 then Continue;  { already the first visible page }
    Tmp := APages[p];
    APages[p] := APages[n];
    APages[n] := Tmp;
    AppendChange(AChanges, ckMoved, APages[p].Name);
  end;
end;

procedure PageMoveDown(var APages: TPageStates; var AChanges: TChanges;
  const ASel: array of integer);
var
  i, n, p: integer;
  Tmp: TPageState;
begin
  for i := High(ASel) downto 0 do
  begin
    n := ASel[i];
    if (n < 0) or (n > High(APages)) then Continue;
    { Swap with the next VISIBLE page, skipping Gone neighbours. }
    p := n + 1;
    while (p <= High(APages)) and APages[p].Gone do Inc(p);
    if p > High(APages) then Continue;  { already the last visible page }
    Tmp := APages[p];
    APages[p] := APages[n];
    APages[n] := Tmp;
    AppendChange(AChanges, ckMoved, APages[p].Name);
  end;
end;

procedure PageMoveToStart(var APages: TPageStates; var AChanges: TChanges;
  AIndex: integer);
var
  i: integer;
  Page: TPageState;
begin
  if (AIndex <= 0) or (AIndex > High(APages)) then Exit;
  Page := APages[AIndex];
  for i := AIndex downto 1 do
    APages[i] := APages[i - 1];
  APages[0] := Page;
  AppendChange(AChanges, ckMoved, Page.Name);
end;

procedure PageMoveToEnd(var APages: TPageStates; var AChanges: TChanges;
  AIndex: integer);
var
  i, Last: integer;
  Page: TPageState;
begin
  Last := High(APages);
  if (AIndex < 0) or (AIndex >= Last) then Exit;
  Page := APages[AIndex];
  for i := AIndex to Last - 1 do
    APages[i] := APages[i + 1];
  APages[Last] := Page;
  AppendChange(AChanges, ckMoved, Page.Name);
end;

procedure PageSort(var APages: TPageStates; var AChanges: TChanges);
var
  i, OldIdx: integer;
  SL: TStringList;
  NewPages: TPageStates;
begin
  SL := TStringList.Create;
  try
    for i := 0 to High(APages) do
      SL.AddObject(APages[i].Name, TObject(PtrInt(i)));
    SL.Sort;
    SetLength(NewPages, SL.Count);
    for i := 0 to SL.Count - 1 do
    begin
      OldIdx := PtrInt(SL.Objects[i]);
      NewPages[i] := APages[OldIdx];
    end;
    APages := NewPages;
  finally
    SL.Free;
  end;
  AppendChange(AChanges, ckMoved, 'sort');
end;

procedure PageReverse(var APages: TPageStates; var AChanges: TChanges);
var
  i, j: integer;
  Tmp: TPageState;
begin
  i := 0;
  j := High(APages);
  while i < j do
  begin
    Tmp := APages[i];
    APages[i] := APages[j];
    APages[j] := Tmp;
    Inc(i);
    Dec(j);
  end;
  AppendChange(AChanges, ckMoved, 'reverse');
end;

function PageRenumber(var APages: TPageStates; var AChanges: TChanges): integer;
var
  i: integer;
  Ext: string;
begin
  Result := 0;
  for i := 0 to High(APages) do
  begin
    if APages[i].Gone then Continue;
    Inc(Result);
    Ext := ExtractFileExt(APages[i].Name);
    APages[i].Name := FormatPageName(Result, PAGE_PAD_DEFAULT, Ext);
  end;
  AppendChange(AChanges, ckMoved, 'renumber');
end;

procedure PageDragDrop(var APages: TPageStates; var AChanges: TChanges;
  AFromIdx, AToIdx: integer);
var
  d: integer;
  Tmp: TPageState;
begin
  if (AFromIdx < 0) or (AToIdx < 0) or (AFromIdx = AToIdx) then Exit;
  if (AFromIdx > High(APages)) or (AToIdx > High(APages)) then Exit;
  Tmp := APages[AFromIdx];
  if AFromIdx < AToIdx then
    for d := AFromIdx to AToIdx - 1 do
      APages[d] := APages[d + 1]
  else
    for d := AFromIdx downto AToIdx + 1 do
      APages[d] := APages[d - 1];
  APages[AToIdx] := Tmp;
  AppendChange(AChanges, ckMoved, Tmp.Name);
end;

{ ----------------------------------------------------------------------------
  PageInsertFront
  ---------------
  Inserts APage at position 0, shifting all existing elements right by one.
  The caller must provide a fully initialized TPageState (Name, OrigName,
  Image, and optionally Data) which this function does NOT free.
  ---------------------------------------------------------------------------- }
procedure PageInsertFront(var APages: TPageStates; var AChanges: TChanges;
  const APage: TPageState);
begin
  PageInsertAt(APages, AChanges, 0, APage);
end;

{ ----------------------------------------------------------------------------
  PageInsertAt
  -------------
  Inserts APage at position AIndex (clamped to 0..Length), shifting all
  existing elements from AIndex onward right by one.  The caller must provide
  a fully initialized TPageState (Name, OrigName, Image, and optionally Data)
  which this function does NOT free.  Used by the page editor to place the
  extra pieces of a split directly after the split page.
  ---------------------------------------------------------------------------- }
procedure PageInsertAt(var APages: TPageStates; var AChanges: TChanges;
  AIndex: integer; const APage: TPageState);
var
  i: integer;
begin
  if AIndex < 0 then AIndex := 0;
  if AIndex > Length(APages) then AIndex := Length(APages);
  SetLength(APages, Length(APages) + 1);
  for i := High(APages) downto AIndex + 1 do
    APages[i] := APages[i - 1];
  APages[AIndex] := APage;
  AppendChange(AChanges, ckMoved, APage.Name);
end;

{ ----------------------------------------------------------------------------
  TSaveChangesThread – Implementation
  ---------------------------------------------------------------------------- }

{ TSaveChangesThread.Create

  Constructs the thread in a suspended state (CreateSuspended=True).  The caller
  must call Start to begin execution.  The thread frees itself on termination
  (FreeOnTerminate=True).  The APages array is shallow-copied: only Name,
  OrigName, and Gone are duplicated; Image references are deliberately dropped
  because the background thread never touches the GUI's image objects. }
constructor TSaveChangesThread.Create(const APageFile: string;
  const APages: TPageStates; ARenumber: boolean; ABackupOld: boolean;
  AOnProgress: TServiceProgressEvent);
var
  i: integer;
begin
  inherited Create(True);          // create suspended — caller calls Start
  FreeOnTerminate := True;         // thread frees itself when done
  FPageFile := APageFile;
  // Shallow-copy the page metadata (Name, OrigName, Gone, Data).
  SetLength(FPages, Length(APages));
  for i := 0 to High(APages) do
  begin
    FPages[i].Name := APages[i].Name;
    FPages[i].OrigName := APages[i].OrigName;
    FPages[i].Gone := APages[i].Gone;
    { Data stream reference: copied as-is.  For inserted pages (not in the
      original archive) and edited pages (image content replaced by the page
      editor) the stream holds the raw image bytes.  The thread reads from it
      but does NOT free it — ownership stays with the main thread's snapshot
      (which lives until the thread completes). }
    FPages[i].Data := APages[i].Data;
    { Image reference intentionally NOT copied — the thread works with
      streams read from disk, not the in-memory TLazIntfImage copies. }
  end;
  FRenumber := ARenumber;
  FBackupOld := ABackupOld;
  FOnProgress := AOnProgress;
  FResult.Success := False;        // pessimistic default
end;

{ TSaveChangesThread.DoProgress

  Called from the worker thread (Execute).  Stores the latest progress values
  in thread-owned fields and posts a SyncProgress call to the main thread's
  event queue via TThread.Queue.  If no progress callback was supplied, the
  Queue call is skipped entirely to avoid unnecessary overhead. }
procedure TSaveChangesThread.DoProgress(APercent: integer; const AMsg: string);
begin
  FPendingPct := APercent;
  FPendingMsg := AMsg;
  // Only queue if there is a listener — avoids pointless main-thread wakeups.
  if Assigned(FOnProgress) then
    TThread.Queue(nil, @SyncProgress);
end;

{ TSaveChangesThread.SyncProgress

  Executes on the MAIN thread (invoked by TThread.Queue).  Reads the latest
  values written by DoProgress and fires the callback.  The guard on
  FOnProgress is re-checked because the callback could have been cleared
  between the Queue call and execution. }
procedure TSaveChangesThread.SyncProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FPendingPct, FPendingMsg);
end;

{ TSaveChangesThread.Execute

  Main worker method — runs on the background thread.

  Algorithm:
    1. Read ALL entries from the source CBZ into RAM (AllEntries).
    2. Walk the FPages snapshot in its current order.  For each page that is
       NOT marked Gone, locate its data in AllEntries by matching OrigName
       (case-insensitive), copy the stream, and append to OutEntries.
       - If FRenumber is True, the output name is generated from the 1-based
         position (e.g. "page_0001.jpg").
       - Otherwise the current Name from the snapshot is used.
    3. Write OutEntries back to disk via ReplaceCBZ (which also handles the
       backup/rollback dance).
    4. Clean up all temporary streams.

  Progress reports: 0 % at start, 60 % after building OutEntries, 100 % on
  successful completion. }
procedure TSaveChangesThread.Execute;
type
  TNameIdx = record Name: string; Idx: integer; end;
var
  i, j, PageNum, SrcIdx: integer;
  AllEntries, OutEntries: TZipEntries;
  Consumed: array of boolean;
  PageExt: string;
  Found: boolean;
  SortedNames: array of TNameIdx;
  Key: TNameIdx;
  Idx: integer;

  function FindIdx(const AName: string): integer;
  var Lo, Hi, Mid: integer; Lc: string;
  begin
    Result := -1;
    Lc := LowerCase(AName);
    Lo := 0;
    Hi := High(SortedNames);
    while Lo <= Hi do
    begin
      Mid := (Lo + Hi) div 2;
      if SortedNames[Mid].Name < Lc then
        Lo := Mid + 1
      else if SortedNames[Mid].Name > Lc then
        Hi := Mid - 1
      else
      begin
        Result := SortedNames[Mid].Idx;
        Exit;
      end;
    end;
  end;

begin
  try
    DoProgress(0, 'Reading all entries into RAM...');
    // Load every entry from the CBZ into memory.  This is the only disk read.
    AllEntries := CollectZipEntries(FPageFile);
    try
      { --- Build sorted lowercase name lookup for O(log n) search --- }
      SetLength(SortedNames, Length(AllEntries));
      for i := 0 to High(AllEntries) do
      begin
        SortedNames[i].Name := LowerCase(AllEntries[i].Name);
        SortedNames[i].Idx := i;
      end;
      { Insertion sort by lowercase name (stable, fast for <1000 entries). }
      for i := 1 to High(SortedNames) do
      begin
        j := i - 1;
        Key := SortedNames[i];
        while (j >= 0) and (SortedNames[j].Name > Key.Name) do
        begin
          SortedNames[j + 1] := SortedNames[j];
          Dec(j);
        end;
        SortedNames[j + 1] := Key;
      end;

      // Upper bound: every page survives (no Gone), plus all metadata entries.
      SetLength(OutEntries, High(FPages) + 1 + Length(AllEntries));
      Idx := -1;
      // Tracks which source entries a page has accounted for, so leftover
      // (non-page) entries can be preserved rather than dropped.
      SetLength(Consumed, Length(AllEntries));

      try
        // Rebuild the page list from the (reordered / filtered) snapshot.
        for i := 0 to High(FPages) do
        begin
          if Terminated then Exit;          // cooperative cancellation

          // Locate this page's source entry by OrigName — O(log n) via binary search.
          Found := False;
          SrcIdx := FindIdx(FPages[i].OrigName);
          if SrcIdx >= 0 then
          begin
            { Match the linear-scan semantics: an entry is only claimed by the
              first page that references it.  Mark it consumed (even for Gone
              pages) so the metadata pass does not re-add it below. }
            Found := not Consumed[SrcIdx];
            if Found then
              Consumed[SrcIdx] := True;
          end;

          if FPages[i].Gone then Continue;  // deleted: accounted for, not written
          // Nothing to write if the page is neither in the archive nor backed
          // by inserted data (should not happen now OrigName is the real name).
          if not (Found or (FPages[i].Data <> nil)) then Continue;

          Inc(Idx);
          OutEntries[Idx].Data := TMemoryStream.Create;
          // Choose the output filename.
          if FRenumber then
          begin
            PageNum := Idx + 1;                // 1-based after Inc
            PageExt := ExtractFileExt(FPages[i].Name);    // preserve extension
            OutEntries[Idx].Name := FormatPageName(PageNum, PAGE_PAD_DEFAULT, PageExt);
          end
          else
            OutEntries[Idx].Name := FPages[i].Name;   // keep the (possibly renamed) name

          if FPages[i].Data <> nil then
          begin
            { Edited/inserted page: the snapshot's raw stream wins over the
              archive entry (the page editor replaces image content in place).
              The OrigName lookup above still consumes the source entry so
              the metadata pass below does not duplicate it. }
            FPages[i].Data.Position := 0;
            OutEntries[Idx].Data.CopyFrom(FPages[i].Data,
              FPages[i].Data.Size);
          end
          else if SrcIdx >= 0 then
          begin
            // Deep-copy the original archive entry data.
            AllEntries[SrcIdx].Data.Position := 0;
            OutEntries[Idx].Data.CopyFrom(AllEntries[SrcIdx].Data,
              AllEntries[SrcIdx].Data.Size);
          end;
        end;

        // Preserve every source entry no page referenced — ComicInfo.xml and
        // any other non-image metadata — so page edits never strip them.
        for j := 0 to High(AllEntries) do
          if not Consumed[j] then
          begin
            Inc(Idx);
            OutEntries[Idx].Name := AllEntries[j].Name;
            OutEntries[Idx].Data := TMemoryStream.Create;
            AllEntries[j].Data.Position := 0;
            OutEntries[Idx].Data.CopyFrom(AllEntries[j].Data,
              AllEntries[j].Data.Size);
          end;

        // Trim to actual count.
        if Idx >= 0 then
          SetLength(OutEntries, Idx + 1)
        else
          SetLength(OutEntries, 0);

        DoProgress(60, 'Writing new CBZ...');
        if FBackupOld then
        begin
          // Safe path: backup original, then write new
          if not ReplaceCBZ(FPageFile, OutEntries) then
          begin
            FResult.ErrorMsg := 'Replace failed — check disk space or permissions';
            Exit;
          end;
        end
        else
          // Direct overwrite — no backup
          WriteZipFromEntriesDeflated(FPageFile, OutEntries);
        FResult.Success := True;
        DoProgress(100, 'Save complete');
      finally
        FreeZipEntries(OutEntries);  // always freed, even on write failure
      end;
    finally
      FreeZipEntries(AllEntries);  // always free the source entries
    end;
  except
    on E: Exception do
    begin
      FResult.Success := False;
      FResult.ErrorMsg := E.Message;
    end;
  end;
end;


end.
