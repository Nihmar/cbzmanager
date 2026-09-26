unit uthreadservice;

{
  ============================================================================
  uthreadservice – Background thread wrappers for service operations.

  Each service (convert, merge, validate, ComicInfo removal, page deletion)
  has a corresponding TThread descendant that:
    1. Captures the input parameters at construction time.
    2. Calls the service's static method inside Execute() on a worker thread.
    3. Reports progress back to the main thread via TThread.Queue.
    4. Stores the result in a public property so the OnTerminate handler
       (or a WaitFor caller) can read the outcome.

  The base class TServiceThread provides the progress-queueing machinery
  shared by all descendants.

  All classes create themselves suspended (CreateSuspended=True) and free
  themselves on termination (FreeOnTerminate=True).
  ============================================================================
}

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math,
  uzipcore, uZipEditor, uservicebase, userviceconvert, uservicemerge, uservicevalidate,
  uservicecomicinfo, uservicecbr;

type
  { ------------------------------------------------------------------------
    TDeletePagesResult – Outcome of a background batch-delete operation.

    @field Success   True if all files were processed without error.
    @field Processed Number of CBZ files that were rewritten.
    @field ErrorMsg  Description of the first error, or empty on success.
    ------------------------------------------------------------------------ }
  TDeletePagesResult = record
    Success: boolean;
    Processed: integer;
    ErrorMsg: string;
  end;

  { ------------------------------------------------------------------------
    TServiceThread – Abstract base class for all service worker threads.

    Owns the progress-callback plumbing: descendants call the protected
    Progress() method from Execute(), which stores the values in thread-local
    fields and schedules SyncProgress on the main thread via TThread.Queue.

    Descendants must:
      - Store their result in a dedicated field during Execute().
      - Expose that result through a public property so the OnTerminate
        handler can read it after the thread finishes.
    ------------------------------------------------------------------------ }
  TServiceThread = class(TThread)
  private
    FOnProgress: TServiceProgressEvent;     // user-supplied callback (may be nil)
    FPendingPct: integer;            // latest percent value from Execute
    FPendingMsg: string;             // latest message from Execute
    procedure SyncProgress;          // fires FOnProgress on the main thread
  protected
    { Call from Execute to safely report progress to the main thread.
      @param APercent 0–100 completion percentage.
      @param AMsg     Human-readable step description. }
    procedure Progress(APercent: integer; const AMsg: string);
  public
    { Create a suspended thread.
      @param AOnProgress Optional progress callback (nil to skip progress). }
    constructor Create(AOnProgress: TServiceProgressEvent);
  end;

  { ------------------------------------------------------------------------
    TConvertThread – Background CBZ-to-WebP conversion.

    Wraps TConvertService.Convert.  The result (per-file success/failure and
    total counts) is available in the Result property after termination.
    ------------------------------------------------------------------------ }
  TConvertThread = class(TServiceThread)
  private
    FFiles: TStringArray;            // list of .cbz filenames to convert
    FDir: string;                    // directory containing the files
    FOptions: TConvertOptions;       // conversion parameters (quality, etc.)
    FResult: TConvertResults;        // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles      Array of .cbz filenames to convert.
      @param ADir        Directory containing the files.
      @param AOptions    Conversion settings (quality, resize, etc.).
      @param AOnProgress Optional progress callback. }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const AOptions: TConvertOptions; AOnProgress: TServiceProgressEvent);
    property Result: TConvertResults read FResult;
  end;

  { ------------------------------------------------------------------------
    TCbrConvertThread – Background CBR-to-CBZ conversion.

    Wraps TConvertCbrService.Convert.  The per-file results are available
    in the Result property after termination.
    ------------------------------------------------------------------------ }
  TCbrConvertThread = class(TServiceThread)
  private
    FFiles: TStringArray;            // list of .cbr filenames to convert
    FDir: string;                    // directory containing the files
    FOptions: TCbrConvertOptions;    // skip-existing / delete-source
    FResult: TConvertResults;        // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles      Array of .cbr filenames to convert.
      @param ADir        Directory containing the files.
      @param AOptions    Conversion settings.
      @param AOnProgress Optional progress callback. }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const AOptions: TCbrConvertOptions; AOnProgress: TServiceProgressEvent);
    property Result: TConvertResults read FResult;
  end;

  { ------------------------------------------------------------------------
    TMergeThread – Background chapter-to-volume merge.

    Wraps TMergeService.Merge.  Groups chapter files into volumes according
    to the naming convention specified in TMergeOptions.
    ------------------------------------------------------------------------ }
  TMergeThread = class(TServiceThread)
  private
    FFiles: TStringArray;            // list of .cbz filenames to merge
    FDir: string;                    // directory containing the files
    FOptions: TMergeOptions;         // merge parameters (grouping, naming)
    FThreads: integer;               // volume-build workers (0 = automatic)
    FResult: TMergeResult;           // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles      Array of chapter .cbz filenames.
      @param ADir        Directory containing the files.
      @param AOptions    Merge configuration.
      @param AOnProgress Optional progress callback.
      @param AThreads    Volume-build workers (0 = automatic, 1 = sequential). }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const AOptions: TMergeOptions; AOnProgress: TServiceProgressEvent;
      AThreads: integer = 0);
    property Result: TMergeResult read FResult;
  end;

  { ------------------------------------------------------------------------
    TValidateThread – Background CBZ integrity validation.

    Wraps TValidateService.ValidateDeep.  Checks each CBZ for structural
    issues (corrupt zip, missing pages, unsupported formats).
    ------------------------------------------------------------------------ }
  TValidateThread = class(TServiceThread)
  private
    FFiles: TStringArray;            // list of .cbz filenames to validate
    FDir: string;                    // directory containing the files
    FThreads: integer;               // decode workers per file (0 = auto)
    FResult: TValidationResults;     // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles      Array of .cbz filenames to validate.
      @param ADir        Directory containing the files.
      @param AThreads    Per-file decode workers (0 = automatic).
      @param AOnProgress Optional progress callback. }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      AThreads: integer; AOnProgress: TServiceProgressEvent);
    property Result: TValidationResults read FResult;
  end;

  { ------------------------------------------------------------------------
    TComicInfoRemoveThread – Background ComicInfo.xml removal.

    Wraps TComicInfoService.Remove.  Strips ComicInfo.xml metadata from each
    CBZ, optionally creating a backup before modifying.
    ------------------------------------------------------------------------ }
  TComicInfoRemoveThread = class(TServiceThread)
  private
    FFiles: TStringArray;            // list of .cbz filenames to process
    FDir: string;                    // directory containing the files
    FBackup: boolean;                // whether to back up each file before modifying
    FResult: TComicInfoResults;      // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles      Array of .cbz filenames to strip.
      @param ADir        Directory containing the files.
      @param ABackup     If True, create a _OLD.cbz backup before modifying.
      @param AOnProgress Optional progress callback. }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      ABackup: boolean; AOnProgress: TServiceProgressEvent);
    property Result: TComicInfoResults read FResult;
  end;

  { ------------------------------------------------------------------------
    TDeletePagesThread – Background batch page deletion across multiple CBZ
    files.

    For each file in the list, filters out pages marked for deletion in the
    boolean mask (FPagesToDelete).  Optionally renumbers the surviving pages
    and can write directly (bypassing backup) when FDeletePerm is True.
    ------------------------------------------------------------------------ }
  TDeletePagesThread = class(TServiceThread)
  private
    FFiles: TStringArray;            // list of .cbz filenames
    FDir: string;                    // directory containing the files
    FPagesToDelete: array of boolean; // mask: True = delete the page at this index
    FRenumber: boolean;              // whether to renumber surviving pages
    FDeletePerm: boolean;
    // if True, write directly; if False, use ReplaceCBZ (with backup)
    FThreads: integer;               // per-file workers (0 = automatic)
    FResult: TDeletePagesResult;     // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles          Array of .cbz filenames to process.
      @param ADir            Directory containing the files.
      @param APagesToDelete  Boolean mask (same length as page count in each
                             CBZ): True entries are removed.
      @param ARenumber       If True, surviving pages are renumbered 001…NNN.
      @param ADeletePerm     If True, write directly over the CBZ; otherwise
                             use the safe ReplaceCBZ with backup.
      @param AOnProgress     Optional progress callback.
      @param AThreads        Per-file workers (0 = automatic, CPU count capped
                             at 4 — every worker holds a whole archive in RAM;
                             1 = sequential). }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const APagesToDelete: array of boolean; ARenumber, ADeletePerm: boolean;
      AOnProgress: TServiceProgressEvent; AThreads: integer = 0);
    property Result: TDeletePagesResult read FResult;
  end;

