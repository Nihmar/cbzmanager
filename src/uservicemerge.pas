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
  uservicebase (for TServiceProgressEvent, BackupFile, and TStringArray).
}
unit uservicemerge;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uzipcore, uZipEditor, uservicebase;

const
  { Fallback chapters-per-volume used when neither an explicit value nor an
    auto-calculated one is available. }
  DEFAULT_CHAPTERS_PER_VOLUME = 7;

{ Extract the chapter-number portion of a CBZ filename as a string,
  preserving leading zeros. Returns empty string if no pattern found. }
function ExtractChapterNumStr(const AFileName: string): string;

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
  TIntArray = array of integer;

  TMergeOptions = record
    SeriesName: string;
    ChapterStart: integer;
    ChapterEnd: integer;
    ChaptersPerVolume: integer;
    ChaptersList: TIntArray;
    Force: boolean;
    Delete: boolean;
    GenerateComicInfo: boolean;
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
      AOnProgress: TServiceProgressEvent = nil): TMergeResult;
  end;

implementation

uses
  StrUtils, ucomicinfo;

{ Extracts the chapter-number portion of a filename as a raw string,
  preserving leading zeros and any formatting.
  E.g. "Series - 0001.cbz" → "0001", "Manga - 042_extra.cbz" → "042".
  Also handles volume names: "Series V012.cbz" → "V012".
  Returns empty string if no pattern match is found. }
function ExtractChapterNumStr(const AFileName: string): string;
var
  Base: string;
  p: integer;
  S: string;
begin
  Result := '';
  Base := ChangeFileExt(AFileName, '');
  { First try: chapter pattern "Series - NNNN" }
  p := RPos(' -', Base);
  if p > 0 then
  begin
    Result := Trim(Copy(Base, p + 2, Length(Base)));
    { Strip leading underscore: "_0000" → "0000" }
    if (Length(Result) > 0) and (Result[1] = '_') then
      Delete(Result, 1, 1);
    { Strip trailing suffix after underscore: "0001_extra" → "0001" }
    p := Pos('_', Result);
    if p > 0 then
      Result := Copy(Result, 1, p - 1);
  end
  else
  begin
    { Second try: volume pattern "Series VNNN" }
    p := RPos(' V', Base);
    if p > 0 then
    begin
      S := Trim(Copy(Base, p + 2, Length(Base)));
      if (Length(S) > 0) and (S[1] in ['0'..'9']) then
      begin
        { Strip trailing suffix after underscore: "V001_extra" → "V001" }
        p := Pos('_', S);
        if p > 0 then
          S := Copy(S, 1, p - 1);
        Result := 'V' + S;
      end;
    end;
  end;
end;

function ExtractChapterNum(const AFileName: string): integer;
var
  S: string;
begin
  S := ExtractChapterNumStr(AFileName);
  if S <> '' then
    Result := StrToIntDef(S, 0)
  else
    Result := 0;
end;

{ Simple insertion sort — stable, adequate for typical chapter counts. }
procedure SortChaptersByNumber(var AChapters: TStringArray);
var
  i, j: integer;
  Key: string;
  KeyNum: integer;
begin
  for i := 1 to High(AChapters) do
  begin
    Key := AChapters[i];
    KeyNum := ExtractChapterNum(Key);
    j := i - 1;
    while (j >= 0) and (ExtractChapterNum(AChapters[j]) > KeyNum) do
    begin
      AChapters[j + 1] := AChapters[j];
      Dec(j);
    end;
    AChapters[j + 1] := Key;
  end;
end;

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
begin
  Result := 0;
  if (SeriesName = '') or (Length(AFiles) = 0) then Exit;

  LowestCh := MaxInt;
  VolCount := 0;

  for i := 0 to High(AFiles) do
  begin
    BaseName := ChangeFileExt(AFiles[i], '');
    if StartsStr(SeriesName + ' V', BaseName) then
    begin
      Inc(VolCount);
      Continue;
    end;
    ChNum := ExtractChapterNum(AFiles[i]);
    if (ChNum >= 0) and (ChNum < LowestCh) then
      LowestCh := ChNum;
  end;

  { If we have at least one volume and the lowest chapter is >= 1,
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
  AOnProgress: TServiceProgressEvent = nil): TMergeResult;
