{
  uservicemerge.pas — Chapter-to-Volume Merge Service

  This unit provides the TMergeService class that automates merging individual
  chapter CBZ files into multi-chapter volume CBZ archives. It supports:

    - Automatic detection of a series name from chapter filenames
      (expects the pattern "Title - NNNN.cbz").
    - Automatic calculation of chapters-per-volume by inspecting existing
      volume files already present in the directory.
    - Grouping chapters into batches of a configurable size and writing each
      batch as a new volume file ("Title V001.cbz", "Title V002.cbz", …).
    - A "force" mode where trailing leftover chapters are appended to the
      most recently created volume instead of forming an undersized final
      volume.
    - Post-merge cleanup: original chapter files are either deleted or
      renamed to *_OLD.cbz (depending on the Delete option).

  The unit depends on uZipEditor (for CBZ read/write/merge primitives) and
  uservicebase (for TProgressEvent, BackupFile, and TStringArray).
}
unit uservicemerge;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor, uservicebase;

type
  { TMergeOptions — Configuration parameters for a merge operation.

    Fields:
      SeriesName      — Human-readable name of the series (e.g. "One Piece").
                        When empty, DetectSeriesName is called to infer it.
      ChapterStart    — Lowest chapter number to include in the merge.
      ChapterEnd      — Highest chapter number to include in the merge.
      ChaptersPerVolume — How many chapters to pack into each volume.
                          0 means "auto-calculate from existing volumes".
      Force           — If True, the last volume absorbs leftover chapters
                        instead of creating an undersized final volume.
      Delete          — If True, original chapter files are deleted after a
                        successful merge; otherwise they are renamed to
                        *_OLD.cbz. }
  TMergeOptions = record
    SeriesName: string;
    ChapterStart: integer;
    ChapterEnd: integer;
    ChaptersPerVolume: integer;  // 0 = auto-calculate
    Force: boolean;
    Delete: boolean;             // True=delete originals, False=rename to _OLD
  end;

  { TMergeResult — Outcome of a merge operation.

    Fields:
      Success        — True if at least one volume was created.
      VolumesCreated — Number of new volume files actually written.
      ErrorMsg       — Human-readable error description when Success=False. }
  TMergeResult = record
    Success: boolean;
    VolumesCreated: integer;
    ErrorMsg: string;
  end;

  { TMergeService — Stateless service that merges chapter CBZ files into
    volume collections. All methods are class methods; no instantiation
    is needed. }
  TMergeService = class
  public
    { Auto-detect series name from a list of filenames.
      Returns empty string if no "Title - NNNN" pattern found. }
    class function DetectSeriesName(const AFiles: TStringArray): string;

    { Calculate chapters-per-volume from existing volume files.
      Scans AFiles for "Title VNNN.cbz", extracts the highest chapter number
      from matching chapter files, and returns (max_chapter-1) / num_volumes.
      Returns 0 if calculation is impossible (no volumes or no chapters). }
    class function CalculateChaptersPerVolume(const AFiles: TStringArray;
      const SeriesName: string): integer;

    { Perform the merge operation.

      Parameters:
        AFiles  — All CBZ filenames in the directory (just names, not paths).
        ADir    — Directory path containing the files (may be empty for cwd).
        Options — Merge parameters (series name, CPV, range, force, delete).
                  When Options.ChaptersPerVolume = 0, auto-calculates from
                  existing volumes.  When Force is True, the last volume
                  absorbs remaining chapters (even if they exceed CPV).
        AOnProgress — Optional callback invoked before each volume write;
                      receives (percent, description).

      Returns a TMergeResult with Success, VolumesCreated, and ErrorMsg. }
    class function Merge(const AFiles: TStringArray; const ADir: string;
      const Options: TMergeOptions;
      AOnProgress: TProgressEvent = nil): TMergeResult;
  end;

implementation

uses
  Math, StrUtils;

{ ---------------------------------------------------------------------------
  DetectSeriesName

  Scans the file list for the first name matching the pattern:
      "Series Name - NNNN.cbz"
  It uses RPos to find the rightmost " -" (space-dash), then takes
  everything to the left of it as the series name.  This handles series
  names that themselves contain hyphens (e.g. "Spider-Man - 0001.cbz").

  Returns:
    The extracted series name, or an empty string if no match was found.
  --------------------------------------------------------------------------- }
class function TMergeService.DetectSeriesName(const AFiles: TStringArray): string;
var
  i, n: integer;
  BaseName: string;