implementation

uses
  uservicepool;

{ ============================================================================
  TDeletePagesThread
  ============================================================================ }

{ TDeletePagesThread.Create

  Copies the variadic boolean array into a dynamic array owned by the thread.
  All other parameters are simple value copies — safe because strings use
  reference counting and the dynamic array is duplicated element-by-element. }
constructor TDeletePagesThread.Create(const AFiles: TStringArray;
  const ADir: string; const APagesToDelete: array of boolean;
  ARenumber, ADeletePerm: boolean; AOnProgress: TServiceProgressEvent;
  AThreads: integer);
var
  i: integer;
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  // Copy the open-array parameter into a thread-owned dynamic array.
  SetLength(FPagesToDelete, Length(APagesToDelete));
  for i := 0 to High(APagesToDelete) do
    FPagesToDelete[i] := APagesToDelete[i];
  FRenumber := ARenumber;
  FDeletePerm := ADeletePerm;
  FThreads := AThreads;
end;

type
  { Per-file outcome slot of a delete-pages pool.  Written once by the
    worker that claimed the index, aggregated in order after the join so
    the result is deterministic for any thread count. }
  TDeletePagesSlot = record
    Written: boolean;      { True when the file was rewritten }
    ErrorMsg: string;      { non-empty when this file failed }
  end;

  { Shared state of a delete-pages pool: the file list, the per-file
    result slots and the progress state.  The claim counter and the answer
    to "stop claiming" live in the TIndexPool base; Slots[Idx] is written
    only by the worker that claimed Idx. }
  TDeletePagesPoolState = class(TIndexPool)
  public
    Files: TStringArray;
    Dir: string;
    PagesToDelete: array of boolean;
    Renumber: boolean;
    DeletePerm: boolean;
    Slots: array of TDeletePagesSlot;
    Completed: integer;        { finished files (under Lock) }
    OnProgress: TServiceProgressEvent;
    { Owner thread, for cooperative cancellation of the join. }
    Thread: TDeletePagesThread;
    function Cancelled: boolean; override;
    function CreateWorker: TIndexPoolWorker; override;
  end;

  { Pool worker: filters the claimed file and writes it back, then reports
    progress — serialized by the pool lock, monotonic via the completed
    counter.  Never raises: failures land in the result slot. }
  TDeletePagesPoolWorker = class(TIndexPoolWorker)
  private
    FPool: TDeletePagesPoolState;
  protected
    procedure ProcessIndex(Idx: integer); override;
  public
    constructor Create(APool: TDeletePagesPoolState);
  end;

