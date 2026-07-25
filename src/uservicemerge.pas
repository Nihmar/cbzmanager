unit uservicemerge;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor, uservicebase;

type
  TMergeOptions = record
    SeriesName: string;
    ChapterStart: integer;
    ChapterEnd: integer;
    ChaptersPerVolume: integer;  // 0 = auto-calculate
    Force: boolean;
    Delete: boolean;             // True=delete originals, False=rename to _OLD
  end;

  TMergeResult = record
    Success: boolean;
    VolumesCreated: integer;
    ErrorMsg: string;
  end;

  { TMergeService }
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
      AFiles: all CBZ filenames in the directory.
      ADir: directory path containing the files.
      Options: merge parameters (series name, CPV, range, force).
      When Options.ChaptersPerVolume = 0, auto-calculates from existing volumes.
      When Force is True, the last volume absorbs remaining chapters
      (even if they exceed CPV). }
    class function Merge(const AFiles: TStringArray; const ADir: string;
      const Options: TMergeOptions;
      AOnProgress: TProgressEvent = nil): TMergeResult;
  end;

implementation

uses
  Math, StrUtils;

class function TMergeService.DetectSeriesName(const AFiles: TStringArray): string;
var
  i, n: integer;
  BaseName: string;
begin
  Result := '';
  for i := 0 to High(AFiles) do
  begin
    BaseName := ChangeFileExt(AFiles[i], '');
    n := LastDelimiter(' -', BaseName);
    if n > 0 then
    begin
      Result := Trim(Copy(BaseName, 1, n - 1));
      Exit;
    end;
  end;
end;

class function TMergeService.CalculateChaptersPerVolume(
  const AFiles: TStringArray; const SeriesName: string): integer;
var
  i, ChNum, LowestCh, VolCount: integer;
  BaseName: string;
  n: integer;
begin
  Result := 0;
  if (SeriesName = '') or (Length(AFiles) = 0) then Exit;

  LowestCh := MaxInt;
  VolCount := 0;

  for i := 0 to High(AFiles) do
  begin
    BaseName := ChangeFileExt(AFiles[i], '');
    { Count existing volumes }
    if StartsStr(SeriesName + ' V', BaseName) then
    begin
      Inc(VolCount);
      Continue;
    end;
    { Find lowest chapter number }
    n := LastDelimiter(' -', BaseName);
    if n > 0 then
    begin
      ChNum := StrToIntDef(Trim(Copy(BaseName, n + 1, MaxInt)), 0);
      if (ChNum > 0) and (ChNum < LowestCh) then
        LowestCh := ChNum;
    end;
  end;

  if (VolCount > 0) and (LowestCh > 1) then
    Result := (LowestCh - 1) div VolCount;

  { Clamp to sensible range }
  if Result < 1 then
    Result := 0;
end;

class function TMergeService.Merge(const AFiles: TStringArray;
  const ADir: string; const Options: TMergeOptions;
  AOnProgress: TProgressEvent = nil): TMergeResult;
var
  i, n, ChNum, CPV, VolNum, TotalCreated, Remaining, TotalBatches: integer;
  BaseName, SeriesName, VolName, FullPath: string;
  ChBatch, Batch: TStringArray;
  VolEntries: TZipEntries;
  CreatedFiles: TStringArray;
begin
  Result.Success := False;
  Result.VolumesCreated := 0;
  Result.ErrorMsg := '';

  SeriesName := Options.SeriesName;
  if SeriesName = '' then
    SeriesName := DetectSeriesName(AFiles);
  if SeriesName = '' then
    SeriesName := 'Unknown';

  { Auto-CPV when set to 0 }
  CPV := Options.ChaptersPerVolume;
  if CPV < 1 then
  begin
    CPV := CalculateChaptersPerVolume(AFiles, SeriesName);
    if CPV < 1 then
      CPV := 7;
  end;

  { Build chapter batch from files matching "Title - NNNN" in range }
  ChBatch := nil;
  for i := 0 to High(AFiles) do
  begin
    BaseName := ChangeFileExt(AFiles[i], '');
    n := LastDelimiter(' -', BaseName);
    if n > 0 then
    begin
      ChNum := StrToIntDef(Trim(Copy(BaseName, n + 1, MaxInt)), 0);
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

  { Group chapters by CPV and merge each group }
  TotalBatches := (Length(ChBatch) + CPV - 1) div CPV;
  TotalCreated := 0;
  VolNum := 1;
  CreatedFiles := nil;
  if Assigned(AOnProgress) and (TotalBatches > 0) then
    AOnProgress(0, Format('Merging 0/%d volumes', [TotalBatches]));
  i := 0;
  while i < Length(ChBatch) do
  begin
    Remaining := Length(ChBatch) - i;

    if Assigned(AOnProgress) then
      AOnProgress((TotalCreated * 100) div TotalBatches,
        Format('Writing volume %d/%d', [TotalCreated + 1, TotalBatches]));

    { Build batch of CPV chapters for this volume }
    if Options.Force and (TotalCreated > 0) and (Remaining <= CPV) then
    begin
      { Force mode: attach remaining chapters to the last created volume }
      { Re-open the last volume and append chapters }
      VolName := Format('%s V%.3d.cbz', [SeriesName, VolNum - 1]);
      FullPath := IncludeTrailingPathDelimiter(ADir) + VolName;
      { Build batch of remaining chapters }
      SetLength(Batch, Remaining);
      for n := 0 to Remaining - 1 do
        Batch[n] := ChBatch[i + n];
      VolEntries := MergeIntoVolume(Batch, ADir);
      try
        if Length(VolEntries) > 0 then
        begin
          WriteZipFromEntriesDeflated(FullPath, VolEntries);
          { No new volume created — entries added to existing }
        end;
      finally
        FreeZipEntries(VolEntries);
      end;
      i := Length(ChBatch);  { mark all as consumed for cleanup phase }
      Break;  { all remaining chapters appended }
    end
    else
    begin
      { Normal: create a new volume }
      Batch := nil;
      for n := 0 to CPV - 1 do
        if i + n < Length(ChBatch) then
        begin
          SetLength(Batch, Length(Batch) + 1);
          Batch[High(Batch)] := ChBatch[i + n];
        end;

      VolName := Format('%s V%.3d.cbz', [SeriesName, VolNum]);
      FullPath := IncludeTrailingPathDelimiter(ADir) + VolName;
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
      Inc(i, CPV);
    end;
  end;

  Result.Success := TotalCreated > 0;
  Result.VolumesCreated := TotalCreated;

  { Phase: Cleanup original chapters — rename to _OLD or delete }
  for n := 0 to i - 1 do
  begin
    FullPath := IncludeTrailingPathDelimiter(ADir) + ChBatch[n];
    if Options.Delete then
      DeleteFile(FullPath)
    else
      BackupFile(FullPath);
  end;
end;

end.
