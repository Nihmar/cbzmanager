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
  Classes, SysUtils,
  uZipEditor, uservicebase, userviceconvert, uservicemerge, uservicevalidate,
  uservicecomicinfo;

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
    FOnProgress: TProgressEvent;     // user-supplied callback (may be nil)
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
    constructor Create(AOnProgress: TProgressEvent);
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
      const AOptions: TConvertOptions; AOnProgress: TProgressEvent);
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
    FResult: TMergeResult;           // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles      Array of chapter .cbz filenames.
      @param ADir        Directory containing the files.
      @param AOptions    Merge configuration.
      @param AOnProgress Optional progress callback. }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const AOptions: TMergeOptions; AOnProgress: TProgressEvent);
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
    FResult: TValidationResults;     // outcome populated by Execute
  protected
    procedure Execute; override;
  public
    { @param AFiles      Array of .cbz filenames to validate.
      @param ADir        Directory containing the files.
      @param AOnProgress Optional progress callback. }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      AOnProgress: TProgressEvent);
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
      ABackup: boolean; AOnProgress: TProgressEvent);
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
    FDeletePerm: boolean;            // if True, write directly; if False, use ReplaceCBZ (with backup)
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
      @param AOnProgress     Optional progress callback. }
    constructor Create(const AFiles: TStringArray; const ADir: string;
      const APagesToDelete: array of boolean;
      ARenumber, ADeletePerm: boolean;
      AOnProgress: TProgressEvent);
    property Result: TDeletePagesResult read FResult;
  end;

implementation

{ ============================================================================
  TDeletePagesThread
  ============================================================================ }

{ TDeletePagesThread.Create

  Copies the variadic boolean array into a dynamic array owned by the thread.
  All other parameters are simple value copies — safe because strings use
  reference counting and the dynamic array is duplicated element-by-element. }
constructor TDeletePagesThread.Create(const AFiles: TStringArray;
  const ADir: string; const APagesToDelete: array of boolean;
  ARenumber, ADeletePerm: boolean; AOnProgress: TProgressEvent);
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
  i: integer;
  FullPath: string;
  Entries: TZipEntries;
begin
  FResult.Success := True;
  FResult.Processed := 0;
  FResult.ErrorMsg := '';
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
    // FilterPagesFromCBZ reads the archive, drops marked pages,
    // optionally renumbers, and returns the surviving entries.
    Entries := FilterPagesFromCBZ(FullPath, FPagesToDelete, FRenumber);
    try
      if Length(Entries) > 0 then
      begin
        // Write path: direct overwrite or safe backup-then-replace.
        if FDeletePerm then
          WriteZipFromEntriesDeflated(FullPath, Entries)
        else
          ReplaceCBZ(FullPath, Entries);
        Inc(FResult.Processed);
      end;
    finally
      FreeZipEntries(Entries);  // always free the temporary entry list
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
constructor TServiceThread.Create(AOnProgress: TProgressEvent);
begin
  inherited Create(True);  { Start suspended — caller must call Start }
  FreeOnTerminate := True; { auto-free after Execute finishes }
  FOnProgress := AOnProgress;
end;

{ TServiceThread.Progress

  Thread-safe progress dispatch.  Stores the values in fields owned by the
  thread object, then enqueues a call to SyncProgress on the main thread.
  Skipped entirely when no callback is assigned. }
procedure TServiceThread.Progress(APercent: integer; const AMsg: string);
begin
  FPendingPct := APercent;
  FPendingMsg := AMsg;
  if Assigned(FOnProgress) then
    TThread.Queue(nil, @SyncProgress);
end;

{ TServiceThread.SyncProgress

  Runs on the MAIN thread.  Reads the latest pending values and fires the
  callback.  The nil-guard is re-checked because the callback could have
  been detached between the Queue call and this execution. }
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
  AOnProgress: TProgressEvent);
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
  TMergeThread
  ============================================================================ }

{ TMergeThread.Create

  Copies merge parameters into thread-owned fields. }
constructor TMergeThread.Create(const AFiles: TStringArray;
  const ADir: string; const AOptions: TMergeOptions;
  AOnProgress: TProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
  FOptions := AOptions;
end;

{ TMergeThread.Execute

  Delegates to TMergeService.Merge.  Progress is reported through the
  inherited Progress mechanism. }
procedure TMergeThread.Execute;
begin
  FResult := TMergeService.Merge(FFiles, FDir, FOptions, @Progress);
end;

{ ============================================================================
  TValidateThread
  ============================================================================ }

{ TValidateThread.Create

  Copies the file list and directory.  Validation does not have extra
  options beyond the file list. }
constructor TValidateThread.Create(const AFiles: TStringArray;
  const ADir: string; AOnProgress: TProgressEvent);
begin
  inherited Create(AOnProgress);
  FFiles := AFiles;
  FDir := ADir;
end;

{ TValidateThread.Execute

  Delegates to TValidateService.ValidateDeep.  Note: the validation service
  does not currently report progress — the progress callback is not passed. }
procedure TValidateThread.Execute;
begin
  FResult := TValidateService.ValidateDeep(FFiles, FDir);
end;

{ ============================================================================
  TComicInfoRemoveThread
  ============================================================================ }

{ TComicInfoRemoveThread.Create

  Copies the file list, directory, and backup flag. }
constructor TComicInfoRemoveThread.Create(const AFiles: TStringArray;
  const ADir: string; ABackup: boolean; AOnProgress: TProgressEvent);
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