function TDeletePagesPoolState.Cancelled: boolean;
begin
  Result := (Thread <> nil) and Thread.Terminated;
end;

function TDeletePagesPoolState.CreateWorker: TIndexPoolWorker;
begin
  Result := TDeletePagesPoolWorker.Create(Self);
end;

constructor TDeletePagesPoolWorker.Create(APool: TDeletePagesPoolState);
begin
  inherited Create(APool);
  FPool := APool;
end;

procedure TDeletePagesPoolWorker.ProcessIndex(Idx: integer);
var
  FullPath: string;
  Entries: TZipEntries;
  Ok: boolean;
begin
  FullPath := IncludeTrailingPathDelimiter(FPool.Dir) + FPool.Files[Idx];
  try
    // FilterPagesFromCBZ reads the archive, drops marked pages,
    // optionally renumbers, and returns the surviving entries.
    Entries := FilterPagesFromCBZ(FullPath, FPool.PagesToDelete,
      FPool.Renumber);
    try
      if Length(Entries) > 0 then
      begin
        // Always write through the safe temp-file + rename path
        // (ReplaceCBZ), matching the sequential behaviour.
        Ok := ReplaceCBZ(FullPath, Entries);
        if Ok and FPool.DeletePerm then
        begin
          // "Delete permanently": drop the _OLD.cbz backup so no recovery
          // copy remains.
          if DeleteFile(ChangeFileExt(FullPath, '') + BACKUP_SUFFIX) then
            ;  // backup removed
        end;
        if Ok then
          FPool.Slots[Idx].Written := True
        else
          FPool.Slots[Idx].ErrorMsg :=
            Format('Failed to write %s', [FPool.Files[Idx]]);
      end;
      { Length(Entries) = 0: silent no-op, like the sequential path —
        the slot stays neutral. }
    finally
      FreeZipEntries(Entries);  // always free the temporary entry list
    end;
  except
    on E: Exception do
      FPool.Slots[Idx].ErrorMsg :=
        Format('%s: %s', [FPool.Files[Idx], E.Message]);
  end;

  FPool.LockPool;
  try
    Inc(FPool.Completed);
    if Assigned(FPool.OnProgress) then
      FPool.OnProgress((FPool.Completed * 100) div FPool.Total,
        Format('Deleting pages from %s (%d/%d)', [FPool.Files[Idx],
          FPool.Completed, FPool.Total]));
  finally
    FPool.UnlockPool;
  end;
