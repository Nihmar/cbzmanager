{
  uservicemerge.pas — Chapter-to-Volume Merge Service

  This unit provides the TMergeService class that automates merging individual
  chapter CBZ files into multi-chapter volume CBZ archives. It supports:

    - Automatic detection of a series name from chapter filenames
      (expects the pattern "Title - NNNN.cbz").
    - Strict file classification: only real chapter files of the merged
      series participate; volume files ("Title VNNN.cbz") and _OLD backups
      are never merged and never cleaned up.
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

  Documented divergences from the Python reference (see AGENTS.md):
    - Non-image zip entries are dropped by MergeIntoVolume instead of being
      renumbered as pages.
    - Force below CPV still produces a single volume (Python skips).
    - Auto CPV < 1 falls back to DEFAULT_CHAPTERS_PER_VOLUME (Python
      crashes on 0 and writes empty volumes for (0,1)).
    - Chapter range [ChapterStart, ChapterEnd] is a GUI feature; the
      default covers every chapter.
    - Empty batches produce no volume file.
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

type
  TIntArray = array of integer;

{ Extract the chapter-number portion of a CBZ filename as a string,
  preserving leading zeros. Returns empty string if no pattern found. }
function ExtractChapterNumStr(const AFileName: string): string;

{ Strict volume classification (mirrors the Python reference regex
  ^(.+)\s(V\d+)\.cbz$): AFileName is a volume file of ASeriesName when its
  stem is exactly "<SeriesName> V<digits>".  Backups such as
  "Series V001_OLD.cbz" and any other suffix are NOT volumes and must never
  be merged or cleaned up. }
function IsVolumeFile(const AFileName, ASeriesName: string): boolean;

{ Strict chapter classification (mirrors the Python reference regexes
  _CHAPTER_RE / _SPECIAL_RE): AFileName is a chapter file when its stem is
  "<Series> - <digits>" (optionally with "_<digits>" sub-chapter suffixes)
  or "<Series> - <alpha-tag>" (specials such as "SP01").  "_OLD" backups,
  decimal chapters, and any other names are rejected.  On success returns
  the series name, the numeric part (0 for specials), and whether the tag
  is alphabetic. }
function IsChapterFile(const AFileName: string; out ASeries: string;
  out ANumber: integer; out AIsSpecial: boolean): boolean;

{ Builds the Volume-column labels for ACount chapters grouped by the custom
  sequence ASeq (chapter counts per volume), continuing after ALastVolume.
  A batch that does not fully fit the remaining rows is skipped (its
  chapters stay unassigned, shown as '-'), mirroring the merge service and
  the Python reference.  An empty sequence yields '?' for every row.
  Pure function — used by the merge dialog preview and by unit tests. }
function CustomSequenceLabels(ACount: integer; const ASeq: TIntArray;
  ALastVolume: integer): TStringArray;

type
  { TChapterInfo — a chapter file and its numeric sort key.  Specials
    receive synthetic numbers after the highest regular chapter, assigned
    by CollectChapters. }
  TChapterInfo = record
    FileName: string;
    Number: integer;
    IsSpecial: boolean;
  end;
  TChapterArray = array of TChapterInfo;
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
      Counts strict volume files ("Title VNNN.cbz" — backups excluded) and
      takes the lowest regular chapter of the series, then returns
      (lowest_chapter-1) / num_volumes.  Returns 0 if calculation is
      impossible (no volumes, no chapters, or volumes already cover
      chapter 1). }
    class function CalculateChaptersPerVolume(const AFiles: TStringArray;
      const SeriesName: string): integer;

    { Float variant of CalculateChaptersPerVolume, matching the Python
      reference exactly: chapters_per_volume = (lowest_chapter - 1) /
      num_volumes with REAL division, so irregular volumes yield
      fractional values (e.g. 4 volumes covering chapters 1..15 →
      15/4 = 3.75).  Returns 0.0 when the calculation is impossible. }
    class function CalculateChaptersPerVolumeFloat(const AFiles: TStringArray;
      const SeriesName: string): Double;

    { Find the highest existing volume number among files named exactly
      "<SeriesName> VNNN.cbz".  Backups ("<SeriesName> VNNN_OLD.cbz") do
      not count.  Returns 0 when no volume matches or the series name is
      empty, so a following merge can start numbering at 1. }
    class function LastVolumeNumber(const AFiles: TStringArray;
      const SeriesName: string): integer;

    { Collect the chapter files of ASeriesName from AFiles, sorted by
      (chapter number, filename).  Volume files, _OLD backups, and files of
      other series are ignored.  Specials (e.g. "SP01") receive synthetic
      numbers after the highest regular chapter, mirroring the Python
      reference. }
    class function CollectChapters(const AFiles: TStringArray;
      const ASeriesName: string): TChapterArray;

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
  E.g. "Series - 0001.cbz" → "0001", "Manga - 042_extra.cbz" → "042_extra",
  "Manga - _042.cbz" → "042".
  Also handles volume names: "Series V012.cbz" → "V012".
  The underscore suffix is kept so variant/part files (e.g. "010_15") stay
  distinguishable from the plain chapter in the UI.
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
  end
  else
  begin
    { Second try: volume pattern "Series VNNN" }
    p := RPos(' V', Base);
    if p > 0 then
    begin
      S := Trim(Copy(Base, p + 2, Length(Base)));
      if (Length(S) > 0) and (S[1] in ['0'..'9']) then
        Result := 'V' + S;
    end;
  end;