begin
  Result := '';
  for i := 0 to High(AFiles) do
  begin
    BaseName := ChangeFileExt(AFiles[i], '');
    n := RPos(' -', BaseName);          // rightmost " -" to avoid splitting
                                         // series names that contain hyphens
    if n > 0 then
    begin
      Result := Trim(Copy(BaseName, 1, n - 1));
      Exit;                               // return on first match
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  CalculateChaptersPerVolume

  Estimates the chapters-per-volume (CPV) value by examining files already
  present in the directory.  It assumes chapters are named
  "SeriesName - NNNN.cbz" and volumes are named "SeriesName VNNN.cbz".

  Algorithm:
    1. Count how many existing volume files are present (VolCount).
    2. Find the lowest chapter number among all chapter files (LowestCh).
    3. CPV = (LowestCh - 1) div VolCount.

  The idea is that if volume 1 already covers chapters 1..N, then
  chapter N+1 is the start of volume 2, so the number of chapters *not*
  yet in any volume divided by the number of existing volumes gives CPV.

  Returns:
    The estimated CPV (>= 1), or 0 if there is not enough data.
  --------------------------------------------------------------------------- }
class function TMergeService.CalculateChaptersPerVolume(
  const AFiles: TStringArray; const SeriesName: string): integer;
var
  i, ChNum, LowestCh, VolCount: integer;
  BaseName: string;
  n: integer;
begin
  Result := 0;
  if (SeriesName = '') or (Length(AFiles) = 0) then Exit;

  LowestCh := MaxInt;                     // start with a very large sentinel
  VolCount := 0;

  for i := 0 to High(AFiles) do
  begin
    BaseName := ChangeFileExt(AFiles[i], '');
    { Count existing volumes }
    if StartsStr(SeriesName + ' V', BaseName) then
    begin
      Inc(VolCount);
      Continue;                           // a volume file, not a chapter
    end;
    { Find lowest chapter number }
    n := RPos(' -', BaseName);
    if n > 0 then
    begin
      ChNum := StrToIntDef(Trim(Copy(BaseName, n + 2, MaxInt)), 0);
      if (ChNum > 0) and (ChNum < LowestCh) then
        LowestCh := ChNum;
    end;
  end;

  { If we have at least one volume and the lowest chapter is > 1,
    the existing volumes cover chapters 1..(LowestCh-1). }
  if (VolCount > 0) and (LowestCh > 1) then
    Result := (LowestCh - 1) div VolCount;

  { Clamp to sensible range }
  if Result < 1 then
    Result := 0;
end;

{ ---------------------------------------------------------------------------
  Merge

  Core merge routine.  It proceeds in three phases:

  Phase 1 — Preparation
    - Resolve the series name (explicit or auto-detected).
    - Determine chapters-per-volume (explicit or auto-calculated; falls
      back to 7 if no data is available).
    - Build a sorted chapter batch from files whose embedded chapter
      number falls within [ChapterStart, ChapterEnd].

  Phase 2 — Volume creation
    - Group the chapter batch into slices of CPV chapters each.
    - For each slice, call MergeIntoVolume to collect the combined ZIP
      entries, then write them out via WriteZipFromEntriesDeflated.
    - If Force is True and this is NOT the first volume, AND the
      remaining chapters would fit in a single batch (Remaining <= CPV),
      append them to the *previous* volume instead of creating a new one.
      This avoids an undersized "leftover" volume.

  Phase 3 — Cleanup
    - For every chapter file that was part of the merge, either delete it
      or rename it to *_OLD.cbz according to Options.Delete.
  --------------------------------------------------------------------------- }
class function TMergeService.Merge(const AFiles: TStringArray;
  const ADir: string; const Options: TMergeOptions;
  AOnProgress: TProgressEvent = nil): TMergeResult;
var
  i, n, ChNum, CPV, VolNum, TotalCreated, Remaining, TotalBatches: integer;
  BaseName, SeriesName, VolName, FullPath: string;
  ChBatch, Batch: TStringArray;
  VolEntries: TZipEntries;
  CreatedFiles: TStringArray;             // track created volumes (for future use)