end;

{ TDeletePagesThread.Execute

  Iterates over every file in FFiles.  For each file:
    1. Reads the CBZ entries via FilterPagesFromCBZ, which removes pages
       whose index is True in FPagesToDelete.
    2. Writes the filtered entries back — either directly (FDeletePerm=True)
       or through the safe ReplaceCBZ path.
    3. Counts successfully processed files in FResult.Processed.

  Checks Terminated before each file to support cooperative cancellation. }
procedure TDeletePagesThread.Execute;
var
  i, ThreadCount: integer;
  FullPath: string;
  Entries: TZipEntries;
  Ok: boolean;
  Pool: TDeletePagesPoolState;
begin
  FResult.Success := True;
  FResult.Processed := 0;
  FResult.ErrorMsg := '';

  ThreadCount := FThreads;
  if ThreadCount <= 0 then
    { Every worker holds a whole archive in RAM — same cap as the CBR and
      merge pools. }
    ThreadCount := Min(OnlineCpuCount, MAX_CBR_CONVERT_THREADS);
  ThreadCount := Min(ThreadCount, Length(FFiles));

  if ThreadCount <= 1 then
  begin
    { Sequential: exactly the historical behaviour. }
    for i := 0 to High(FFiles) do
    begin
      if Terminated then
      begin
        FResult.ErrorMsg := 'Cancelled';
        FResult.Success := False;
        Exit;
      end;
      // Build the full path from directory + filename.
      FullPath := IncludeTrailingPathDelimiter(FDir) + FFiles[i];
      Progress((i * 100) div Length(FFiles),
        Format('Deleting pages from %s (%d/%d)', [FFiles[i], i + 1, Length(FFiles)]));
      // Each file is processed independently: a failure must not abort the rest
      // of the batch (mirrors the other service threads).  Errors are captured
      // in FResult and surfaced by the termination handler.
      try
        // FilterPagesFromCBZ reads the archive, drops marked pages,
        // optionally renumbers, and returns the surviving entries.
        Entries := FilterPagesFromCBZ(FullPath, FPagesToDelete, FRenumber);
        try
          if Length(Entries) > 0 then
          begin
            // Always write through the safe temp-file + rename path
            // (ReplaceCBZ).  Overwriting the live file in place via
            // WriteZipFromEntriesDeflated was the only branch that created the
            // output stream on the original name, which fails on filesystems
            // that lease/reject overwriting an open archive (e.g. CIFS/SMB) with
            // "Unable to create file".  ReplaceCBZ writes to a .new temp file and
            // renames, matching every other service.
            Ok := ReplaceCBZ(FullPath, Entries);
            if Ok and FDeletePerm then
            begin
              // "Delete permanently": drop the _OLD.cbz backup so no recovery
              // copy remains.
              if DeleteFile(ChangeFileExt(FullPath, '') + BACKUP_SUFFIX) then
                ;  // backup removed
            end;
            if Ok then
              Inc(FResult.Processed)
            else
            begin
              FResult.Success := False;
              if FResult.ErrorMsg = '' then
                FResult.ErrorMsg := Format('Failed to write %s', [FFiles[i]]);
            end;
          end;
        finally
          FreeZipEntries(Entries);  // always free the temporary entry list
        end;
      except
        on E: Exception do
        begin
          FResult.Success := False;
          if FResult.ErrorMsg = '' then
            FResult.ErrorMsg := Format('%s: %s', [FFiles[i], E.Message]);
        end;
      end;
    end;
  end
  else
  begin
    { Parallel: a pool of file workers claims indices and writes each
      result into its own slot; the outcome is aggregated in order after
      the join, so it is identical for any thread count.  Per-file
      failures never abort the batch, mirroring the sequential path. }
    Pool := TDeletePagesPoolState.Create(Length(FFiles));
    try
      Pool.Files := FFiles;
      Pool.Dir := FDir;
      Pool.PagesToDelete := FPagesToDelete;
      Pool.Renumber := FRenumber;
      Pool.DeletePerm := FDeletePerm;
      Pool.Thread := Self;
      SetLength(Pool.Slots, Length(FFiles));
      { The per-file completion reports funnel through the service thread's
        synchronized Progress, serialized by the pool lock. }
      Pool.OnProgress := @Progress;
      Pool.Run(ThreadCount);
      for i := 0 to High(FFiles) do
      begin
        if Pool.Slots[i].Written then
          Inc(FResult.Processed);
        if (Pool.Slots[i].ErrorMsg <> '') and (FResult.ErrorMsg = '') then
        begin
          FResult.Success := False;
          FResult.ErrorMsg := Pool.Slots[i].ErrorMsg;
        end;
      end;
      if Terminated then
      begin
        FResult.ErrorMsg := 'Cancelled';
        FResult.Success := False;
      end;
    finally
      Pool.Free;
    end;
  end;
  Progress(100, Format('Complete: %d files processed', [FResult.Processed]));
