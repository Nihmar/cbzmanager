unit uservicecomicinfo;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor, uservicebase;

type
  TComicInfoEntry = record
    FileName: string;
    HasComicInfo: boolean;
    Removed: boolean;
    Error: string;
  end;
  TComicInfoResults = array of TComicInfoEntry;

  { TComicInfoService }
  TComicInfoService = class
  public
    { Scan files and return whether each has ComicInfo.xml. }
    class function Scan(const AFiles: TStringArray;
      const ADir: string): TComicInfoResults;

    { Remove ComicInfo.xml from the given files (by filename).
      Creates backup of each modified file when ABackup=True.
      Returns updated results. }
    class function Remove(const AFiles: TStringArray; const ADir: string;
      ABackup: boolean; AOnProgress: TProgressEvent = nil): TComicInfoResults;
  end;

implementation

class function TComicInfoService.Scan(const AFiles: TStringArray;
  const ADir: string): TComicInfoResults;
var
  i: integer;
  FullPath: string;
  Entries: TZipEntries;
  j: integer;
begin
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
          if SameText(Entries[j].Name, 'ComicInfo.xml') then
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
          if SameText(Entries[j].Name, 'ComicInfo.xml') then
          begin
            Found := True;
            Break;
          end;
        Result[i].HasComicInfo := Found;

        if not Found then Continue;

        { Filter out ComicInfo.xml entries in-place }
        k := 0;
        for j := 0 to High(Entries) do
        begin
          if SameText(Entries[j].Name, 'ComicInfo.xml') then
          begin
            Entries[j].Data.Free;
            Entries[j].Data := nil;
            Continue;
          end;
          if j <> k then
          begin
            Entries[k] := Entries[j];
            Entries[j].Data := nil;
          end;
          Inc(k);
        end;
        SetLength(Entries, k);

        { Backup original if requested }
        if ABackup then
          BackupFile(FullPath);

        { Write new CBZ without ComicInfo.xml }
        WriteZipFromEntriesDeflated(FullPath, Entries);

        { Free remaining streams }
        for j := 0 to High(Entries) do
          Entries[j].Data.Free;

        Result[i].Removed := True;
        Entries := nil;  { prevent double-free in finally }
      finally
        if Entries <> nil then
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
