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
  end;

  { Dynamic array of TPageState — represents the entire page list of a CBZ. }
  TPageStates = array of TPageState;

  { ------------------------------------------------------------------------
    TChangeKind – Enumerates the types of changes tracked for undo/redo.
      - ckDeleted: the page was removed from the list.
      - ckMoved:   the page was reordered to a different position.
    ------------------------------------------------------------------------ }
  TChangeKind = (ckDeleted, ckMoved);

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
  i, n: integer;
  Tmp: TPageState;
begin
  for i := 0 to High(ASel) do
  begin
    n := ASel[i];
    if (n > 0) and (n <= High(APages)) then
    begin
      Tmp := APages[n - 1];
      APages[n - 1] := APages[n];
      APages[n] := Tmp;
      AppendChange(AChanges, ckMoved, APages[n - 1].Name);
    end;
  end;
end;

procedure PageMoveDown(var APages: TPageStates; var AChanges: TChanges;
  const ASel: array of integer);
var
  i, n: integer;
  Tmp: TPageState;
begin
  for i := High(ASel) downto 0 do
  begin
    n := ASel[i];
    if (n >= 0) and (n < High(APages)) then
    begin
      Tmp := APages[n + 1];
      APages[n + 1] := APages[n];
      APages[n] := Tmp;
      AppendChange(AChanges, ckMoved, APages[n + 1].Name);
    end;
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
  AppendChange(AChanges, ckMoved, 'inversione');
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
    APages[i].Name := FormatPageName(Result, 4, Ext);
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
  // Shallow-copy the page metadata (Name, OrigName, Gone).
  SetLength(FPages, Length(APages));
  for i := 0 to High(APages) do
  begin
    FPages[i].Name := APages[i].Name;
    FPages[i].OrigName := APages[i].OrigName;
    FPages[i].Gone := APages[i].Gone;
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
         position (e.g. "0001.jpg").
       - Otherwise the current Name from the snapshot is used.
    3. Write OutEntries back to disk via ReplaceCBZ (which also handles the
       backup/rollback dance).
    4. Clean up all temporary streams.

  Progress reports: 0 % at start, 60 % after building OutEntries, 100 % on
  successful completion. }
procedure TSaveChangesThread.Execute;
var
  i, j, PageNum: integer;
  AllEntries, OutEntries: TZipEntries;
  NewName, PageExt: string;
begin
  try
    DoProgress(0, 'Reading all entries into RAM...');
    // Load every entry from the CBZ into memory.  This is the only disk read.
    AllEntries := CollectZipEntries(FPageFile);
    try
      SetLength(OutEntries, 0);
      // Rebuild the entry list from the (possibly reordered / filtered) snapshot.
      for i := 0 to High(FPages) do
      begin
        if Terminated then Exit;            // cooperative cancellation
        if FPages[i].Gone then Continue;    // skip deleted pages

        // Find the original entry data by matching the OrigName.
        for j := 0 to High(AllEntries) do
          if SameText(AllEntries[j].Name, FPages[i].OrigName) then
          begin
            SetLength(OutEntries, Length(OutEntries) + 1);
            // Choose the output filename.
            if FRenumber then
            begin
              PageNum := Length(OutEntries);                // 1-based after append
              PageExt := ExtractFileExt(FPages[i].Name);    // preserve original extension
              NewName := FormatPageName(PageNum, 4, PageExt); // e.g. "0003.jpg"
            end
            else
              NewName := FPages[i].Name;  // keep the (possibly user-renamed) name

            OutEntries[High(OutEntries)].Name := NewName;
            // Deep-copy the entry's data stream so OutEntries owns its memory.
            OutEntries[High(OutEntries)].Data := TMemoryStream.Create;
            AllEntries[j].Data.Position := 0;
            OutEntries[High(OutEntries)].Data.CopyFrom(AllEntries[j].Data,
              AllEntries[j].Data.Size);
            Break;  // entry found — move to next page in snapshot
          end;
      end;

      DoProgress(60, 'Writing new CBZ...');
      if FBackupOld then
      begin
        // Safe path: backup original, then write new
        if not ReplaceCBZ(FPageFile, OutEntries) then
        begin
          FResult.ErrorMsg := 'Replace failed — check disk space or permissions';
          FreeZipEntries(OutEntries);
          Exit;
        end;
      end
      else
      begin
        // Direct overwrite — no backup
        WriteZipFromEntriesDeflated(FPageFile, OutEntries);
      end;
      FreeZipEntries(OutEntries);
      FResult.Success := True;
      DoProgress(100, 'Save complete');
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
