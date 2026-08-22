{ ============================================================================
  uservicecomicinfo – ComicInfo.xml scanning and removal service.

  ComicInfo.xml is a metadata file commonly embedded inside CBZ archives
  (especially those created by comic management tools like ComicRack).
  This service provides two operations:

    - Scan   – Check which CBZ files contain a ComicInfo.xml entry.
    - Remove – Strip the ComicInfo.xml entry from CBZ files, optionally
               creating a backup before modification.

  Both operations are static class methods that report progress through a
  TServiceProgressEvent callback (may be nil).  Errors are captured per-file in
  the TComicInfoResults array rather than raising exceptions.
  ============================================================================ }
unit uservicecomicinfo;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uzipcore, uservicebase;

type
  { ------------------------------------------------------------------------
    TComicInfoEntry – Per-file result of a ComicInfo scan/remove operation.

    @field FileName     Name of the CBZ file that was processed.
    @field HasComicInfo True when ComicInfo.xml was found inside the archive.
    @field Removed      True when ComicInfo.xml was successfully removed
                        (always False after a Scan; set by Remove).
    @field ErrorMsg     Error message if the operation failed on this file;
                        empty string on success.
    ------------------------------------------------------------------------ }
  TComicInfoEntry = record
    FileName: string;
    HasComicInfo: boolean;
    Removed: boolean;
    ErrorMsg: string;
  end;

  { ------------------------------------------------------------------------
    TComicInfoResults – Dynamic array of per-file ComicInfo results.
    ------------------------------------------------------------------------ }
  TComicInfoResults = array of TComicInfoEntry;

  { ------------------------------------------------------------------------
    TComicInfoService – Stateless service for ComicInfo.xml operations.

    All methods are class methods; no instantiation is required.  Each
    method processes a list of CBZ filenames located in a single directory.
    ------------------------------------------------------------------------ }
  TComicInfoService = class
  public
    { ------------------------------------------------------------------------
      Scan – Determine which files contain a ComicInfo.xml entry.

      Opens each CBZ, reads the central directory, and checks whether any
      entry is named "ComicInfo.xml" (case-insensitive comparison).

      @param  AFiles Array of CBZ filenames (bare names, not full paths).
      @param  ADir   Directory containing the files.
      @return An array of TComicInfoEntry, one per input file, with the
              HasComicInfo and ErrorMsg fields populated.
      ------------------------------------------------------------------------ }
    class function Scan(const AFiles: TStringArray;
      const ADir: string): TComicInfoResults;

    { ------------------------------------------------------------------------
      Remove – Strip ComicInfo.xml from CBZ files.

      For each file that contains ComicInfo.xml, this method rebuilds the
      archive without that entry and writes it back.  Optionally backs up
      the original before overwriting.  Files are processed in parallel on
      a worker pool: AThreads selects the size (0 = automatic, CPU count
      capped at 4 — every worker holds a whole archive in RAM; 1 =
      sequential).

      @param  AFiles      Array of CBZ filenames to process.
      @param  ADir        Directory containing the files.
      @param  ABackup     If True, rename the original to *_OLD.cbz before
                          writing the modified version.
      @param  AOnProgress Optional progress callback (percentage + message).
      @param  AThreads    Worker-pool size (0 = automatic).
      @return An array of TComicInfoEntry with HasComicInfo and Removed
              fields reflecting the outcome for each file.
      ------------------------------------------------------------------------ }
    class function Remove(const AFiles: TStringArray; const ADir: string;
      ABackup: boolean; AOnProgress: TServiceProgressEvent = nil;
      AThreads: integer = 0): TComicInfoResults;
  private
    { Processes a single file (AIndex into AFiles) and returns its result
      entry.  Never raises: errors are captured in the result. }
    class function RemoveOne(AIndex: integer; const AFiles: TStringArray;
      const ADir: string; ABackup: boolean;
      AOnProgress: TServiceProgressEvent): TComicInfoEntry;
  end;

implementation

uses
  Math;

