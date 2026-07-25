unit uservicebase;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor;

type
  { Result record shared by all services }
  TServiceResult = record
    Success: boolean;
    Processed: integer;
    Message: string;
  end;

  { Progress callback for long operations.
    APercent: 0-100, AMsg: current file/step description. }
  TProgressEvent = procedure(APercent: integer; const AMsg: string) of object;
  TProgressProc = procedure(APercent: integer; const AMsg: string);

{ Create backup of AFilePath as Name_OLD.cbz.
  Deletes existing _OLD.cbz silently before renaming.
  Returns True on success. }
function BackupFile(const AFilePath: string): boolean;

{ Collect *.cbz filenames from a directory (non-recursive). }
function CollectCBZFiles(const ADir: string): TStringArray;

{ Write a new CBZ from in-memory entries, backing up the original.
  The new file is written to a .new temp file, then the original is
  renamed to _OLD.cbz and the .new file takes its place.
  On failure, the original file is preserved if possible.
  Returns True if the replacement was successful. }
function ReplaceCBZ(const AFilePath: string;
  const ANewEntries: TZipEntries): boolean;

implementation

function BackupFile(const AFilePath: string): boolean;
var
  OldFile: string;
begin
  OldFile := ChangeFileExt(AFilePath, '') + '_OLD.cbz';
  if FileExists(OldFile) then
    DeleteFile(OldFile);
  Result := RenameFile(AFilePath, OldFile);
end;

function CollectCBZFiles(const ADir: string): TStringArray;
var
  SearchRec: TSearchRec;
  Dir: string;
begin
  Result := nil;
  Dir := IncludeTrailingPathDelimiter(ADir);
  if FindFirst(Dir + '*.cbz', faAnyFile, SearchRec) = 0 then
  begin
    repeat
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := SearchRec.Name;
    until FindNext(SearchRec) <> 0;
    FindClose(SearchRec);
  end;
end;

function ReplaceCBZ(const AFilePath: string;
  const ANewEntries: TZipEntries): boolean;
var
  OldFile, NewFile: string;
begin
  OldFile := ChangeFileExt(AFilePath, '') + '_OLD.cbz';
  NewFile := AFilePath + '.new';
  try
    WriteZipFromEntriesDeflated(NewFile, ANewEntries);
    if FileExists(OldFile) then
      DeleteFile(OldFile);
    Result := RenameFile(AFilePath, OldFile);
    if Result then
      Result := RenameFile(NewFile, AFilePath);
    if not Result then
    begin
      { Rollback: try to restore the original }
      if FileExists(AFilePath) then
        DeleteFile(AFilePath);
      RenameFile(OldFile, AFilePath);
    end;
  except
    if FileExists(NewFile) then
      DeleteFile(NewFile);
    Result := False;
  end;
end;

end.