end;

function ExtractChapterNum(const AFileName: string): integer;
var
  S: string;
  i: integer;
begin
  S := ExtractChapterNumStr(AFileName);
  { Use the integer part so decimal chapters (e.g. "010.5") and sub-chapter
    markers (e.g. "010_15") map to their whole-number index (10) instead of
    collapsing to 0 and being silently dropped from a chapter range. }
  i := 1;
  while (i <= Length(S)) and (S[i] in ['0'..'9']) do
    Inc(i);
  Result := StrToIntDef(Copy(S, 1, i - 1), 0);
end;

{ Simple insertion sort of TChapterArray by (Number, FileName) — stable,
  adequate for typical chapter counts.  Ties on number are broken by
  filename so the order is deterministic regardless of input order. }
procedure SortChapters(var AChapters: TChapterArray);
var
  i, j: integer;
  Key: TChapterInfo;
begin
  for i := 1 to High(AChapters) do
  begin
    Key := AChapters[i];
    j := i - 1;
    while (j >= 0) and
          ((AChapters[j].Number > Key.Number) or
           ((AChapters[j].Number = Key.Number) and
            (AChapters[j].FileName > Key.FileName))) do
    begin
      AChapters[j + 1] := AChapters[j];
      Dec(j);
    end;
    AChapters[j + 1] := Key;
  end;
end;

{ ---------------------------------------------------------------------------
  CustomSequenceLabels

  Pure labeling of the Volume column for a custom chapter sequence —
  extracted so the dialog preview logic is unit-testable without a GUI.
  --------------------------------------------------------------------------- }
function CustomSequenceLabels(ACount: integer; const ASeq: TIntArray;
  ALastVolume: integer): TStringArray;
var
  i, j, VolNum, Consumed, SeqIdx: integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  if ACount = 0 then Exit;
  if Length(ASeq) = 0 then
  begin
    for i := 0 to ACount - 1 do
      Result[i] := '?';
    Exit;
  end;
  VolNum := ALastVolume + 1;
  Consumed := 0;
  SeqIdx := 0;
  for i := 0 to ACount - 1 do
  begin
    if SeqIdx <= High(ASeq) then
    begin
      { A batch that does not fully fit the remaining rows is skipped
        entirely (the merge service breaks there too) — label the
        remaining rows as unassigned. }
      if ASeq[SeqIdx] > ACount - i then
      begin
        for j := i to ACount - 1 do
          Result[j] := '-';
        Break;
      end;
      Result[i] := Format('Vol.%d', [VolNum]);
      Inc(Consumed);
      if Consumed >= ASeq[SeqIdx] then
      begin
        Inc(VolNum);
        Inc(SeqIdx);
        Consumed := 0;
      end;
    end
    else
      Result[i] := '-';
  end;
end;

