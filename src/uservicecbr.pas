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
  Math, uservicepool;

type
  { Shared state of a CBR conversion pool: the file list, the result slots
    and the progress state.  The claim counter lives in TIndexPool; each
    worker writes only Result[Idx] with the Idx it claimed, so slot writes
    need no lock.  Unlike the WebP pool there is no Error field: CBR
    failures are per-file and land in the result entry, never aborting the
    batch. }
  TCbrConvertPoolState = class(TIndexPool)
  public
    Files: TStringArray;
    Dir: string;
    Options: TCbrConvertOptions;
    Results: TConvertResults;
    Completed: integer;        { finished files (under Lock) }
    OnProgress: TServiceProgressEvent;
    { Shared translator for within-file progress (may be nil). }
    Progress: TLockedProgress;
    function CreateWorker: TIndexPoolWorker; override;
  end;

  { Pool worker: converts the claimed file with the untouched per-file
    logic, then reports progress — serialized by the pool lock, monotonic
    via the completed counter. }
  TCbrConvertWorker = class(TIndexPoolWorker)
  private
    FPool: TCbrConvertPoolState;
    FProgress: TLockedProgress;
  protected
    procedure ProcessIndex(Idx: integer); override;
  public
    constructor Create(APool: TCbrConvertPoolState;
      AProgress: TLockedProgress);
  end;

function TCbrConvertPoolState.CreateWorker: TIndexPoolWorker;
begin
  Result := TCbrConvertWorker.Create(Self, Progress);
end;

constructor TCbrConvertWorker.Create(APool: TCbrConvertPoolState;
  AProgress: TLockedProgress);
begin
  inherited Create(APool);
  FPool := APool;
  FProgress := AProgress;
end;

{ TCbrConvertWorker.ProcessIndex

  Converts one claimed file (the per-file logic never raises — errors land
  in the result entry), then reports progress per finished file.  The
  percentage derives from the completed counter, so the sequence is
  monotonic even though files finish out of order. }
procedure TCbrConvertWorker.ProcessIndex(Idx: integer);
begin
  if FProgress <> nil then
    FPool.Results[Idx] := TConvertCbrService.ConvertOne(Idx, FPool.Files,
      FPool.Dir, FPool.Options, @FProgress.Translate)
  else
    FPool.Results[Idx] := TConvertCbrService.ConvertOne(Idx, FPool.Files,
      FPool.Dir, FPool.Options, FPool.OnProgress);

  FPool.LockPool;
  try
    Inc(FPool.Completed);
    if Assigned(FPool.OnProgress) then
      FPool.OnProgress((FPool.Completed * 100) div FPool.Total,
        Format('Converting CBR %s (%d/%d)', [FPool.Files[Idx],
          FPool.Completed, FPool.Total]));
  finally
    FPool.UnlockPool;
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
    Pool := TCbrConvertPoolState.Create(Total);
    Locked := TLockedProgress.Create;
    try
      Pool.Files := AFiles;
      Pool.Dir := ADir;
      Pool.Options := Options;
      Pool.Results := Result;
      Pool.OnProgress := AOnProgress;
      { Fold within-file progress through the pool lock, so the service
        callback is never entered concurrently. }
      Locked.Lock := Pool.Lock;
      Locked.Inner := AOnProgress;
      Pool.Progress := Locked;
      Pool.Run(ThreadCount);
    finally
      Pool.Free;
      Locked.Free;
    end;
  end;

  if Assigned(AOnProgress) then
    AOnProgress(100, 'Complete');
end;

end.
