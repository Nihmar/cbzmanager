unit uservicebase;

{ ============================================================================
  uservicebase – Shared service-layer types, callbacks, and I/O utilities.

  This unit defines:
    - BACKUP_SUFFIX: the suffix used for _OLD.cbz backup files.
    - TServiceProgressEvent / TServiceProgressProc: progress-reporting callback types.
    - BackupFile:      renames a file to a _OLD.cbz backup.
    - CollectCBZFiles: collects *.cbz filenames from a directory.
    - ReplaceCBZ:      atomically replaces a CBZ file with new entries,
                       preserving the original as a backup.

  These routines have no GUI dependencies and are safe to call from
  background threads.
  ============================================================================
}
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uzipcore;

const
  { Suffix that identifies a backup copy of a CBZ.  A file "manga.cbz" is
    backed up as "manga_OLD.cbz".  Single source of truth for the backup
    naming convention used by BackupFile and ReplaceCBZ. }
  BACKUP_SUFFIX = '_OLD.cbz';

  { File extension identifying a comic archive.  Single source of truth for
    the ".cbz" suffix used when enumerating and matching archives. }
  CBZ_EXT = '.cbz';

  { File extension identifying a RAR comic archive (read via libarchive).
    CBR files are read-only in the preview and must be converted to CBZ
    before editing. }
  CBR_EXT = '.cbr';

  { Automatic worker-pool caps.  Every worker holds its working set in RAM:
    convert-webp keeps one full-resolution image per worker, cbr-to-cbz a
    whole decompressed archive per worker — hence the lower CBR cap. }
  MAX_WEBP_CONVERT_THREADS = 8;
  MAX_CBR_CONVERT_THREADS = 4;

type
  { ------------------------------------------------------------------------
    TServiceProgressEvent – Method-pointer callback for progress reporting.

    Used by services that run on the main thread.  The callback receives a
    percentage (0–100) and a human-readable description of the current step.
    ------------------------------------------------------------------------ }
  TServiceProgressEvent = procedure(APercent: integer; const AMsg: string) of object;

  { ------------------------------------------------------------------------
    TServiceProgressProc – Plain procedure callback for progress reporting.

    Same semantics as TServiceProgressEvent but as a bare procedure pointer — useful
    when the callback does not belong to an object instance (e.g. a background
    thread wrapper passes @Progress to a static service method).
    ------------------------------------------------------------------------ }
  TServiceProgressProc = procedure(APercent: integer; const AMsg: string);

  { ------------------------------------------------------------------------
    TFileProgress – Translates within-file progress (0–100) into global
    progress across a whole batch of files, so the progress bar keeps
    advancing while a single large archive is processed.

    Usage: for file i of N, create one instance with FIndex := i,
    FTotal := N, FInner := <user callback> and pass @Translate to the
    per-entry conversion function.
    ------------------------------------------------------------------------ }
  TFileProgress = class
  private
    FIndex: integer;
    FTotal: integer;
    FInner: TServiceProgressEvent;
  public
    constructor Create(AIndex, ATotal: integer; AInner: TServiceProgressEvent);
    { TServiceProgressEvent-compatible: forwards the message unchanged with
      GlobalFilePercent(FIndex, FTotal, APercent) as the percentage. }
    procedure Translate(APercent: integer; const AMsg: string);
  end;

  { ------------------------------------------------------------------------
    TLockedProgress – Serializes a progress callback through a pool lock.

    Pool workers report progress concurrently (per entry or per file), so
    the underlying callback must never be entered twice at once — it may
    block (e.g. TServiceThread.Progress uses a blocking Synchronize).
    Create one shared instance per pool and pass @Translate as the
    callback.
    ------------------------------------------------------------------------ }
  TLockedProgress = class
    Lock: PRTLCriticalSection;
    Inner: TServiceProgressEvent;
    procedure Translate(APercent: integer; const AMsg: string);
  end;

{ ------------------------------------------------------------------------
  GlobalFilePercent – Fold a within-file percentage into a global one.

  (AFileIndex * 100 + AWithinFile) div AFileTotal gives 0–100 across the
  whole batch: file 0 of 4 at 50% → 12, file 3 of 4 at 100% → 100.
  Guarded: AFileTotal <= 0 yields 0 (no files → nothing to show).
  ------------------------------------------------------------------------ }
function GlobalFilePercent(AFileIndex, AFileTotal, AWithinFile: integer): integer;

{ ------------------------------------------------------------------------
  OnlineCpuCount – Number of online CPUs for automatic worker-pool sizes.

  TThread.ProcessorCount can report 1 even on many-core machines (FPC
  relies on sched_getaffinity in some environments), so on Linux it falls
  back to counting /proc/cpuinfo "processor" lines.  Always >= 1.
  ------------------------------------------------------------------------ }
function OnlineCpuCount: integer;

{ ------------------------------------------------------------------------
  CBZFullPath – Join a directory and a bare filename into a full path.

  Centralises the "IncludeTrailingPathDelimiter(ADir) + AFileName" idiom
  shared by every batch service.
  ------------------------------------------------------------------------ }
