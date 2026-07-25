unit userviceconvert;
{$mode objfpc}{$h+}
interface

uses
  Classes, SysUtils, uZipEditor, uservicebase;

type
  TConvertOptions = record
    Quality: integer;
    ReplaceOnlyIfSmaller: boolean;
    SkipExistingWebP: boolean;
    RemoveComicInfo: boolean;
    RenumberPages: boolean;
    BackupOld: boolean;
  end;

  TConvertEntry = record
    FileName: string;
    Success: boolean;
    PagesConverted: integer;
    ErrorMsg: string;
  end;
  TConvertResults = array of TConvertEntry;

  { TConvertService }
  TConvertService = class
  public
    class function Convert(const AFiles: TStringArray; const ADir: string;
      const Options: TConvertOptions;
      AOnProgress: TProgressEvent = nil): TConvertResults;
  end;

implementation

class function TConvertService.Convert(const AFiles: TStringArray;
  const ADir: string; const Options: TConvertOptions;
  AOnProgress: TProgressEvent = nil): TConvertResults;
var
  i, NewCount, Total: integer;
  FullPath: string;
  NewEntries: TZipEntries;
begin
  Total := Length(AFiles);
  SetLength(Result, Total);
  if Assigned(AOnProgress) and (Total > 0) then
    AOnProgress(0, Format('Converting 0/%d files', [Total]));
  for i := 0 to High(AFiles) do
  begin
    if Assigned(AOnProgress) then
      AOnProgress((i * 100) div Total,
        Format('Converting %s (%d/%d)', [AFiles[i], i + 1, Total]));
    Result[i].FileName := AFiles[i];
    FullPath := IncludeTrailingPathDelimiter(ADir) + AFiles[i];
    try
      NewEntries := ConvertCBZToWebP(FullPath, Options.Quality,
        Options.ReplaceOnlyIfSmaller, Options.SkipExistingWebP,
        Options.RemoveComicInfo, Options.RenumberPages, NewCount);
      try
        if NewCount > 0 then
        begin
          if Options.BackupOld then
            BackupFile(FullPath);
          { Write new CBZ }
        WriteZipFromEntriesDeflated(FullPath, NewEntries);
          Result[i].Success := True;
          Result[i].PagesConverted := NewCount;
        end
        else
        begin
          Result[i].Success := True;
          Result[i].PagesConverted := 0;
          Result[i].ErrorMsg := 'No convertible images found';
        end;
      finally
        FreeZipEntries(NewEntries);
      end;
    except
      on E: Exception do
      begin
        Result[i].Success := False;
        Result[i].PagesConverted := 0;
        Result[i].ErrorMsg := E.Message;
      end;
    end;
  end;
end;

end.
