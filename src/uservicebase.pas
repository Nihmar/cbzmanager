unit uservicebase;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils;

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

end.
