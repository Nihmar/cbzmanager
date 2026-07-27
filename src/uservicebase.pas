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
  if FindFirst(Dir + '*.cbz', faAnyFile, SearchRec) = 0 then
  begin
    repeat
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := SearchRec.Name;                 // bare filename only
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);                                     // release OS search handle
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
    { Cannot back up — leave .new for manual recovery, abort. }
    Exit;
  end;

  { Step 4: move .new → original }
  Result := RenameFile(NewFile, AFilePath);
  if not Result then
  begin
    { Rollback: restore original from _OLD, leave .new as recovery file. }
    RenameFile(OldFile, AFilePath);
  end;
end;

end.