begin
  Result.Success := False;
  Result.VolumesCreated := 0;
  Result.ErrorMsg := '';

  { ---- Phase 1: Preparation --------------------------------------------- }

  { Resolve series name: explicit > auto-detect > fallback }
  SeriesName := Options.SeriesName;
  if SeriesName = '' then
    SeriesName := DetectSeriesName(AFiles);
  if SeriesName = '' then
    SeriesName := 'Unknown';

  { Determine CPV: explicit > auto-calculate > hard-coded fallback of 7 }
  CPV := Options.ChaptersPerVolume;
  if CPV < 1 then
  begin
    CPV := CalculateChaptersPerVolume(AFiles, SeriesName);
    if CPV < 1 then
      CPV := 7;                           // sensible default when no data exists
  end;

  { Build the chapter batch: every file matching "SeriesName - NNNN.cbz"
    whose chapter number is within the requested range.  We use RPos(' -')
    so series names containing hyphens are handled correctly. }
  ChBatch := nil;
  for i := 0 to High(AFiles) do
  begin
    BaseName := ChangeFileExt(AFiles[i], '');
    n := RPos(' -', BaseName);
    if n > 0 then
    begin
      ChNum := StrToIntDef(Trim(Copy(BaseName, n + 2, MaxInt)), 0);
      if (ChNum >= Options.ChapterStart) and (ChNum <= Options.ChapterEnd) then
      begin
        SetLength(ChBatch, Length(ChBatch) + 1);
        ChBatch[High(ChBatch)] := AFiles[i];
      end;
    end;
  end;

  if Length(ChBatch) = 0 then
  begin
    Result.ErrorMsg := 'No matching chapter files found';
    Exit;
  end;

  { ---- Phase 2: Volume creation ----------------------------------------- }

  TotalBatches := (Length(ChBatch) + CPV - 1) div CPV;  // ceiling division
  TotalCreated := 0;
  VolNum := 1;
  CreatedFiles := nil;

  { Signal start of merge via progress callback }
  if Assigned(AOnProgress) and (TotalBatches > 0) then
    AOnProgress(0, Format('Merging 0/%d volumes', [TotalBatches]));

  i := 0;
  while i < Length(ChBatch) do
  begin
    Remaining := Length(ChBatch) - i;

    { Report progress before writing each volume }
    if Assigned(AOnProgress) then
      AOnProgress((TotalCreated * 100) div TotalBatches,
        Format('Writing volume %d/%d', [TotalCreated + 1, TotalBatches]));

    { ---- Force mode: append leftovers to the previous volume ----------- }
    if Options.Force and (TotalCreated > 0) and (Remaining <= CPV) then
    begin
      { The remaining chapters are few enough to fit in one normal batch.
        Instead of creating a new (undersized) volume, re-open the last
        volume we just wrote and append these chapters to it. }
      VolName := Format('%s V%.3d.cbz', [SeriesName, VolNum - 1]);
      FullPath := IncludeTrailingPathDelimiter(ADir) + VolName;

      { Build a batch containing all remaining chapters }
      SetLength(Batch, Remaining);
      for n := 0 to Remaining - 1 do
        Batch[n] := ChBatch[i + n];

      VolEntries := MergeIntoVolume(Batch, ADir);
      try
        if Length(VolEntries) > 0 then
        begin
          WriteZipFromEntriesDeflated(FullPath, VolEntries);
          { No new volume counter increment — entries were added to existing }
        end;
      finally
        FreeZipEntries(VolEntries);
      end;

      i := Length(ChBatch);               // mark all chapters as consumed
      Break;                               // exit the while loop
    end
    { ---- Normal mode: create a new volume file ------------------------- }
    else
    begin
      { Collect up to CPV chapters into a batch slice }
      Batch := nil;
      for n := 0 to CPV - 1 do
        if i + n < Length(ChBatch) then
        begin
          SetLength(Batch, Length(Batch) + 1);
          Batch[High(Batch)] := ChBatch[i + n];
        end;

      VolName := Format('%s V%.3d.cbz', [SeriesName, VolNum]);
      FullPath := IncludeTrailingPathDelimiter(ADir) + VolName;

      { Merge the batch into a single set of ZIP entries, then flush to disk }
      VolEntries := MergeIntoVolume(Batch, ADir);
      try
        if Length(VolEntries) > 0 then
        begin
          WriteZipFromEntriesDeflated(FullPath, VolEntries);
          SetLength(CreatedFiles, Length(CreatedFiles) + 1);
          CreatedFiles[High(CreatedFiles)] := FullPath;
          Inc(TotalCreated);
        end;
      finally
        FreeZipEntries(VolEntries);
      end;

      Inc(VolNum);
      Inc(i, CPV);                         // advance past the batch we just wrote
    end;
  end;

  Result.Success := TotalCreated > 0;
  Result.VolumesCreated := TotalCreated;

  { ---- Phase 3: Cleanup — remove or back up original chapter files ---- }
  for n := 0 to High(ChBatch) do
  begin
    FullPath := IncludeTrailingPathDelimiter(ADir) + ChBatch[n];
    if Options.Delete then
      DeleteFile(FullPath)                 // permanent deletion
    else
      BackupFile(FullPath);                // rename to *_OLD.cbz
  end;
end;

end.