end;

{ ============================================================================
  TServiceThread – Base class
  ============================================================================ }

{ TServiceThread.Create

  Creates the thread suspended so the caller can set additional properties
  before calling Start.  The thread frees itself when Execute returns. }
constructor TServiceThread.Create(AOnProgress: TServiceProgressEvent);
begin
  inherited Create(True);  { Start suspended — caller must call Start }
  FreeOnTerminate := True; { auto-free after Execute finishes }
  FOnProgress := AOnProgress;
end;

{ TServiceThread.Progress

  Thread-safe progress dispatch.  Stores the values in fields owned by the
  thread object, then hands SyncProgress to the main thread with a BLOCKING
  Synchronize call.

  Synchronize (not Queue) is deliberate:
  - The thread object has FreeOnTerminate=True, so with Queue the main
    thread could still find a queued SyncProgress after the worker freed
    itself (use-after-free, crashed with SIGSEGV in SyncProgress).
  - FPC's CheckSynchronize RE-RAISES exceptions raised by queued methods on
    the MAIN thread (classes.inc "for Queue entries we dispose the entry
    and raise the exception"), so a failing progress callback escaped the
    event loop and killed the app ("Range check error" + crash).  With
    Synchronize the exception is passed back to the worker and re-raised
    inside Execute, where the per-file try/except records it as a file
    error instead of taking down the GUI.
  - The per-entry progress flood can queue thousands of entries; a
    synchronous update keeps the queue bounded and the UI fresh.

  Skipped entirely when no callback is assigned. }
procedure TServiceThread.Progress(APercent: integer; const AMsg: string);
begin
  FPendingPct := APercent;
  FPendingMsg := AMsg;
  if Assigned(FOnProgress) then
    Synchronize(@SyncProgress);
end;

{ TServiceThread.SyncProgress

  Runs on the MAIN thread (via Synchronize — the worker blocks until this
  returns, so the thread object is guaranteed alive).  Reads the latest
  pending values and fires the callback.  The nil-guard is re-checked
  because the callback could have been detached between the Progress call
  and this execution. }
procedure TServiceThread.SyncProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FPendingPct, FPendingMsg);
end;