{ ---------------------------------------------------------------------------
  IsVolumeFile

  Strict volume classification mirroring the Python reference regex
  ^(.+)\s(V\d+)\.cbz$: the stem must be exactly "<SeriesName> V<digits>".
  Anything else — "Series V001_OLD.cbz", "Series V001_extra.cbz" — is not
  a volume and must never be merged, numbered, or cleaned up.
  --------------------------------------------------------------------------- }
function IsVolumeFile(const AFileName, ASeriesName: string): boolean;
var
  Base, S: string;
  i: integer;
begin
  Result := False;
  if ASeriesName = '' then Exit;
  Base := ChangeFileExt(AFileName, '');
  if not StartsStr(ASeriesName + ' V', Base) then Exit;
  { The remainder after "<SeriesName> V" must be all digits. }
  S := Copy(Base, Length(ASeriesName) + 3, MaxInt);
  if S = '' then Exit;
  for i := 1 to Length(S) do
    if not (S[i] in ['0'..'9']) then Exit;
  Result := True;
end;

{ ---------------------------------------------------------------------------
  IsChapterFile

  Strict chapter classification mirroring the Python reference regexes
  _CHAPTER_RE (numeric tags) and _SPECIAL_RE (alphabetic tags):

    "Series - 001.cbz"      → chapter 1
    "Series - 010_15.cbz"   → chapter 10 (sub-chapter suffix)
    "Series - SP01.cbz"     → special tag
    "Series - 001_OLD.cbz"  → rejected (backup)
    "Series - 010.5.cbz"    → rejected (decimal, not a Python pattern)

  Returns the series name, the numeric part (0 for specials), and whether
  the tag is alphabetic.
  --------------------------------------------------------------------------- }
function IsChapterFile(const AFileName: string; out ASeries: string;
  out ANumber: integer; out AIsSpecial: boolean): boolean;
var
  Base, Tag: string;
  p, i: integer;
begin
  Result := False;
  ASeries := '';
  ANumber := 0;
  AIsSpecial := False;
  Base := ChangeFileExt(AFileName, '');
  { Rightmost " -" separates the series name from the chapter tag, so
    series names containing hyphens ("Spider-Man - 001.cbz") work. }
  p := RPos(' -', Base);
  if p <= 0 then Exit;
  ASeries := Trim(Copy(Base, 1, p - 1));
  if ASeries = '' then Exit;
  Tag := Trim(Copy(Base, p + 2, MaxInt));
  if Tag = '' then Exit;

  if Tag[1] in ['0'..'9'] then
  begin
    { Numeric tag: <digits>(_<digits>)* — "010", "010_15", "010_15_2" }
    i := 1;
    while (i <= Length(Tag)) and (Tag[i] in ['0'..'9']) do
      Inc(i);
    ANumber := StrToIntDef(Copy(Tag, 1, i - 1), 0);
    while i <= Length(Tag) do
    begin
      { Each remaining group must be "_<digits>"; "_OLD" is rejected. }
      if (Tag[i] <> '_') or (i = Length(Tag)) or
         not (Tag[i + 1] in ['0'..'9']) then
        Exit;
      Inc(i, 2);
      while (i <= Length(Tag)) and (Tag[i] in ['0'..'9']) do
        Inc(i);
    end;
    Result := True;
  end
  else if Tag[1] in ['A'..'Z', 'a'..'z'] then
  begin
    { Special tag: [A-Za-z][A-Za-z0-9]*(_<digits>)* — "SP01", "Omake" }
    i := 2;
    while (i <= Length(Tag)) and
          (Tag[i] in ['A'..'Z', 'a'..'z', '0'..'9']) do
      Inc(i);
    while i <= Length(Tag) do
    begin
      if (Tag[i] <> '_') or (i = Length(Tag)) or
         not (Tag[i + 1] in ['0'..'9']) then
        Exit;
      Inc(i, 2);
      while (i <= Length(Tag)) and (Tag[i] in ['0'..'9']) do
        Inc(i);
    end;
    AIsSpecial := True;
    Result := True;
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
  CalculateChaptersPerVolumeFloat

  Python-exact CPV estimate: chapters_per_volume = (lowest_chapter - 1) /
  num_volumes with REAL division, so irregular existing volumes yield
  fractional values (e.g. 4 volumes covering chapters 1..15 → 15/4 =
  3.75).  The integer CalculateChaptersPerVolume is the Trunc() of this
  value (same semantics as Python's int()).

  Algorithm:
    1. Count how many existing volume files are present (VolCount) using
       strict classification — backups like "Series V001_OLD.cbz" do not
       count.
    2. Find the lowest regular chapter number of the series (specials and
       _OLD backups are excluded).
    3. CPV = (LowestCh - 1) / VolCount.

  The idea is that if volume 1 already covers chapters 1..N, then
  chapter N+1 is the start of volume 2, so the number of chapters *not*
  yet in any volume divided by the number of existing volumes gives CPV.

  Returns:
    The estimated CPV (> 0), or 0.0 if there is not enough data.
  --------------------------------------------------------------------------- }