function CBZFullPath(const ADir, AFileName: string): string;

{ ------------------------------------------------------------------------
  ReportServiceStart – Emit the initial "AVerb 0/N files" progress message.

  No-op when AOnProgress is nil or ATotal is zero.
  ------------------------------------------------------------------------ }
procedure ReportServiceStart(AOnProgress: TServiceProgressEvent;
  const AVerb: string; ATotal: integer);

{ ------------------------------------------------------------------------
  ReportServiceProgress – Emit a per-file "AVerb AFileName (i/N)" message.

  APercent is computed as (AIndex * 100) div ATotal.  AIndex is 0-based;
  the message shows AIndex + 1.  No-op when AOnProgress is nil or ATotal
  is zero.
  ------------------------------------------------------------------------ }
procedure ReportServiceProgress(AOnProgress: TServiceProgressEvent;
  const AVerb, AFileName: string; AIndex, ATotal: integer);

{ ------------------------------------------------------------------------
  BackupFile – Rename AFilePath to a _OLD.cbz backup.

  Constructs the backup name by replacing the extension with "_OLD.cbz"
  (e.g. "manga.cbz" → "manga_OLD.cbz").  If a previous _OLD.cbz already
  exists it is silently deleted before the rename.

  @param  AFilePath Full path to the .cbz file to back up.
  @return True if the rename succeeded, False otherwise (e.g. file locked).
  ------------------------------------------------------------------------ }
function BackupFile(const AFilePath: string): boolean;

{ ------------------------------------------------------------------------
  CollectCBZFiles – List *.cbz filenames in a directory (non-recursive).

  Uses FindFirst/FindNext to enumerate files matching the "*.cbz" pattern.
  Only bare filenames (not full paths) are returned.

  @param  ADir Directory to search.
  @return Array of matching filenames, or an empty array if none found.
  ------------------------------------------------------------------------ }
function CollectCBZFiles(const ADir: string): TStringArray;

{ ------------------------------------------------------------------------
  CollectCBRFiles – List *.cbr filenames in a directory (non-recursive).

  Same semantics as CollectCBZFiles (case-insensitive extension match),
  for the RAR archive conversion operation.
  ------------------------------------------------------------------------ }
function CollectCBRFiles(const ADir: string): TStringArray;

{ ------------------------------------------------------------------------
  ReplaceCBZ – Atomically replace a CBZ file with new in-memory entries.

  The replacement is performed as a four-step sequence designed to be as
  safe as possible against partial failures:

    1. Write the new entries to a temporary ".new" file.
       If this step fails the original file is untouched.
    2. Delete any existing "_OLD.cbz" backup.
    3. Rename the original → "_OLD.cbz".
       If this fails the ".new" file is left for manual recovery.
    4. Rename the ".new" file → original name.
       If this fails the original is restored from the "_OLD" backup.

  @param  AFilePath   Full path to the target .cbz file.
  @param  ANewEntries Array of TZipEntry records to write.
  @return True if the replacement completed successfully.
  ------------------------------------------------------------------------ }
function ReplaceCBZ(const AFilePath: string;
  const ANewEntries: TZipEntries): boolean;

implementation

{ ----------------------------------------------------------------------------
  CBZFullPath
  ---------------------------------------------------------------------------- }
function CBZFullPath(const ADir, AFileName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ADir) + AFileName;
end;

{ ----------------------------------------------------------------------------
  ReportServiceStart
  ---------------------------------------------------------------------------- }
procedure ReportServiceStart(AOnProgress: TServiceProgressEvent;
  const AVerb: string; ATotal: integer);
begin
  if Assigned(AOnProgress) and (ATotal > 0) then
    AOnProgress(0, Format('%s 0/%d files', [AVerb, ATotal]));
end;

{ ----------------------------------------------------------------------------
  ReportServiceProgress
  ---------------------------------------------------------------------------- }
procedure ReportServiceProgress(AOnProgress: TServiceProgressEvent;
  const AVerb, AFileName: string; AIndex, ATotal: integer);
begin
  if Assigned(AOnProgress) and (ATotal > 0) then
    AOnProgress((AIndex * 100) div ATotal,
      Format('%s %s (%d/%d)', [AVerb, AFileName, AIndex + 1, ATotal]));
end;

{ ----------------------------------------------------------------------------
  GlobalFilePercent / TFileProgress
  ---------------------------------------------------------------------------- }
function GlobalFilePercent(AFileIndex, AFileTotal, AWithinFile: integer): integer;
begin
  if AFileTotal <= 0 then
    Exit(0);
  Result := (AFileIndex * 100 + AWithinFile) div AFileTotal;
end;

{ ----------------------------------------------------------------------------
  TLockedProgress
  ---------------------------------------------------------------------------- }
procedure TLockedProgress.Translate(APercent: integer; const AMsg: string);
begin
  EnterCriticalSection(Lock^);
  try
    if Assigned(Inner) then Inner(APercent, AMsg);
  finally
    LeaveCriticalSection(Lock^);
  end;
