{ ============================================================================
  uservicecbr – CBR-to-CBZ conversion service.

  Batch-converts RAR comic archives (.cbr) into CBZ files, entirely in RAM:
  the RAR entries are decompressed into memory via libarchive (uarchive.pas),
  filtered and renumbered by ConvertCbrToCbz (uzipeditor.pas), and written
  with WriteZipFromEntriesDeflated.  The source .cbr is never modified
  unless DeleteSource is set (and even then only after a successful write).

  Defaults: files whose .cbz target already exists are skipped (no silent
  overwrite); renumbering to page_NNNN.* is always applied (house policy).
  ============================================================================ }
unit uservicecbr;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uzipcore, uZipEditor, uservicebase, userviceconvert;

type
  { ------------------------------------------------------------------------
    TCbrConvertOptions – Settings controlling the CBR→CBZ conversion.

    @field SkipExisting  When True, files whose .cbz target already exists
                         are left alone (default, avoids silent overwrites).
    @field DeleteSource  When True, the .cbr source is deleted after a
                         successful conversion (default: kept).
    @field Threads       Number of worker threads used to convert files in
                         parallel.  0 = automatic (CPU count, capped at 4 —
                         every worker holds a whole decompressed archive in
                         RAM); 1 = sequential.
    ------------------------------------------------------------------------ }
  TCbrConvertOptions = record
    SkipExisting: boolean;
    DeleteSource: boolean;
    Threads: integer;
  end;

  { ------------------------------------------------------------------------
    TConvertCbrService – Stateless service for batch CBR→CBZ conversion.

    Results reuse TConvertResults: PagesConverted carries the number of
    pages written to the new CBZ, OriginalSize/NewSize the source/target
    file sizes (so the shared results dialog works unchanged).
    ------------------------------------------------------------------------ }
  TConvertCbrService = class
  public
    { Batch-convert every file in AFiles (bare .cbr names) inside ADir.
      Per-file results: Success True when the CBZ was written (or the file
      was skipped because its target exists); failures carry ErrorMsg. }
    class function Convert(const AFiles: TStringArray; const ADir: string;
      const Options: TCbrConvertOptions;
      AOnProgress: TServiceProgressEvent = nil): TConvertResults;
  private
    { Converts a single file (AIndex into AFiles) and returns its result
      entry.  AOnProgress receives within-file progress (folded through
      TFileProgress).  Never raises: errors are captured in the result. }
    class function ConvertOne(AIndex: integer; const AFiles: TStringArray;
      const ADir: string; const Options: TCbrConvertOptions;
      AOnProgress: TServiceProgressEvent): TConvertEntry;
  end;

implementation

uses
  Math;

type
  { Shared state of a CBR conversion pool: the file list, the result slots
    and the claim counter.  Mutable fields are guarded by Lock; each worker
    writes only Result[Idx] with the Idx it claimed, so slot writes need no
    lock.  Unlike the WebP pool there is no Error field: CBR failures are
    per-file and land in the result entry, never aborting the batch. }
  TCbrConvertPoolState = class
    Lock: TRTLCriticalSection;
    Files: TStringArray;
    Dir: string;
    Options: TCbrConvertOptions;
    Results: TConvertResults;
    Next: integer;             { next file index (under Lock) }
    Completed: integer;        { finished files (under Lock) }
    Total: integer;
    OnProgress: TServiceProgressEvent;
    constructor Create;
    destructor Destroy; override;
  end;

  { Pool worker: claims the next file index under the lock, converts that
    file with the untouched per-file logic, then reports progress —
    serialized, monotonic via the completed counter. }
  TCbrConvertWorker = class(TThread)
  private
    FPool: TCbrConvertPoolState;
    FProgress: TLockedProgress;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TCbrConvertPoolState;
      AProgress: TLockedProgress);
  end;

function GetFileSize(const APath: string): int64;
var
  SR: TSearchRec;
begin
  if FindFirst(APath, faAnyFile, SR) = 0 then
  begin
    Result := SR.Size;
    FindClose(SR);
  end
  else
    Result := 0;
end;

constructor TCbrConvertPoolState.Create;
begin
  inherited Create;
  InitCriticalSection(Lock);
end;

destructor TCbrConvertPoolState.Destroy;
begin
  DoneCriticalSection(Lock);
  inherited Destroy;
end;

constructor TCbrConvertWorker.Create(APool: TCbrConvertPoolState;
  AProgress: TLockedProgress);
begin
  { Created suspended: the caller Start()s every worker before joining. }
  inherited Create(True);
  FPool := APool;
  FProgress := AProgress;
end;