{ ============================================================================
  TConvertThread
  ============================================================================ }

{ TConvertThread.Create

  Copies the file list, directory, and options into thread-owned fields.
  The actual work is deferred to Execute. }
constructor TConvertThread.Create(const AFiles: TStringArray;
  const ADir: string; const AOptions: TConvertOptions;
  AOnProgress: TServiceProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FOptions := AOptions;
end;

{ TConvertThread.Execute

  Delegates entirely to the static TConvertService.Convert method, passing
  @Progress as the progress callback.  The result is stored in FResult for
  the OnTerminate handler to read. }
procedure TConvertThread.Execute;
begin
  FResult := TConvertService.Convert(FFiles, FDir, FOptions, @Progress);
end;

{ ============================================================================
  TCbrConvertThread
  ============================================================================ }

constructor TCbrConvertThread.Create(const AFiles: TStringArray;
  const ADir: string; const AOptions: TCbrConvertOptions;
  AOnProgress: TServiceProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FOptions := AOptions;
end;

procedure TCbrConvertThread.Execute;
begin
  FResult := TConvertCbrService.Convert(FFiles, FDir, FOptions, @Progress);
end;

{ ============================================================================
  TMergeThread
  ============================================================================ }

{ TMergeThread.Create

  Copies merge parameters into thread-owned fields. }
constructor TMergeThread.Create(const AFiles: TStringArray; const ADir: string;
  const AOptions: TMergeOptions; AOnProgress: TServiceProgressEvent;
  AThreads: integer);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FOptions := AOptions;
  FThreads := AThreads;
end;

{ TMergeThread.Execute

  Delegates to TMergeService.Merge.  Progress is reported through the
  inherited Progress mechanism. }
procedure TMergeThread.Execute;
begin
  FResult := TMergeService.Merge(FFiles, FDir, FOptions, @Progress, FThreads);
end;

{ ============================================================================
  TValidateThread
  ============================================================================ }

{ TValidateThread.Create

  Copies the file list and directory.  Validation does not have extra
  options beyond the file list. }
constructor TValidateThread.Create(const AFiles: TStringArray;
  const ADir: string; AThreads: integer; AOnProgress: TServiceProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FThreads := AThreads;
end;

procedure TValidateThread.Execute;
begin
  FResult := TValidateService.ValidateDeep(FFiles, FDir, @Progress, FThreads);
end;

{ ============================================================================
  TComicInfoRemoveThread
  ============================================================================ }

{ TComicInfoRemoveThread.Create

  Copies the file list, directory, and backup flag. }
constructor TComicInfoRemoveThread.Create(const AFiles: TStringArray;
  const ADir: string; ABackup: boolean; AOnProgress: TServiceProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FBackup := ABackup;
end;

{ TComicInfoRemoveThread.Execute

  Delegates to TComicInfoService.Remove.  Progress is reported through
  @Progress. }
procedure TComicInfoRemoveThread.Execute;
begin
  FResult := TComicInfoService.Remove(FFiles, FDir, FBackup, @Progress);
end;

end.