class function TMergeService.CalculateChaptersPerVolumeFloat(
  const AFiles: TStringArray; const SeriesName: string): Double;
var
  i, ChNum, LowestCh, VolCount: integer;
  Series: string;
  IsSpecial: boolean;
begin
  Result := 0.0;
  if (SeriesName = '') or (Length(AFiles) = 0) then Exit;

  LowestCh := MaxInt;
  VolCount := 0;

  for i := 0 to High(AFiles) do
  begin
    if IsVolumeFile(AFiles[i], SeriesName) then
    begin
      Inc(VolCount);
      Continue;
    end;
    { Only regular chapters of this series can lower the lowest-chapter
      bound; specials are numbered after the regular chapters and _OLD
      backups are not chapters at all. }
    if IsChapterFile(AFiles[i], Series, ChNum, IsSpecial) and
       (Series = SeriesName) and not IsSpecial and
       (ChNum < LowestCh) then
      LowestCh := ChNum;
  end;

  { If we have at least one volume and the lowest real chapter is >= 1,
    the existing volumes cover chapters 1..(LowestCh-1).  LowestCh stays
    MaxInt when the series has no regular chapters left (fully merged
    folder) — then there is nothing to estimate from and we return 0. }
  if (VolCount > 0) and (LowestCh > 1) and (LowestCh < MaxInt) then
    Result := (LowestCh - 1) / VolCount;
end;

{ ---------------------------------------------------------------------------
  CalculateChaptersPerVolume

  Integer truncation of CalculateChaptersPerVolumeFloat, for callers that
  need a whole-number CPV (e.g. the dialog's spin edit).  Same semantics
  as Python's int() on the float value.
  --------------------------------------------------------------------------- }
class function TMergeService.CalculateChaptersPerVolume(
  const AFiles: TStringArray; const SeriesName: string): integer;
begin
  Result := Trunc(CalculateChaptersPerVolumeFloat(AFiles, SeriesName));
end;

{ ---------------------------------------------------------------------------
  LastVolumeNumber

  Scans AFiles for files named exactly "<SeriesName> VNNN.cbz" (the volume
  pattern written by Merge) and returns the largest number found.  A suffix
  after the digits ("Series V012_OLD.cbz") is NOT a volume and does not
  count.  Files of other series are ignored, so the result only reflects
  the series being merged.
  --------------------------------------------------------------------------- }
class function TMergeService.LastVolumeNumber(const AFiles: TStringArray;
  const SeriesName: string): integer;
var
  i, Num, Err: integer;
  S: string;
begin
  Result := 0;
  if SeriesName = '' then Exit;
  for i := 0 to High(AFiles) do
  begin
    if not IsVolumeFile(AFiles[i], SeriesName) then Continue;
    { The number starts right after "<SeriesName> V"; IsVolumeFile
      guarantees the remainder is all digits. }
    S := Copy(ChangeFileExt(AFiles[i], ''), Length(SeriesName) + 3, MaxInt);
    Val(S, Num, Err);
    if (Err = 0) and (Num > Result) then
      Result := Num;
  end;
end;

{ ---------------------------------------------------------------------------
  CollectChapters

  Builds the ordered chapter list of ASeriesName from AFiles:

    1. Every file classified as a chapter of ASeriesName is collected;
       regular chapters carry their numeric part, specials carry 0.
    2. The list is sorted by (number, filename).
    3. Specials are assigned sequential numbers after the highest regular
       chapter (Python reference behaviour: with regular chapters up to 100,
       "SP01" becomes chapter 101, "SP02" 102, ...) in filename order.
    4. The list is re-sorted so specials land after the regular chapters.
  --------------------------------------------------------------------------- }
class function TMergeService.CollectChapters(const AFiles: TStringArray;
  const ASeriesName: string): TChapterArray;
var
  i, MaxNum, NextNum: integer;
  Series: string;
  Num: integer;
  IsSpecial: boolean;
begin
  Result := nil;
  if ASeriesName = '' then Exit;

  MaxNum := 0;
  for i := 0 to High(AFiles) do
    if IsChapterFile(AFiles[i], Series, Num, IsSpecial) and
       (Series = ASeriesName) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].FileName := AFiles[i];
      Result[High(Result)].Number := Num;
      Result[High(Result)].IsSpecial := IsSpecial;
      if not IsSpecial and (Num > MaxNum) then
        MaxNum := Num;
    end;

  SortChapters(Result);

  NextNum := MaxNum + 1;
  for i := 0 to High(Result) do
    if Result[i].IsSpecial then
    begin
      Result[i].Number := NextNum;
      Inc(NextNum);
    end;

  SortChapters(Result);
