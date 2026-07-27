{ ============================================================================
  uservicecomicinfo – ComicInfo.xml scanning and removal service.

  ComicInfo.xml is a metadata file commonly embedded inside CBZ archives
  (especially those created by comic management tools like ComicRack).
  This service provides two operations:

    - Scan   – Check which CBZ files contain a ComicInfo.xml entry.
    - Remove – Strip the ComicInfo.xml entry from CBZ files, optionally
               creating a backup before modification.

  Both operations are static class methods that report progress through a
  TProgressEvent callback (may be nil).  Errors are captured per-file in
  the TComicInfoResults array rather than raising exceptions.
  ============================================================================ }
unit uservicecomicinfo;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor, uservicebase;

type
  { ------------------------------------------------------------------------
    TComicInfoEntry – Per-file result of a ComicInfo scan/remove operation.

    @field FileName     Name of the CBZ file that was processed.
    @field HasComicInfo True when ComicInfo.xml was found inside the archive.
    @field Removed      True when ComicInfo.xml was successfully removed
                        (always False after a Scan; set by Remove).
    @field Error        Error message if the operation failed on this file;
                        empty string on success.
    ------------------------------------------------------------------------ }
  TComicInfoEntry = record
    FileName: string;
    HasComicInfo: boolean;
    Removed: boolean;
    Error: string;
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
              HasComicInfo and Error fields populated.
      ------------------------------------------------------------------------ }
    class function Scan(const AFiles: TStringArray;
      const ADir: string): TComicInfoResults;

    { ------------------------------------------------------------------------
      Remove – Strip ComicInfo.xml from CBZ files.

      For each file that contains ComicInfo.xml, this method rebuilds the
      archive without that entry and writes it back.  Optionally backs up
      the original before overwriting.

      @param  AFiles      Array of CBZ filenames to process.
      @param  ADir        Directory containing the files.
      @param  ABackup     If True, rename the original to *_OLD.cbz before
                          writing the modified version.
      @param  AOnProgress Optional progress callback (percentage + message).
      @return An array of TComicInfoEntry with HasComicInfo and Removed
              fields reflecting the outcome for each file.
      ------------------------------------------------------------------------ }
    class function Remove(const AFiles: TStringArray; const ADir: string;
      ABackup: boolean; AOnProgress: TProgressEvent = nil): TComicInfoResults;
  end;

implementation

{ ----------------------------------------------------------------------------
  Scan
  ---------------------------------------------------------------------------- }
class function TComicInfoService.Scan(const AFiles: TStringArray;
  const ADir: string): TComicInfoResults;
var
  i: integer;
  FullPath: string;
  Entries: TZipEntries;
  j: integer;
begin
  Result := nil;
  SetLength(Result, Length(AFiles));
  for i := 0 to High(AFiles) do
  begin
    Result[i].FileName := AFiles[i];
    Result[i].Removed := False;
    FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
    try
      Entries := CollectZipEntries(FullPath);
      try
        Result[i].HasComicInfo := False;
        for j := 0 to High(Entries) do
          if SameText(Entries[j].Name, COMICINFO_XML) then
          begin
            Result[i].HasComicInfo := True;
            Break;
          end;
      finally
        FreeZipEntries(Entries);
      end;
    except
      on E: Exception do
      begin
        Result[i].Error := E.Message;
      end;
    end;
  end;
end;

{ ----------------------------------------------------------------------------
  Remove

  Iterates over each file, collects its ZIP entries, checks for
  ComicInfo.xml, and — if found — rebuilds the archive without it by
  compacting the entry array in-place.  The compaction shifts non-skipped
  entries toward the front of the array, nil'ing the Data pointer of the
  moved source to prevent the final FreeZipEntries call from double-freeing
  memory that now belongs to the compacted array.
  ---------------------------------------------------------------------------- }
class function TComicInfoService.Remove(const AFiles: TStringArray;
  const ADir: string; ABackup: boolean;
  AOnProgress: TProgressEvent = nil): TComicInfoResults;
var
  i, j, k, Total: integer;
  FullPath: string;
  Entries: TZipEntries;
  Found: boolean;
begin
  Total := Length(AFiles);
  Result := nil;
  SetLength(Result, Total);
  if Assigned(AOnProgress) and (Total > 0) then
    AOnProgress(0, Format('Scanning 0/%d files', [Total]));
  for i := 0 to High(AFiles) do
  begin
    if Assigned(AOnProgress) then
      AOnProgress((i * 100) div Total,
        Format('Removing from %s (%d/%d)', [AFiles[i], i + 1, Total]));
    Result[i].FileName := AFiles[i];
    Result[i].Removed := False;
    FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
    try
      Entries := CollectZipEntries(FullPath);
      try
        { Check if ComicInfo.xml exists }
        Found := False;
        for j := 0 to High(Entries) do
          if SameText(Entries[j].Name, COMICINFO_XML) then
          begin
            Found := True;
            Break;
          end;
        Result[i].HasComicInfo := Found;

        if not Found then Continue;

        { Build filtered output array — transfer ownership from Entries.
          Walk through Entries; skip ComicInfo.xml entries.  Non-skipped
          entries are compacted toward the front of the array by shifting
          them down when a gap has opened (j <> k).  The Data pointer of
          the shifted source is nil'd to prevent FreeZipEntries from
          double-freeing it later. }
        k := 0;
        for j := 0 to High(Entries) do
        begin
          if SameText(Entries[j].Name, COMICINFO_XML) then
            Continue;   { Entries[j].Data will be freed by FreeZipEntries below }
          if j <> k then
          begin
            Entries[k] := Entries[j];      { shift entry to compacted position }
            Entries[j].Data := nil;        { transferred — source no longer owns it }
          end;
          Inc(k);
        end;
        SetLength(Entries, k);             { truncate to the compacted count }

        { Backup original if requested }
        if ABackup then
          BackupFile(FullPath);

        { Write new CBZ without ComicInfo.xml }
        WriteZipFromEntriesDeflated(FullPath, Entries);

        Result[i].Removed := True;
      finally
        FreeZipEntries(Entries);
      end;
    except
      on E: Exception do
      begin
        Result[i].Error := E.Message;
      end;
    end;
  end;
end;

end.