type
  { Shared state of a ComicInfo-removal pool: the file list, the result
    slots and the claim counter.  Mutable fields are guarded by Lock; each
    worker writes only Results[Idx] with the Idx it claimed, so slot
    writes need no lock.  Errors are per-file and land in the result
    entry, never aborting the batch. }
  TComicInfoPoolState = class
    Lock: TRTLCriticalSection;
    Files: TStringArray;
    Dir: string;
    Backup: boolean;
    Results: TComicInfoResults;
    Next: integer;             { next file index (under Lock) }
    Completed: integer;        { finished files (under Lock) }
    Total: integer;
    OnProgress: TServiceProgressEvent;
    constructor Create;
    destructor Destroy; override;
  end;

  { Pool worker: claims the next file index under the lock, removes
    ComicInfo.xml from that file, then reports progress — serialized,
    monotonic via the completed counter. }
  TComicInfoWorker = class(TThread)
  private
    FPool: TComicInfoPoolState;
    FProgress: TLockedProgress;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TComicInfoPoolState;
      AProgress: TLockedProgress);
  end;

constructor TComicInfoPoolState.Create;
begin
  inherited Create;
  InitCriticalSection(Lock);
end;

destructor TComicInfoPoolState.Destroy;
begin
  DoneCriticalSection(Lock);
  inherited Destroy;
end;

constructor TComicInfoWorker.Create(APool: TComicInfoPoolState;
  AProgress: TLockedProgress);
begin
  { Created suspended: the caller Start()s every worker before joining. }
  inherited Create(True);
  FPool := APool;
  FProgress := AProgress;
end;

{ TComicInfoWorker.Execute

  Claims the next file index under the pool lock, processes that file
  (the per-file logic never raises — errors land in the result entry),
  then reports progress per finished file.  The percentage derives from
  the completed counter, so the sequence is monotonic even though files
  finish out of order. }
procedure TComicInfoWorker.Execute;
var
  Idx: integer;
begin
  while True do
  begin
    EnterCriticalSection(FPool.Lock);
    try
      if FPool.Next >= Length(FPool.Files) then Exit;
      Idx := FPool.Next;
      Inc(FPool.Next);
    finally
      LeaveCriticalSection(FPool.Lock);
    end;

    FPool.Results[Idx] := TComicInfoService.RemoveOne(Idx, FPool.Files,
      FPool.Dir, FPool.Backup, @FProgress.Translate);

    EnterCriticalSection(FPool.Lock);
    try
      Inc(FPool.Completed);
      if Assigned(FPool.OnProgress) then
        FPool.OnProgress((FPool.Completed * 100) div FPool.Total,
          Format('Removing from %s (%d/%d)', [FPool.Files[Idx],
            FPool.Completed, FPool.Total]));
    finally
      LeaveCriticalSection(FPool.Lock);
    end;
  end;
end;

{ ----------------------------------------------------------------------------
  Scan
  ---------------------------------------------------------------------------- }
class function TComicInfoService.Scan(const AFiles: TStringArray;
  const ADir: string): TComicInfoResults;
var
  i: integer;
  FullPath: string;
  Entries: TZipEntries;
begin
  Result := nil;
  SetLength(Result, Length(AFiles));
  for i := 0 to High(AFiles) do
  begin
    Result[i].FileName := AFiles[i];
    Result[i].Removed := False;
    FullPath := CBZFullPath(ADir, AFiles[i]);
    try
      Entries := CollectZipEntries(FullPath);
      try
        Result[i].HasComicInfo := FindComicInfoIndex(Entries) >= 0;
      finally
        FreeZipEntries(Entries);
      end;
    except
      on E: Exception do
      begin
        Result[i].ErrorMsg := E.Message;
      end;
    end;
  end;
end;

{ ----------------------------------------------------------------------------
  RemoveOne

  The per-file body of Remove: collects the ZIP entries, checks for
  ComicInfo.xml and — if found — rebuilds the archive without it (the
  ComicInfo removal/compaction is delegated to StripComicInfo, uzipcore).
  Never raises: failures are captured in the result entry.
  ---------------------------------------------------------------------------- }
class function TComicInfoService.RemoveOne(AIndex: integer;
  const AFiles: TStringArray; const ADir: string; ABackup: boolean;
  AOnProgress: TServiceProgressEvent): TComicInfoEntry;