end;

{ ---------------------------------------------------------------------------
  Merge

  Core merge routine.  It proceeds in three phases:

  Phase 1 — Preparation
    - Resolve the series name (explicit or auto-detected).
    - Determine chapters-per-volume (explicit or auto-calculated; falls
      back to 7 if no data is available).
    - Build a sorted chapter batch from the chapter files of the series
      (strict classification — volume files and _OLD backups never
      participate) whose chapter number falls within
      [ChapterStart, ChapterEnd].

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
      or rename it to *_OLD.cbz according to Options.Delete.  A guard
      re-checks the strict classification so volume files, backups, and
      files of other series can never be renamed or deleted.
  --------------------------------------------------------------------------- }
class function TMergeService.Merge(const AFiles: TStringArray;
  const ADir: string; const Options: TMergeOptions;
  AOnProgress: TServiceProgressEvent = nil): TMergeResult;
var
  i, n, CPV, VolNum, TotalCreated, Remaining, TotalBatches: integer;
  ChIdx, ListIdx, BatchSize: integer;
  UseList: boolean;
  CPVF: Double;
  SeriesName, VolName, FullPath: string;
  ChBatch, Batch, ToClean: TStringArray;
  CreatedPaths: TStringArray;
  Chapters: TChapterArray;
  CleanSeries: string;
  CleanNum: integer;
  CleanSpecial: boolean;
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

  { Determine CPV: explicit > auto-calculate > hard-coded fallback of 7.
    The auto value uses the Python reference's REAL division
    ((lowest-1)/num_volumes), which can be fractional (e.g. 3.75); CPV is
    its integer part (Python int()), and TotalBatches uses the float as
    Python does (int(num_chapters / chapters_per_volume)). }
  if Options.ChaptersPerVolume >= 1 then
    CPVF := Options.ChaptersPerVolume
  else
  begin
    CPVF := CalculateChaptersPerVolumeFloat(AFiles, SeriesName);
    if CPVF < 1.0 then
      CPVF := DEFAULT_CHAPTERS_PER_VOLUME; // sensible default when no data exists
  end;
  CPV := Trunc(CPVF);

  { Build the chapter batch from CollectChapters: only chapter files of the
    merged series whose number falls within [ChapterStart, ChapterEnd].
    Volume files, _OLD backups, and files of other series never enter the
    batch, so they are never merged and never cleaned up.  The list comes
    pre-sorted by (chapter number, filename). }
  ChBatch := nil;
  ToClean := nil;
  Chapters := TMergeService.CollectChapters(AFiles, SeriesName);
  for i := 0 to High(Chapters) do
    if (Chapters[i].Number >= Options.ChapterStart) and
       (Chapters[i].Number <= Options.ChapterEnd) then
    begin
      SetLength(ChBatch, Length(ChBatch) + 1);
      ChBatch[High(ChBatch)] := Chapters[i].FileName;
    end;

  if Length(ChBatch) = 0 then
  begin
    Result.ErrorMsg := 'No matching chapter files found';
    Exit;
  end;

  { ---- Phase 2: Volume creation ----------------------------------------- }

  UseList := Length(Options.ChaptersList) > 0;

  if UseList then
    TotalBatches := Length(Options.ChaptersList)
  else
    { Only full volumes are created.  Python reference:
      num_new_volumes = int(num_chapters / chapters_per_volume).  With
      Force, leftover chapters are absorbed into the last volume — the
      count stays the same. }
    TotalBatches := Trunc(Length(ChBatch) / CPVF);

  TotalCreated := 0;
  { Number new volumes after the highest existing one, so repeated merges
    extend the series instead of overwriting earlier volumes. }
  VolNum := LastVolumeNumber(AFiles, SeriesName) + 1;
  ChIdx := 0;
  ListIdx := 0;
  CreatedPaths := nil;

  if Assigned(AOnProgress) and (TotalBatches > 0) then
    AOnProgress(0, Format('Merging 0/%d volumes', [TotalBatches]));

  try
    while ChIdx < Length(ChBatch) do
    begin
      { Without Force: stop after full volumes, leaving leftovers untouched.
        TotalBatches = 0 (fewer chapters than CPV — the Python reference's
        "Not enough chapters") breaks immediately, so nothing is created. }
      if not Options.Force then
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
        Inc(ListIdx);
        { A batch that does not fully fit the remaining chapters is skipped
          entirely (Python reference: "if plan.ch_index + count > num_chapters:
          break") — its chapters stay unmerged, which is exactly what the
          dialog preview shows for the overflow rows ('-').  The BatchSize <= 0
          guard also prevents an infinite loop from a malformed list. }
        if (BatchSize <= 0) or (BatchSize > Remaining) then
          Break;
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
          { Track the path before writing so a partially written volume
            from a failed WriteZipFromEntriesDeflated is rolled back too. }
          SetLength(CreatedPaths, Length(CreatedPaths) + 1);
          CreatedPaths[High(CreatedPaths)] := FullPath;
          WriteZipFromEntriesDeflated(FullPath, VolEntries);
          Inc(TotalCreated);
          { Only chapters merged into a volume that was actually written are
            eligible for cleanup — an empty/ComicInfo-only batch produces no
            volume and its sources must be left alone. }
          for n := 0 to BatchSize - 1 do
          begin
            SetLength(ToClean, Length(ToClean) + 1);
            ToClean[High(ToClean)] := Batch[n];
          end;
          { Advance the volume number only for volumes actually written, so a
            skipped batch does not leave a numbering gap. }
          Inc(VolNum);
        end;
      finally
        FreeZipEntries(VolEntries);
      end;

      Inc(ChIdx, BatchSize);
    end;
  except
    on E: Exception do
    begin
      { Roll back every volume created in this run, mirroring the Python
        reference (created_paths.unlink()), so a re-run cannot duplicate
        the content of already-merged chapters. }
      for n := 0 to High(CreatedPaths) do
        DeleteFile(CreatedPaths[n]);
      Result.Success := False;
      Result.VolumesCreated := 0;
      Result.ErrorMsg := Format(
        'Error during merge — created volumes have been removed (%s)',
        [E.Message]);
      Exit;
    end;
  end;

  Result.Success := TotalCreated > 0;
  Result.VolumesCreated := TotalCreated;

  { Below-threshold case (fewer chapters than CPV, no Force): report why
    nothing was created instead of failing with an empty error message.
    CPVF is shown with one decimal like the Python reference's ":.1f"
    format. }
  if (TotalCreated = 0) and (Result.ErrorMsg = '') then
    Result.ErrorMsg := Format(
      'Not enough chapters for a full volume (%d chapter(s), %.1f per volume)',
      [Length(ChBatch), CPVF]);

  { ---- Phase 3: Cleanup — remove or back up original chapter files ---- }
  for n := 0 to High(ToClean) do
  begin
    { Defense in depth: only chapter files of the merged series may be
      cleaned up.  Volume files, _OLD backups, and files of other series
      must never be renamed or deleted by a merge, even if they somehow
      reached ToClean. }
    if not IsChapterFile(ToClean[n], CleanSeries, CleanNum, CleanSpecial) or
       (CleanSeries <> SeriesName) then
      Continue;
    FullPath := CBZFullPath(ADir, ToClean[n]);
    if Options.Delete then
      DeleteFile(FullPath)
    else
      BackupFile(FullPath);
  end;
end;

end.