end;

{ ----------------------------------------------------------------------------
  OnlineCpuCount
  ---------------------------------------------------------------------------- }
function OnlineCpuCount: integer;
var
  T: TextFile;
  Line: string;
begin
  Result := TThread.ProcessorCount;
  if Result > 1 then Exit;
  Result := 0;
  {$IFDEF LINUX}
  if FileExists('/proc/cpuinfo') then
  begin
    try
      AssignFile(T, '/proc/cpuinfo');
      Reset(T);
      while not Eof(T) do
      begin
        ReadLn(T, Line);
        if Pos('processor', Line) = 1 then Inc(Result);
      end;
      CloseFile(T);
    except
      Result := 0;
    end;
  end;
  {$ENDIF}
  if Result < 1 then Result := 1;
end;

constructor TFileProgress.Create(AIndex, ATotal: integer;
  AInner: TServiceProgressEvent);
begin
  FIndex := AIndex;
  FTotal := ATotal;
  FInner := AInner;
end;

procedure TFileProgress.Translate(APercent: integer; const AMsg: string);
begin
  if Assigned(FInner) then
    FInner(GlobalFilePercent(FIndex, FTotal, APercent), AMsg);
end;

{ ----------------------------------------------------------------------------
  BackupFile
  ---------------------------------------------------------------------------- }
function BackupFile(const AFilePath: string): boolean;
var
  OldFile: string;
begin
  // Build the backup name: strip extension, append the backup suffix.
  OldFile := ChangeFileExt(AFilePath, '') + BACKUP_SUFFIX;
  // Remove any stale backup first — DeleteFile returns False if the file
  // doesn't exist, which is harmless.
  if FileExists(OldFile) then
    DeleteFile(OldFile);
  Result := RenameFile(AFilePath, OldFile);
end;

{ ----------------------------------------------------------------------------
  CollectCBZFiles
  ---------------------------------------------------------------------------- }
function CollectCBZFiles(const ADir: string): TStringArray;
var
  SearchRec: TSearchRec;
  Dir: string;
begin
  Result := nil;                                              // empty array by default
  Dir := IncludeTrailingPathDelimiter(ADir);                  // ensure "dir/"
  { Enumerate every file and match the extension in code.  FindFirst mask
    matching is case-sensitive on Unix, so a "*.cbz" mask would miss files
    named "*.CBZ" on Linux; a SameText check keeps Windows and Linux
    behaviour identical. }
  if FindFirst(Dir + AllFilesMask, faAnyFile, SearchRec) = 0 then
  begin
    repeat
      if SameText(ExtractFileExt(SearchRec.Name), CBZ_EXT) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := SearchRec.Name;               // bare filename only
      end;
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);                                     // release OS search handle
  end;
end;

function CollectCBRFiles(const ADir: string): TStringArray;
var
  SearchRec: TSearchRec;
  Dir: string;
begin
  Result := nil;
  Dir := IncludeTrailingPathDelimiter(ADir);
  { Same case-insensitive matching as CollectCBZFiles (Unix FindFirst masks
    are case-sensitive, so "*.cbr" would miss "*.CBR"). }
  if FindFirst(Dir + AllFilesMask, faAnyFile, SearchRec) = 0 then
  begin
    repeat
      if SameText(ExtractFileExt(SearchRec.Name), CBR_EXT) then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := SearchRec.Name;
      end;
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);
  end;
end;

{ ----------------------------------------------------------------------------
  ReplaceCBZ

  Performs an atomic-ish replacement of a CBZ file.  See the interface-level
  doc comment for the detailed four-step algorithm.
  ---------------------------------------------------------------------------- }
function ReplaceCBZ(const AFilePath: string;
  const ANewEntries: TZipEntries): boolean;
var
  OldFile, NewFile: string;
begin
  // Compute derived filenames.
  OldFile := ChangeFileExt(AFilePath, '') + BACKUP_SUFFIX;     // backup destination
  NewFile := AFilePath + '.new';                               // temporary new file

  { Step 1: write new CBZ to a temp file. If this fails, original is intact. }
  try
    WriteZipFromEntriesDeflated(NewFile, ANewEntries);
  except
    DeleteFile(NewFile);  // clean up partial/damaged temp file
    Result := False;
    Exit;
  end;

  { Step 2: remove any existing _OLD backup so RenameFile can succeed. }
  if FileExists(OldFile) then
    DeleteFile(OldFile);

  { Step 3: move original → _OLD }
  Result := RenameFile(AFilePath, OldFile);
  if not Result then
  begin
    { Cannot back up — clean up the temp file and abort. }
    DeleteFile(NewFile);
    Result := False;
    Exit;
  end;

  { Step 4: move .new → original }
  Result := RenameFile(NewFile, AFilePath);
  if not Result then
  begin
    { Rollback: restore original from _OLD and clean up temp files. }
    RenameFile(OldFile, AFilePath);
    DeleteFile(NewFile);
    Result := False;
  end;
end;

end.