var
  FullPath: string;
  Entries: TZipEntries;
  Found: boolean;
begin
  Result.FileName := AFiles[AIndex];
  Result.Removed := False;
  FullPath := CBZFullPath(ADir, AFiles[AIndex]);
  try
    Entries := CollectZipEntries(FullPath);
    try
      { Check if ComicInfo.xml exists }
      Found := FindComicInfoIndex(Entries) >= 0;
      Result.HasComicInfo := Found;

      if not Found then Exit;

      { Drop ComicInfo.xml, compacting the surviving entries. }
      StripComicInfo(Entries);

      if not HasImageEntries(Entries) then
      begin
        { No image entries survive: the archive is a metadata-only (or
          otherwise non-image) collection, so writing it back would leave an
          empty or otherwise invalid CBZ while the result still reports
          removed.  Keep the original untouched and mark this file skipped so
          the corruption never happens silently. }
        Result.Removed := False;
        Result.ErrorMsg := 'No images to keep';
        Exit;
      end;

      { Backup original if requested }
      if ABackup then
        if not BackupFile(FullPath) then
          raise Exception.CreateFmt('Failed to create backup of %s',
            [FullPath]);

      { Write new CBZ without ComicInfo.xml }
      WriteZipFromEntriesDeflated(FullPath, Entries);

      Result.Removed := True;
    finally
      FreeZipEntries(Entries);
    end;
  except
    on E: Exception do
    begin
      Result.ErrorMsg := E.Message;
    end;
  end;
end;

{ ----------------------------------------------------------------------------
  Remove

  Processes the file list sequentially (AThreads <= 1) or on a worker
  pool; the per-file work is shared via RemoveOne, so the output is
  byte-identical for any thread count.
  ---------------------------------------------------------------------------- }
class function TComicInfoService.Remove(const AFiles: TStringArray;
  const ADir: string; ABackup: boolean;
  AOnProgress: TServiceProgressEvent; AThreads: integer): TComicInfoResults;
var
  i, Total, ThreadCount: integer;
  Pool: TComicInfoPoolState;
  Locked: TLockedProgress;
  Workers: array of TComicInfoWorker;
  Started: boolean;
begin
  Total := Length(AFiles);
  Result := nil;
  SetLength(Result, Total);
  ReportServiceStart(AOnProgress, 'Scanning', Total);

  ThreadCount := AThreads;
  if ThreadCount <= 0 then
    ThreadCount := Min(OnlineCpuCount, MAX_CBR_CONVERT_THREADS);
  ThreadCount := Min(ThreadCount, Total);

  if ThreadCount <= 1 then
  begin
    { Sequential: exactly the historical behaviour (per-file message before
      each file, direct callback, no thread creation). }
    for i := 0 to High(AFiles) do
    begin
      ReportServiceProgress(AOnProgress, 'Removing from', AFiles[i], i, Total);
      Result[i] := RemoveOne(i, AFiles, ADir, ABackup, AOnProgress);
    end;
  end
  else
  begin
    Pool := TComicInfoPoolState.Create;
    Locked := TLockedProgress.Create;
    Workers := nil;
    Started := False;
    try
      Pool.Files := AFiles;
      Pool.Dir := ADir;
      Pool.Backup := ABackup;
      Pool.Results := Result;
      Pool.Total := Total;
      Pool.OnProgress := AOnProgress;
      Locked.Lock := @Pool.Lock;
      Locked.Inner := AOnProgress;

      SetLength(Workers, ThreadCount);
      for i := 0 to ThreadCount - 1 do
        Workers[i] := TComicInfoWorker.Create(Pool, Locked);
      Started := True;
      for i := 0 to ThreadCount - 1 do
        Workers[i].Start;
    finally
      { Join and free the workers here — also covers a mid-spawn failure,
        where only the created (started) workers must be waited for. }
      if Started then
        for i := 0 to High(Workers) do
          Workers[i].WaitFor;
      for i := 0 to High(Workers) do
        if Workers[i] <> nil then
          Workers[i].Free;
      Pool.Free;
      Locked.Free;
    end;
  end;

  if Assigned(AOnProgress) then
    AOnProgress(100, 'Complete');
end;

end.