{ TCbrConvertWorker.Execute

  Claims the next file index under the pool lock, converts that file (the
  per-file logic never raises — errors land in the result entry), then
  reports progress per finished file.  The percentage derives from the
  completed counter, so the sequence is monotonic even though files finish
  out of order. }
procedure TCbrConvertWorker.Execute;
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

    FPool.Results[Idx] := TConvertCbrService.ConvertOne(Idx, FPool.Files,
      FPool.Dir, FPool.Options, @FProgress.Translate);

    EnterCriticalSection(FPool.Lock);
    try
      Inc(FPool.Completed);
      if Assigned(FPool.OnProgress) then
        FPool.OnProgress((FPool.Completed * 100) div FPool.Total,
          Format('Converting CBR %s (%d/%d)', [FPool.Files[Idx],
            FPool.Completed, FPool.Total]));
    finally
      LeaveCriticalSection(FPool.Lock);
    end;
  end;
end;

class function TConvertCbrService.ConvertOne(AIndex: integer;
  const AFiles: TStringArray; const ADir: string;
  const Options: TCbrConvertOptions;
  AOnProgress: TServiceProgressEvent): TConvertEntry;
var
  FullPath, TargetPath: string;
  Entries: TZipEntries;
  Translator: TFileProgress;
begin
  Result.FileName := AFiles[AIndex];
  FullPath := CBZFullPath(ADir, AFiles[AIndex]);
  TargetPath := ChangeFileExt(FullPath, CBZ_EXT);
  Result.OriginalSize := GetFileSize(FullPath);
  try
    if Options.SkipExisting and FileExists(TargetPath) then
    begin
      Result.Success := True;
      Result.PagesConverted := 0;
      Result.NewSize := Result.OriginalSize;
      Result.ErrorMsg := 'Target exists — skipped';
      Exit;
    end;

    { Folds CollectCbrEntries' within-file percentages into a smooth
      global 0–100 sweep across the whole batch. }
    Translator := TFileProgress.Create(AIndex, Length(AFiles), AOnProgress);
    try
      Entries := ConvertCbrToCbz(FullPath, @Translator.Translate);
    finally
      Translator.Free;
    end;
    try
      if Length(Entries) = 0 then
        raise Exception.Create('No images found');
      WriteZipFromEntriesDeflated(TargetPath, Entries);
      Result.Success := True;
      Result.PagesConverted := Length(Entries);
      Result.NewSize := GetFileSize(TargetPath);
      { Delete the source only after the target has been written. }
      if Options.DeleteSource and not DeleteFile(FullPath) then
        raise Exception.CreateFmt('Converted, but failed to delete %s',
          [AFiles[AIndex]]);
    finally
      FreeZipEntries(Entries);
    end;
  except
    on E: Exception do
    begin
      Result.Success := False;
      Result.PagesConverted := 0;
      Result.NewSize := Result.OriginalSize;
      Result.ErrorMsg := E.Message;
    end;
  end;
end;

class function TConvertCbrService.Convert(const AFiles: TStringArray;
  const ADir: string; const Options: TCbrConvertOptions;
  AOnProgress: TServiceProgressEvent = nil): TConvertResults;
var
  i, Total, ThreadCount: integer;
  Pool: TCbrConvertPoolState;
  Locked: TLockedProgress;
  Workers: array of TCbrConvertWorker;
  Started: boolean;
begin
  Total := Length(AFiles);
  Result := nil;
  SetLength(Result, Total);
  ReportServiceStart(AOnProgress, 'Converting CBR', Total);

  ThreadCount := Options.Threads;
  if ThreadCount <= 0 then
    ThreadCount := Min(OnlineCpuCount, MAX_CBR_CONVERT_THREADS);
  ThreadCount := Min(ThreadCount, Total);

  if ThreadCount <= 1 then
  begin
    { Sequential: exactly the historical behaviour (per-file message before
      each file, direct callback, no thread creation). }
    for i := 0 to High(AFiles) do
    begin
      ReportServiceProgress(AOnProgress, 'Converting CBR', AFiles[i], i, Total);
      Result[i] := ConvertOne(i, AFiles, ADir, Options, AOnProgress);
    end;
  end
  else
  begin
    Pool := TCbrConvertPoolState.Create;
    Locked := TLockedProgress.Create;
    Workers := nil;
    Started := False;
    try
      Pool.Files := AFiles;
      Pool.Dir := ADir;
      Pool.Options := Options;
      Pool.Results := Result;
      Pool.Total := Total;
      Pool.OnProgress := AOnProgress;
      Locked.Lock := @Pool.Lock;
      Locked.Inner := AOnProgress;

      SetLength(Workers, ThreadCount);
      for i := 0 to ThreadCount - 1 do
        Workers[i] := TCbrConvertWorker.Create(Pool, Locked);
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