var
  i, n, ChNum, CPV, VolNum, TotalCreated, Remaining, TotalBatches: integer;
  ChIdx, ListIdx, BatchSize: integer;
  UseList: boolean;
  SeriesName, VolName, FullPath: string;
  ChBatch, Batch: TStringArray;
  VolEntries: TZipEntries;
  CI: TComicInfo;
  XML: string;
  k, ChFirst, ChLast: integer;
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
      CPV := DEFAULT_CHAPTERS_PER_VOLUME; // sensible default when no data exists
  end;

  ChBatch := nil;
  for i := 0 to High(AFiles) do
  begin
    ChNum := ExtractChapterNum(AFiles[i]);
    if (ChNum >= Options.ChapterStart) and (ChNum <= Options.ChapterEnd) then
    begin
      SetLength(ChBatch, Length(ChBatch) + 1);
      ChBatch[High(ChBatch)] := AFiles[i];
    end;
  end;

  if Length(ChBatch) = 0 then
  begin
    Result.ErrorMsg := 'No matching chapter files found';
    Exit;
  end;

  { Sort chapters by extracted number so filesystem order doesn't matter.
    A simple insertion sort suffices — chapter lists are rarely huge. }
  SortChaptersByNumber(ChBatch);

  { ---- Phase 2: Volume creation ----------------------------------------- }

  UseList := Length(Options.ChaptersList) > 0;

  if UseList then
    TotalBatches := Length(Options.ChaptersList)
  else
  begin
    { Only full volumes are created.  With Force, leftover chapters are
      absorbed into the last volume — the count stays the same. }
    TotalBatches := Length(ChBatch) div CPV;
  end;

  TotalCreated := 0;
  VolNum := 1;
  ChIdx := 0;
  ListIdx := 0;

  if Assigned(AOnProgress) and (TotalBatches > 0) then
    AOnProgress(0, Format('Merging 0/%d volumes', [TotalBatches]));

  while ChIdx < Length(ChBatch) do
  begin
    { Without Force: stop after full volumes, leaving leftovers untouched }
    if not Options.Force then
      if TotalBatches > 0 then
        if TotalCreated >= TotalBatches then
          Break;

    Remaining := Length(ChBatch) - ChIdx;

    if Assigned(AOnProgress) and (TotalBatches > 0) then
      AOnProgress((TotalCreated * 100) div TotalBatches,
        Format('Writing volume %d/%d', [TotalCreated + 1, TotalBatches]));

    if UseList then
    begin
      if ListIdx > High(Options.ChaptersList) then
        Break;
      BatchSize := Options.ChaptersList[ListIdx];
      if BatchSize > Remaining then
        BatchSize := Remaining;
      Inc(ListIdx);
    end
    else
    begin
      BatchSize := CPV;
      if BatchSize > Remaining then
      begin
        if Options.Force then
          BatchSize := Remaining   // absorb remainder into last volume
        else
          Break;                   // skip incomplete final volume
      end
      else if Options.Force and (TotalBatches > 0) and
        (TotalCreated + 1 >= TotalBatches) then
      begin
        { Last full batch with Force: absorb any trailing leftovers now }
        BatchSize := Remaining;
      end;
    end;

    Batch := nil;
    SetLength(Batch, BatchSize);
    for n := 0 to BatchSize - 1 do
      Batch[n] := ChBatch[ChIdx + n];

    VolName := Format('%s V%.3d.cbz', [SeriesName, VolNum]);
    FullPath := CBZFullPath(ADir, VolName);

    VolEntries := MergeIntoVolume(Batch, ADir, AOnProgress);
    try
      if Length(VolEntries) > 0 then
      begin
        if Options.GenerateComicInfo then
        begin
          CI := DefaultComicInfo;
          CI.Series := SeriesName;
          CI.Volume := VolNum;
          ChFirst := ExtractChapterNum(Batch[0]);
          ChLast := ExtractChapterNum(Batch[High(Batch)]);
          if (ChFirst > 0) and (ChLast > 0) then
            CI.Number := Format('%d-%d', [ChFirst, ChLast])
          else
            CI.Number := IntToStr(VolNum);
          CI.Title := Format('%s Vol.%d', [SeriesName, VolNum]);
          CI.PageCount := Length(VolEntries);
          CI.Manga := 'Unknown';
          XML := GenerateComicInfoXML(CI);
          k := Length(VolEntries);
          SetLength(VolEntries, k + 1);
          VolEntries[k].Name := COMICINFO_XML;
          VolEntries[k].Data := TMemoryStream.Create;
          if Length(XML) > 0 then
            VolEntries[k].Data.Write(XML[1], Length(XML));
          VolEntries[k].Data.Position := 0;
        end;
        WriteZipFromEntriesDeflated(FullPath, VolEntries);
        Inc(TotalCreated);
      end;
    finally
      FreeZipEntries(VolEntries);
    end;

    Inc(VolNum);
    Inc(ChIdx, BatchSize);
  end;

  Result.Success := TotalCreated > 0;
  Result.VolumesCreated := TotalCreated;

  { ---- Phase 3: Cleanup — remove or back up original chapter files ---- }
  for n := 0 to ChIdx - 1 do
  begin
    FullPath := CBZFullPath(ADir, ChBatch[n]);
    if Options.Delete then
      DeleteFile(FullPath)
    else
      BackupFile(FullPath);
  end;
end;

end.
